import Foundation
import CodeIslandCore
import CodeIslandRuntime

@main
struct CodeIslandPhaseThreeActivityRegression {
    static func main() {
        let adapter = CodeIslandActivityIntentAdapter()
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let working = metadata(state: .working, at: startedAt)

        guard adapter.intent(for: working, previous: nil)?.kind == .sessionStarted else {
            fatalError("The first working projection must produce a session-start intent")
        }

        let waiting = metadata(state: .waitingForApproval, at: startedAt.addingTimeInterval(10))
        let attention = adapter.intent(for: waiting, previous: working)
        guard attention?.kind == .attentionRequired(.approval),
              attention?.subject.projectDisplayName == "Atoll",
              attention?.subject.origin?.terminalSessionIdentifier == "terminal-7" else {
            fatalError("Attention intents must contain only the sanitized handoff subject")
        }

        let repeatedWaiting = metadata(state: .waitingForApproval, at: startedAt.addingTimeInterval(20))
        guard adapter.intent(for: repeatedWaiting, previous: waiting) == nil else {
            fatalError("Repeated state must not produce duplicate presentation intents")
        }

        let completed = metadata(state: .recentlyCompleted, at: startedAt.addingTimeInterval(30))
        guard adapter.intent(for: completed, previous: waiting)?.kind == .completed else {
            fatalError("Completion must produce a content-free completion intent")
        }

        let failed = metadata(state: .failed, at: startedAt.addingTimeInterval(40))
        guard adapter.intent(for: failed, previous: working)?.kind == .failed else {
            fatalError("Failure must produce a content-free failure intent")
        }

        let ended = metadata(state: .ended, at: startedAt.addingTimeInterval(50))
        guard adapter.intent(for: ended, previous: working)?.kind == .dismissed else {
            fatalError("A terminal session must dismiss its future presentation")
        }
    }

    private static func metadata(state: SessionState, at date: Date) -> SessionMetadata {
        SessionMetadata(
            provider: .codex,
            sessionID: OpaqueSessionID("session-1")!,
            project: ProjectIdentity(displayName: "Atoll", workingDirectory: "/tmp/Atoll")!,
            origin: OriginNavigation(
                applicationBundleIdentifier: "com.apple.Terminal",
                terminalSessionIdentifier: "terminal-7",
                workspaceIdentifier: nil,
                paneIdentifier: nil,
                tty: "/dev/ttys007"
            ),
            state: state,
            startedAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: date,
            endedAt: state.isTerminal ? date : nil
        )
    }
}
