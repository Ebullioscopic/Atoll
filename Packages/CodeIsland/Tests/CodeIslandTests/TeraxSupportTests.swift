import XCTest
@testable import CodeIsland
@testable import CodeIslandCore

/// Terax (app.crynta.terax) support. Terax is a native single-window terminal whose
/// tabs live inside a webview; it sets no TERM_PROGRAM and ships no URL scheme,
/// AppleScript dictionary, focus CLI, or native tab shortcut, so — like Superset —
/// click-to-jump can only bring its window forward (app-level activation).
final class TeraxSupportTests: XCTestCase {

    private func makeSession(termBundleId: String?, source: String) -> SessionSnapshot {
        var session = SessionSnapshot()
        session.source = source
        session.termBundleId = termBundleId
        return session
    }

    /// The core fix: Terax must be a recognized terminal, otherwise its bundle id
    /// falls through to detectRunningTerminal() and the click jumps to the wrong app.
    func testTeraxIsRecognizedTerminal() {
        XCTAssertTrue(
            TerminalActivator.knownTerminals.contains { $0.bundleId == "app.crynta.terax" },
            "Terax must be in knownTerminals so click-to-jump routes to it deterministically"
        )
    }

    /// Terax hosts a CLI; it is not an IDE integrated terminal and not native-app mode.
    func testTeraxClaudeSessionClassification() {
        let session = makeSession(termBundleId: "app.crynta.terax", source: "claude")
        XCTAssertFalse(session.isIDETerminal)
        XCTAssertFalse(session.isNativeAppMode)
    }
}
