import XCTest
@testable import CodeIslandCore

final class SessionSnapshotTitleTests: XCTestCase {
    /// Synthetic paths — tests must not assume clone location or OS username.
    private let fixtureLeaf = "myproject"
    private var fixtureCwd: String { "/tmp/\(fixtureLeaf)" }
    private var fixtureMetadataCwd: String { "\(fixtureCwd)/.claude" }

    private func cursorProjectsCwd(encodedTail: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let homeEncoded = String(home.dropFirst()).replacingOccurrences(of: "/", with: "-")
        return "\(home)/.cursor/projects/\(homeEncoded)-\(encodedTail)/agent-transcripts"
    }

    func testDisplayTitlePrefersProviderSessionTitle() {
        var snapshot = SessionSnapshot()
        snapshot.sessionTitle = "Investigate icon sizing"

        XCTAssertEqual(
            snapshot.displayTitle(sessionId: "019d6331-3593-7b53-9513-c1dd25d708b0"),
            "Investigate icon sizing"
        )
    }

    func testDisplayTitleFallsBackToSessionIdWhenNoProviderTitleExists() {
        let snapshot = SessionSnapshot()

        XCTAssertEqual(
            snapshot.displayTitle(sessionId: "019d632b-abee-76e3-80d6-667ea86ebeaf"),
            "019d632b-abee-76e3-80d6-667ea86ebeaf"
        )
    }

    func testProjectDisplayNameStillUsesFolderName() {
        var snapshot = SessionSnapshot()
        snapshot.cwd = fixtureCwd

        XCTAssertEqual(snapshot.projectDisplayName, fixtureLeaf)
    }

    func testProjectDisplayNameSkipsClaudeMetadataDir() {
        var snapshot = SessionSnapshot()
        snapshot.cwd = fixtureMetadataCwd

        XCTAssertEqual(snapshot.projectDisplayName, fixtureLeaf)
    }

    func testProjectDisplayNameKeepsLegitimateDotRepos() {
        var snapshot = SessionSnapshot()
        snapshot.cwd = "/tmp/code/.dotfiles"
        XCTAssertEqual(snapshot.projectDisplayName, ".dotfiles")

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        snapshot.cwd = "\(home)/.config"
        XCTAssertEqual(snapshot.projectDisplayName, ".config")
        XCTAssertFalse(SessionSnapshot.isUnhelpfulHookCwd("\(home)/.config"))
    }

    func testProjectDisplayNameDoesNotUseHomeUsernameForGlobalClaudeDir() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var snapshot = SessionSnapshot()
        snapshot.cwd = "\(home)/.claude"

        XCTAssertNotEqual(snapshot.projectDisplayName, (home as NSString).lastPathComponent)
        XCTAssertEqual(snapshot.projectDisplayName, "Session")
    }

    func testProjectDisplayNameDecodesCursorProjectsPath() {
        var snapshot = SessionSnapshot()
        snapshot.cwd = cursorProjectsCwd(encodedTail: fixtureLeaf)

        XCTAssertEqual(snapshot.projectDisplayName, fixtureLeaf)
    }

    func testProjectDisplayNamePreservesHyphenatedCursorProjectLeaf() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let hyphenLeaf = "my-sample-app"
        let projectDir = "\(home)/\(hyphenLeaf)"
        try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: projectDir) }

        var snapshot = SessionSnapshot()
        snapshot.cwd = cursorProjectsCwd(encodedTail: hyphenLeaf)

        XCTAssertEqual(snapshot.projectDisplayName, hyphenLeaf)
    }

    func testProjectDisplayNamePeelsMetadataDirFromCursorEncodedPath() throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let metadataDir = "\(home)/\(fixtureLeaf)/.claude"
        try fm.createDirectory(atPath: metadataDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: "\(home)/\(fixtureLeaf)") }

        var snapshot = SessionSnapshot()
        snapshot.cwd = cursorProjectsCwd(encodedTail: "\(fixtureLeaf)-.claude")

        XCTAssertEqual(snapshot.projectDisplayName, fixtureLeaf)
    }

    func testDisplaySessionIdPrefersProviderSessionId() {
        var snapshot = SessionSnapshot()
        snapshot.providerSessionId = "019d6330-beed-7a13-b61e-cacf03d3cefe"

        XCTAssertEqual(
            snapshot.displaySessionId(sessionId: "hook-codex-session"),
            "019d6330-beed-7a13-b61e-cacf03d3cefe"
        )
    }

    func testDisplaySessionIdFallsBackToTrackedSessionId() {
        let snapshot = SessionSnapshot()

        XCTAssertEqual(
            snapshot.displaySessionId(sessionId: "hook-codex-session"),
            "hook-codex-session"
        )
    }

    func testSessionTitleAssignmentDoesNotOverwriteProjectDisplayName() {
        var snapshot = SessionSnapshot()
        snapshot.cwd = fixtureCwd
        snapshot.sessionTitle = "查看图标bug和窗口大小bug解法"

        XCTAssertEqual(
            snapshot.displayTitle(sessionId: "019d6331-3593-7b53-9513-c1dd25d708b0"),
            "查看图标bug和窗口大小bug解法"
        )
        XCTAssertEqual(snapshot.projectDisplayName, fixtureLeaf)
    }
}
