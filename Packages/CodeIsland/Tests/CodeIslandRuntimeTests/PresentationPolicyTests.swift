import CodeIslandCore
import Foundation
import XCTest
@testable import CodeIslandRuntime

final class PresentationPolicyTests: XCTestCase {
    func testDashboardOrdersWaitingWorkingThenRecentAndDropsEndedSessions() throws {
        let base = Date(timeIntervalSince1970: 1_000)
        let projection = CodeIslandDashboardProjection(sessions: [
            metadata(id: "ended", state: .ended, at: base.addingTimeInterval(50)),
            metadata(id: "working", state: .working, at: base.addingTimeInterval(20)),
            metadata(id: "recent", state: .recentlyCompleted, at: base.addingTimeInterval(30)),
            metadata(id: "waiting", state: .waitingForApproval, at: base.addingTimeInterval(10)),
        ])

        XCTAssertEqual(projection.items.map(\.sessionID.rawValue), ["waiting", "working", "recent"])
        XCTAssertEqual(projection.items.map(\.section), [.waiting, .working, .recent])
    }

    func testSystemWinsAndBlockingHandoffMayInterruptOnlyNoncriticalContent() {
        let policy = CodeIslandPresentationPolicy()
        let attention = intent(.attentionRequired(.approval))

        XCTAssertEqual(
            policy.disposition(
                for: attention,
                context: context(occupancy: .noncritical, originMatch: .different)
            ),
            .present(.attention(.approval))
        )
        XCTAssertEqual(
            policy.disposition(
                for: attention,
                context: context(occupancy: .systemOrPrivacy, originMatch: .different)
            ),
            .enqueue
        )
    }

    func testExactOriginSuppressionRequiresSessionSpecificEvidence() {
        let expected = OriginNavigation(
            applicationBundleIdentifier: "com.apple.Terminal",
            terminalSessionIdentifier: "terminal-7",
            workspaceIdentifier: nil,
            paneIdentifier: nil,
            tty: "/dev/ttys007"
        )
        let matcher = CodeIslandExactOriginMatcher()

        XCTAssertEqual(
            matcher.match(
                expected: expected,
                visible: CodeIslandVisibleOrigin(
                    applicationBundleIdentifier: "com.apple.Terminal",
                    terminalSessionIdentifier: nil,
                    workspaceIdentifier: nil,
                    paneIdentifier: nil,
                    tty: nil
                )
            ),
            .unknown
        )
        XCTAssertEqual(
            matcher.match(
                expected: expected,
                visible: CodeIslandVisibleOrigin(
                    applicationBundleIdentifier: "com.apple.Terminal",
                    terminalSessionIdentifier: "terminal-7",
                    workspaceIdentifier: nil,
                    paneIdentifier: nil,
                    tty: "/dev/ttys007"
                )
            ),
            .exactSession
        )

        XCTAssertEqual(
            matcher.match(
                expected: OriginNavigation(
                    applicationBundleIdentifier: nil,
                    terminalSessionIdentifier: nil,
                    workspaceIdentifier: nil,
                    paneIdentifier: "pane-2",
                    tty: nil
                ),
                visible: CodeIslandVisibleOrigin(
                    applicationBundleIdentifier: "com.example.Terminal",
                    terminalSessionIdentifier: nil,
                    workspaceIdentifier: nil,
                    paneIdentifier: "pane-2",
                    tty: nil
                )
            ),
            .unknown
        )

        let completion = intent(.completed)
        XCTAssertEqual(
            CodeIslandPresentationPolicy().disposition(
                for: completion,
                context: context(occupancy: .available, originMatch: .unknown)
            ),
            .present(.completed)
        )
        XCTAssertEqual(
            CodeIslandPresentationPolicy().disposition(
                for: completion,
                context: context(occupancy: .available, originMatch: .exactSession)
            ),
            .suppress
        )
    }

    private func context(
        occupancy: CodeIslandNotchOccupancy,
        originMatch: CodeIslandExactOriginMatch
    ) -> CodeIslandPresentationContext {
        CodeIslandPresentationContext(
            occupancy: occupancy,
            supportsSecondaryIndicator: false,
            originMatch: originMatch
        )
    }

    private func intent(_ kind: CodeIslandActivityIntentKind) -> CodeIslandActivityIntent {
        let metadata = metadata(
            id: "session-1",
            state: .working,
            at: Date(timeIntervalSince1970: 1_000)
        )
        return CodeIslandActivityIntent(
            kind: kind,
            subject: CodeIslandActivitySubject(metadata: metadata),
            occurredAt: metadata.updatedAt
        )
    }

    private func metadata(id: String, state: SessionState, at date: Date) -> SessionMetadata {
        SessionMetadata(
            provider: .codex,
            sessionID: OpaqueSessionID(id)!,
            project: ProjectIdentity(displayName: "Atoll")!,
            origin: nil,
            state: state,
            startedAt: Date(timeIntervalSince1970: 900),
            updatedAt: date,
            endedAt: state.isTerminal ? date : nil
        )
    }
}
