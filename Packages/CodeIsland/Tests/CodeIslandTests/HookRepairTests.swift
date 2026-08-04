import XCTest
@testable import CodeIsland

/// Regression coverage for #182: verifyAndRepair must respect a user who
/// deleted some hook events by hand instead of silently re-adding them. The
/// decision is made by `ConfigInstaller.shouldPreservePartialHooks`.
final class HookRepairTests: XCTestCase {

    // Shaped like CLIConfig.events: (eventName, timeout, async).
    private let events: [(String, Int, Bool)] = [
        ("PreToolUse", 0, false),
        ("PostToolUse", 0, false),
        ("PermissionRequest", 0, false),
    ]

    private func ourEntry() -> [String: Any] {
        ["hooks": [["type": "command", "command": "~/.codeisland/codeisland-bridge"]]]
    }

    private func foreignEntry() -> [String: Any] {
        ["hooks": [["type": "command", "command": "/usr/bin/true"]]]
    }

    func testNeverInstalledIsNotPreserved() {
        // Nothing of ours present → this is a fresh/wiped config, install it.
        XCTAssertFalse(ConfigInstaller.shouldPreservePartialHooks(hooks: [:], events: events))
    }

    func testUserKeptSubsetIsPreserved() {
        // User deleted PostToolUse/PermissionRequest, kept PreToolUse.
        let hooks: [String: Any] = ["PreToolUse": [ourEntry()]]
        XCTAssertTrue(ConfigInstaller.shouldPreservePartialHooks(hooks: hooks, events: events))
    }

    func testCompleteInstallIsPreserved() {
        let hooks: [String: Any] = [
            "PreToolUse": [ourEntry()],
            "PostToolUse": [ourEntry()],
            "PermissionRequest": [ourEntry()],
        ]
        XCTAssertTrue(ConfigInstaller.shouldPreservePartialHooks(hooks: hooks, events: events))
    }

    func testForeignOnlyHooksAreNotPreserved() {
        // Only third-party hooks present → ours still need to be installed.
        let hooks: [String: Any] = ["PreToolUse": [foreignEntry()]]
        XCTAssertFalse(ConfigInstaller.shouldPreservePartialHooks(hooks: hooks, events: events))
    }

    func testStaleAsyncEntryForcesRepair() {
        // Our hook present but carries a legacy "async" key → must be rewritten.
        let staleEntry: [String: Any] = [
            "hooks": [["type": "command", "command": "~/.codeisland/codeisland-bridge", "async": true]]
        ]
        let hooks: [String: Any] = ["PreToolUse": [staleEntry]]
        XCTAssertFalse(ConfigInstaller.shouldPreservePartialHooks(hooks: hooks, events: events))
    }
}
