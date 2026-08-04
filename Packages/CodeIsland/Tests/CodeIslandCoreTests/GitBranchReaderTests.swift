import XCTest
@testable import CodeIslandCore

final class GitBranchReaderTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "git-branch-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: root)
        super.tearDown()
    }

    private func write(_ path: String, _ content: String) throws {
        let full = root + "/" + path
        let dir = (full as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try content.write(toFile: full, atomically: true, encoding: .utf8)
    }

    // MARK: parseHEAD

    func testParseHEADBranchRef() {
        XCTAssertEqual(GitBranchReader.parseHEAD("ref: refs/heads/main\n"), "main")
        XCTAssertEqual(GitBranchReader.parseHEAD("ref: refs/heads/feat/notch-ui\n"), "feat/notch-ui")
    }

    func testParseHEADDetachedShortensSHA() {
        XCTAssertEqual(
            GitBranchReader.parseHEAD("29e5256a1b2c3d4e5f60718293a4b5c6d7e8f901\n"),
            "29e5256"
        )
    }

    func testParseHEADRejectsGarbage() {
        XCTAssertNil(GitBranchReader.parseHEAD(""))
        XCTAssertNil(GitBranchReader.parseHEAD("not a head"))
        XCTAssertNil(GitBranchReader.parseHEAD("ref: refs/heads/"))
    }

    // MARK: parseGitdirPointer

    func testParseGitdirPointerAbsoluteAndRelative() {
        XCTAssertEqual(
            GitBranchReader.parseGitdirPointer("gitdir: /repo/.git/worktrees/wt\n", relativeTo: "/x"),
            "/repo/.git/worktrees/wt"
        )
        XCTAssertEqual(
            GitBranchReader.parseGitdirPointer("gitdir: ../repo/.git\n", relativeTo: "/a/b"),
            "/a/repo/.git"
        )
        XCTAssertNil(GitBranchReader.parseGitdirPointer("something else", relativeTo: "/a"))
    }

    // MARK: read(cwd:)

    func testReadPrimaryCheckoutFromSubdirectory() throws {
        try write("repo/.git/HEAD", "ref: refs/heads/main\n")
        try write("repo/src/deep/placeholder", "")

        let info = GitBranchReader.read(cwd: root + "/repo/src/deep")
        XCTAssertEqual(info, GitBranchInfo(branch: "main", isWorktree: false))
    }

    func testReadLinkedWorktree() throws {
        try write("repo/.git/HEAD", "ref: refs/heads/main\n")
        try write("repo/.git/worktrees/fix-1/HEAD", "ref: refs/heads/fix/session-bug\n")
        try write("wt/.git", "gitdir: \(root!)/repo/.git/worktrees/fix-1\n")

        let info = GitBranchReader.read(cwd: root + "/wt")
        XCTAssertEqual(info, GitBranchInfo(branch: "fix/session-bug", isWorktree: true))
    }

    func testReadDetachedHead() throws {
        try write("repo/.git/HEAD", "0123456789abcdef0123456789abcdef01234567\n")

        let info = GitBranchReader.read(cwd: root + "/repo")
        XCTAssertEqual(info, GitBranchInfo(branch: "0123456", isWorktree: false))
    }

    func testReadNonRepoReturnsNil() throws {
        try write("plain/file.txt", "hi")
        XCTAssertNil(GitBranchReader.read(cwd: root + "/plain"))
    }

    // MARK: submodule vs linked worktree

    func testSubmoduleUnderWorktreesDirIsNotAWorktree() throws {
        // Primary checkout lives under a directory literally named "worktrees";
        // a submodule's gitdir pointer resolves to .git/modules/… — must not
        // be flagged as a linked worktree.
        try write("worktrees/repo/.git/modules/sub/HEAD", "ref: refs/heads/main\n")
        try write("worktrees/repo/sub/.git", "gitdir: \(root!)/worktrees/repo/.git/modules/sub\n")

        let info = GitBranchReader.read(cwd: root + "/worktrees/repo/sub")
        XCTAssertEqual(info, GitBranchInfo(branch: "main", isWorktree: false))
    }
}
