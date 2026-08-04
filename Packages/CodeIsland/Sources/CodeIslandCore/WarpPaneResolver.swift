import Foundation
import SQLite3

/// A single Warp pane that matches a working directory query.
public struct WarpPaneMatch: Equatable {
    public let paneUUID: String
    public let paneId: Int64
    public let tabId: Int64
    public let windowDbId: Int64
    public let cwd: String
    public let tabIndexInWindow: Int
    public let tabCountInWindow: Int
    public let isActiveTab: Bool
    public let isPaneActive: Bool
    public let isPaneFocused: Bool

    public init(
        paneUUID: String,
        paneId: Int64,
        tabId: Int64,
        windowDbId: Int64,
        cwd: String,
        tabIndexInWindow: Int,
        tabCountInWindow: Int,
        isActiveTab: Bool,
        isPaneActive: Bool,
        isPaneFocused: Bool
    ) {
        self.paneUUID = paneUUID
        self.paneId = paneId
        self.tabId = tabId
        self.windowDbId = windowDbId
        self.cwd = cwd
        self.tabIndexInWindow = tabIndexInWindow
        self.tabCountInWindow = tabCountInWindow
        self.isActiveTab = isActiveTab
        self.isPaneActive = isPaneActive
        self.isPaneFocused = isPaneFocused
    }
}

public enum WarpPaneResolverError: Error, Equatable {
    case sqliteFileMissing(String)
    case sqliteOpenFailed(String)
    case queryFailed(String)
}

/// Reads Warp's local SQLite state to find the terminal pane currently showing a
/// given working directory, plus enough hierarchy (tab, window) to best-effort
/// drive a focus keystroke afterwards.
///
/// The database is always opened **read-only** over a URI. WAL pages are honored,
/// and a short busy timeout avoids contending with Warp while it is writing.
public struct WarpPaneResolver {
    public let sqlitePath: String

    public init(sqlitePath: String = WarpPaneResolver.defaultSQLitePath) {
        self.sqlitePath = sqlitePath
    }

