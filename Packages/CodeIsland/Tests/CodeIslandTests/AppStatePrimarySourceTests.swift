import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class AppStatePrimarySourceTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SettingsKey.defaultSource)
        super.tearDown()
    }

    /// #149 regression: when sessions exist but none are actively working
    /// (all .idle), the primary source / mascot should reflect the user's
    /// configured default rather than echoing whichever source spoke last.
    func testIdleSessionsRespectUserDefaultMascot() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "claude"
        session.status = .idle
        session.lastActivity = Date()
        appState.sessions["s1"] = session

        appState.refreshDerivedState()

        XCTAssertEqual(appState.primarySource, "codex",
            "All-idle sessions must fall back to user-configured default mascot (#149)")
    }

    /// Sanity: an active session always wins over the default mascot — we
    /// don't want to mute "what's actually running right now" just because
    /// the user picked a preferred idle mascot.
    func testActiveSessionWinsOverUserDefaultMascot() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "claude"
        session.status = .running
        session.lastActivity = Date()
        appState.sessions["s1"] = session

        appState.refreshDerivedState()

        XCTAssertEqual(appState.primarySource, "claude",
            "Active work overrides the user default — show what's actually running")
    }

    /// #102 still holds: with no sessions at all, default mascot wins.
    func testEmptyStateRespectsUserDefaultMascot() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        appState.refreshDerivedState()

        XCTAssertEqual(appState.primarySource, "codex")
    }

    /// Mixed: one active, one idle — active source wins regardless of default.
    func testMixedActiveAndIdleSessionsUseActiveSource() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var idleSession = SessionSnapshot()
        idleSession.source = "claude"
        idleSession.status = .idle
        idleSession.lastActivity = Date()
        appState.sessions["s1"] = idleSession

        var runningSession = SessionSnapshot()
        runningSession.source = "gemini"
        runningSession.status = .running
        runningSession.lastActivity = Date()
        appState.sessions["s2"] = runningSession

        appState.refreshDerivedState()

        XCTAssertEqual(appState.primarySource, "gemini",
            "When at least one session is running, surface that source not the user default")
    }

    func testAppleCompanionPayloadIncludesMultipleSessionsByPriority() {
        let appState = AppState()
        let now = Date()

        var codex = SessionSnapshot()
        codex.source = "codex"
        codex.status = .processing
        codex.currentTool = "Read"
        codex.cwd = "/tmp/CodeIsland"
        codex.lastActivity = now
        codex.addRecentMessage(ChatMessage(isUser: false, text: "正在检查 StandBy 多会话展示"))
        appState.sessions["codex-1"] = codex

        var claude = SessionSnapshot()
        claude.source = "claude"
        claude.status = .waitingQuestion
        claude.currentTool = "AskUserQuestion"
        claude.cwd = "/tmp/workspace"
        claude.lastActivity = now.addingTimeInterval(-3)
        claude.addRecentMessage(ChatMessage(isUser: true, text: "你想写什么类型的小说？"))
        appState.sessions["claude-1"] = claude

        var gemini = SessionSnapshot()
        gemini.source = "gemini"
        gemini.status = .idle
        gemini.cwd = "/tmp/notes"
        gemini.lastActivity = now.addingTimeInterval(-1)
        appState.sessions["gemini-1"] = gemini

        appState.refreshDerivedState()
        let payload = appState.appleCompanionStatePayload(sequence: 99)

        XCTAssertEqual(payload.sessions.map(\.sessionId), ["claude-1", "codex-1", "gemini-1"])
        XCTAssertEqual(payload.sessions[0].status, .waitingQuestion)
        XCTAssertEqual(payload.sessions[1].source, "codex")
        XCTAssertEqual(payload.sessions[1].message, "正在检查 StandBy 多会话展示")
    }

    // MARK: - Buddy (ESP32) frame alignment with island display

    /// When a session is idle, esp32DisplayFrame must use the user-configured
    /// default mascot — matching the island's CompactLeftWing.displaySource.
    func testESP32DisplayFrameUsesDefaultSourceWhenIdle() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "cursor"
        session.status = .idle
        session.lastActivity = Date()
        appState.sessions["s1"] = session
        appState.refreshDerivedState()

        let frame = appState.esp32DisplayFrame(session: session)
        XCTAssertEqual(frame.mascot, .codex,
            "Idle session must show user-configured default mascot on Buddy, not the session source")
        XCTAssertEqual(frame.status, .idle)
    }

    /// When a session is actively running, esp32DisplayFrame must use the
    /// session's own source — not the user default.
    func testESP32DisplayFrameUsesSessionSourceWhenActive() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "cursor"
        session.status = .running
        session.lastActivity = Date()
        appState.sessions["s1"] = session
        appState.refreshDerivedState()

        let frame = appState.esp32DisplayFrame(session: session)
        XCTAssertEqual(frame.mascot, .cursor,
            "Active session must show its own source on Buddy, not the user default")
        XCTAssertEqual(frame.status, .running)
    }

    /// With no sessions, esp32DisplayFrame falls back to the user default.
    func testESP32DisplayFrameFallsBackToDefaultWhenNoSession() {
        UserDefaults.standard.set("gemini", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        appState.refreshDerivedState()

        let frame = appState.esp32DisplayFrame(session: nil)
        XCTAssertEqual(frame.mascot, .gemini,
            "No-session state must show user-configured default mascot on Buddy")
        XCTAssertEqual(frame.status, .idle)
    }

    func testESP32StatsUseGlobalToolCountAcrossSessions() {
        let appState = AppState()

        var first = SessionSnapshot()
        first.recordTool("Read", description: nil, success: true, agentType: nil, maxHistory: 20)
        first.recordTool("Edit", description: nil, success: true, agentType: nil, maxHistory: 20)
        appState.sessions["s1"] = first

        var second = SessionSnapshot()
        second.recordTool("Bash", description: nil, success: false, agentType: nil, maxHistory: 20)
        appState.sessions["s2"] = second
        appState.refreshDerivedState()

        let stats = appState.esp32StatsPayload(session: second)
        XCTAssertEqual(stats.toolCallCount, 3)
    }

    func testESP32DisplayIdentityStaysStableAcrossStatusAndDefaultMascotChanges() {
        UserDefaults.standard.set("codex", forKey: SettingsKey.defaultSource)

        let appState = AppState()
        var session = SessionSnapshot()
        session.source = "cursor"
        session.status = .running
        appState.sessions["s1"] = session
        appState.activeSessionId = "s1"

        XCTAssertEqual(appState.esp32DisplayIdentity(), "session:s1")

        session.status = .idle
        appState.sessions["s1"] = session

        XCTAssertEqual(appState.esp32DisplayIdentity(), "session:s1",
            "Completion/error animations should still be scoped to the same session even when idle display falls back to the default mascot")
    }

    func testESP32DisplayIdentityChangesWhenDisplayedSessionChanges() {
        let appState = AppState()
        appState.sessions["s1"] = SessionSnapshot()
        appState.sessions["s2"] = SessionSnapshot()

        appState.activeSessionId = "s1"
        XCTAssertEqual(appState.esp32DisplayIdentity(), "session:s1")

        appState.activeSessionId = "s2"
        XCTAssertEqual(appState.esp32DisplayIdentity(), "session:s2")
    }
}
