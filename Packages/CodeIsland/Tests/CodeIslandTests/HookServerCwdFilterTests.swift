import XCTest
@testable import CodeIsland

/// Coverage for the cwd-substring blocklist that powers Settings → Behavior →
/// "Ignore Hooks From Paths" (#125). The matcher itself is a tiny pure function
/// extracted from `HookServer.eventMatchesExcludedCwd` so it can be exercised
/// without spinning up the whole socket / SettingsManager singleton.
final class HookServerCwdFilterTests: XCTestCase {

    func testEmptyPatternsCSVNeverMatches() {
        XCTAssertFalse(HookServer.cwdMatchesAnyPattern("/Users/me/proj", patternsCSV: ""))
        XCTAssertFalse(HookServer.cwdMatchesAnyPattern("", patternsCSV: ""))
    }

    func testWhitespaceOnlyPatternsAreIgnored() {
        // A user might accidentally type ", , ," — none of those should ever match.
        XCTAssertFalse(HookServer.cwdMatchesAnyPattern("/anything", patternsCSV: " , ,  "))
    }

    func testSingleSubstringMatchesWhenCwdContainsIt() {
        XCTAssertTrue(HookServer.cwdMatchesAnyPattern(
            "/Users/me/proj/.claude-mem/cache",
            patternsCSV: ".claude-mem"
        ))
    }

    func testSingleSubstringMissesWhenAbsent() {
        XCTAssertFalse(HookServer.cwdMatchesAnyPattern(
            "/Users/me/proj/src",
            patternsCSV: ".claude-mem"
        ))
    }

    func testAnyOfMultipleSubstringsTriggersMatch() {
        XCTAssertTrue(HookServer.cwdMatchesAnyPattern(
            "/Users/me/.cache/agents/run/123",
            patternsCSV: ".claude-mem,.cache/agents,.foo/bar"
        ))
    }

    func testTrimsWhitespaceAroundEntries() {
        // " .claude-mem " should still match when cwd contains ".claude-mem".
        XCTAssertTrue(HookServer.cwdMatchesAnyPattern(
            "/Users/me/.claude-mem/x",
            patternsCSV: " .claude-mem , .other "
        ))
    }

    func testEmptyEntriesBetweenCommasAreNotTreatedAsMatchAll() {
        // ",foo," contains an empty token between commas — it must NOT match
        // every cwd just because the entry trimmed to "" (would be a footgun).
        XCTAssertFalse(HookServer.cwdMatchesAnyPattern(
            "/Users/me/proj",
            patternsCSV: ",foo,"
        ))
    }

    func testIsSubstringMatchNotPrefixOrSuffix() {
        // Documents the contract: the match is `String.contains` — substring
        // anywhere in the cwd, not a prefix/suffix or glob. Keeps the spec
        // explicit so a future "let's switch to globs" doesn't silently break.
        XCTAssertTrue(HookServer.cwdMatchesAnyPattern("/a/b/foo/c", patternsCSV: "foo"))
        XCTAssertTrue(HookServer.cwdMatchesAnyPattern("foo/a/b", patternsCSV: "foo"))
        XCTAssertTrue(HookServer.cwdMatchesAnyPattern("/a/b/foo", patternsCSV: "foo"))
    }
}
