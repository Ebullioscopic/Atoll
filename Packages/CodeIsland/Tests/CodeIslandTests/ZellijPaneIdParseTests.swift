import XCTest
@testable import CodeIsland

/// `ZELLIJ_PANE_ID` env shape varies across Zellij versions: bare integer, "terminal_N"
/// prefix (Zellij's `PaneId::Display` impl), or "plugin_N" (plugin pane — agents don't
/// run there). The parser must accept the first two and reject the third / unknown shapes.
final class ZellijPaneIdParseTests: XCTestCase {
    func testParsesBareInteger() {
        XCTAssertEqual(TerminalActivator.parseZellijPaneId("5"), 5)
        XCTAssertEqual(TerminalActivator.parseZellijPaneId("0"), 0)
        XCTAssertEqual(TerminalActivator.parseZellijPaneId("12345"), 12345)
    }

    func testParsesTerminalPrefix() {
        XCTAssertEqual(TerminalActivator.parseZellijPaneId("terminal_5"), 5)
        XCTAssertEqual(TerminalActivator.parseZellijPaneId("terminal_0"), 0)
        XCTAssertEqual(TerminalActivator.parseZellijPaneId("terminal_42"), 42)
    }

    func testRejectsPluginPanes() {
        // Plugin panes host Zellij UI plugins (status bar, tab bar etc.), not user shells.
        // Agents never run there — returning nil makes the activator skip cleanly to fallback.
        XCTAssertNil(TerminalActivator.parseZellijPaneId("plugin_3"))
    }

    func testRejectsUnknownShapes() {
        XCTAssertNil(TerminalActivator.parseZellijPaneId(""))
        XCTAssertNil(TerminalActivator.parseZellijPaneId("not-a-number"))
        XCTAssertNil(TerminalActivator.parseZellijPaneId("terminal_"))     // prefix only, no number
        XCTAssertNil(TerminalActivator.parseZellijPaneId("terminal_abc"))  // prefix + non-numeric
        XCTAssertNil(TerminalActivator.parseZellijPaneId("foo_5"))         // unknown prefix
    }
}
