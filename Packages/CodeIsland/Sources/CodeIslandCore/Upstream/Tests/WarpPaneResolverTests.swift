import XCTest
import SQLite3
@testable import CodeIslandCore

final class WarpPaneResolverTests: XCTestCase {

    // MARK: - cwdVariants (pure logic)

    func testCwdVariantsEmptyInputProducesEmptySet() {
        XCTAssertEqual(WarpPaneResolver.cwdVariants(""), [])
        XCTAssertEqual(WarpPaneResolver.cwdVariants("   "), [])
    }

    func testCwdVariantsIncludesFirmlinkForShortPath() {
        let variants = WarpPaneResolver.cwdVariants("/tmp/foo")
        XCTAssertTrue(variants.contains("/tmp/foo"))
        XCTAssertTrue(variants.contains("/private/tmp/foo"))
    }

    func testCwdVariantsIncludesRealPathForPrivatePrefix() {
        let variants = WarpPaneResolver.cwdVariants("/private/var/folders/xy/abc")
        XCTAssertTrue(variants.contains("/private/var/folders/xy/abc"))
        XCTAssertTrue(variants.contains("/var/folders/xy/abc"))
    }

    func testCwdVariantsIncludesTrailingSlashForms() {
        let withoutSlash = WarpPaneResolver.cwdVariants("/Users/bob/code")
        XCTAssertTrue(withoutSlash.contains("/Users/bob/code"))
        XCTAssertTrue(withoutSlash.contains("/Users/bob/code/"))

        let withSlash = WarpPaneResolver.cwdVariants("/Users/bob/code/")
        XCTAssertTrue(withSlash.contains("/Users/bob/code/"))
        XCTAssertTrue(withSlash.contains("/Users/bob/code"))
    }

    func testCwdVariantsDoesNotDoubleNestPrivate() {
        let variants = WarpPaneResolver.cwdVariants("/private/tmp/foo")
        XCTAssertFalse(variants.contains("/private/private/tmp/foo"))
    }

    // MARK: - resolve (SQLite)

    func testResolveThrowsWhenDatabaseMissing() {
        let missing = NSTemporaryDirectory() + "nonexistent-warp-\(UUID().uuidString).sqlite"
        let resolver = WarpPaneResolver(sqlitePath: missing)
        XCTAssertThrowsError(try resolver.resolve(cwd: "/tmp/foo")) { error in
            guard case WarpPaneResolverError.sqliteFileMissing(let path) = error else {
                return XCTFail("expected .sqliteFileMissing, got \(error)")
            }
            XCTAssertEqual(path, missing)
        }
    }

