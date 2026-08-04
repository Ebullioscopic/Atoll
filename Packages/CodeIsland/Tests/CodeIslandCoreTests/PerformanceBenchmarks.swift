import XCTest
import SQLite3
@testable import CodeIslandCore

/// Micro-benchmarks measuring per-call cost of hot-path helpers I added in
/// the Apr 2026 session-monitoring overhaul. These assert only a generous
/// ceiling so a future regression (e.g. accidentally O(n²) parser) fails CI
/// instead of silently eating CPU in production. Absolute numbers are
/// printed for humans to read; thresholds are set for debug-config runs.
final class PerformanceBenchmarks: XCTestCase {

    // MARK: - JSONLTailer.scanLines

    func testScanLinesOnRealisticTranscriptMix() {
        // Claude transcripts are ~75% tool_use + tool_result + meta, ~15% assistant text,
        // ~10% user prompts. This bench approximates that distribution so we measure
        // real-world cost, not the best-case assistant-only path.
        let assistant = Self.makeAssistantLine(textLength: 200)
        let user = Self.makeUserLine(textLength: 60)
        let toolUse = Self.makeToolUseLine()
        let toolResult = Self.makeToolResultLine()

        let mix: [String] = Array(repeating: toolUse, count: 4)
                          + Array(repeating: toolResult, count: 3)
                          + [assistant, assistant]
                          + [user]
        var blob = Data()
        blob.reserveCapacity(1_200_000)
        var lineCount = 0
        while blob.count < 1_000_000 {
            for line in mix {
                blob.append(contentsOf: line.utf8)
                blob.append(0x0A)
                lineCount += 1
                if blob.count >= 1_000_000 { break }
            }
        }

        let start = Date()
        let result = JSONLTailer.scanLines(blob)
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        print("[bench] scanLines realistic mix \(blob.count) bytes / \(lineCount) lines: \(String(format: "%.2f", elapsedMs))ms")
        XCTAssertNotNil(result.delta.lastAssistantMessage)
        XCTAssertLessThan(elapsedMs, 5_000)
    }

    func testScanLinesOnOneMegabyteOfAssistantLines() {
        let line = Self.makeAssistantLine(textLength: 120)
        let approxLines = 1_000_000 / (line.count + 1)
        var blob = Data()
        blob.reserveCapacity(1_050_000)
        for _ in 0..<approxLines {
            blob.append(contentsOf: line.utf8)
            blob.append(0x0A)
        }

        let start = Date()
        let result = JSONLTailer.scanLines(blob)
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        print("[bench] scanLines ~1MB (\(approxLines) lines): \(String(format: "%.2f", elapsedMs))ms")
        XCTAssertFalse(result.delta.isEmpty)
        XCTAssertLessThan(elapsedMs, 5_000, "1MB scan must stay under 5s even in debug")
    }

    // MARK: - HookEvent.init

    func testHookEventInitThousandCallsRemainsFast() throws {
        let payload: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "s-bench",
            "tool_name": "Bash",
            "tool_use_id": "toolu_bench",
            "tool_input": ["command": "ls -la", "description": "list"],
            "transcript_path": "/tmp/x.jsonl",
            "_tty": "/dev/ttys001",
            "_tmux": "/tmp/tmux-0/default,123"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)