    /// Warp-Stable's database path under the user's Group Containers.
    public static let defaultSQLitePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite"
    }()

    /// Return every pane matching the supplied cwd (after firmlink normalization),
    /// ordered from best → worst match: pane currently active > pane currently
    /// focused > newest pane by row id.
    public func resolve(cwd: String) throws -> [WarpPaneMatch] {
        let variants = Array(WarpPaneResolver.cwdVariants(cwd))
        guard !variants.isEmpty else { return [] }
        guard FileManager.default.fileExists(atPath: sqlitePath) else {
            throw WarpPaneResolverError.sqliteFileMissing(sqlitePath)
        }
        return try performQuery(
            cwdCandidates: variants,
            caseInsensitive: WarpPaneResolver.isCaseInsensitivePath(cwd)
        )
    }

    public func isActiveTab(cwd: String) throws -> Bool {
        try resolve(cwd: cwd).contains { $0.isActiveTab }
    }

    // MARK: - Cwd normalization

    /// Every path string that should count as the same working directory in Warp's
    /// database. Handles Apple firmlinks (/tmp ↔ /private/tmp, /var ↔ /private/var,
    /// /etc ↔ /private/etc) and trailing-slash variance.
    public static func cwdVariants(_ raw: String) -> Set<String> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var seeds: [String] = [trimmed]
        if trimmed.hasSuffix("/") && trimmed != "/" {
            seeds.append(String(trimmed.dropLast()))
        } else {
            seeds.append(trimmed + "/")
        }

        var variants = Set<String>()
        for seed in seeds {
            variants.insert(seed)
            if seed.hasPrefix("/private/") {
                variants.insert(String(seed.dropFirst("/private".count)))
            } else if seed.hasPrefix("/tmp") || seed.hasPrefix("/var") || seed.hasPrefix("/etc") {
                variants.insert("/private" + seed)
            }
        }
        return variants
    }

    // MARK: - SQLite

    private func performQuery(cwdCandidates: [String], caseInsensitive: Bool) throws -> [WarpPaneMatch] {
        let uri = WarpPaneResolver.fileURI(for: sqlitePath)
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        let openStatus = sqlite3_open_v2(uri, &db, flags, nil)
        guard openStatus == SQLITE_OK, let handle = db else {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "code=\(openStatus)"
            if let handle = db { sqlite3_close_v2(handle) }
            throw WarpPaneResolverError.sqliteOpenFailed(message)
        }
        defer { sqlite3_close_v2(handle) }

        // Let sqlite block briefly if Warp is holding a write lock.
        sqlite3_busy_timeout(handle, 150)

        let placeholders = cwdCandidates.map { _ in "?" }.joined(separator: ", ")
        let whereClause: String
        if caseInsensitive {
            whereClause = "tp.cwd IN (\(placeholders)) OR tp.cwd COLLATE NOCASE IN (\(placeholders))"
        } else {
            whereClause = "tp.cwd IN (\(placeholders))"
        }
        let sql = """
        SELECT
            tp.id,
            tp.uuid,
            tp.cwd,
            tp.is_active,
            COALESCE(pl.is_focused, 0) AS focused,
            pn.tab_id,
            t.window_id,
            w.active_tab_index,
            (
                SELECT COUNT(*) FROM tabs t2
                WHERE t2.window_id = t.window_id AND t2.id < t.id
            ) AS tab_idx,
            (
                SELECT COUNT(*) FROM tabs t3
                WHERE t3.window_id = t.window_id
            ) AS tab_count
        FROM terminal_panes tp
        LEFT JOIN pane_leaves pl ON tp.id = pl.pane_node_id AND pl.kind = 'terminal'
        LEFT JOIN pane_nodes pn ON tp.id = pn.id
        LEFT JOIN tabs t ON pn.tab_id = t.id
        LEFT JOIN windows w ON t.window_id = w.id
        WHERE \(whereClause)
        ORDER BY tp.is_active DESC, focused DESC, tp.id DESC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let query = stmt else {
            let message = String(cString: sqlite3_errmsg(handle))
            throw WarpPaneResolverError.queryFailed("prepare: \(message)")
        }
        defer { sqlite3_finalize(query) }

        for (idx, candidate) in cwdCandidates.enumerated() {
            let bindStatus = candidate.withCString { cstr in
                sqlite3_bind_text(query, Int32(idx + 1), cstr, -1, Self.sqliteTransient)
            }
            guard bindStatus == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(handle))
                throw WarpPaneResolverError.queryFailed("bind \(idx): \(message)")
            }
        }
        if caseInsensitive {
            let offset = cwdCandidates.count
            for (idx, candidate) in cwdCandidates.enumerated() {
                let bindStatus = candidate.withCString { cstr in
                    sqlite3_bind_text(query, Int32(offset + idx + 1), cstr, -1, Self.sqliteTransient)
                }
                guard bindStatus == SQLITE_OK else {
                    let message = String(cString: sqlite3_errmsg(handle))
                    throw WarpPaneResolverError.queryFailed("bind nocase \(idx): \(message)")
                }
            }
        }

        var matches: [WarpPaneMatch] = []
        while sqlite3_step(query) == SQLITE_ROW {
            let paneId = sqlite3_column_int64(query, 0)
            let uuidHex: String
            if let blobPointer = sqlite3_column_blob(query, 1) {
                let byteCount = Int(sqlite3_column_bytes(query, 1))
                let buffer = UnsafeRawBufferPointer(start: blobPointer, count: byteCount)
                uuidHex = buffer.map { String(format: "%02X", $0) }.joined()
            } else {
                uuidHex = ""
            }
            let cwdText = sqlite3_column_text(query, 2).map { String(cString: $0) } ?? ""
            let paneActive = sqlite3_column_int(query, 3) != 0
            let paneFocused = sqlite3_column_int(query, 4) != 0
            let tabId = sqlite3_column_int64(query, 5)
            let windowId = sqlite3_column_int64(query, 6)
            let activeTabIndex = Int(sqlite3_column_int(query, 7))
            let tabIndex = Int(sqlite3_column_int(query, 8))
            let tabCount = Int(sqlite3_column_int(query, 9))

            matches.append(WarpPaneMatch(
                paneUUID: uuidHex,
                paneId: paneId,
                tabId: tabId,
                windowDbId: windowId,
                cwd: cwdText,
                tabIndexInWindow: tabIndex,
                tabCountInWindow: tabCount,
                isActiveTab: activeTabIndex == tabIndex,
                isPaneActive: paneActive,
                isPaneFocused: paneFocused
            ))
        }
        return matches
    }

    /// Percent-encode the characters that have meaning inside a sqlite URI. The
    /// path body itself is preserved so the user's filesystem is unchanged.
    static func fileURI(for path: String) -> String {
        var encoded = ""
        encoded.reserveCapacity(path.count + 16)
        for scalar in path.unicodeScalars {
            switch scalar {
            case "%": encoded.append("%25")
            case "?": encoded.append("%3F")
            case "#": encoded.append("%23")
            case " ": encoded.append("%20")
            default:  encoded.unicodeScalars.append(scalar)
            }
        }
        return "file://\(encoded)?mode=ro"
    }

    /// macOS paths are usually case-insensitive even though the original casing
    /// can differ between Codex's cwd and Warp's SQLite row. Respect case-sensitive
    /// volumes by walking to the nearest existing parent and reading its volume flag.
    static func isCaseInsensitivePath(_ path: String) -> Bool {
        var url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        while !fm.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        if let values = try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]),
           let supportsCaseSensitive = values.volumeSupportsCaseSensitiveNames {
            return !supportsCaseSensitive
        }
        return true
    }

    /// The canonical `SQLITE_TRANSIENT` sentinel as a Swift destructor type.
    private static let sqliteTransient = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )
}