    func testResolveReturnsNothingForUnknownCwd() throws {
        let dbPath = try createTestDatabase(panes: [
            TestPane(id: 1, uuid: "AA", cwd: "/Users/bob/real", isActive: true, isFocused: true, tabId: 1, windowId: 1, activeTabIndex: 0)
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let resolver = WarpPaneResolver(sqlitePath: dbPath)
        let matches = try resolver.resolve(cwd: "/some/other/path")
        XCTAssertEqual(matches, [])
    }

    func testResolveFindsExactCwdMatch() throws {
        let dbPath = try createTestDatabase(panes: [
            TestPane(id: 42, uuid: "DEADBEEF", cwd: "/Users/bob/code", isActive: true, isFocused: true, tabId: 5, windowId: 3, activeTabIndex: 2),
            TestPane(id: 43, uuid: "CAFEBABE", cwd: "/Users/bob/other", isActive: false, isFocused: false, tabId: 6, windowId: 3, activeTabIndex: 2)
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let resolver = WarpPaneResolver(sqlitePath: dbPath)
        let matches = try resolver.resolve(cwd: "/Users/bob/code")
        XCTAssertEqual(matches.count, 1)
        let hit = try XCTUnwrap(matches.first)
        XCTAssertEqual(hit.paneId, 42)
        XCTAssertEqual(hit.paneUUID, "DEADBEEF")
        XCTAssertEqual(hit.tabId, 5)
        XCTAssertEqual(hit.windowDbId, 3)
        XCTAssertEqual(hit.cwd, "/Users/bob/code")
        XCTAssertTrue(hit.isPaneActive)
        XCTAssertTrue(hit.isPaneFocused)
    }

    func testResolveMatchesCwdCaseInsensitivelyOnDefaultMacVolumes() throws {
        let dbPath = try createTestDatabase(panes: [
            TestPane(id: 42, uuid: "DEADBEEF", cwd: "/Users/bob/codeisland", isActive: true, isFocused: true, tabId: 5, windowId: 3, activeTabIndex: 0)
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let resolver = WarpPaneResolver(sqlitePath: dbPath)
        let matches = try resolver.resolve(cwd: "/Users/bob/CodeIsland")
        XCTAssertEqual(matches.first?.paneId, 42)
        XCTAssertEqual(matches.first?.cwd, "/Users/bob/codeisland")
    }

    func testResolveResolvesFirmlinkVariant() throws {
        let dbPath = try createTestDatabase(panes: [
            TestPane(id: 1, uuid: "01", cwd: "/private/tmp/work", isActive: true, isFocused: true, tabId: 1, windowId: 1, activeTabIndex: 0)
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let resolver = WarpPaneResolver(sqlitePath: dbPath)
        let matches = try resolver.resolve(cwd: "/tmp/work")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.cwd, "/private/tmp/work")
    }

    func testResolveOrdersActiveBeforeFocusedBeforeNewestId() throws {
        // Three panes all sharing the same cwd in the same tab. Resolver must return
        // active first, then focused, then newest id.
        let dbPath = try createTestDatabase(panes: [
            TestPane(id: 1, uuid: "01", cwd: "/shared", isActive: false, isFocused: false, tabId: 1, windowId: 1, activeTabIndex: 0),
            TestPane(id: 2, uuid: "02", cwd: "/shared", isActive: false, isFocused: true,  tabId: 1, windowId: 1, activeTabIndex: 0),
            TestPane(id: 3, uuid: "03", cwd: "/shared", isActive: true,  isFocused: false, tabId: 1, windowId: 1, activeTabIndex: 0),
            TestPane(id: 4, uuid: "04", cwd: "/shared", isActive: false, isFocused: false, tabId: 1, windowId: 1, activeTabIndex: 0)
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let resolver = WarpPaneResolver(sqlitePath: dbPath)
        let matches = try resolver.resolve(cwd: "/shared")
        XCTAssertEqual(matches.map(\.paneId), [3, 2, 4, 1])
    }

    func testResolveComputesTabIndexWithinWindow() throws {
        // Window 10 has tabs 20, 21, 22 in that insertion order; window 11 has 30.
        let dbPath = try createTestDatabase(panes: [
            TestPane(id: 100, uuid: "A0", cwd: "/w10-t20", isActive: false, isFocused: false, tabId: 20, windowId: 10, activeTabIndex: 2),
            TestPane(id: 101, uuid: "A1", cwd: "/w10-t21", isActive: false, isFocused: false, tabId: 21, windowId: 10, activeTabIndex: 2),
            TestPane(id: 102, uuid: "A2", cwd: "/w10-t22", isActive: true,  isFocused: true,  tabId: 22, windowId: 10, activeTabIndex: 2),
            TestPane(id: 200, uuid: "B0", cwd: "/w11-t30", isActive: true,  isFocused: true,  tabId: 30, windowId: 11, activeTabIndex: 0)
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let resolver = WarpPaneResolver(sqlitePath: dbPath)

        let w10t20 = try XCTUnwrap(try resolver.resolve(cwd: "/w10-t20").first)
        XCTAssertEqual(w10t20.tabIndexInWindow, 0)
        XCTAssertEqual(w10t20.tabCountInWindow, 3)
        XCTAssertFalse(w10t20.isActiveTab)

        let w10t22 = try XCTUnwrap(try resolver.resolve(cwd: "/w10-t22").first)
        XCTAssertEqual(w10t22.tabIndexInWindow, 2)
        XCTAssertEqual(w10t22.tabCountInWindow, 3)
        XCTAssertTrue(w10t22.isActiveTab)

        let w11t30 = try XCTUnwrap(try resolver.resolve(cwd: "/w11-t30").first)
        XCTAssertEqual(w11t30.tabIndexInWindow, 0)
        XCTAssertEqual(w11t30.tabCountInWindow, 1)
        XCTAssertTrue(w11t30.isActiveTab)
    }

    func testIsActiveTabReflectsWindowActiveTabIndex() throws {
        let dbPath = try createTestDatabase(panes: [
            TestPane(id: 1, uuid: "01", cwd: "/inactive", isActive: true, isFocused: true, tabId: 10, windowId: 1, activeTabIndex: 1),
            TestPane(id: 2, uuid: "02", cwd: "/active", isActive: false, isFocused: false, tabId: 11, windowId: 1, activeTabIndex: 1)
        ])
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        let resolver = WarpPaneResolver(sqlitePath: dbPath)
        XCTAssertFalse(try resolver.isActiveTab(cwd: "/inactive"))
        XCTAssertTrue(try resolver.isActiveTab(cwd: "/active"))
    }

    func testFileURIEncodesSpacesAndSpecials() {
        XCTAssertEqual(
            WarpPaneResolver.fileURI(for: "/Users/alice/my path/warp.sqlite"),
            "file:///Users/alice/my%20path/warp.sqlite?mode=ro"
        )
        XCTAssertEqual(
            WarpPaneResolver.fileURI(for: "/tmp/a#b?c%.sqlite"),
            "file:///tmp/a%23b%3Fc%25.sqlite?mode=ro"
        )
    }

    // MARK: - Test fixture: create a minimal Warp-shaped SQLite database

    private struct TestPane {
        let id: Int64
        let uuid: String          // hex string — converted to blob on insert
        let cwd: String
        let isActive: Bool
        let isFocused: Bool
        let tabId: Int64
        let windowId: Int64
        let activeTabIndex: Int
    }

    /// Build a fresh SQLite file shaped like Warp's real schema, prefilled with the
    /// given panes (plus the matching tab + window rows). Returns the path so the
    /// caller can clean it up.
    private func createTestDatabase(panes: [TestPane]) throws -> String {
        let path = NSTemporaryDirectory() + "warp-test-\(UUID().uuidString).sqlite"
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
              let handle = db else {
            XCTFail("could not open test sqlite")
            throw NSError(domain: "WarpPaneResolverTests", code: 1)
        }
        defer { sqlite3_close_v2(handle) }

        let ddl = """
        CREATE TABLE windows (
            id INTEGER PRIMARY KEY NOT NULL,
            active_tab_index INTEGER NOT NULL
        );
        CREATE TABLE tabs (
            id INTEGER PRIMARY KEY NOT NULL,
            window_id INTEGER NOT NULL REFERENCES windows(id)
        );
        CREATE TABLE pane_nodes (
            id INTEGER PRIMARY KEY NOT NULL,
            tab_id INTEGER NOT NULL REFERENCES tabs(id),
            parent_pane_node_id INTEGER REFERENCES pane_nodes(id),
            flex REAL,
            is_leaf INTEGER NOT NULL
        );
        CREATE TABLE pane_leaves (
            pane_node_id INTEGER NOT NULL UNIQUE REFERENCES pane_nodes(id),
            kind TEXT NOT NULL,
            is_focused INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (pane_node_id, kind)
        );
        CREATE TABLE terminal_panes (
            id INTEGER PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL DEFAULT 'terminal',
            uuid BLOB NOT NULL UNIQUE,
            cwd TEXT,
            is_active INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (id, kind) REFERENCES pane_leaves(pane_node_id, kind)
        );
        """
        try execOrFail(handle, sql: ddl)

        var windowIDs = Set<Int64>()
        var tabIDs = Set<Int64>()
        var activeIndexByWindow: [Int64: Int] = [:]
        for pane in panes {
            windowIDs.insert(pane.windowId)
            tabIDs.insert(pane.tabId)
            activeIndexByWindow[pane.windowId] = pane.activeTabIndex
        }
        for windowID in windowIDs.sorted() {
            let idx = activeIndexByWindow[windowID] ?? 0
            try execOrFail(handle, sql: "INSERT INTO windows(id, active_tab_index) VALUES (\(windowID), \(idx));")
        }

        // Gather (tabId → windowId) from the panes. Real Warp has one row per tab; tests
        // only insert tabs that actually have panes referencing them.
        var tabToWindow: [Int64: Int64] = [:]
        for pane in panes { tabToWindow[pane.tabId] = pane.windowId }
        for tabID in tabIDs.sorted() {
            let windowID = tabToWindow[tabID]!
            try execOrFail(handle, sql: "INSERT INTO tabs(id, window_id) VALUES (\(tabID), \(windowID));")
        }

        for pane in panes {
            try execOrFail(handle, sql: "INSERT INTO pane_nodes(id, tab_id, parent_pane_node_id, flex, is_leaf) VALUES (\(pane.id), \(pane.tabId), NULL, NULL, 1);")
            try execOrFail(handle, sql: "INSERT INTO pane_leaves(pane_node_id, kind, is_focused) VALUES (\(pane.id), 'terminal', \(pane.isFocused ? 1 : 0));")
            try insertTerminalPane(handle, pane: pane)
        }
        return path
    }

    private func insertTerminalPane(_ handle: OpaquePointer, pane: TestPane) throws {
        var stmt: OpaquePointer?
        let sql = "INSERT INTO terminal_panes(id, kind, uuid, cwd, is_active) VALUES (?, 'terminal', ?, ?, ?);"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let query = stmt else {
            XCTFail("prepare insert terminal_panes failed")
            throw NSError(domain: "WarpPaneResolverTests", code: 2)
        }
        defer { sqlite3_finalize(query) }

        sqlite3_bind_int64(query, 1, pane.id)

        let bytes = hexDecode(pane.uuid)
        let transient = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
        bytes.withUnsafeBufferPointer { buffer in
            _ = sqlite3_bind_blob(query, 2, buffer.baseAddress, Int32(buffer.count), transient)
        }

        _ = pane.cwd.withCString { cstr in
            sqlite3_bind_text(query, 3, cstr, -1, transient)
        }
        sqlite3_bind_int(query, 4, pane.isActive ? 1 : 0)

        guard sqlite3_step(query) == SQLITE_DONE else {
            XCTFail("insert terminal_panes failed: \(String(cString: sqlite3_errmsg(handle)))")
            throw NSError(domain: "WarpPaneResolverTests", code: 3)
        }
    }

    private func execOrFail(_ handle: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if status != SQLITE_OK {
            let msg = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            XCTFail("sqlite exec failed: \(msg)\n\(sql)")
            throw NSError(domain: "WarpPaneResolverTests", code: 4)
        }
    }

    private func hexDecode(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var iterator = hex.unicodeScalars.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            let pair = String(high) + String(low)
            if let byte = UInt8(pair, radix: 16) { bytes.append(byte) }
        }
        return bytes
    }
}
