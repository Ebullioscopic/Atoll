import Foundation

/// Builds links understood by the installed Codex macOS app.
public enum CodexAppLink {
    public static let scheme = "codex"
    public static let threadsHost = "threads"

    public static func url(forSessionID sessionID: String) -> URL? {
        guard !sessionID.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = threadsHost
        components.path = "/\(sessionID)"
        return components.url
    }
}
