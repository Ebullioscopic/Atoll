import CodeIslandCore
import CodeIslandRuntime
import CodeIslandUI
import Foundation

@main
struct CodeIslandPhaseSixPresentationRegression {
    static func main() {
        dashboardOrdersOnlyDisplayableMetadata()
        dashboardStateCarriesOnlyProjectedRows()
        presentationPolicyRespectsAtollOccupancy()
        exactOriginSuppressionRequiresAPositiveSessionMatch()
        exactOriginMatcherRejectsApplicationOnlyMatches()
        queuedPopOutsHaveDeterministicPriority()
    }

    private static func exactOriginMatcherRejectsApplicationOnlyMatches() {
        let expected = OriginNavigation(
            applicationBundleIdentifier: "com.apple.Terminal",
            terminalSessionIdentifier: "terminal-7",
            workspaceIdentifier: "workspace-1",
            paneIdentifier: "pane-2",
            tty: "/dev/ttys007"
        )
        let matcher = CodeIslandExactOriginMatcher()

        guard matcher.match(
            expected: expected,
            visible: CodeIslandVisibleOrigin(
                applicationBundleIdentifier: "com.apple.Terminal",
                terminalSessionIdentifier: "terminal-7",
                workspaceIdentifier: "workspace-1",
                paneIdentifier: "pane-2",
                tty: "/dev/ttys007"
            )
        ) == .exactSession else {
            fatalError("Matching terminal handles must produce a positive exact-session match")
        }

        guard matcher.match(
            expected: expected,
            visible: CodeIslandVisibleOrigin(
                applicationBundleIdentifier: "com.apple.Terminal",
                terminalSessionIdentifier: nil,
                workspaceIdentifier: nil,
                paneIdentifier: nil,
                tty: nil
            )
        ) == .unknown else {
            fatalError("A frontmost application without a session handle must remain uncertain")
        }

        guard matcher.match(
            expected: expected,
            visible: CodeIslandVisibleOrigin(
                applicationBundleIdentifier: "com.apple.Terminal",
                terminalSessionIdentifier: "terminal-8",
                workspaceIdentifier: "workspace-1",
                paneIdentifier: "pane-3",
                tty: "/dev/ttys008"
            )
        ) == .different else {
            fatalError("A visible tab or pane belonging to another session must not suppress")
        }

        guard matcher.match(
            expected: expected,
            visible: CodeIslandVisibleOrigin(
                applicationBundleIdentifier: "com.googlecode.iterm2",
                terminalSessionIdentifier: "terminal-7",
                workspaceIdentifier: "workspace-1",
                paneIdentifier: "pane-2",
                tty: "/dev/ttys007"
            )
        ) == .different else {
            fatalError("A different frontmost application must not be treated as the session origin")
        }

        let paneOnly = OriginNavigation(
            applicationBundleIdentifier: nil,
            terminalSessionIdentifier: nil,
            workspaceIdentifier: nil,
            paneIdentifier: "pane-2",
            tty: nil
        )
        guard matcher.match(
            expected: paneOnly,
            visible: CodeIslandVisibleOrigin(
                applicationBundleIdentifier: "com.example.Terminal",
                terminalSessionIdentifier: nil,
                workspaceIdentifier: nil,
                paneIdentifier: "pane-2",
                tty: nil
            )
        ) == .unknown else {
            fatalError("A non-global pane handle requires matching application identity")
        }
    }

    private static func dashboardStateCarriesOnlyProjectedRows() {
        let projection = CodeIslandDashboardProjection(sessions: [
            metadata(
                id: "working",
                state: .working,
                updatedAt: Date(timeIntervalSince1970: 1_000)
            ),
        ])
        let state = CodeIslandDashboardState.sessions(
            provider: .codex,
            items: projection.items
        )
        guard state.provider == .codex,
              !state.requiresActivation,
              state.items.map(\.sessionID.rawValue) == ["working"] else {
            fatalError("The active dashboard must carry only projected metadata rows")
        }
    }

    private static func dashboardOrdersOnlyDisplayableMetadata() {
        let base = Date(timeIntervalSince1970: 1_000)
        let sessions = [
            metadata(id: "ended", state: .ended, updatedAt: base.addingTimeInterval(50)),
            metadata(id: "working-new", state: .working, updatedAt: base.addingTimeInterval(40)),
            metadata(id: "completed", state: .recentlyCompleted, updatedAt: base.addingTimeInterval(60)),
            metadata(id: "waiting-new", state: .waitingForQuestion, updatedAt: base.addingTimeInterval(30)),
            metadata(id: "working-old", state: .working, updatedAt: base.addingTimeInterval(20)),
            metadata(id: "waiting-old", state: .waitingForApproval, updatedAt: base.addingTimeInterval(10)),
        ]

        let projection = CodeIslandDashboardProjection(sessions: sessions)
        let orderedIDs = projection.items.map(\.sessionID.rawValue)
        guard orderedIDs == [
            "waiting-old", "waiting-new", "working-new", "working-old", "completed",
        ] else {
            fatalError("Dashboard must order waiting, working, then recent sessions deterministically: \(orderedIDs)")
        }
        guard projection.items.map(\.section) == [
            .waiting, .waiting, .working, .working, .recent,
        ] else {
            fatalError("Dashboard sections must be derived only from sanitized session state")
        }
    }

