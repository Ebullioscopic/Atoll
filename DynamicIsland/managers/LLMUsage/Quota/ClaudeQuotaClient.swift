import Foundation

actor ClaudeCredentialStore {
    static let shared = ClaudeCredentialStore()
    private var cached: ClaudeQuotaClient.Credentials?

    fileprivate func get() -> ClaudeQuotaClient.Credentials? { cached }
    fileprivate func set(_ creds: ClaudeQuotaClient.Credentials) { cached = creds }
    fileprivate func clear() { cached = nil }

    // Atomically replace the cache with a fresh load from source. Running the load
    // inside the actor closes the window where a concurrent reader could slot a stale
    // credential in between a separate clear() and set().
    fileprivate func reload(from load: @Sendable () -> ClaudeQuotaClient.Credentials?) -> ClaudeQuotaClient.Credentials? {
        cached = load()
        return cached
    }
}

struct ClaudeQuotaClient {
    let session: URLSession
    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let refreshScope = "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
    /// Where a credential was read from, so a refreshed pair can be written back to the
    /// same place.
    fileprivate enum CredentialSource: Sendable {
        case file(URL)
        case keychain(service: String)
    }

    /// One Claude Code OAuth credential. `raw` is the credential JSON exactly as read:
    /// Claude Code keeps more under `claudeAiOauth` than the three fields used here
    /// (scopes, subscriptionType, rateLimitTier, refreshTokenExpiresAt), and a write-back
    /// must hand all of it back untouched.
    fileprivate struct Credentials: Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Int64
        let raw: Data
        let source: CredentialSource

        /// nil when the JSON has no usable pair. A logged-out Claude Code leaves the item in
        /// place with empty tokens and `expiresAt: 0`; that is "no credential", not one to refresh.
        static func parse(_ data: Data, source: CredentialSource) -> Credentials? {
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let oauth = obj["claudeAiOauth"] as? [String: Any],
                  let access = oauth["accessToken"] as? String, !access.isEmpty,
                  let refresh = oauth["refreshToken"] as? String, !refresh.isEmpty,
                  let expires = (oauth["expiresAt"] as? NSNumber)?.int64Value
            else { return nil }
            return Credentials(accessToken: access, refreshToken: refresh, expiresAt: expires, raw: data, source: source)
        }

        /// The same credential carrying a new token pair, with `raw` edited to match so the
        /// fields Atoll does not use survive the write-back.
        func rotated(accessToken: String, refreshToken: String, expiresAt: Int64) -> Credentials? {
            guard var obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                  var oauth = obj["claudeAiOauth"] as? [String: Any] else { return nil }
            oauth["accessToken"] = accessToken
            oauth["refreshToken"] = refreshToken
            oauth["expiresAt"] = expiresAt
            obj["claudeAiOauth"] = oauth
            guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
            return Credentials(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt, raw: data, source: source)
        }
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
            case .iso(let s):
                // The usage endpoint returns fractional seconds ("2026-07-03T00:30:00.282668+00:00");
                // the default formatter rejects those, so try the fractional form first.
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: s) { return date }
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: s)
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

    private func attemptFetch(_ creds: Credentials) async -> FetchOutcome {
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

    private func currentCredentials() async -> Credentials? {
        if let cached = await ClaudeCredentialStore.shared.get() { return cached }
        guard let loaded = Self.loadCredentialsFromSource() else { return nil }
        await ClaudeCredentialStore.shared.set(loaded)
        return loaded
    }

    // Force a re-read from source, bypassing the in-memory cache. Called after an auth
    // failure so a token rotated by Claude Code is picked up without an app restart.
    // The invalidate-and-reload is a single atomic actor operation (see reload(from:)).
    private func reloadCredentials() async -> Credentials? {
        await ClaudeCredentialStore.shared.reload(from: { Self.loadCredentialsFromSource() })
    }

    // File first never prompts; Keychain only as fallback. On the Keychain path, read the
    // freshest "Claude Code-credentials*" item: newer Claude Code stores its token under a
    // per-install hash suffix and no longer updates the un-suffixed item.
    private static func loadCredentialsFromSource() -> Credentials? {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
        if let data = try? Data(contentsOf: path), let parsed = Credentials.parse(data, source: .file(path)) {
            return parsed
        }
        guard let item = KeychainReader.freshestGenericPassword(servicePrefix: "Claude Code-credentials") else { return nil }
        return Credentials.parse(Data(item.secret.utf8), source: .keychain(service: item.service))
    }

    /// Stores a rotated pair where the credential was read from. The refresh that produced
    /// it invalidated the previous pair, so without this the source keeps a dead refresh
    /// token: the next Atoll launch cannot refresh, and neither can Claude Code, which is
    /// then logged out. Best-effort — the in-memory copy carries this process either way.
    private static func writeBack(_ creds: Credentials) {
        switch creds.source {
        case .file(let url):
            do {
                try creds.raw.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                print("⚠️ ClaudeQuotaClient: could not write refreshed credentials to \(url.lastPathComponent): \(error)")
            }
        case .keychain(let service):
            guard let secret = String(data: creds.raw, encoding: .utf8) else { return }
            if let status = KeychainReader.updateGenericPassword(service: service, secret: secret) {
                print("⚠️ ClaudeQuotaClient: could not write refreshed credentials to Keychain item \(service): OSStatus \(status)")
            }
        }
    }

    private func validAccessToken(_ creds: Credentials) async -> String? {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        // Refresh only once the token has actually expired. Refreshing early widens the
        // window in which Claude Code, on the same schedule, refreshes the same pair; one
        // of the two then loses its refresh token.
        if creds.expiresAt > nowMs { return creds.accessToken }
        // Claude Code may already have rotated the pair. Take a fresh read from the source
        // before spending the refresh token we hold.
        let reloaded = await reloadCredentials()
        if let reloaded, reloaded.expiresAt > nowMs { return reloaded.accessToken }
        let current = reloaded ?? creds

        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": current.refreshToken,
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
        guard let rotated = current.rotated(accessToken: refreshed.accessToken, refreshToken: refreshed.refreshToken, expiresAt: expiresAt) else {
            return refreshed.accessToken
        }
        await ClaudeCredentialStore.shared.set(rotated)
        Self.writeBack(rotated)
        return refreshed.accessToken
    }
}
