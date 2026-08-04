import XCTest
@testable import CodeIsland
import CodeIslandCore
import SQLite3

@MainActor
final class AppStateCodexSubsessionTests: XCTestCase {
    func testCodexSubagentMetadataParsesParentThreadFromRolloutSessionMeta() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeisland-codex-subagent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("rollout.jsonl")
        let line = """
        {"timestamp":"2026-05-01T00:00:00Z","type":"session_meta","payload":{"id":"child","cwd":"/repo","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent","depth":1,"agent_nickname":"Galileo","agent_role":"worker"}}},"base_instructions":{"text":"large payload follows"}}}
        """
        try (line + "\n").write(to: file, atomically: true, encoding: .utf8)

        let metadata = try XCTUnwrap(AppState.codexSubagentMetadata(inTranscriptPath: file.path))

        XCTAssertEqual(metadata.parentThreadId, "parent")
        XCTAssertEqual(metadata.agentType, "worker")
        XCTAssertEqual(metadata.agentNickname, "Galileo")
    }

    func testCodexSubagentMetadataFallsBackToThreadSpawnEdgesDatabase() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeisland-codex-subagent-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let statePath = dir.appendingPathComponent("state_5.sqlite").path

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(statePath, &db), SQLITE_OK)
        defer { sqlite3_close_v2(db) }
        let sql = """
        CREATE TABLE thread_spawn_edges (
            parent_thread_id TEXT NOT NULL,
            child_thread_id TEXT NOT NULL PRIMARY KEY,
            status TEXT NOT NULL
        );
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            agent_role TEXT,
            agent_nickname TEXT,
            source TEXT
        );
        INSERT INTO thread_spawn_edges VALUES ('parent-thread', 'child-thread', 'running');
        INSERT INTO threads VALUES ('child-thread', 'worker', 'Ohm', '{"subagent":{"thread_spawn":{"parent_thread_id":"parent-thread"}}}');
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)

        let metadata = try XCTUnwrap(AppState.codexSubagentMetadata(
            threadId: "child-thread",
            transcriptPath: nil,
            statePath: statePath
        ))

        XCTAssertEqual(metadata.parentThreadId, "parent-thread")
        XCTAssertEqual(metadata.agentType, "worker")
        XCTAssertEqual(metadata.agentNickname, "Ohm")
    }

    func testKnownCodexSubagentSessionMergesIntoParentFromTranscriptMetadata() throws {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("codeisland-codex-subagent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let childTranscript = dir.appendingPathComponent("child.jsonl")
        let line = """
        {"type":"session_meta","payload":{"id":"child-thread","cwd":"/repo","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent-thread","agent_nickname":"Ohm","agent_role":"worker"}}}}}
        """
        try (line + "\n").write(to: childTranscript, atomically: true, encoding: .utf8)

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "codex"
        parent.providerSessionId = "parent-thread"
        parent.status = .running

        var child = SessionSnapshot()
        child.source = "codex"
        child.providerSessionId = "child-thread"
        child.status = .running
        child.currentTool = "sleep"
        child.transcriptPath = childTranscript.path
        child.lastActivity = Date()

        appState.sessions["parent"] = parent
        appState.sessions["child"] = child

        XCTAssertTrue(appState.applyCodexSubsessionModeToKnownSessions())

        XCTAssertNil(appState.sessions["child"])
        XCTAssertEqual(appState.sessions["parent"]?.subagents["child-thread"]?.agentType, "worker")
        XCTAssertEqual(appState.sessions["parent"]?.subagents["child-thread"]?.toolDescription, "Ohm")
        XCTAssertEqual(appState.activeSessionId, "parent")
    }

    func testCurrentPluginSessionModeSeparateSplitsMergedCodexSubagent() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("separate", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "codex"
        parent.providerSessionId = "parent-thread"
        parent.status = .running
        parent.currentTool = "Agent"
        parent.toolDescription = "Hypatia"
        parent.cwd = "/repo"
        parent.model = "gpt-test"
        parent.remoteHostId = "test-remote"
        parent.remoteHostName = "Test Remote"
        var subagent = SubagentState(agentId: "child-thread", agentType: "worker")
        subagent.currentTool = "sleep"
        subagent.toolDescription = "sleep 45"
        parent.subagents["child-thread"] = subagent
        appState.sessions["parent"] = parent

        appState.applyCurrentPluginSessionMode(persist: false)

        XCTAssertTrue(appState.sessions["parent"]?.subagents.isEmpty == true)
        XCTAssertNil(appState.sessions["parent"]?.currentTool)
        XCTAssertEqual(appState.sessions["child-thread"]?.source, "codex")
        XCTAssertEqual(appState.sessions["child-thread"]?.providerSessionId, "child-thread")
        XCTAssertEqual(appState.sessions["child-thread"]?.cwd, "/repo")
        XCTAssertEqual(appState.sessions["child-thread"]?.model, "gpt-test")
        XCTAssertEqual(appState.sessions["child-thread"]?.remoteHostId, "test-remote")
        XCTAssertEqual(appState.sessions["child-thread"]?.remoteHostName, "Test Remote")
        XCTAssertEqual(appState.sessions["child-thread"]?.currentTool, "sleep")
        XCTAssertEqual(appState.activeSessionId, "child-thread")
    }

    func testCurrentPluginSessionModeHideClearsMergedCodexSubagent() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("hide", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "codex"
        parent.status = .running
        parent.currentTool = "Agent"
        parent.toolDescription = "Hypatia"
        parent.subagents["child-thread"] = SubagentState(agentId: "child-thread", agentType: "worker")
        appState.sessions["parent"] = parent

        appState.applyCurrentPluginSessionMode(persist: false)

        XCTAssertTrue(appState.sessions["parent"]?.subagents.isEmpty == true)
        XCTAssertNil(appState.sessions["parent"]?.currentTool)
        XCTAssertNil(appState.sessions["child-thread"])
    }

    func testFindSessionIdCanExcludeChildSessionAndRequireActiveParent() {
        let appState = AppState()

        var parent = SessionSnapshot()
        parent.source = "codex"
        parent.status = .running
        parent.cliPid = 1234
        parent.startTime = Date(timeIntervalSince1970: 100)
        parent.lastActivity = Date()

        var child = SessionSnapshot()
        child.source = "codex"
        child.status = .running
        child.cliPid = 1234
        child.startTime = Date(timeIntervalSince1970: 200)
        child.lastActivity = Date()

        appState.sessions["parent"] = parent
        appState.sessions["child"] = child

        XCTAssertEqual(
            appState.findSessionId(forSource: "codex", ppid: 1234, excluding: "child", requireActive: true),
            "parent"
        )
    }

    func testFindSessionIdDoesNotTreatIdleCodexThreadAsNativeSubsessionParent() {
        let appState = AppState()

        var idle = SessionSnapshot()
        idle.source = "codex"
        idle.status = .idle
        idle.cliPid = 1234
        idle.lastActivity = Date()

        appState.sessions["idle"] = idle

        XCTAssertNil(
            appState.findSessionId(forSource: "codex", ppid: 1234, excluding: "new-thread", requireActive: true)
        )
    }
}
