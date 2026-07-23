import XCTest
@testable import CodeIsland

/// #242 — the remote install script must MERGE our hooks into existing config
/// files, never replace whole event keys. Every SSH connect re-runs the script,
/// so a replace would wipe user-authored hooks (e.g. a custom SessionStart) on
/// each connection. These tests execute the real embedded Python script against
/// a sandbox $HOME.
final class RemoteInstallerHookMergeTests: XCTestCase {
    private var sandboxHome: URL!

    override func setUpWithError() throws {
        sandboxHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeisland-remote-merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sandboxHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sandboxHome)
    }

    private func runConfigureScript() throws {
        let host = RemoteHost(name: "test-host", host: "example.invalid")
        let script = RemoteInstaller.configureRemoteHooksScript(host: host, remoteSocketPath: "/tmp/ci-test.sock", customCLIs: [])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-"]
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = sandboxHome.path
        // Keep the script away from any real Codex home configured in the caller env.
        environment.removeValue(forKey: "CODEX_HOME")
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        stdin.fileHandleForWriting.write(Data(script.utf8))
        stdin.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "configure script failed: \(err)")
    }

    private func writeJSON(_ object: [String: Any], to relativePath: String) throws {
        let url = sandboxHome.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        try data.write(to: url)
    }

    private func readJSON(_ relativePath: String) throws -> [String: Any] {
        let url = sandboxHome.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func commands(in entries: [[String: Any]]) -> [String] {
        entries.flatMap { entry -> [String] in
            ((entry["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
        }
    }

    func testClaudeInstallPreservesUserSessionStartHooks() throws {
        let userEntry: [String: Any] = [
            "matcher": "",
            "hooks": [["type": "command", "command": "echo my-custom-session-start", "timeout": 5]],
        ]
        try writeJSON(["hooks": ["SessionStart": [userEntry]]], to: ".claude/settings.json")

        try runConfigureScript()

        let settings = try readJSON(".claude/settings.json")
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        let sessionStart = try XCTUnwrap(hooks["SessionStart"] as? [[String: Any]])
        let cmds = commands(in: sessionStart)
        XCTAssertTrue(cmds.contains { $0.contains("my-custom-session-start") }, "user hook was wiped: \(cmds)")
        XCTAssertTrue(cmds.contains { $0.contains("codeisland-remote-hook.py") }, "our hook missing: \(cmds)")
        // User entry stays first — we append after it.
        XCTAssertTrue(commands(in: [sessionStart[0]]).contains { $0.contains("my-custom-session-start") })
    }

    func testClaudeInstallIsIdempotentAcrossReconnects() throws {
        let userEntry: [String: Any] = [
            "hooks": [["type": "command", "command": "echo keep-me", "timeout": 5]],
        ]
        try writeJSON(["hooks": ["Stop": [userEntry]]], to: ".claude/settings.json")

        // Simulate three SSH reconnects.
        try runConfigureScript()
        try runConfigureScript()
        try runConfigureScript()

        let settings = try readJSON(".claude/settings.json")
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        let cmds = commands(in: stop)
        XCTAssertEqual(cmds.filter { $0.contains("keep-me") }.count, 1, "user hook duplicated or lost: \(cmds)")
        XCTAssertEqual(cmds.filter { $0.contains("codeisland-remote-hook.py") }.count, 1, "our hook not deduped: \(cmds)")
    }

    func testCodexInstallPreservesUserHooks() throws {
        let userEntry: [String: Any] = [
            "hooks": [["type": "command", "command": "echo codex-user-hook", "timeout": 5]],
        ]
        try writeJSON(["hooks": ["SessionStart": [userEntry]]], to: ".codex/hooks.json")

        try runConfigureScript()

        let settings = try readJSON(".codex/hooks.json")
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        let sessionStart = try XCTUnwrap(hooks["SessionStart"] as? [[String: Any]])
        let cmds = commands(in: sessionStart)
        XCTAssertTrue(cmds.contains { $0.contains("codex-user-hook") }, "user hook was wiped: \(cmds)")
        XCTAssertTrue(cmds.contains { $0.contains("codeisland-remote-hook.py") }, "our hook missing: \(cmds)")
    }

    func testCodeBuddyInstallPreservesUserHooks() throws {
        let userEntry: [String: Any] = [
            "matcher": "*",
            "hooks": [["type": "command", "command": "echo buddy-user-hook", "timeout": 5]],
        ]
        try writeJSON(["hooks": ["PermissionRequest": [userEntry]]], to: ".codebuddy/settings.json")

        try runConfigureScript()

        let settings = try readJSON(".codebuddy/settings.json")
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        let permission = try XCTUnwrap(hooks["PermissionRequest"] as? [[String: Any]])
        let cmds = commands(in: permission)
        XCTAssertTrue(cmds.contains { $0.contains("buddy-user-hook") }, "user hook was wiped: \(cmds)")
        XCTAssertTrue(cmds.contains { $0.contains("codeisland-remote-hook.py") }, "our hook missing: \(cmds)")
    }

    func testQoderInstallPreservesUserHooks() throws {
        let userEntry: [String: Any] = [
            "hooks": [["type": "command", "command": "echo qoder-user-hook", "timeout": 5]],
        ]
        try writeJSON(["hooks": ["SessionStart": [userEntry]]], to: ".qoder/settings.json")

        try runConfigureScript()

        let settings = try readJSON(".qoder/settings.json")
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        let sessionStart = try XCTUnwrap(hooks["SessionStart"] as? [[String: Any]])
        let cmds = commands(in: sessionStart)
        XCTAssertTrue(cmds.contains { $0.contains("qoder-user-hook") }, "user hook was wiped: \(cmds)")
        XCTAssertTrue(cmds.contains { $0.contains("CODEISLAND_SOURCE=qoder") }, "Qoder source missing: \(cmds)")
        XCTAssertTrue(cmds.contains { $0.contains("codeisland-remote-hook.py") }, "our hook missing: \(cmds)")
    }

    func testQoderInstallIsIdempotentAcrossReconnects() throws {
        let userEntry: [String: Any] = [
            "hooks": [["type": "command", "command": "echo keep-qoder", "timeout": 5]],
        ]
        try writeJSON(["hooks": ["Stop": [userEntry]]], to: ".qoder/settings.json")

        try runConfigureScript()
        try runConfigureScript()
        try runConfigureScript()

        let settings = try readJSON(".qoder/settings.json")
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        let cmds = commands(in: stop)
        XCTAssertEqual(cmds.filter { $0.contains("keep-qoder") }.count, 1, "user hook duplicated or lost: \(cmds)")
        XCTAssertEqual(cmds.filter { $0.contains("CODEISLAND_SOURCE=qoder") }.count, 1, "our hook not deduped: \(cmds)")
    }
}
