import XCTest
import CodeIslandCore
@testable import CodeIsland

/// Guards the seams between `ClaudeConfigPaths` (CodeIslandCore) and the app targets
/// that depend on it. Both contracts below are enforced only by convention in the
/// source, so a rename or a dropped override would otherwise fail silently at runtime.
final class ClaudeConfigPathsWiringTests: XCTestCase {

    /// The preference key literal is duplicated: `SettingsKey.claudeConfigDir` drives the
    /// @AppStorage field, `ClaudeConfigPaths.preferenceKey` is what the resolver reads.
    /// If they drift, the Settings field silently stops affecting resolution — the user
    /// types a path, the UI accepts it, and nothing changes.
    func testSettingsKeyMatchesResolverPreferenceKey() {
        XCTAssertEqual(SettingsKey.claudeConfigDir, ClaudeConfigPaths.preferenceKey)
    }

    /// The Claude CLIConfig carries `configPath: "settings.json"` — correct ONLY because
    /// `rootOverride` supplies the config dir. Drop the override and `fullPath` silently
    /// becomes `~/settings.json`: it would not error, it would write hooks into the
    /// user's home directory. Pin the resolved path to the resolver's own answer.
    func testClaudeConfigPathResolvesThroughRootOverride() throws {
        let claude = try XCTUnwrap(
            ConfigInstaller.allCLIs.first { $0.source == "claude" },
            "built-in Claude CLIConfig is missing")

        XCTAssertEqual(claude.fullPath, ClaudeConfigPaths.settingsPath())
        XCTAssertEqual(claude.dirPath, ClaudeConfigPaths.configDir())
        XCTAssertNotEqual(
            claude.fullPath, NSHomeDirectory() + "/settings.json",
            "rootOverride was dropped — hooks would be written to the home directory")
    }
}
