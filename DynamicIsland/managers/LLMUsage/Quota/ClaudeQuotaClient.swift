import Foundation

actor ClaudeCredentialStore {
    static let shared = ClaudeCredentialStore()
    private var cached: ClaudeQuotaClient.CredentialFile.OAuth?

    fileprivate func get() -> ClaudeQuotaClient.CredentialFile.OAuth? { cached }
    fileprivate func set(_ creds: ClaudeQuotaClient.CredentialFile.OAuth) { cached = creds }
    fileprivate func clear() { cached = nil }

    // Atomically replace the cache with a fresh load from source. Running the load
    // inside the actor closes the window where a concurrent reader could slot a stale
    // credential in between a separate clear() and set().
    fileprivate func reload(from load: @Sendable () -> ClaudeQuotaClient.CredentialFile.OAuth?) -> ClaudeQuotaClient.CredentialFile.OAuth? {
        cached = load()
        return cached
    }
}

struct ClaudeQuotaClient {
    let session: URLSession
    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let refreshScope = "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
    private static let refreshSkewMs: Int64 = 5 * 60 * 1000

    fileprivate struct CredentialFile: Decodable, Sendable {
        struct OAuth: Decodable, Sendable {
            let accessToken: String
            let refreshToken: String
            let expiresAt: Int64
        }
        let claudeAiOauth: OAuth
    }

    private struct RefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Int
    }

    private enum ResetsAt: Decodable {
        case iso(String)
        case epochMs(Double)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .iso(s) }
            else { self = .epochMs(try c.decode(Double.self)) }
        }
        var date: Date? {
            switch self {
            case .iso(let s): return ISO8601DateFormatter().date(from: s)
            case .epochMs(let ms): return Date(timeIntervalSince1970: ms / 1000)
            }
        }
    }

    private struct Window: Decodable {
        let utilization: Double
        let resetsAt: ResetsAt
    }

    private struct UsageResponse: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
    }

    private enum FetchOutcome {
        case success((session: UsageLimit?, week: UsageLimit?))
        case authFailure // 401/403: the access token is no longer accepted.
        case otherFailure // network/decoding/5xx: reloading credentials would not help.
    }

    func fetchLimits() async -> (session: UsageLimit?, week: UsageLimit?) {
        guard let creds = await currentCredentials() else { return (nil, nil) }
        switch await attemptFetch(creds) {
        case .success(let limits):
            return limits
        case .authFailure:
            // Claude Code likely rotated the OAuth token out from under our cache
            // (revoked access token, or a refresh token it already consumed). Drop the
            // cached copy, re-read from source (file → Keychain, which CC has updated),
            // and retry exactly once. No retry on non-auth failures.
            guard let fresh = await reloadCredentials() else { return (nil, nil) }
            if case .success(let limits) = await attemptFetch(fresh) { return limits }
            return (nil, nil)
        case .otherFailure:
            return (nil, nil)
        }
    }

    private func attemptFetch(_ creds: CredentialFile.OAuth) async -> FetchOutcome {
        guard let token = await validAccessToken(creds) else { return .authFailure }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.69", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .otherFailure }
            if http.statusCode == 401 || http.statusCode == 403 { return .authFailure }
            guard (200..<300).contains(http.statusCode) else { return .otherFailure }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let decoded = try decoder.decode(UsageResponse.self, from: data)
            let sessionLimit = decoded.fiveHour.map { UsageLimit(used: $0.utilization, limit: 100, resetsAt: $0.resetsAt.date) }
            let weekLimit = decoded.sevenDay.map { UsageLimit(used: $0.utilization, limit: 100, resetsAt: $0.resetsAt.date) }
            return .success((sessionLimit, weekLimit))
        } catch {
            return .otherFailure
        }
    }

    private func currentCredentials() async -> CredentialFile.OAuth? {
        if let cached = await ClaudeCredentialStore.shared.get() { return cached }
        guard let loaded = Self.loadCredentialsFromSource() else { return nil }
        await ClaudeCredentialStore.shared.set(loaded)
        return loaded
    }

    // Force a re-read from source, bypassing the in-memory cache. Called after an auth
    // failure so a token rotated by Claude Code is picked up without an app restart.
    // The invalidate-and-reload is a single atomic actor operation (see reload(from:)).
    private func reloadCredentials() async -> CredentialFile.OAuth? {
        await ClaudeCredentialStore.shared.reload(from: { Self.loadCredentialsFromSource() })
    }

    // File first never prompts; Keychain only as fallback. On the Keychain path, read the
    // freshest "Claude Code-credentials*" item: newer Claude Code stores its token under a
    // per-install hash suffix and no longer updates the un-suffixed item.
    private static func loadCredentialsFromSource() -> CredentialFile.OAuth? {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: path),
           let parsed = try? JSONDecoder().decode(CredentialFile.self, from: data) {
            return parsed.claudeAiOauth
        }
        guard let json = KeychainReader.freshestGenericPassword(servicePrefix: "Claude Code-credentials"),
              let parsed = try? JSONDecoder().decode(CredentialFile.self, from: Data(json.utf8)) else { return nil }
        return parsed.claudeAiOauth
    }

    private func validAccessToken(_ creds: CredentialFile.OAuth) async -> String? {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        guard creds.expiresAt - nowMs <= Self.refreshSkewMs else { return creds.accessToken }
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": creds.refreshToken,
            "client_id": Self.clientID,
            "scope": Self.refreshScope
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            // Refresh failed. Report the token as invalid (nil) so the caller classifies
            // this as an auth failure and reloads credentials from source, instead of
            // proceeding with an access token we already know is stale.
            return nil
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let refreshed = try? decoder.decode(RefreshResponse.self, from: data) else { return nil }
        let expiresAt = nowMs + Int64(refreshed.expiresIn) * 1000
        let updated = CredentialFile.OAuth(accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken, expiresAt: expiresAt)
        await ClaudeCredentialStore.shared.set(updated)
        return refreshed.accessToken
    }
}
