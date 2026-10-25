import Foundation
import os

/// Hardware operations used by the daemon; a fixture can exercise safety without touching fans.
protocol CoolingHardware: AnyObject {
    func hottestTemperature() throws -> Double?
    func setPreset(_ fraction: Double, index: Int) throws
    func setAutomatic(index: Int) throws
    func restoreOwnedFans()
}
extension CoolingSMC: CoolingHardware {}

/// One authenticated controller lease, confined to the daemon's serial queue.
final class CoolingDaemonEngine {
    private let hardwareProvider: () throws -> CoolingHardware
    private var hardware: CoolingHardware?
    private var presets: [Int: Double] = [:]
    private var boostedFans: Set<Int> = []
    private var controlNotice: String?
    private let logger = os.Logger(subsystem: "com.Ebullioscopic.Atoll", category: "Cooling")
    private var closed = false
    private let clock: () -> TimeInterval
    private var leaseExpires: TimeInterval
    private var lastTemperatureCheck = -Double.infinity

    /// Starts a 15-second lease without opening AppleSMC or changing the firmware's Auto mode.
    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, hardwareProvider: @escaping () throws -> CoolingHardware = { try CoolingSMC() }) {
        self.clock = clock
        leaseExpires = clock() + 15
        self.hardwareProvider = hardwareProvider
    }

    /// Lazily opens hardware only for an authorized fan command.
    private func controller() throws -> CoolingHardware {
        if let hardware { return hardware }
        let value = try hardwareProvider()
        hardware = value
        return value
    }

    /// Rejects expired sessions and unsupported commands; successful commands renew the lease.
    func execute(_ request: CoolingRequest) -> CoolingReply {
        let now = clock()
        guard !closed, now < leaseExpires else {
            close(reason: "The fan-control heartbeat expired.")
            return CoolingReply(ok: false, message: "The fan-control connection expired. Reconnect to continue.")
        }
        do {
            switch request.command {
            case "ping": break
            case "preset":
                guard let fan = request.fanID, (0..<8).contains(fan), let fraction = request.fraction,
                      [0.3, 0.5, 0.7, 1.0].contains(fraction) else { throw CoolingSMC.Error.invalidData }
                let controller = try controller()
                guard let temperature = try? controller.hottestTemperature(), temperature.isFinite,
                      (15...115).contains(temperature) else {
                    restore(reason: "macOS Auto restored because temperature readings are unavailable.")
                    return reply(ok: false, message: controlNotice)
                }
                // Track ownership before a write so a partial failure can always be cleaned up.
                presets[fan] = fraction
                do {
                    try controller.setPreset(temperature >= 95 ? 1 : fraction, index: fan)
                    boostedFans.remove(fan)
                    if temperature >= 95 {
                        presets[fan] = 1
                        try boostForHeat(temperature, controller: controller)
                    } else { updateBoostNotice() }
                    lastTemperatureCheck = clock()
                } catch {
                    restore(reason: "macOS Auto restored because a fan-speed change could not be confirmed.")
                    throw error
                }
            case "auto":
                guard let fan = request.fanID, (0..<8).contains(fan) else { throw CoolingSMC.Error.invalidData }
                try controller().setAutomatic(index: fan)
                presets[fan] = nil
                boostedFans.remove(fan)
                updateBoostNotice()
            case "quit": close()
            default: throw CoolingSMC.Error.invalidData
            }
            // Hardware writes can take several seconds. Give the next heartbeat a full lease.
            leaseExpires = clock() + 15
            return reply(ok: true)
        } catch {
            return reply(ok: false, message: error.localizedDescription)
        }
    }

    /// Boosts owned fans at 95°C; unreadable sensors and expired leases still restore firmware control.
    func tick() -> Bool {
        let now = clock()
        guard !closed, now < leaseExpires else { close(reason: "The fan-control heartbeat expired."); return false }
        if !presets.isEmpty, now - lastTemperatureCheck >= 2 {
            lastTemperatureCheck = now
            guard let controller = hardware, let value = try? controller.hottestTemperature(),
                  value.isFinite, (15...115).contains(value) else {
                restore(reason: "macOS Auto restored because temperature readings are unavailable.")
                return true
            }
            if value >= 95 {
                do { try boostForHeat(value, controller: controller) }
                catch { restore(reason: "macOS Auto restored because the high-temperature fan boost failed.") }
            }
        }
        return true
    }

    /// Raises only fans this session owns and latches 100% until an explicit preset or Auto command.
    private func boostForHeat(_ temperature: Double, controller: CoolingHardware) throws {
        for fan in presets.keys.sorted() {
            if presets[fan] != 1 {
                try controller.setPreset(1, index: fan)
                presets[fan] = 1
            }
        }
        let changed = boostedFans != Set(presets.keys)
        boostedFans = Set(presets.keys)
        updateBoostNotice()
        if changed { logger.notice("Cooling temperature \(temperature, privacy: .public)°C: controlled fans held at 100%.") }
    }

    /// Keeps the visible safety explanation until all boosted fans are explicitly changed.
    private func updateBoostNotice() {
        controlNotice = boostedFans.isEmpty ? nil : "High temperature: controlled fans held at 100%. Choose a preset after cooling."
    }

    /// Includes confirmed targets and any safety fallback in commands and heartbeat replies.
    private func reply(ok: Bool, message: String? = nil) -> CoolingReply {
        CoolingReply(ok: ok, message: message, controlNotice: controlNotice, effectivePresets: presets)
    }

    /// Releases only fans this connection changed; it never reapplies a previous manual preset.
    private func restore(reason: String) {
        if !presets.isEmpty {
            hardware?.restoreOwnedFans()
            logger.notice("Cooling: \(reason, privacy: .public)")
        }
        presets.removeAll()
        boostedFans.removeAll()
        controlNotice = reason
    }

    /// Makes cleanup idempotent for disconnect, timeout, feature disable, or daemon termination.
    func close(reason: String = "The fan-control connection closed.") { restore(reason: reason); closed = true }
}
