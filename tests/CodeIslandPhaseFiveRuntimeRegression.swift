import CodeIslandCore
import CodeIslandRuntime
import Foundation

private enum RuntimeRegressionFailure: Error {
    case failed(String)
}

private func verify(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RuntimeRegressionFailure.failed(message) }
}

@main
private struct CodeIslandPhaseFiveRuntimeRegression {
    static func main() throws {
        try verifyCodexMonitoringCapabilityIsAvailable()
        try verifyInactiveStartIsReadOnly()
        try verifyReceiptResumesListenerBeforeVerification()
        try verifyReceiptGatesRepairAfterListenerStartup()
    }

    private static func verifyCodexMonitoringCapabilityIsAvailable() throws {
        let profile = ProviderCapabilityRegistry.phaseFive.profile(for: .codex)
        try verify(profile?.verifiedCapability == .monitoring, "Codex must remain Monitoring")
        try verify(profile?.isActivationAvailable == true, "verified Codex Monitoring must be activatable")
        try verify(
            profile?.limitations == [
                .interactiveQuestionObservationUnavailable,
                .toolFailureObservationUnavailable,
            ],
            "unverified question and failure behavior must remain gated"
        )
    }

    private static func verifyInactiveStartIsReadOnly() throws {
        let fixture = RuntimeFixture(installed: false)
        try fixture.runtime.start(plan: fixture.plan)

        try verify(fixture.runtime.state == .inactive, "no receipt must remain inactive")
        try verify(!fixture.runtime.isRunning, "no receipt must not start a listener")
        try verify(fixture.recorder.events == ["installer.load"], "inactive startup must only inspect the managed receipt")
    }

    private static func verifyReceiptResumesListenerBeforeVerification() throws {
        let fixture = RuntimeFixture(installed: true)
        try fixture.runtime.start(plan: fixture.plan)

        try verify(fixture.runtime.state == .active(provider: .codex), "verified receipt must resume Codex Monitoring")
        try verify(fixture.runtime.isRunning, "resumed listener must report running")
        try verify(
            fixture.recorder.events == [
                "installer.load",
                "preflight",
                "listener.start",
                "installer.verify",
            ],
            "resume must make the listener ready before verification"
        )

        let observation = SessionObservation(
            provider: .codex,
            sessionID: OpaqueSessionID("thr_runtime")!,
            project: ProjectIdentity(displayName: "Atoll"),
            origin: nil,
            transition: .started,
            observedAt: Date(timeIntervalSince1970: 1_754_275_200)
        )
        fixture.runtime.receive(observation)
        try verify(fixture.store.saved.count == 1, "runtime must persist only the projected session")
        try verify(fixture.store.saved[0].state == .working, "runtime must project lifecycle state")
        try verify(fixture.projections.value.count == 1, "runtime must publish one sanitized projection")

        fixture.runtime.shutdown()
        try verify(!fixture.runtime.isRunning, "shutdown must stop runtime services")
        try verify(
            fixture.recorder.events.suffix(3) == [
                "listener.passThrough",
                "listener.drain",
                "listener.stop",
            ],
            "shutdown must enter pass-through and must not uninstall consented hooks"
        )
        try verify(!fixture.recorder.events.contains("installer.remove"), "app shutdown must preserve activation")
    }

    private static func verifyReceiptGatesRepairAfterListenerStartup() throws {
        let fixture = RuntimeFixture(installed: true, requiresRepair: true)
        try fixture.runtime.start(plan: fixture.plan)

        try verify(fixture.runtime.state == .active(provider: .codex), "receipt-owned drift must be repaired")
        try verify(
            fixture.recorder.events == [
                "installer.load",
                "preflight",
                "listener.start",
                "installer.verify",
                "installer.repair",
                "installer.verify",
            ],
            "repair must run only after receipt load and listener readiness"
        )
    }
}

private final class RuntimeFixture {
    let recorder = RuntimeEventRecorder()
    let store = RecordingMetadataStore()
    let projections = RuntimeLocked<[(SessionMetadata, SessionMetadata?)]>([])
    let plan: CodeIslandInstallationPlan
    let runtime: CodeIslandRuntime

