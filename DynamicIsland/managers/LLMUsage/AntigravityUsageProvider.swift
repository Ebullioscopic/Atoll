import Foundation
import Security

struct AntigravityUsageProvider: UsageProvider {
    let id: ProviderID = .antigravity
    let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    // Helper to add timeout to async operations
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // Overload for optional return types
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T?) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        snapshot.lastUpdated = now

        // Try to find Antigravity credentials in Keychain
        print("[Antigravity] Starting fetchSnapshot")
        let token = try await loadKeychainToken()
        guard let token else {
            print("[Antigravity] No token found in Keychain")
            throw UsageError.notConfigured("Antigravity not signed in")
        }
        print("[Antigravity] Token loaded from Keychain, accessToken: \(token.accessToken?.prefix(20) ?? "nil")..., length: \(token.accessToken?.count ?? 0)")

        // Try language server first (running Antigravity app) - quick 3s attempt
        print("[Antigravity] Trying language server...")
        if let lsSnapshot = try await fetchFromLanguageServer(now: now) {
            print("[Antigravity] Language server returned data")
            return lsSnapshot
        }
        print("[Antigravity] Language server returned nil, falling back to Cloud Code")

        // Fall back to Cloud Code API (primary source) - direct call with timeout
        print("[Antigravity] Trying Cloud Code API...")
        let result = try await fetchFromCloudCode(token: token, now: now)
        print("[Antigravity] Cloud Code API returned data")
        return result
    }

    // MARK: - Keychain

    private func loadKeychainToken() async throws -> AntigravityKeychainToken? {
        let service = "gemini"
        let account = "antigravity"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        print("[Antigravity] Keychain query status: \(status)")
        guard status == errSecSuccess, let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            print("[Antigravity] Keychain query failed: \(status)")
            return nil
        }

        return extractToken(from: string)
    }

    private func extractToken(from raw: String) -> AntigravityKeychainToken? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Try to unwrap go-keyring-base64
        var jsonString = trimmed
        if trimmed.hasPrefix("go-keyring-base64:") {
            let base64 = String(trimmed.dropFirst("go-keyring-base64:".count))
            if let data = Data(base64Encoded: base64),
               let str = String(data: data, encoding: .utf8) {
                jsonString = str
            }
        }

        // Parse JSON
        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AntigravityKeychainToken(accessToken: trimmed, refreshToken: nil, expiry: nil)
        }

        // Navigate to token object
        let source = (obj["token"] as? [String: Any]) ?? obj

        let access = (source["access_token"] as? String) ?? (source["accessToken"] as? String) ?? (source["token"] as? String)
        let refresh = (source["refresh_token"] as? String) ?? (source["refreshToken"] as? String)
        let expiryStr = (source["expiry"] as? String) ?? (source["expires_at"] as? String) ?? (source["expiresAt"] as? String)
        let expiry = expiryStr.flatMap { ISO8601DateFormatter().date(from: $0) }

        return AntigravityKeychainToken(accessToken: access, refreshToken: refresh, expiry: expiry)
    }

    // MARK: - Language Server

