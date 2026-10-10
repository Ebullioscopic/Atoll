import Foundation

/// Read-only transport inside Atoll. SMC writes run in the bundled helper.
final class AppleSMCTransport {
    private let smc: CoolingSMC
    /// Opens the app’s read-only AppleSMC transport.
    init() throws { smc = try CoolingSMC() }
    /// Returns validated live fan readings without changing firmware control.
    func discoverAndRead() throws -> [CoolingFan] { try smc.fans() }
    /// Returns the hottest readable valid temperature, or nil when none are available.
    func temperature() throws -> Double? { try smc.hottestTemperature() }
}
