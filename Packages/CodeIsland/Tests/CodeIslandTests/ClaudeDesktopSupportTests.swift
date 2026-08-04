import XCTest
@testable import CodeIsland
@testable import CodeIslandCore

/// #211 — Claude Code Desktop support. Local Code-tab sessions run the same
/// engine as the CLI and fire the same ~/.claude/settings.json hooks; their
/// hook subprocesses inherit __CFBundleIdentifier=com.anthropic.claudefordesktop.
final class ClaudeDesktopSupportTests: XCTestCase {

    private func makeSession(termBundleId: String?, source: String) -> SessionSnapshot {
        var session = SessionSnapshot()
        session.source = source
        session.termBundleId = termBundleId
        return session
    }

    func testDesktopClaudeSessionIsNativeAppMode() {
        let session = makeSession(termBundleId: "com.anthropic.claudefordesktop", source: "claude")
        XCTAssertTrue(session.isNativeAppMode)
        XCTAssertFalse(session.isIDETerminal)
    }

    func testTerminalClaudeSessionIsNotNativeAppMode() {
        let session = makeSession(termBundleId: "com.googlecode.iterm2", source: "claude")
        XCTAssertFalse(session.isNativeAppMode)
    }

    func testNonClaudeSourceInsideClaudeDesktopIsNotNativeAppMode() {
        // e.g. a Codex CLI launched from some embedded surface must not be
        // claimed by the Claude Desktop mapping.
        let session = makeSession(termBundleId: "com.anthropic.claudefordesktop", source: "codex")
        XCTAssertFalse(session.isNativeAppMode)
    }

    func testClickJumpDoesNotStealTerminalClaudeSessions() {
        // The source→bundle fallback list must NOT contain claude: most claude
        // sessions are terminal CLI runs, and the fallback would redirect their
        // click-to-jump to the desktop app whenever it happens to be running.
        XCTAssertNil(TerminalActivator.sourceToNativeAppBundleId["claude"])
    }
}