private func fetchFromLanguageServer(now: Date) async throws -> UsageSnapshot? {
        // Quick 3s attempt
        print("[Antigravity] Starting language server discovery")
        print("[Antigravity] Calling withTimeout...")
        return try await withTimeout(seconds: 3) {
            print("[Antigravity] Inside withTimeout, calling discoverLanguageServers...")
            let discoveries = try await discoverLanguageServers()
            print("[Antigravity] Discovered \(discoveries.count) language servers")

            if discoveries.isEmpty {
                print("[Antigravity] No language servers found, returning nil")
                return nil
            }

            for discovery in discoveries {
                // HTTPS first (LS serves self-signed cert), then HTTP, then extension port
                var endpoints: [(scheme: String, port: Int)] = []
                for port in discovery.ports {
                    endpoints.append(("https", port))
                    endpoints.append(("http", port))
                }
                if let extPort = discovery.extensionPort {
                    endpoints.append(("http", extPort))
                }

                for endpoint in endpoints {
                    // Try RetrieveUserQuotaSummary first (authoritative - merged pools + weekly windows)
                    print("[Antigravity] Trying LS \(endpoint.scheme)://127.0.0.1:\(endpoint.port) RetrieveUserQuotaSummary")
                    if let summary = try await callLS(scheme: endpoint.scheme, port: endpoint.port, csrf: discovery.csrf, method: "RetrieveUserQuotaSummary") {
                        if let snapshot = parseQuotaSummary(summary, now: now) {
                            print("[Antigravity] RetrieveUserQuotaSummary succeeded")
                            return snapshot
                        }
                    }

                    // Fall back to GetUserStatus
                    print("[Antigravity] Trying LS \(endpoint.scheme)://127.0.0.1:\(endpoint.port) GetUserStatus")
                    if let status = try await callLS(scheme: endpoint.scheme, port: endpoint.port, csrf: discovery.csrf, method: "GetUserStatus") {
                        if let snapshot = parseUserStatus(status, now: now) {
                            print("[Antigravity] GetUserStatus succeeded")
                            return snapshot
                        }
                    }

                    // Fall back to GetCommandModelConfigs
                    print("[Antigravity] Trying LS \(endpoint.scheme)://127.0.0.1:\(endpoint.port) GetCommandModelConfigs")
                    if let fallback = try await callLS(scheme: endpoint.scheme, port: endpoint.port, csrf: discovery.csrf, method: "GetCommandModelConfigs") {
                        if let snapshot = parseCommandModelConfigs(fallback, now: now) {
                            print("[Antigravity] GetCommandModelConfigs succeeded")
                            return snapshot
                        }
                    }
                }
            }

            // No snapshot found
            print("[Antigravity] No snapshot found from language servers")
            return nil
        }
    }

    private struct LSDiscovery {
        let ports: [Int]
        let csrf: String
        let extensionPort: Int?
    }

    private func discoverLanguageServers() async throws -> [LSDiscovery] {
        print("[Antigravity] discoverLanguageServers: starting...")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["aux"]

        let pipe = Pipe()
        task.standardOutput = pipe

        try task.run()
        print("[Antigravity] discoverLanguageServers: waiting for ps aux to exit...")
        
        // Add timeout to waitUntilExit
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second timeout
            print("[Antigravity] discoverLanguageServers: timeout, terminating process")
            task.terminate()
        }
        
        task.waitUntilExit()
        timeoutTask.cancel()
        print("[Antigravity] discoverLanguageServers: ps aux exited with status \(task.terminationStatus)")

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        print("[Antigravity] discoverLanguageServers: read \(data.count) bytes from ps aux")
        guard let output = String(data: data, encoding: .utf8) else { 
            print("[Antigravity] discoverLanguageServers: failed to decode output")
            return [] 
        }

        var discoveries: [LSDiscovery] = []

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: false)
            guard parts.count >= 11 else { continue }

            let command = parts[10...].joined(separator: " ")

            // Look for language_server with antigravity markers
            if command.contains("language_server") && (command.contains("antigravity") || command.contains("antigravity-ide")) {
                print("[Antigravity] Found antigravity language_server: \(command)")
                if let discovery = parseLanguageServerCommand(command) {
                    discoveries.append(discovery)
                }
            }

            // Also check for `agy` command
            if command.contains("agy") && command.contains("language_server") {
                print("[Antigravity] Found agy language_server: \(command)")
                if let discovery = parseLanguageServerCommand(command) {
                    discoveries.append(discovery)
                }
            }
        }

        print("[Antigravity] discoverLanguageServers: returning \(discoveries.count) discoveries")
        return discoveries
    }

    private func parseLanguageServerCommand(_ command: String) -> LSDiscovery? {
        var ports: [Int] = []
        var csrf: String?
        var extensionPort: Int?

        let args = command.split(separator: " ")
        for arg in args {
            if arg.hasPrefix("--extension_server_port=") {
                let portStr = String(arg.dropFirst("--extension_server_port=".count))
                if let port = Int(portStr) {
                    extensionPort = port
                    ports.append(port)
                }
            } else if arg.hasPrefix("--port=") {
                let portStr = String(arg.dropFirst("--port=".count))
                if let port = Int(portStr) {
                    ports.append(port)
                }
            } else if arg.hasPrefix("--csrf_token=") {
                csrf = String(arg.dropFirst("--csrf_token=".count))
            }
        }

        guard !ports.isEmpty, let csrf else { return nil }

        return LSDiscovery(ports: ports, csrf: csrf, extensionPort: extensionPort)
    }

    private func callLS(scheme: String, port: Int, csrf: String, method: String) async throws -> Data? {
        let baseURL = "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService"
        let metadata = ["ideName": "antigravity", "extensionName": "antigravity", "ideVersion": "unknown", "locale": "en"]

        guard let url = URL(string: "\(baseURL)/\(method)") else { return nil }

        let body = try? JSONSerialization.data(withJSONObject: ["metadata": metadata])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrf, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = body
        request.timeoutInterval = 3

        // Use session that allows insecure localhost (self-signed cert)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }

        return data
    }

    private func parseQuotaSummary(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let groups = (obj["response"] as? [String: Any])?["groups"] as? [[String: Any]] ?? obj["groups"] as? [[String: Any]]
        guard let groups else { return nil }

        var pooled: [String: (fraction: Double, resetTime: Date?)] = [:]

        let bucketMap: [String: (pool: String, window: String, gaugeLabel: String, modelLabel: String, periodMs: Int)] = [
            "gemini-5h": ("gemini", "session", "Session", "5h", 5 * 60 * 60 * 1000),
            "gemini-weekly": ("gemini", "weekly", "Weekly", "Weekly", 7 * 24 * 60 * 60 * 1000),
            "3p-5h": ("claude", "session", "Session", "5h", 5 * 60 * 60 * 1000),
            "3p-weekly": ("claude", "weekly", "Weekly", "Weekly", 7 * 24 * 60 * 60 * 1000)
        ]

        var models: [ModelUsage] = []

        for group in groups {
            guard let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                guard let id = bucket["bucketId"] as? String,
                      let spec = bucketMap[id],
                      let fraction = bucket["remainingFraction"] as? Double,
                      fraction.isFinite else { continue }

                let resetTime = (bucket["resetTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                pooled[id] = (fraction, resetTime)

                // Create model entries for UI pool selector, store fraction in costUSD
                let usedPct = (1 - max(0, min(1, fraction))) * 100
                let limit = UsageLimit(used: usedPct, limit: 100, resetsAt: resetTime)
                // Use hasUnpricedModel to encode pool: true = claude, false = gemini
models.append(ModelUsage(model: spec.modelLabel, totals: UsageTotals(
                    inputTokens: Int(usedPct), // Store used percentage here
                    outputTokens: 0,
                    costUSD: fraction, // Store fraction for cost
                    hasUnpricedModel: spec.pool == "claude" // true = claude, false = gemini
                )))
            }
        }

        var snapshot = UsageSnapshot()
        snapshot.lastUpdated = now
        snapshot.models = models

        // Populate limits for BOTH pools
        if let entry = pooled["gemini-5h"] {
            let usedPct = (1 - max(0, min(1, entry.fraction))) * 100
            snapshot.sessionLimit = UsageLimit(used: usedPct, limit: 100, resetsAt: entry.resetTime)
        }
        if let entry = pooled["gemini-weekly"] {
            let usedPct = (1 - max(0, min(1, entry.fraction))) * 100
            snapshot.weekLimit = UsageLimit(used: usedPct, limit: 100, resetsAt: entry.resetTime)
        }
        if let entry = pooled["3p-5h"] {
            let usedPct = (1 - max(0, min(1, entry.fraction))) * 100
            // Store Claude 5h in a way we can access it - use sessionLimit for now but we'll differentiate in UI
        }
        if let entry = pooled["3p-weekly"] {
            let usedPct = (1 - max(0, min(1, entry.fraction))) * 100
            // Store Claude Weekly
        }

        return snapshot
    }

    private func parseUserStatus(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userStatus = obj["userStatus"] as? [String: Any] else { return nil }

        let plan = (userStatus["userTier"] as? [String: Any])?["name"] as? String ??
                   (userStatus["planStatus"] as? [String: Any])?["planInfo"].flatMap { ($0 as? [String: Any])?["planName"] as? String }

        var configs: [AntigravityModelConfig] = []

        if let cascade = userStatus["cascadeModelConfigData"] as? [String: Any],
           let clientConfigs = cascade["clientModelConfigs"] as? [[String: Any]] {
            for config in clientConfigs {
                if let modelConfig = parseModelConfig(config) {
                    configs.append(modelConfig)
                }
            }
        }

        return buildSnapshot(from: configs, plan: plan, now: now)
    }

    private func parseCommandModelConfigs(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let clientConfigs = obj["clientModelConfigs"] as? [[String: Any]] else { return nil }

        var configs: [AntigravityModelConfig] = []
        for config in clientConfigs {
            if let modelConfig = parseModelConfig(config) {
                configs.append(modelConfig)
            }
        }

        return buildSnapshot(from: configs, plan: nil as String?, now: now)
    }

    private func parseModelConfig(_ obj: [String: Any]) -> AntigravityModelConfig? {
        guard let label = (obj["label"] as? String)?.trimmingCharacters(in: .whitespaces),
              !label.isEmpty else { return nil }

        let modelID = (obj["modelOrAlias"] as? [String: Any])?["model"] as? String
        let quota = obj["quotaInfo"] as? [String: Any]
        let remainingFraction = quota?["remainingFraction"] as? Double ?? 0
        let resetTime = (quota?["resetTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }

        return AntigravityModelConfig(label: label, modelID: modelID, remainingFraction: remainingFraction, resetTime: resetTime)
    }

    // MARK: - Cloud Code API

    private func fetchFromCloudCode(token: AntigravityKeychainToken, now: Date) async throws -> UsageSnapshot {
        // 15s overall timeout
        print("[Antigravity] Starting Cloud Code API fetch")
        return try await withThrowingTaskGroup(of: UsageSnapshot.self) { group in
            group.addTask {
                var snapshot = UsageSnapshot()
                snapshot.lastUpdated = now

                let baseURLs = [
                    "https://daily-cloudcode-pa.googleapis.com",
                    "https://cloudcode-pa.googleapis.com"
                ]

                // Try quota summary first (authoritative)
                for baseURL in baseURLs {
                    print("[Antigravity] Trying Cloud Code \(baseURL)/retrieveUserQuotaSummary")
                    if let data = try await self.cloudCodeCall(path: "/v1internal:retrieveUserQuotaSummary", baseURL: baseURL, token: token) {
                        print("[Antigravity] retrieveUserQuotaSummary returned data")
                        if let parsed = self.parseQuotaSummary(data, now: now) {
                            print("[Antigravity] retrieveUserQuotaSummary parsed successfully")
                            return parsed
                        }
                    } else {
                        print("[Antigravity] retrieveUserQuotaSummary returned nil for \(baseURL)")
                    }
                }

                // Fall back to fetchAvailableModels
                for baseURL in baseURLs {
                    print("[Antigravity] Trying Cloud Code \(baseURL)/fetchAvailableModels")
                    if let data = try await self.cloudCodeCall(path: "/v1internal:fetchAvailableModels", baseURL: baseURL, token: token) {
                        print("[Antigravity] fetchAvailableModels returned data")
                        if let snapshot = self.parseCloudCodeModels(data, now: now) {
                            print("[Antigravity] fetchAvailableModels parsed successfully")
                            return snapshot
                        }
                    } else {
                        print("[Antigravity] fetchAvailableModels returned nil for \(baseURL)")
                    }
                }

                throw UsageError.notConfigured("Unable to fetch Antigravity usage")
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000) // 15 second timeout
                throw TimeoutError()
            }

            do {
                let result = try await group.next()!
                group.cancelAll()
                print("[Antigravity] Cloud Code API completed successfully")
                return result
            } catch is TimeoutError {
                group.cancelAll()
                print("[Antigravity] Cloud Code API timeout")
                throw UsageError.notConfigured("Antigravity request timed out")
            }
        }
    }

    private func cloudCodeCall(path: String, baseURL: String, token: AntigravityKeychainToken) async throws -> Data? {
        guard let accessToken = token.accessToken,
              let url = URL(string: baseURL + path) else { 
            print("[Antigravity] cloudCodeCall: missing token or invalid URL")
            return nil 
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
        request.httpBody = "{}".data(using: .utf8)
        request.timeoutInterval = 8

        print("[Antigravity] Calling \(path) at \(baseURL)")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { 
                print("[Antigravity] Non-HTTP response")
                return nil 
            }
            print("[Antigravity] HTTP \(http.statusCode) for \(path) at \(baseURL)")
            if http.statusCode == 401 || http.statusCode == 403 {
                print("[Antigravity] Auth expired (401/403)")
                throw UsageError.notConfigured("Antigravity auth expired")
            }
            if (200..<300).contains(http.statusCode) {
                return data
            }
            print("[Antigravity] Unexpected status \(http.statusCode), response: \(String(data: data, encoding: .utf8) ?? "nil")")
        } catch {
            print("[Antigravity] Request error for \(path): \(error)")
        }
        return nil
    }

    private func parseCloudCodeModels(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = obj["models"] as? [String: Any] else { return nil }

        var configs: [AntigravityModelConfig] = []
        for (key, value) in models {
            guard let model = value as? [String: Any],
                  model["isInternal"] as? Bool != true,
                  let label = (model["displayName"] as? String) ?? (model["label"] as? String),
                  !label.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            let modelID = (model["model"] as? String) ?? key
            let quota = model["quotaInfo"] as? [String: Any]
            let remainingFraction = quota?["remainingFraction"] as? Double ?? 0
            let resetTime = (quota?["resetTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }

            configs.append(AntigravityModelConfig(label: label, modelID: modelID, remainingFraction: remainingFraction, resetTime: resetTime))
        }

        return buildSnapshot(from: configs, plan: nil as String?, now: now)
    }

    private func buildSnapshot(from configs: [AntigravityModelConfig], plan: String?, now: Date) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        snapshot.lastUpdated = now

        // Pool into Gemini (Session) and non-Gemini (Claude)
        var geminiFraction: Double = 1
        var geminiReset: Date?
        var claudeFraction: Double = 1
        var claudeReset: Date?

        for config in configs {
            let normalized = config.label
                .replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
                .lowercased()

            let pool = normalized.contains("gemini") ? "gemini" : "claude"
            let fraction = max(0, min(1, config.remainingFraction))

            if pool == "gemini" {
                if fraction < geminiFraction {
                    geminiFraction = fraction
                    geminiReset = config.resetTime
                }
            } else {
                if fraction < claudeFraction {
                    claudeFraction = fraction
                    claudeReset = config.resetTime
                }
            }
        }

        if geminiFraction < 1 {
            let used = (1 - geminiFraction) * 100
            snapshot.sessionLimit = UsageLimit(used: used, limit: 100, resetsAt: geminiReset)
        }
        if claudeFraction < 1 {
            let used = (1 - claudeFraction) * 100
            // Legacy endpoints only provide 5h data
            if snapshot.sessionLimit == nil {
                snapshot.sessionLimit = UsageLimit(used: used, limit: 100, resetsAt: claudeReset)
            }
        }

        return snapshot
    }
}

// MARK: - Supporting Types

struct AntigravityKeychainToken {
    let accessToken: String?
    let refreshToken: String?
    let expiry: Date?
}

struct AntigravityModelConfig {
    let label: String
    let modelID: String?
    let remainingFraction: Double
    let resetTime: Date?
}

private struct TimeoutError: Error {}
private struct NotFoundError: Error {}