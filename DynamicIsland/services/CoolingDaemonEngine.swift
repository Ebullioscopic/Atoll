import Foundation

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
    private var ownsFans = false
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
            close()
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
                      (15..<95).contains(temperature) else {
                    restore()
                    return CoolingReply(ok: false, message: "Automatic cooling restored because temperatures are high or unavailable.")
                }
                ownsFans = true
                do { try controller.setPreset(fraction, index: fan) }
                catch { restore(); throw error }
            case "auto":
                guard let fan = request.fanID, (0..<8).contains(fan) else { throw CoolingSMC.Error.invalidData }
                try controller().setAutomatic(index: fan)
            case "quit": close()
            default: throw CoolingSMC.Error.invalidData
            }
            // Hardware writes can take several seconds. Give the next heartbeat a full lease.
            leaseExpires = clock() + 15
            return CoolingReply(ok: true)
        } catch {
            return CoolingReply(ok: false, message: error.localizedDescription)
        }
    }

    /// Restores firmware control on lease expiry, or on high/unreadable temperatures while manual.
    func tick() -> Bool {
        let now = clock()
        guard !closed, now < leaseExpires else { close(); return false }
        if ownsFans, now - lastTemperatureCheck >= 2 {
            if let value = try? hardware?.hottestTemperature(), value.isFinite, (15..<95).contains(value) {
                lastTemperatureCheck = now
            } else { restore() }
        }
        return true
    }

    /// Releases only fans this connection changed; it never reapplies a previous manual preset.
    private func restore() {
        if ownsFans { hardware?.restoreOwnedFans(); ownsFans = false }
    }

    /// Makes cleanup idempotent for disconnect, timeout, feature disable, or daemon termination.
    func close() { restore(); closed = true }
}
