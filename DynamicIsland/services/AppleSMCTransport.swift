import Foundation

/// Read-only transport inside Atoll. SMC writes run in the bundled helper.
final class AppleSMCTransport {
    private let smc: CoolingSMC
    init() throws { smc = try CoolingSMC() }
    func discoverAndRead() throws -> [CoolingFan] { try smc.fans() }
    func temperature() throws -> Double? { try smc.hottestTemperature() }
}
