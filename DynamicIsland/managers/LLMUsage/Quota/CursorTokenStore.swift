import Foundation
import SQLite3

enum CursorTokenStore {
    static func accessToken() -> String? {
        if let token = KeychainReader.genericPassword(service: "cursor-access-token") { return token }
        return readTokenFromStateDB()
    }

    // Cursor dashboard cookie: WorkosCursorSessionToken value is "<userId>::<jwt>", userId is the JWT sub.
    static func sessionCookie() -> (userId: String, cookieToken: String)? {
        guard let jwt = accessToken(), let userId = userId(fromJWT: jwt) else { return nil }
        return (userId, "\(userId)%3A%3A\(jwt)")
    }

    private static func userId(fromJWT jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else { return nil }
        return sub.contains("|") ? String(sub.split(separator: "|").last ?? "") : sub
    }

    private static func readTokenFromStateDB() -> String? {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let text = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: text)
    }
}
