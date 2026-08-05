import CodeIslandCore
import CodeIslandRuntime
import Foundation

@main
struct CodeIslandPhaseFourActivationRegression {
    static func main() throws {
        try verifyConsentAndConflictGates()
        try verifyListenerFirstActivationAndOrderedRemoval()
        try verifyFailedInstallReturnsToPassThrough()
    }

    private static func verifyConsentAndConflictGates() throws {
        let recorder = EventRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        let plan = makePlan()

        do {
            _ = try coordinator.activate(plan: plan, consent: nil)
            preconditionFailure("Activation must require consent")
        } catch let error as CodeIslandActivationError {
            precondition(error == .consentRequired)
        }
        precondition(recorder.events.isEmpty)

        let otherPlan = makePlan()
        do {
            _ = try coordinator.activate(
                plan: plan,
                consent: otherPlan.consent(confirmedByUser: true)
            )
            preconditionFailure("Consent must be bound to one plan")
        } catch let error as CodeIslandActivationError {
            precondition(error == .staleConsent)
        }
        precondition(recorder.events.isEmpty)

        let blocked = makePlan(blockers: [.legacyApplicationRunning])
        do {
            _ = try coordinator.activate(
                plan: blocked,
                consent: blocked.consent(confirmedByUser: true)
            )
            preconditionFailure("An adoption conflict must stop before preflight")
        } catch let error as CodeIslandActivationError {
            precondition(error == .blocked([.legacyApplicationRunning]))
        }
        precondition(recorder.events.isEmpty)
        precondition(plan.consent(confirmedByUser: false) == nil)
    }

    private static func verifyListenerFirstActivationAndOrderedRemoval() throws {
        let recorder = EventRecorder()
        let coordinator = makeCoordinator(recorder: recorder)
        let plan = makePlan()
        let consent = plan.consent(confirmedByUser: true)

        let receipt = try coordinator.activate(plan: plan, consent: consent)
        precondition(receipt.planID == plan.id)
        precondition(
            recorder.events
                == ["preflight", "listener.start", "installer.install", "installer.verify"]
        )

        try coordinator.deactivate(receipt: receipt)
        precondition(
            recorder.events
                == [
                    "preflight",
                    "listener.start",
                    "installer.install",
                    "installer.verify",
                    "listener.passThrough",
                    "installer.remove",
                    "listener.drain",
                    "listener.stop",
                ]
        )
    }

    private static func verifyFailedInstallReturnsToPassThrough() throws {
        let recorder = EventRecorder()
        let coordinator = CodeIslandActivationCoordinator(
            preflight: RecordingPreflight(recorder: recorder),
            listener: RecordingListener(recorder: recorder),
            installer: RecordingInstaller(recorder: recorder, shouldFailInstall: true),
            drainTimeout: 0.25
        )
        let plan = makePlan()

        do {
            _ = try coordinator.activate(
                plan: plan,
                consent: plan.consent(confirmedByUser: true)
            )
            preconditionFailure("The installer failure must escape")
        } catch RecordingFailure.install {
            // Expected.
        }
        precondition(
            recorder.events
                == [
                    "preflight",
                    "listener.start",
                    "installer.install",
                    "listener.passThrough",
                    "listener.drain",
                    "listener.stop",
                ]
        )
    }

    private static func makeCoordinator(
        recorder: EventRecorder
    ) -> CodeIslandActivationCoordinator {
        CodeIslandActivationCoordinator(
            preflight: RecordingPreflight(recorder: recorder),
            listener: RecordingListener(recorder: recorder),
            installer: RecordingInstaller(recorder: recorder),
            drainTimeout: 0.25
        )
    }

    private static func makePlan(
        blockers: Set<CodeIslandAdoptionBlocker> = []
    ) -> CodeIslandInstallationPlan {
        let root = URL(fileURLWithPath: "/private/tmp/atoll-phase-four-contract")
        return CodeIslandInstallationPlan(
            provider: .codex,
            bundledBridgeURL: root.appendingPathComponent("bundled-bridge"),
            changes: [
                CodeIslandConfigurationChange(
                    kind: .modifyProviderHooks,
                    url: root.appendingPathComponent("hooks.json")
                ),
                CodeIslandConfigurationChange(
                    kind: .installManagedBridge,
                    url: root.appendingPathComponent("managed-bridge")
                ),
                CodeIslandConfigurationChange(
                    kind: .writeManagedReceipt,
                    url: root.appendingPathComponent("receipt.json")
                ),
                CodeIslandConfigurationChange(
                    kind: .createListenerSocket,
                    url: root.appendingPathComponent("listener.sock")
                ),
            ],
            blockers: blockers
        )
    }
}

private final class EventRecorder {
    var events: [String] = []
}

private struct RecordingPreflight: CodeIslandActivationPreflighting {
    let recorder: EventRecorder

    func validate(plan: CodeIslandInstallationPlan) throws {
        recorder.events.append("preflight")
    }
}

private struct RecordingListener: CodeIslandListenerControlling {
    let recorder: EventRecorder

    func start(at socketURL: URL) throws {
        recorder.events.append("listener.start")
    }

    func enterPassThrough() {
        recorder.events.append("listener.passThrough")
    }

    func drain(timeout: TimeInterval) {
        precondition(timeout == 0.25)
        recorder.events.append("listener.drain")
    }

    func stop() {
        recorder.events.append("listener.stop")
    }
}

private enum RecordingFailure: Error {
    case install
}

private struct RecordingInstaller: CodeIslandManagedInstalling {
    let recorder: EventRecorder
    var shouldFailInstall = false

    func install(plan: CodeIslandInstallationPlan) throws -> CodeIslandManagedInstallationReceipt {
        recorder.events.append("installer.install")
        if shouldFailInstall { throw RecordingFailure.install }
        return CodeIslandManagedInstallationReceipt(
            planID: plan.id,
            provider: plan.provider,
            hookConfigurationURL: plan.url(for: .modifyProviderHooks)!,
            managedBridgeURL: plan.url(for: .installManagedBridge)!,
            managedReceiptURL: plan.url(for: .writeManagedReceipt)!,
            managedCommand: "managed command",
            hookEvents: plan.hookEvents,
            bridgeDigest: "digest"
        )
    }

    func verify(receipt: CodeIslandManagedInstallationReceipt) throws {
        recorder.events.append("installer.verify")
    }

    func remove(receipt: CodeIslandManagedInstallationReceipt) throws {
        recorder.events.append("installer.remove")
    }
}