    init(installed: Bool, requiresRepair: Bool = false) {
        let root = URL(fileURLWithPath: "/private/tmp/atoll-phase-five-runtime")
        plan = CodeIslandInstallationPlan(
            provider: .codex,
            bundledBridgeURL: root.appendingPathComponent("bundled"),
            changes: [
                CodeIslandConfigurationChange(kind: .modifyProviderHooks, url: root.appendingPathComponent("hooks.json")),
                CodeIslandConfigurationChange(kind: .installManagedBridge, url: root.appendingPathComponent("codeisland-bridge")),
                CodeIslandConfigurationChange(kind: .writeManagedReceipt, url: root.appendingPathComponent("receipt.json")),
                CodeIslandConfigurationChange(kind: .createListenerSocket, url: root.appendingPathComponent("listener.sock")),
            ],
            blockers: []
        )
        let receipt = installed ? CodeIslandManagedInstallationReceipt(
            planID: UUID(),
            provider: .codex,
            hookConfigurationURL: plan.url(for: .modifyProviderHooks)!,
            managedBridgeURL: plan.url(for: .installManagedBridge)!,
            managedReceiptURL: plan.url(for: .writeManagedReceipt)!,
            managedCommand: "managed",
            hookEvents: plan.hookEvents,
            bridgeDigest: "digest",
            listenerSocketURL: plan.url(for: .createListenerSocket)
        ) : nil
        let coordinator = CodeIslandActivationCoordinator(
            preflight: RuntimePreflight(recorder: recorder),
            listener: RuntimeListener(recorder: recorder),
            installer: RuntimeInstaller(
                recorder: recorder,
                receipt: receipt,
                requiresRepair: requiresRepair
            ),
            drainTimeout: 0.25
        )
        runtime = CodeIslandRuntime(
            coordinator: coordinator,
            metadataStore: store
        ) { [projections] current, previous in
            projections.withValue { $0.append((current, previous)) }
        }
    }
}

private final class RuntimeEventRecorder: @unchecked Sendable {
    var events: [String] = []
}

private struct RuntimePreflight: CodeIslandActivationPreflighting {
    let recorder: RuntimeEventRecorder
    func validate(plan: CodeIslandInstallationPlan) throws { recorder.events.append("preflight") }
}

private struct RuntimeListener: CodeIslandListenerControlling {
    let recorder: RuntimeEventRecorder
    func start(at socketURL: URL) throws { recorder.events.append("listener.start") }
    func enterPassThrough() { recorder.events.append("listener.passThrough") }
    func drain(timeout: TimeInterval) { recorder.events.append("listener.drain") }
    func stop() { recorder.events.append("listener.stop") }
}

private final class RuntimeInstaller: CodeIslandManagedInstalling, @unchecked Sendable {
    let recorder: RuntimeEventRecorder
    let receipt: CodeIslandManagedInstallationReceipt?
    let requiresRepair: Bool
    private var verificationCount = 0

    init(
        recorder: RuntimeEventRecorder,
        receipt: CodeIslandManagedInstallationReceipt?,
        requiresRepair: Bool
    ) {
        self.recorder = recorder
        self.receipt = receipt
        self.requiresRepair = requiresRepair
    }
    func loadManagedReceipt() throws -> CodeIslandManagedInstallationReceipt? {
        recorder.events.append("installer.load")
        return receipt
    }
    func install(plan: CodeIslandInstallationPlan) throws -> CodeIslandManagedInstallationReceipt {
        recorder.events.append("installer.install")
        return receipt!
    }
    func verify(receipt: CodeIslandManagedInstallationReceipt) throws {
        recorder.events.append("installer.verify")
        verificationCount += 1
        if requiresRepair, verificationCount == 1 {
            throw RuntimeRegressionFailure.failed("receipt-owned drift")
        }
    }
    func repair(
        receipt: CodeIslandManagedInstallationReceipt,
        plan: CodeIslandInstallationPlan
    ) throws -> CodeIslandManagedInstallationReceipt {
        recorder.events.append("installer.repair")
        return receipt
    }
    func remove(receipt: CodeIslandManagedInstallationReceipt) throws { recorder.events.append("installer.remove") }
}

private final class RecordingMetadataStore: SessionMetadataStoring, @unchecked Sendable {
    var saved: [SessionMetadata] = []
    func load() throws -> [SessionMetadata] { saved }
    func save(_ sessions: [SessionMetadata]) throws { saved = sessions }
}

private final class RuntimeLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&stored)
        lock.unlock()
    }
}
