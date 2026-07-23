import XCTest
@testable import CodeIslandCore

final class ClaudeConfigPathsTests: XCTestCase {
    private let home = "/Users/tester"

    /// Nothing exists anywhere → the historical `~/.claude` default.
    func testFallsBackToDotClaudeWhenNothingSet() {
        let result = ClaudeConfigPaths.resolve(
            preference: nil, environment: nil, homeDir: home, directoryExists: { _ in false })
        XCTAssertEqual(result, "/Users/tester/.claude")
    }

    /// The regression this resolver exists for: a user with a custom CLAUDE_CONFIG_DIR
    /// was silently scanned at ~/.claude, which is empty, so no sessions ever appeared.
    func testEnvironmentVariableWins() {
        let result = ClaudeConfigPaths.resolve(
            preference: nil,
            environment: "/Users/tester/.config/claude-code",
            homeDir: home,
            directoryExists: { _ in false })
        XCTAssertEqual(result, "/Users/tester/.config/claude-code")
    }

    /// The preference must outrank the environment — it is the only channel that
    /// survives a Finder launch, where no shell environment is inherited.
    func testPreferenceOutranksEnvironment() {
        let result = ClaudeConfigPaths.resolve(
            preference: "/explicit/dir",
            environment: "/env/dir",
            homeDir: home,
            directoryExists: { _ in true })
        XCTAssertEqual(result, "/explicit/dir")
    }

    /// With no preference and no environment (the Finder case), a populated
    /// ~/.config/claude-code is auto-detected instead of defaulting to ~/.claude.
    func testProbesXDGDirectoryWhenPopulated() {
        let result = ClaudeConfigPaths.resolve(
            preference: nil, environment: nil, homeDir: home,
            directoryExists: { $0 == "/Users/tester/.config/claude-code/projects" })
        XCTAssertEqual(result, "/Users/tester/.config/claude-code")
    }

    /// Both XDG spellings exist in the wild; ~/.config/claude (the ccusage-style
    /// default) is probed first and wins when both are populated.
    func testProbesConfigClaudeSpellingFirst() {
        let result = ClaudeConfigPaths.resolve(
            preference: nil, environment: nil, homeDir: home,
            directoryExists: { $0 == "/Users/tester/.config/claude/projects"
                       || $0 == "/Users/tester/.config/claude-code/projects" })
        XCTAssertEqual(result, "/Users/tester/.config/claude")
    }

    /// An empty ~/.config/claude-code (created by some other tool) must not shadow
    /// a real ~/.claude.
    func testEmptyXDGDirectoryDoesNotShadowDotClaude() {
        let result = ClaudeConfigPaths.resolve(
            preference: nil, environment: nil, homeDir: home,
            directoryExists: { $0 == "/Users/tester/.config/claude-code" })
        XCTAssertEqual(result, "/Users/tester/.claude")
    }

    /// Claude Code has no XDG rung — it reads $CLAUDE_CONFIG_DIR or ~/.claude. So when
    /// BOTH are populated and nothing points elsewhere, ~/.claude must win, or a stale
    /// XDG dir would silently repoint us away from what Claude Code actually reads.
    func testLiveDotClaudeOutranksPopulatedXDGDirectory() {
        let result = ClaudeConfigPaths.resolve(
            preference: nil, environment: nil, homeDir: home,
            directoryExists: { $0 == "/Users/tester/.claude/projects"
                       || $0 == "/Users/tester/.config/claude-code/projects" })
        XCTAssertEqual(result, "/Users/tester/.claude")
    }

    /// A settings.json alone must NOT mark a dir live — CodeIsland's own hook installer
    /// writes that file, so counting it would let us manufacture the signal we read back.
    func testSettingsJsonAloneDoesNotMarkDirectoryLive() {
        let result = ClaudeConfigPaths.resolve(
            preference: nil, environment: nil, homeDir: home,
            directoryExists: { $0 == "/Users/tester/.claude/settings.json"
                       || $0 == "/Users/tester/.config/claude-code/projects" })
        XCTAssertEqual(result, "/Users/tester/.config/claude-code")
    }

