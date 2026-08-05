import CodeIslandCore
import CodeIslandRuntime
import Foundation

@main
struct CodeIslandPhaseFourSocketRegression {
    static func main() throws {
        try verifySystemSocketClassification()
        try verifyAdoptionPreflightReclaimsOnlyDisclosedStaleSocket()
    }

    private static func verifySystemSocketClassification() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let inspector = CodeIslandSystemSocketInspector()

        let missing = root.appendingPathComponent("missing.sock")
        precondition(inspector.state(at: missing) == .absent)

        let regular = root.appendingPathComponent("regular.sock")
        try Data("not a socket".utf8).write(to: regular)
        precondition(inspector.state(at: regular) == .unexpectedFile)

        let reclaimer = CodeIslandSystemStaleSocketReclaimer(
            inspector: FixedSocketInspector(state: .stale)
        )
        do {
            try reclaimer.reclaimStaleSocket(at: regular)
            preconditionFailure("A regular file must never be unlinked as a socket")
        } catch let error as CodeIslandActivationPreflightError {
            precondition(error == .legacySocketPathUnsafe)
        }
        precondition(fileManager.fileExists(atPath: regular.path))
    }

    private static func verifyAdoptionPreflightReclaimsOnlyDisclosedStaleSocket() throws {
        let recorder = SocketRecorder()
        let stalePlan = makePlan(socketKind: .replaceStaleListenerSocket)
        let preflight = CodeIslandAdoptionPreflight(
            socketInspector: FixedSocketInspector(state: .stale),
            applicationInspector: FixedApplicationInspector(isRunning: false),
            staleSocketReclaimer: RecordingSocketReclaimer(recorder: recorder)
        )

        try preflight.validate(plan: stalePlan)
        precondition(recorder.reclaimed == [stalePlan.url(for: .replaceStaleListenerSocket)!])

        let occupiedPreflight = CodeIslandAdoptionPreflight(
            socketInspector: FixedSocketInspector(state: .occupied),
            applicationInspector: FixedApplicationInspector(isRunning: false),
            staleSocketReclaimer: RecordingSocketReclaimer(recorder: recorder)
        )
        do {
            try occupiedPreflight.validate(plan: makePlan(socketKind: .createListenerSocket))
            preconditionFailure("An occupied socket must block listener startup")
        } catch let error as CodeIslandActivationPreflightError {
            precondition(error == .legacySocketOccupied)
        }
        precondition(recorder.reclaimed.count == 1)

        let runningAppPreflight = CodeIslandAdoptionPreflight(
            socketInspector: FixedSocketInspector(state: .absent),
            applicationInspector: FixedApplicationInspector(isRunning: true),
            staleSocketReclaimer: RecordingSocketReclaimer(recorder: recorder)
        )
        do {
            try runningAppPreflight.validate(plan: makePlan(socketKind: .createListenerSocket))
            preconditionFailure("Atoll must never compete with the old app")
        } catch let error as CodeIslandActivationPreflightError {
            precondition(error == .legacyApplicationRunning)
        }
        precondition(recorder.reclaimed.count == 1)
    }

    private static func makePlan(
        socketKind: CodeIslandConfigurationChangeKind
    ) -> CodeIslandInstallationPlan {
        let root = URL(fileURLWithPath: "/private/tmp/atoll-phase-four-socket-contract")
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
                    kind: socketKind,
                    url: root.appendingPathComponent("listener.sock")
                ),
            ],
            blockers: []
        )
    }

}

private final class SocketRecorder {
    var reclaimed: [URL] = []
}

private struct FixedSocketInspector: CodeIslandSocketInspecting {
    let state: CodeIslandSocketState

    func state(at socketURL: URL) -> CodeIslandSocketState {
        state
    }
}

private struct FixedApplicationInspector: CodeIslandLegacyApplicationInspecting {
    let isRunning: Bool

    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        precondition(bundleIdentifier == "com.codeisland.app")
        return isRunning
    }
}

private struct RecordingSocketReclaimer: CodeIslandStaleSocketReclaiming {
    let recorder: SocketRecorder

    func reclaimStaleSocket(at socketURL: URL) throws {
        recorder.reclaimed.append(socketURL)
    }
}
