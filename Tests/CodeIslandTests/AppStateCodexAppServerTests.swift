import XCTest
@testable import CodeIsland
@testable import CodeIslandCore

@MainActor
final class AppStateCodexAppServerTests: XCTestCase {
    func testCodexExecutablePathRecognizesChatGPTDesktopBundle() {
        XCTAssertTrue(AppState.isCodexExecutablePath(
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        ))
    }

    func testCodexExecutablePathRejectsUnrelatedResourceBinary() {
        XCTAssertFalse(AppState.isCodexExecutablePath(
            "/Applications/OtherAgent.app/Contents/Resources/codex"
        ))
    }

    func testCodexDiscoveryUsesTranscriptCwdForDesktopProcess() {
        XCTAssertTrue(AppState.codexDiscoveryUsesTranscriptCwd(processCwd: nil))
        XCTAssertTrue(AppState.codexDiscoveryUsesTranscriptCwd(processCwd: "/"))
        XCTAssertFalse(AppState.codexDiscoveryUsesTranscriptCwd(
            processCwd: "/Users/haoo/Documents/project"
        ))
    }

    func testCodexPlaceholderHookIsIgnoredButProjectHookIsKept() {
        XCTAssertTrue(AppState.isCodexPlaceholderHook(
            source: "codex",
            cwd: "/",
            hasTranscriptPath: false
        ))
        XCTAssertTrue(AppState.isCodexPlaceholderHook(
            source: "codex",
            cwd: nil,
            hasTranscriptPath: false
        ))
        XCTAssertFalse(AppState.isCodexPlaceholderHook(
            source: "codex",
            cwd: "/Users/haoo/Documents/project",
            hasTranscriptPath: false
        ))
        XCTAssertFalse(AppState.isCodexPlaceholderHook(
            source: "codex",
            cwd: "/",
            hasTranscriptPath: true
        ))
    }

    func testCodexTranscriptCwdReadsLargeSessionMetaLine() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeisland-codex-meta-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        let payload: [String: Any] = [
            "cwd": "/Users/haoo/Documents/project",
            "instructions": String(repeating: "x", count: 10_000),
        ]
        let object: [String: Any] = ["type": "session_meta", "payload": payload]
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try data.write(to: url)

        XCTAssertEqual(
            AppState.codexSessionCwd(path: url.path),
            "/Users/haoo/Documents/project"
        )
    }

    func testCodexAppServerExecutablePrefersRunningBundlePath() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("codeisland-codex-app-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("Nested/Codex.app", isDirectory: true)
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        let bundledExecutable = resourcesURL.appendingPathComponent("codex")
        try makeExecutable(at: bundledExecutable)

        let fallbackExecutable = tempDir.appendingPathComponent("fallback-codex")
        try makeExecutable(at: fallbackExecutable)

        let resolved = AppState.codexAppServerExecutableURL(
            runningBundleURLs: [bundleURL],
            fallbackPaths: [fallbackExecutable.path],
            fileManager: fm
        )

        XCTAssertEqual(resolved?.path, bundledExecutable.path)
    }

    func testCodexAppServerExecutableFallsBackWhenNoRunningBundlePathExists() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("codeisland-codex-app-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tempDir) }

        let fallbackExecutable = tempDir.appendingPathComponent("fallback-codex")
        try makeExecutable(at: fallbackExecutable)

        let resolved = AppState.codexAppServerExecutableURL(
            runningBundleURLs: [],
            fallbackPaths: [fallbackExecutable.path],
            fileManager: fm
        )

        XCTAssertEqual(resolved?.path, fallbackExecutable.path)
    }

    func testActiveWithApprovalFlagMapsToWaitingApproval() {
        var snapshot = SessionSnapshot()
        snapshot.status = .idle

        AppState.applyCodexThreadStatus(&snapshot, status: [
            "type": .string("active"),
            "activeFlags": .array([.string("waitingOnApproval")])
        ])

        XCTAssertEqual(snapshot.status, .waitingApproval)
    }

    func testActiveWithUserInputFlagMapsToWaitingQuestion() {
        var snapshot = SessionSnapshot()
        snapshot.status = .idle

        AppState.applyCodexThreadStatus(&snapshot, status: [
            "type": .string("active"),
            "activeFlags": .array([.string("waitingOnUserInput")])
        ])

        XCTAssertEqual(snapshot.status, .waitingQuestion)
    }

    func testActiveWithoutFlagsMapsToRunningAndClearsTool() {
        var snapshot = SessionSnapshot()
        snapshot.status = .waitingApproval
        snapshot.currentTool = "Bash"
        snapshot.toolDescription = "pending"

        AppState.applyCodexThreadStatus(&snapshot, status: [
            "type": .string("active"),
            "activeFlags": .array([])
        ])

        XCTAssertEqual(snapshot.status, .running)
        XCTAssertNil(snapshot.currentTool)
        XCTAssertNil(snapshot.toolDescription)
    }

    func testIdleMapsToIdleAndClearsTool() {
        var snapshot = SessionSnapshot()
        snapshot.status = .running
        snapshot.currentTool = "Read"
        snapshot.toolDescription = "foo.swift"

        AppState.applyCodexThreadStatus(&snapshot, status: [
            "type": .string("idle")
        ])

        XCTAssertEqual(snapshot.status, .idle)
        XCTAssertNil(snapshot.currentTool)
        XCTAssertNil(snapshot.toolDescription)
    }

    func testNotLoadedAndSystemErrorMapToIdle() {
        var s1 = SessionSnapshot()
        s1.status = .running
        AppState.applyCodexThreadStatus(&s1, status: ["type": .string("notLoaded")])
        XCTAssertEqual(s1.status, .idle)

        var s2 = SessionSnapshot()
        s2.status = .running
        AppState.applyCodexThreadStatus(&s2, status: ["type": .string("systemError")])
        XCTAssertEqual(s2.status, .idle)
    }

    func testUnknownStatusTypeIsNoOp() {
        var snapshot = SessionSnapshot()
        snapshot.status = .running
        snapshot.currentTool = "Bash"

        AppState.applyCodexThreadStatus(&snapshot, status: [
            "type": .string("futureEnumCaseTBD")
        ])

        XCTAssertEqual(snapshot.status, .running)
        XCTAssertEqual(snapshot.currentTool, "Bash")
    }

    func testNilStatusIsNoOp() {
        var snapshot = SessionSnapshot()
        snapshot.status = .running
        AppState.applyCodexThreadStatus(&snapshot, status: nil)
        XCTAssertEqual(snapshot.status, .running)
    }

    func testApprovalFlagTakesPrecedenceOverUserInputFlag() {
        // Codex can theoretically emit both flags at once; approval is strictly
        // more actionable, so we should route to .waitingApproval.
        var snapshot = SessionSnapshot()
        snapshot.status = .idle

        AppState.applyCodexThreadStatus(&snapshot, status: [
            "type": .string("active"),
            "activeFlags": .array([
                .string("waitingOnUserInput"),
                .string("waitingOnApproval")
            ])
        ])

        XCTAssertEqual(snapshot.status, .waitingApproval)
    }

    private func makeExecutable(at url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