    /// A typo'd or relative value must fall through to auto-detect rather than being
    /// taken literally — the hook installer would otherwise create the bogus directory
    /// and report success while Claude Code read somewhere else.
    func testUnusableValuesFallThroughToAutoDetect() {
        XCTAssertNil(ClaudeConfigPaths.normalized("claude-config", homeDir: home))
        XCTAssertNil(ClaudeConfigPaths.normalized("./claude", homeDir: home))
        XCTAssertNil(ClaudeConfigPaths.normalized("/", homeDir: home))

        // A bad preference must not win — resolution continues down the chain.
        let result = ClaudeConfigPaths.resolve(
            preference: "relative/typo", environment: nil, homeDir: home,
            directoryExists: { $0 == "/Users/tester/.config/claude-code/projects" })
        XCTAssertEqual(result, "/Users/tester/.config/claude-code")
    }

    /// A stray regular FILE named `projects` must not mark a config dir live. This
    /// exercises the REAL filesystem probe against a real temp tree — asserting it via
    /// the injected `directoryExists` would prove nothing, since the injection is
    /// precisely what abstracts the file-vs-directory distinction away.
    func testRegularFileNamedProjectsIsNotTreatedAsLive() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ccp-" + UUID().uuidString)
        let asDir = root.appendingPathComponent("dir")
        let asFile = root.appendingPathComponent("file")
        try fm.createDirectory(at: asDir.appendingPathComponent("projects"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: asFile, withIntermediateDirectories: true)
        try Data("not a directory".utf8)
            .write(to: asFile.appendingPathComponent("projects"))
        defer { try? fm.removeItem(at: root) }

        XCTAssertTrue(ClaudeConfigPaths.isLiveConfigDir(
            asDir.path, directoryExists: ClaudeConfigPaths.defaultDirectoryExists))
        XCTAssertFalse(ClaudeConfigPaths.isLiveConfigDir(
            asFile.path, directoryExists: ClaudeConfigPaths.defaultDirectoryExists),
            "a regular file named projects must not mark the dir live")
    }

    func testEmptyAndWhitespaceValuesAreIgnored() {
        XCTAssertNil(ClaudeConfigPaths.normalized("", homeDir: home))
        XCTAssertNil(ClaudeConfigPaths.normalized("   ", homeDir: home))
        XCTAssertNil(ClaudeConfigPaths.normalized(nil, homeDir: home))
    }

    func testTildeExpansionAndTrailingSlashes() {
        XCTAssertEqual(ClaudeConfigPaths.normalized("~", homeDir: home), home)
        XCTAssertEqual(
            ClaudeConfigPaths.normalized("~/.config/claude-code", homeDir: home),
            "/Users/tester/.config/claude-code")
        XCTAssertEqual(ClaudeConfigPaths.normalized("/a/b///", homeDir: home), "/a/b")
        XCTAssertEqual(ClaudeConfigPaths.normalized("  /a/b  ", homeDir: home), "/a/b")
    }

    /// CLAUDE_CONFIG_DIR is a single path, not a PATH-style list. `:` is legal in an
    /// APFS filename, so splitting on it would silently truncate a valid directory.
    func testColonIsPreservedAsPartOfPath() {
        XCTAssertEqual(
            ClaudeConfigPaths.normalized("/Users/tester/AI:ML/claude", homeDir: home),
            "/Users/tester/AI:ML/claude")
    }

    /// Claude Code normalizes its config path to NFC; matching that keeps a decomposed
    /// path (what some macOS APIs return) resolving to the same directory.
    func testUnicodePathsAreNormalizedToNFC() {
        let decomposed = "/Users/tester/Cafe\u{0301}/claude"   // e + combining acute
        let precomposed = "/Users/tester/Caf\u{00E9}/claude"   // é

        let result = try? XCTUnwrap(ClaudeConfigPaths.normalized(decomposed, homeDir: home))

        // Compare BYTES, not Strings. Swift's == on String uses canonical equivalence,
        // so `decomposed == precomposed` is already true and an XCTAssertEqual here
        // would pass even if the normalization were deleted entirely.
        XCTAssertEqual(Array((result ?? "").utf8), Array(precomposed.utf8))
        XCTAssertNotEqual(Array((result ?? "").utf8), Array(decomposed.utf8))
    }

    func testDisplayPathCollapsesHomePrefix() {
        XCTAssertEqual(
            ClaudeConfigPaths.displayPath("/Users/tester/.claude/settings.json", homeDir: home),
            "~/.claude/settings.json")
        XCTAssertEqual(
            ClaudeConfigPaths.displayPath("/opt/elsewhere/settings.json", homeDir: home),
            "/opt/elsewhere/settings.json")
        // A different user's home that merely shares a prefix must not be collapsed.
        XCTAssertEqual(
            ClaudeConfigPaths.displayPath("/Users/tester2/.claude", homeDir: home),
            "/Users/tester2/.claude")
    }
}
