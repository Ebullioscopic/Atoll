import Foundation

/// A deterministic fan controller; these tests never open AppleSMC or require administrator access.
private final class Fixture: CoolingHardware {
    var temperature: Double? = 40
    var writes = 0
    var restores = 0
    var automatic = 0
    var failWrite = false
    /// Supplies thermal readings, including missing and invalid samples.
    func hottestTemperature() throws -> Double? { temperature }
    /// Records allowed writes and simulates a failed hardware operation.
    func setPreset(_ fraction: Double, index: Int) throws {
        writes += 1
        if failWrite { throw CoolingSMC.Error.unavailable }
    }
    /// Records firmware Auto commands independently of thermal readings.
    func setAutomatic(index: Int) throws { automatic += 1 }
    /// Counts cleanup to check lease expiry and idempotent restoration.
    func restoreOwnedFans() { restores += 1 }
}

@main struct CoolingDaemonRegression {
    /// Exercises watchdog and rollback behavior with a monotonic test clock and no hardware writes.
    static func main() {
        var time = 0.0
        var opens = 0
        let hardware = Fixture()
        let engine = CoolingDaemonEngine(clock: { time }, hardwareProvider: { opens += 1; return hardware })
        precondition(engine.execute(CoolingRequest(command: "ping")).ok && opens == 0, "idle heartbeat opened SMC")
        for invalid in [CoolingRequest(command: "shell"), CoolingRequest(command: "preset", fanID: -1, fraction: 0.5), CoolingRequest(command: "preset", fanID: 0, fraction: 0.4), CoolingRequest(command: "auto", fanID: 8)] {
            precondition(!engine.execute(invalid).ok && opens == 0, "invalid request reached hardware")
        }
        let preset = CoolingRequest(command: "preset", fanID: 0, fraction: 1)
        precondition(engine.execute(preset).ok && hardware.writes == 1)
        time = 14
        precondition(engine.tick())
        precondition(engine.execute(CoolingRequest(command: "ping")).ok)
        time = 28
        precondition(engine.tick() && hardware.restores == 0, "heartbeat failed to renew lease")
        time = 30
        precondition(!engine.tick() && hardware.restores == 1, "expired lease failed to restore Auto")
        precondition(!engine.execute(preset).ok && hardware.writes == 1, "expired session reapplied manual mode")
        engine.close()
        precondition(hardware.restores == 1, "cleanup was not idempotent")

        for temperature: Double? in [95, nil, .nan, 14] {
            let fixture = Fixture()
            let session = CoolingDaemonEngine(clock: { time }, hardwareProvider: { fixture })
            precondition(session.execute(preset).ok)
            fixture.temperature = temperature
            time += 2
            precondition(session.tick() && fixture.restores == 1, "thermal watchdog failed")
            for fraction in [0.3, 0.5, 0.7, 1.0] {
                precondition(!session.execute(CoolingRequest(command: "preset", fanID: 0, fraction: fraction)).ok)
            }
            precondition(fixture.writes == 1, "unsafe thermal preset applied")
            precondition(session.execute(CoolingRequest(command: "auto", fanID: 0)).ok && fixture.automatic == 1)
        }
        let failure = Fixture()
        failure.failWrite = true
        let session = CoolingDaemonEngine(clock: { time }, hardwareProvider: { failure })
        precondition(!session.execute(preset).ok && failure.restores == 1, "failed write did not restore")
        failure.failWrite = false
        precondition(session.execute(preset).ok)
        precondition(session.execute(CoolingRequest(command: "quit")).ok && failure.restores == 2)
        precondition(!session.execute(CoolingRequest(command: "ping")).ok)
        print("Cooling daemon: validation, lease renewal/expiry, thermal guard, rollback, quit, and lazy hardware passed")
    }
}
