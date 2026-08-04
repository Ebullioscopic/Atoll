import XCTest
@testable import CodeIsland
@testable import CodeIslandCore

/// Branch resolution runs detached off the main actor (maybeRefreshGitBranch)
/// and lands back on the snapshot — poll briefly for the async write.
@MainActor
final class AppStateGitBranchTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "appstate-git-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(
            atPath: root + "/repo/.git", withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(
            toFile: root + "/repo/.git/HEAD", atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: root)
        super.tearDown()
    }

    private func event(_ name: String, sessionId: String, cwd: String) throws -> HookEvent {
        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": name,
            "session_id": sessionId,
            "_source": "claude",
            "cwd": cwd,
        ])
        return try XCTUnwrap(HookEvent(from: data))
    }

    private func waitForBranch(_ appState: AppState, _ sessionId: String, expected: String?) async {
        for _ in 0..<200 {
            if appState.sessions[sessionId]?.gitBranch == expected { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testBranchResolvesAsynchronouslyOnFirstEvent() async throws {
        let appState = AppState()
        appState.handleEvent(try event("PreToolUse", sessionId: "s-git", cwd: root + "/repo"))

        await waitForBranch(appState, "s-git", expected: "main")
        XCTAssertEqual(appState.sessions["s-git"]?.gitBranch, "main")
        XCTAssertEqual(appState.sessions["s-git"]?.gitIsWorktree, false)
    }

    func testBranchRefreshesOnStopAfterSwitch() async throws {
        let appState = AppState()
        appState.handleEvent(try event("PreToolUse", sessionId: "s-git2", cwd: root + "/repo"))
        await waitForBranch(appState, "s-git2", expected: "main")

        try "ref: refs/heads/feature-x\n".write(
            toFile: root + "/repo/.git/HEAD", atomically: true, encoding: .utf8)
        appState.handleEvent(try event("Stop", sessionId: "s-git2", cwd: root + "/repo"))

        await waitForBranch(appState, "s-git2", expected: "feature-x")
        XCTAssertEqual(appState.sessions["s-git2"]?.gitBranch, "feature-x")
    }
}