    private static func presentationPolicyRespectsAtollOccupancy() {
        let policy = CodeIslandPresentationPolicy()
        let working = intent(.processing)

        guard policy.disposition(
            for: working,
            context: .init(occupancy: .available, supportsSecondaryIndicator: false, originMatch: .unknown)
        ) == .present(.compact(isSecondary: false)) else {
            fatalError("Processing should use the compact activity when Atoll is free")
        }

        guard policy.disposition(
            for: working,
            context: .init(occupancy: .noncritical, supportsSecondaryIndicator: true, originMatch: .unknown)
        ) == .present(.compact(isSecondary: true)) else {
            fatalError("Processing should share only a layout that explicitly supports a secondary indicator")
        }

        guard policy.disposition(
            for: working,
            context: .init(occupancy: .noncritical, supportsSecondaryIndicator: false, originMatch: .unknown)
        ) == .stateOnly else {
            fatalError("Processing must yield when the occupied layout cannot coexist")
        }

        let completion = intent(.completed, sessionID: "completed")
        guard policy.disposition(
            for: completion,
            context: .init(occupancy: .noncritical, supportsSecondaryIndicator: false, originMatch: .different)
        ) == .enqueue else {
            fatalError("Completion must queue behind media, timers, and recording")
        }

        let attention = intent(.attentionRequired(.approval), sessionID: "waiting")
        guard policy.disposition(
            for: attention,
            context: .init(occupancy: .noncritical, supportsSecondaryIndicator: false, originMatch: .different)
        ) == .present(.attention(.approval)) else {
            fatalError("A blocking handoff may interrupt noncritical Atoll content")
        }
        guard policy.disposition(
            for: attention,
            context: .init(occupancy: .systemOrPrivacy, supportsSecondaryIndicator: false, originMatch: .different)
        ) == .enqueue else {
            fatalError("System and privacy presentation must win over blocking agent handoffs")
        }
    }

    private static func exactOriginSuppressionRequiresAPositiveSessionMatch() {
        let policy = CodeIslandPresentationPolicy()
        let completion = intent(.completed)

        for match in [CodeIslandExactOriginMatch.different, .unknown] {
            let result = policy.disposition(
                for: completion,
                context: .init(occupancy: .available, supportsSecondaryIndicator: false, originMatch: match)
            )
            guard result == .present(.completed) else {
                fatalError("An application-level or uncertain origin match must not suppress completion")
            }
        }

        guard policy.disposition(
            for: completion,
            context: .init(occupancy: .available, supportsSecondaryIndicator: false, originMatch: .exactSession)
        ) == .suppress else {
            fatalError("Only a positive exact-session match may suppress a completion pop-out")
        }

        let attention = intent(.attentionRequired(.approval))
        guard policy.disposition(
            for: attention,
            context: .init(occupancy: .available, supportsSecondaryIndicator: false, originMatch: .exactSession)
        ) == .suppress else {
            fatalError("An already-visible exact origin must not make Atoll select Code Island")
        }
    }

    private static func queuedPopOutsHaveDeterministicPriority() {
        let base = Date(timeIntervalSince1970: 2_000)
        let queued = [
            intent(.sessionStarted, sessionID: "start", at: base),
            intent(.completed, sessionID: "complete", at: base.addingTimeInterval(1)),
            intent(.failed, sessionID: "failure", at: base.addingTimeInterval(2)),
            intent(.attentionRequired(.approval), sessionID: "attention", at: base.addingTimeInterval(3)),
        ]
        let ordered = CodeIslandPresentationPolicy().orderedQueue(queued)
        guard ordered.map(\.subject.sessionID.rawValue) == [
            "attention", "failure", "complete", "start",
        ] else {
            fatalError("Queued handoffs and pop-outs must have stable semantic priority")
        }
    }

    private static func intent(
        _ kind: CodeIslandActivityIntentKind,
        sessionID: String = "session-1",
        at date: Date = Date(timeIntervalSince1970: 1_000)
    ) -> CodeIslandActivityIntent {
        CodeIslandActivityIntent(
            kind: kind,
            subject: CodeIslandActivitySubject(metadata: metadata(id: sessionID, state: .working, updatedAt: date)),
            occurredAt: date
        )
    }

    private static func metadata(
        id: String,
        state: SessionState,
        updatedAt: Date
    ) -> SessionMetadata {
        SessionMetadata(
            provider: .codex,
            sessionID: OpaqueSessionID(id)!,
            project: ProjectIdentity(displayName: "Atoll", workingDirectory: "/tmp/Atoll")!,
            origin: OriginNavigation(
                applicationBundleIdentifier: "com.apple.Terminal",
                terminalSessionIdentifier: "terminal-7",
                workspaceIdentifier: nil,
                paneIdentifier: nil,
                tty: "/dev/ttys007"
            ),
            state: state,
            startedAt: Date(timeIntervalSince1970: 900),
            updatedAt: updatedAt,
            endedAt: state.isTerminal ? updatedAt : nil
        )
    }
}
