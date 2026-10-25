import Foundation
import IOKit

// AppleSMC ABI and fan-key access adapted from raminsharifi/MacFanControl (MIT).
// See THIRD_PARTY_FAN_CONTROL.md for the complete notice.
struct CoolingFan: Identifiable, Equatable, Codable {
    enum Mode: String, Codable { case automatic, manual, system, unknown }
    let id: Int
    let name: String
    let actualRPM: Double
    let targetRPM: Double
    let minimumRPM: Double
    let maximumRPM: Double
    let mode: Mode

    /// Maps a finite preset fraction into this fan’s validated hardware RPM range.
    func rpm(at fraction: Double) throws -> Double {
        guard fraction.isFinite, (0...1).contains(fraction), minimumRPM.isFinite,
              maximumRPM.isFinite, minimumRPM >= 0, maximumRPM > minimumRPM else {
            throw CoolingSMC.Error.invalidData
        }
        return minimumRPM + (maximumRPM - minimumRPM) * fraction
    }
}

final class CoolingSMC {
    enum Error: LocalizedError {
        case unavailable, kernel(Int32), result(UInt8), invalidData, permission, verification(String)
        /// Describes sensor, privilege, or write-verification failures for the Cooling UI.
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Fan sensors are unavailable on this Mac."
            case .kernel(let code): return "Cannot access the fan controller (\(code))."
            case .result(let code): return "Fan controller returned error 0x\(String(code, radix: 16))."
            case .invalidData: return "The fan controller returned invalid limits or sensor data."
            case .permission: return "Administrator authorization is required to change fan speed."
            case .verification(let detail): return "The fan controller did not confirm the requested speed: \(detail)"
            }
        }
    }

    struct Value {
        let type: String
        let bytes: [UInt8]
        /// Decodes the supported SMC integer, fixed-point, or little-endian float payload.
        var number: Double? {
            switch type {
            case "flt " where bytes.count == 4:
                let bits = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
                return Double(Float(bitPattern: bits))
            case "fpe2" where bytes.count == 2: return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
            case "sp78" where bytes.count == 2: return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
            case "ui8 " where bytes.count == 1: return Double(bytes[0])
            case "ui16" where bytes.count == 2: return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            case "ui32" where bytes.count == 4: return Double(bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            default: return nil
            }
        }
    }

    private let connection: io_connect_t
    private var cache: [String: (Int, String)] = [:]
    private var temperatureKeys: [String]?
    private var controlled: Set<Int> = []
    private var unlocked = false

    /// Opens an AppleSMC IOKit connection; throws when the service cannot be accessed.
    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw Error.unavailable }
        defer { IOObjectRelease(service) }
        var port: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &port)
        guard result == KERN_SUCCESS else { throw Error.kernel(result) }
        connection = port
    }

    /// Releases the IOKit connection owned by this transport.
    deinit { IOServiceClose(connection) }

    /// Encodes exactly four UTF-8 bytes as the SMC key’s big-endian numeric identifier.
    static func fourCC(_ name: String) throws -> UInt32 {
        guard name.utf8.count == 4 else { throw Error.invalidData }
        return name.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    /// Converts a numeric SMC key or data-type identifier back into four ASCII bytes.
    private static func string(_ value: UInt32) -> String {
        String(bytes: (0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }, encoding: .ascii) ?? ""
    }

    // The 80-byte IOKit structure contains HOST-endian fields. Its result is
    // at offset 40, command at 42, data32 at 44, and byte payload at 48.
    /// Exchanges the 80-byte host-endian SMC structure and validates kernel and firmware results.
    private func call(key: UInt32 = 0, command: UInt8, size: Int = 0, index: UInt32 = 0,
                      bytes: [UInt8] = []) throws -> [UInt8] {
        guard (0...32).contains(size), bytes.count <= 32 else { throw Error.invalidData }
        var input = [UInt8](repeating: 0, count: 80)
        /// Stores a 32-bit structure field in host byte order on supported little-endian Macs.
        func put(_ value: UInt32, _ offset: Int) {
            for n in 0..<4 { input[offset + n] = UInt8(truncatingIfNeeded: value >> (8 * n)) }
        }
        put(key, 0); put(UInt32(size), 28); put(index, 44)
        input[42] = command
        for (n, byte) in bytes.enumerated() { input[48 + n] = byte }
        var output = [UInt8](repeating: 0, count: 80)
        var length = 80
        let result = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                IOConnectCallStructMethod(connection, 2, source.baseAddress!, 80, destination.baseAddress!, &length)
            }
        }
        guard result == KERN_SUCCESS else { throw Error.kernel(result) }
        guard length == 80 else { throw Error.invalidData }
        guard output[40] == 0 else { throw Error.result(output[40]) }
        return output
    }

    /// Reads a little-endian 32-bit field from a validated SMC response structure.
    private func host32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }

    /// Loads and caches a key’s payload length and native data type.
    private func info(_ name: String) throws -> (size: Int, type: String) {
        if let value = cache[name] { return value }
        let response = try call(key: Self.fourCC(name), command: 9)
        let size = Int(host32(response, at: 28))
        guard (1...32).contains(size) else { throw Error.invalidData }
        let type = Self.string(host32(response, at: 32))
        cache[name] = (size, type)
        return (size, type)
    }

    /// Reads one SMC key without changing firmware state.
    func read(_ name: String) throws -> Value {
        let metadata = try info(name)
        let response = try call(key: Self.fourCC(name), command: 5, size: metadata.size)
        return Value(type: metadata.type, bytes: Array(response[48..<(48 + metadata.size)]))
    }

    /// Reads a supported numeric key and rejects non-finite sensor values.
    private func number(_ key: String) throws -> Double {
        guard let number = try read(key).number, number.isFinite else { throw Error.invalidData }
        return number
    }

    /// Discovers fan count, hardware limits, actual and target RPM, and per-fan control mode.
    func fans() throws -> [CoolingFan] {
        let count = try number("FNum")
        guard count.rounded() == count, (0...8).contains(count) else { throw Error.invalidData }
        return try (0..<Int(count)).map { index in
            let prefix = "F\(index)"
            let minimum = try number(prefix + "Mn"), maximum = try number(prefix + "Mx")
            let actual = try number(prefix + "Ac"), target = try number(prefix + "Tg")
            guard minimum >= 0, maximum > minimum, maximum < 20000, actual >= 0,
                  actual <= maximum * 1.25, target >= 0, target <= maximum * 1.25 else { throw Error.invalidData }
            let raw = try? number(modeKey(index))
            let mode: CoolingFan.Mode
            switch raw { case 0: mode = .automatic; case 1: mode = .manual; case .some: mode = .system; case nil: mode = .unknown }
            return CoolingFan(id: index, name: count == 2 ? (index == 0 ? "Left Fan" : "Right Fan") : "Fan \(index + 1)",
                              actualRPM: actual, targetRPM: target, minimumRPM: minimum, maximumRPM: maximum, mode: mode)
        }
    }

    /// Returns the maximum valid readable temperature, caching discovered temperature keys.
    func hottestTemperature() throws -> Double? {
        if temperatureKeys == nil {
            let count = try number("#KEY")
            guard count > 0, count < 100000 else { throw Error.invalidData }
            var keys: [String] = []
            for index in 0..<Int(count) {
                guard let output = try? call(command: 8, index: UInt32(index)) else { continue }
                let key = Self.string(host32(output, at: 0))
                guard key.hasPrefix("T"), let value = try? read(key), ["flt ", "sp78"].contains(value.type),
                      let temperature = value.number, (15...115).contains(temperature) else { continue }
                keys.append(key)
            }
            temperatureKeys = keys
        }
        return temperatureKeys?.compactMap { key -> Double? in
            guard let value = try? number(key), (15...115).contains(value) else { return nil }
            return value
        }.max()
    }

    /// Finds the available per-fan manual-mode key, preferring newer lowercase `md` firmware.
    private func modeKey(_ index: Int) throws -> String {
        for key in ["F\(index)md", "F\(index)Md"] where (try? info(key)) != nil { return key }
        throw Error.unavailable
    }

    /// Writes a size-checked SMC payload only when the helper is running as root.
    private func write(_ key: String, _ bytes: [UInt8]) throws {
        guard geteuid() == 0 else { throw Error.permission }
        guard try info(key).size == bytes.count else { throw Error.invalidData }
        _ = try call(key: Self.fourCC(key), command: 6, size: bytes.count, bytes: bytes)
    }

    /// Encodes a bounded RPM target in the key’s native `flt ` or `fpe2` format.
    static func rpmBytes(_ rpm: Double, type: String) throws -> [UInt8] {
        guard rpm.isFinite, (0...16383).contains(rpm) else { throw Error.invalidData }
        switch type {
        case "flt ":
            let bits = Float(rpm).bitPattern
            return (0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) }
        case "fpe2":
            let value = UInt16(rpm * 4)
            return [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
        default: throw Error.invalidData
        }
    }

    /// Writes the requested fan target using its reported SMC data type.
    private func writeRPM(_ rpm: Double, index: Int) throws {
        let key = "F\(index)Tg"
        try write(key, Self.rpmBytes(rpm, type: info(key).type))
    }

    /// Enters manual control, writes a range-based target, and verifies mode and RPM before success.
    /// Attempts Auto rollback if firmware rejects or ignores the request.
    func setPreset(_ fraction: Double, index: Int) throws {
        guard let fan = try fans().first(where: { $0.id == index }) else { throw Error.invalidData }
        let rpm = try fan.rpm(at: fraction)
        let key = try modeKey(index)
        // Ensure target encoding is known BEFORE entering manual mode.
        _ = try Self.rpmBytes(rpm, type: info("F\(index)Tg").type)
        controlled.insert(index)
        do {
            if fan.mode != .manual {
                do { try write(key, [1]) }
                catch {
                    if case Error.kernel = error { throw error }
                    // Firmware may reject direct writes until Ftst is enabled.
                }
                // A successful write can still be ignored by thermalmonitord.
                // Confirm the mode before deciding that the unlock is unnecessary.
                if (try? number(key)) != 1 {
                    try write("Ftst", [1]); unlocked = true
                    Thread.sleep(forTimeInterval: 3)
                    var engaged = false
                    for _ in 0..<30 {
                        if (try? write(key, [1])) != nil, (try? number(key)) == 1 { engaged = true; break }
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                    guard engaged else { throw Error.verification("manual mode was not accepted (mode \((try? number(key)) ?? -1)).") }
                }
            }
            try writeRPM(rpm, index: index)
            var observedMode = -1.0, observedTarget = -1.0
            let tolerance = max(50, fan.maximumRPM * 0.01)
            // Firmware target telemetry can settle asynchronously and quantize
            // RPM. Read the mode AND the target instead of trusting write success.
            for _ in 0..<20 {
                observedMode = (try? number(key)) ?? -1
                observedTarget = (try? number("F\(index)Tg")) ?? -1
                if observedMode == 1, abs(observedTarget - rpm) <= tolerance { return }
                Thread.sleep(forTimeInterval: 0.1)
            }
            throw Error.verification("requested \(Int(rpm)) RPM; mode \(observedMode), target \(observedTarget) RPM.")
        } catch {
            try? setAutomatic(index: index)
            throw error
        }
    }

    /// Returns a validated fan to firmware control and releases the manual unlock when possible.
    func setAutomatic(index: Int) throws {
        let count = try number("FNum")
        guard (1...8).contains(count), count.rounded() == count, (0..<Int(count)).contains(index) else { throw Error.invalidData }
        try write(modeKey(index), [0])
        // Returning to firmware control is valid even if target telemetry is
        // temporarily unreadable; clearing the target is a best-effort cleanup.
        try? writeRPM(0, index: index)
        guard try number(modeKey(index)) != 1 else { throw Error.verification("Auto mode was not accepted.") }
        controlled.remove(index)
        if controlled.isEmpty, (try? fans().allSatisfy { $0.mode != .manual }) == true,
           (try? number("Ftst")) == 1 { try write("Ftst", [0]); unlocked = false }
    }

    /// Retries Auto restoration for fans this connection changed, then clears its firmware unlock.
    func restoreOwnedFans() {
        for _ in 0..<3 {
            for index in Array(controlled) { try? setAutomatic(index: index) }
            if controlled.isEmpty { break }
            Thread.sleep(forTimeInterval: 0.1)
        }
        if unlocked { try? write("Ftst", [0]); unlocked = false }
        if !controlled.isEmpty { fputs("Atoll cooling: automatic restoration could not be confirmed.\n", stderr) }
    }
}