        let iterations = 1000
        let start = Date()
        for _ in 0..<iterations {
            _ = HookEvent(from: data)
        }
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        print("[bench] HookEvent.init x\(iterations): \(String(format: "%.2f", elapsedMs))ms (~\(String(format: "%.1f", elapsedMs * 1000 / Double(iterations)))μs/call)")
        XCTAssertLessThan(elapsedMs, 500)
    }

    // MARK: - drainMessages

    func testDrainMessagesThousandNotifications() {
        let line = #"{"jsonrpc":"2.0","method":"thread/status/changed","params":{"threadId":"t-x","status":{"type":"active","activeFlags":["waitingOnApproval"]}}}"#
        let iterations = 1000
        var buffer = Data()
        buffer.reserveCapacity((line.count + 1) * iterations)
        for _ in 0..<iterations {
            buffer.append(contentsOf: line.utf8)
            buffer.append(0x0A)
        }

        let start = Date()
        let messages = CodexAppServerClient.drainMessages(buffer: &buffer)
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        print("[bench] drainMessages \(iterations) ndjson lines: \(String(format: "%.2f", elapsedMs))ms")
        XCTAssertEqual(messages.count, iterations)
        XCTAssertLessThan(elapsedMs, 1000)
    }

    // MARK: - WarpPaneResolver.resolve

    func testWarpResolverOnThousandPanes() throws {
        let dbPath = NSTemporaryDirectory() + "warp-bench-\(UUID().uuidString).sqlite"
        try Self.seedWarpDatabase(at: dbPath, paneCount: 1000)
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let resolver = WarpPaneResolver(sqlitePath: dbPath)
        _ = try resolver.resolve(cwd: "/project-0")  // warm page cache

        let start = Date()
        let match = try resolver.resolve(cwd: "/project-777")
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        print("[bench] WarpPaneResolver over 1000 panes: \(String(format: "%.2f", elapsedMs))ms")
        XCTAssertEqual(match.first?.paneId, 777)
        XCTAssertLessThan(elapsedMs, 200)
    }

    // MARK: - Fixtures

    private static func makeAssistantLine(textLength: Int) -> String {
        let text = String(repeating: "a", count: textLength)
        let payload: [String: Any] = [
            "type": "assistant",
            "message": [
                "content": [["type": "text", "text": text]]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }

    private static func makeUserLine(textLength: Int) -> String {
        let text = String(repeating: "u", count: textLength)
        let payload: [String: Any] = [
            "type": "user",
            "message": ["content": text]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }

    private static func makeToolUseLine() -> String {
        let payload: [String: Any] = [
            "type": "tool_use",
            "message": [
                "content": [[
                    "type": "tool_use",
                    "id": "toolu_\(UUID().uuidString.prefix(12))",
                    "name": "Bash",
                    "input": ["command": "ls -la /Users/foo/some/deep/path"]
                ]]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }

    private static func makeToolResultLine() -> String {
        let payload: [String: Any] = [
            "type": "tool_result",
            "message": [
                "content": [[
                    "type": "tool_result",
                    "tool_use_id": "toolu_abcdef012345",
                    "content": String(repeating: "output ", count: 30)
                ]]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return String(data: data, encoding: .utf8)!
    }

    private static func seedWarpDatabase(at path: String, paneCount: Int) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let handle = db else {
            XCTFail("could not create bench database")
            throw NSError(domain: "PerformanceBenchmarks", code: 1)
        }
        defer { sqlite3_close_v2(handle) }

        let ddl = """
        CREATE TABLE windows (id INTEGER PRIMARY KEY, active_tab_index INTEGER NOT NULL);
        CREATE TABLE tabs (id INTEGER PRIMARY KEY, window_id INTEGER NOT NULL);
        CREATE TABLE pane_nodes (id INTEGER PRIMARY KEY, tab_id INTEGER NOT NULL, parent_pane_node_id INTEGER, flex REAL, is_leaf INTEGER NOT NULL);
        CREATE TABLE pane_leaves (pane_node_id INTEGER NOT NULL UNIQUE, kind TEXT NOT NULL, is_focused INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (pane_node_id, kind));
        CREATE TABLE terminal_panes (id INTEGER PRIMARY KEY, kind TEXT NOT NULL DEFAULT 'terminal', uuid BLOB NOT NULL UNIQUE, cwd TEXT, is_active INTEGER NOT NULL DEFAULT 0);
        """
        try Self.exec(handle: handle, sql: ddl)

        sqlite3_exec(handle, "BEGIN", nil, nil, nil)
        try Self.exec(handle: handle, sql: "INSERT INTO windows(id, active_tab_index) VALUES (1, 0);")
        let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
        for idx in 0..<paneCount {
            try Self.exec(handle: handle, sql: "INSERT INTO tabs(id, window_id) VALUES (\(idx), 1);")
            try Self.exec(handle: handle, sql: "INSERT INTO pane_nodes(id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES (\(idx), \(idx), NULL, NULL, 1);")
            try Self.exec(handle: handle, sql: "INSERT INTO pane_leaves(pane_node_id, kind, is_focused) VALUES (\(idx), 'terminal', 0);")

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "INSERT INTO terminal_panes(id, kind, uuid, cwd, is_active) VALUES (?, 'terminal', ?, ?, 0)", -1, &stmt, nil) == SQLITE_OK, let query = stmt else {
                throw NSError(domain: "PerformanceBenchmarks", code: 2)
            }
            sqlite3_bind_int64(query, 1, Int64(idx))
            // Spread the id across all 16 bytes so the UNIQUE uuid constraint isn't
            // violated for idx ≥ 256.
            var uuidBytes = [UInt8](repeating: 0, count: 16)
            let value = UInt64(idx)
            for byteIndex in 0..<8 {
                uuidBytes[byteIndex] = UInt8((value >> (byteIndex * 8)) & 0xff)
            }
            uuidBytes.withUnsafeBufferPointer { buf in
                _ = sqlite3_bind_blob(query, 2, buf.baseAddress, Int32(buf.count), transient)
            }
            let cwd = "/project-\(idx)"
            _ = cwd.withCString { sqlite3_bind_text(query, 3, $0, -1, transient) }
            _ = sqlite3_step(query)
            sqlite3_finalize(query)
        }
        sqlite3_exec(handle, "COMMIT", nil, nil, nil)
    }

    private static func exec(handle: OpaquePointer, sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            XCTFail("sqlite exec failed: \(msg)")
            throw NSError(domain: "PerformanceBenchmarks", code: 3)
        }
    }
}
