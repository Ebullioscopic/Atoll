import Foundation

/// A deterministic fan controller; these tests never open AppleSMC or require administrator access.
private final class Fixture: CoolingHardware {
    var temperature: Double? = 40
    var writes = 0
    var restores = 0
    var automatic = 0
    var failWrite = false
    var failFan: Int?
    var targets: [Int: Double] = [:]
    /// Supplies thermal readings, including missing and invalid samples.
    func hottestTemperature() throws -> Double? { temperature }
    /// Records allowed writes and simulates a failed hardware operation.
    func setPreset(_ fraction: Double, index: Int) throws {
        writes += 1
        if failWrite || failFan == index { throw CoolingSMC.Error.unavailable }
        targets[index] = fraction
    }
    /// Records firmware Auto commands independently of thermal readings.
    func setAutomatic(index: Int) throws { automatic += 1; targets[index] = nil }
    /// Counts cleanup to check lease expiry and idempotent restoration.
    func restoreOwnedFans() { restores += 1; targets.removeAll() }
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

        for temperature: Double? in [nil, .nan, .infinity, 14, 116] {
            let fixture = Fixture()
            let session = CoolingDaemonEngine(clock: { time }, hardwareProvider: { fixture })
            precondition(session.execute(preset).ok)
            fixture.temperature = temperature
            time += 2
            precondition(session.tick() && fixture.restores == 1, "sensor failure did not restore Auto")
            let status = session.execute(CoolingRequest(command: "ping"))
            precondition(status.effectivePresets?.isEmpty == true && status.controlNotice != nil, "sensor fallback was silent")
            for fraction in [0.3, 0.5, 0.7, 1.0] {
                precondition(!session.execute(CoolingRequest(command: "preset", fanID: 0, fraction: fraction)).ok)
            }
            precondition(fixture.writes == 1, "unsafe thermal preset applied")
            precondition(session.execute(CoolingRequest(command: "auto", fanID: 0)).ok && fixture.automatic == 1)
        }
        // Heat raises owned fans, preserves an existing maximum, and leaves Auto fans alone.
        let hotHardware = Fixture()
        let hot = CoolingDaemonEngine(clock: { time }, hardwareProvider: { hotHardware })
        precondition(hot.execute(CoolingRequest(command: "preset", fanID: 0, fraction: 0.7)).ok)
        precondition(hot.execute(CoolingRequest(command: "preset", fanID: 1, fraction: 1)).ok)
        hotHardware.temperature = 95
        time += 2
        precondition(hot.tick() && hotHardware.restores == 0)
        precondition(hotHardware.targets == [0: 1, 1: 1] && hotHardware.writes == 3, "heat did not boost just the owned fans")
        let boosted = hot.execute(CoolingRequest(command: "ping"))
        precondition(boosted.ok && boosted.effectivePresets == [0: 1, 1: 1] && boosted.controlNotice != nil)
        let encoded = try! JSONEncoder().encode(boosted)
        let decoded = try! JSONDecoder().decode(CoolingReply.self, from: encoded)
        precondition(decoded.effectivePresets == boosted.effectivePresets && decoded.controlNotice == boosted.controlNotice)
        hotHardware.temperature = 85
        time += 2
        precondition(hot.tick() && hotHardware.targets == [0: 1, 1: 1] && hotHardware.writes == 3, "cooling automatically lowered boosted fans")
        precondition(hot.execute(CoolingRequest(command: "preset", fanID: 0, fraction: 0.7)).effectivePresets == [0: 0.7, 1: 1])
        precondition(hot.execute(CoolingRequest(command: "auto", fanID: 1)).controlNotice == nil)
        hotHardware.temperature = 96
        time += 2
        precondition(hot.tick() && hotHardware.targets == [0: 1], "boost reclaimed a fan explicitly returned to Auto")
        precondition(hot.execute(CoolingRequest(command: "auto", fanID: 0)).effectivePresets?.isEmpty == true)
        let writesAfterAuto = hotHardware.writes
        time += 2
        precondition(hot.tick() && hotHardware.writes == writesAfterAuto, "watchdog overrode explicit Auto")
        hot.close()
        precondition(hotHardware.restores == 0, "session restored fans it no longer owns")

        // A hot first command reports its effective maximum target instead of a lower requested preset.
        for fraction in [0.3, 0.5, 0.7, 1.0] {
            let fixture = Fixture()
            fixture.temperature = 100
            let session = CoolingDaemonEngine(clock: { time }, hardwareProvider: { fixture })
            let result = session.execute(CoolingRequest(command: "preset", fanID: 0, fraction: fraction))
            precondition(result.ok && result.effectivePresets == [0: 1] && result.controlNotice != nil)
            precondition(fixture.targets == [0: 1] && fixture.restores == 0)
            time += 2
            precondition(session.tick() && fixture.writes == 1, "watchdog repeatedly wrote an existing maximum target")
            session.close()
            precondition(fixture.restores == 1, "boosted fan was not restored on disconnect")
        }

        // An unconfirmed boost releases ownership and explains why firmware control was restored.
        let boostFailure = Fixture()
        let failedBoost = CoolingDaemonEngine(clock: { time }, hardwareProvider: { boostFailure })
        precondition(failedBoost.execute(CoolingRequest(command: "preset", fanID: 0, fraction: 0.7)).ok)
        boostFailure.failWrite = true
        boostFailure.temperature = 96
        time += 2
        precondition(failedBoost.tick() && boostFailure.restores == 1)
        let failedStatus = failedBoost.execute(CoolingRequest(command: "ping"))
        precondition(failedStatus.effectivePresets?.isEmpty == true && failedStatus.controlNotice?.contains("boost failed") == true)

        // If the second fan rejects a boost, release both fans, including the already boosted first fan.
        let partialHardware = Fixture()
        let partialBoost = CoolingDaemonEngine(clock: { time }, hardwareProvider: { partialHardware })
        precondition(partialBoost.execute(CoolingRequest(command: "preset", fanID: 0, fraction: 0.3)).ok)
        precondition(partialBoost.execute(CoolingRequest(command: "preset", fanID: 1, fraction: 0.7)).ok)
        partialHardware.failFan = 1
        partialHardware.temperature = 96
        time += 2
        precondition(partialBoost.tick() && partialHardware.writes == 4 && partialHardware.restores == 1)
        precondition(partialHardware.targets.isEmpty && partialBoost.execute(CoolingRequest(command: "ping")).effectivePresets?.isEmpty == true)

        let failure = Fixture()
        failure.failWrite = true
        let session = CoolingDaemonEngine(clock: { time }, hardwareProvider: { failure })
        precondition(!session.execute(preset).ok && failure.restores == 1, "failed write did not restore")
        failure.failWrite = false
        precondition(session.execute(preset).ok)
        precondition(session.execute(CoolingRequest(command: "quit")).ok && failure.restores == 2)
        precondition(!session.execute(CoolingRequest(command: "ping")).ok)
        print("Cooling daemon: validation, lease renewal/expiry, maximum-speed thermal boost, latched targets, sensor fallback, rollback, quit, and lazy hardware passed")
    }
}
