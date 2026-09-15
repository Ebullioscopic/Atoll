import Foundation
import os

struct AntigravityUsageProvider: UsageProvider {
    let id: ProviderID = .antigravity
    let session: URLSession
    private static let log = os.Logger(subsystem: "com.atoll.DynamicIsland", category: "AntigravityUsage")

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

        // The language server path needs no keychain token, so try it first —
        // reading the token item owned by the Gemini CLI otherwise triggers the
        // login keychain password prompt on every refresh.
        // LS discovery/transport failures are availability issues, not snapshot
        // errors — fall through to the keychain path rather than aborting.
        var lsSnapshot: UsageSnapshot?
        do {
            lsSnapshot = try await fetchFromLanguageServer(now: now)
        } catch {
            Self.log.info("Antigravity language server unavailable (\(error)) — falling back to keychain token path")
        }
        if let lsSnapshot {
            return lsSnapshot
        }

        let token = try await loadKeychainToken()
        guard let token else {
            throw UsageError.notConfigured("Antigravity not signed in")
        }

        return try await fetchFromCloudCode(token: token, now: now)
    }

    // MARK: - Keychain

    private func loadKeychainToken() async throws -> AntigravityKeychainToken? {
        // Use the `security` CLI — it matches the item's apple-tool partition grant, so no login-keychain password prompt (unlike SecItemCopyMatching).
        return try await withTimeout(seconds: 3) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            task.arguments = ["find-generic-password", "-a", "antigravity", "-s", "gemini", "-w"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()

            do { try task.run() } catch { return nil }

            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                task.terminate()
            }

            // Blocking on waitUntilExit() defeats withTimeout cancellation and
            // strands the process on the cooperative pool; resume from the
            // termination handler instead and terminate on cancellation.
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    task.terminationHandler = { _ in
                        continuation.resume()
                    }
                }
            } onCancel: {
                task.terminate()
            }
            timeoutTask.cancel()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard task.terminationStatus == 0,
                  let string = String(data: data, encoding: .utf8) else { return nil }

            return extractToken(from: string)
        }
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

    private struct LSEndpoint {
        let scheme: String
        let port: Int
        let csrf: String
    }

    private func fetchFromLanguageServer(now: Date) async throws -> UsageSnapshot? {
        guard let (quota, endpoint) = try await fetchQuotaFromLanguageServer(now: now) else {
            Self.log.info("Antigravity LS: no endpoint answered the quota calls")
            return nil
        }
        Self.log.info("Antigravity LS: quota via \(endpoint.scheme, privacy: .public):\(endpoint.port, privacy: .public)")
        var snapshot = quota
        // Token usage is a separate, slower walk over conversation history; a failure or
        // timeout there must not take the quota gauges down with it.
        do {
            if let usage = try await withTimeout(seconds: 10, operation: { try await self.fetchTokenUsage(endpoint: endpoint, now: now) }) {
                snapshot.today = usage.today
                snapshot.week = usage.week
                snapshot.session = usage.session
            }
        } catch {
            Self.log.info("Antigravity token usage unavailable: \(String(describing: error), privacy: .public)")
        }
        return snapshot
    }

    private func fetchQuotaFromLanguageServer(now: Date) async throws -> (UsageSnapshot, LSEndpoint)? {
        return try await withTimeout(seconds: 8) {
            let discoveries = try await discoverLanguageServers()
            Self.log.info("Antigravity LS: discovered \(discoveries.count, privacy: .public) server(s): \(discoveries.map { "\($0.ports)" }.joined(separator: " "), privacy: .public)")

            if discoveries.isEmpty {
                return nil
            }

            for discovery in discoveries {
                var endpoints: [(scheme: String, port: Int)] = []
                for port in discovery.ports {
                    endpoints.append(("https", port))
                    endpoints.append(("http", port))
                }
                if let extPort = discovery.extensionPort {
                    endpoints.append(("http", extPort))
                }

                for endpoint in endpoints {
                    let ep = LSEndpoint(scheme: endpoint.scheme, port: endpoint.port, csrf: discovery.csrf)
                    if let summary = try await callLS(scheme: endpoint.scheme, port: endpoint.port, csrf: discovery.csrf, method: "RetrieveUserQuotaSummary") {
                        if let snapshot = parseQuotaSummary(summary, now: now) {
                            return (snapshot, ep)
                        }
                    }

                    if let status = try await callLS(scheme: endpoint.scheme, port: endpoint.port, csrf: discovery.csrf, method: "GetUserStatus") {
                        if let snapshot = parseUserStatus(status, now: now) {
                            return (snapshot, ep)
                        }
                    }

                    if let fallback = try await callLS(scheme: endpoint.scheme, port: endpoint.port, csrf: discovery.csrf, method: "GetCommandModelConfigs") {
                        if let snapshot = parseCommandModelConfigs(fallback, now: now) {
                            return (snapshot, ep)
                        }
                    }
                }
            }

            return nil
        }
    }

    private struct LSDiscovery {
        let ports: [Int]
        let csrf: String
        let extensionPort: Int?
    }

    private func discoverLanguageServers() async throws -> [LSDiscovery] {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/ps")
                // pid + full command line only: far less output than `ps aux`.
                task.arguments = ["-axo", "pid=,args="]

                let pipe = Pipe()
                task.standardOutput = pipe

                do {
                    try task.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    task.terminate()
                }

                // Drain the pipe BEFORE waiting: with hundreds of processes the listing
                // exceeds the 64 KB pipe buffer, so waiting first deadlocks until the
                // timeout kills ps and only the head of the list is ever seen.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                timeoutTask.cancel()

                guard let output = String(data: data, encoding: .utf8) else {
                    Self.log.info("Antigravity LS: ps output not decodable (\(data.count, privacy: .public) bytes, status \(task.terminationStatus, privacy: .public))")
                    continuation.resume(returning: [])
                    return
                }

                var discoveries: [LSDiscovery] = []
                let lines = output.split(separator: "\n")
                var candidates = 0

                for line in lines {
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    guard parts.count >= 2 else { continue }

                    let pid = Int32(parts[0])
                    let command = parts[1...].joined(separator: " ")

                    let isAntigravity = command.contains("language_server")
                        && (command.contains("antigravity") || command.contains("antigravity-ide") || command.contains("agy"))
                    guard isAntigravity else { continue }
                    candidates += 1

                    // The desktop client starts its language server with "--https_server_port 0"
                    // (a kernel-assigned port), so the command line alone may not name a port;
                    // ask lsof which ports that PID is actually listening on.
                    let listening = pid.map { Self.listeningPorts(pid: $0) } ?? []
                    Self.log.debug("Antigravity LS: candidate pid \(pid ?? -1, privacy: .public) listening on \(listening, privacy: .public)")
                    if let discovery = parseLanguageServerCommand(String(command), fallbackPorts: listening) {
                        discoveries.append(discovery)
                    }
                }
                Self.log.debug("Antigravity LS: ps returned \(lines.count, privacy: .public) lines (status \(task.terminationStatus, privacy: .public)), \(candidates, privacy: .public) language_server candidate(s)")

                continuation.resume(returning: discoveries)
            }
        }
    }

    private func parseLanguageServerCommand(_ command: String, fallbackPorts: [Int] = []) -> LSDiscovery? {
        var ports: [Int] = []
        var csrf: String?
        var extensionPort: Int?

        // Flags appear either as "--name=value" (IDE) or "--name value" (desktop client).
        let args = command.split(separator: " ").map(String.init)
        var flags: [String: String] = [:]
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("--") {
                if let eq = arg.firstIndex(of: "=") {
                    flags[String(arg[arg.index(arg.startIndex, offsetBy: 2)..<eq])] = String(arg[arg.index(after: eq)...])
                } else if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
                    flags[String(arg.dropFirst(2))] = args[i + 1]
                    i += 1
                }
            }
            i += 1
        }

        if let p = flags["extension_server_port"].flatMap(Int.init), p > 0 {
            extensionPort = p
            ports.append(p)
        }
        for key in ["port", "https_server_port", "server_port"] {
            if let p = flags[key].flatMap(Int.init), p > 0, !ports.contains(p) { ports.append(p) }
        }
        for p in fallbackPorts where !ports.contains(p) { ports.append(p) }
        csrf = flags["csrf_token"]

        guard !ports.isEmpty, let csrf, !csrf.isEmpty else { return nil }

        return LSDiscovery(ports: ports, csrf: csrf, extensionPort: extensionPort)
    }

    /// TCP ports `pid` is listening on, via `lsof -Fn` (one "n<addr>:<port>" line per socket).
    private static func listeningPorts(pid: Int32) -> [Int] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-nP", "-a", "-p", "\(pid)", "-iTCP", "-sTCP:LISTEN", "-Fn"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return [] }
        // lsof normally returns in milliseconds; if it ever hangs (stuck mount, wedged
        // socket), kill it so the synchronous read below cannot block discovery forever.
        let watchdog = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        watchdog.cancel()
        guard task.terminationStatus == 0, let out = String(data: data, encoding: .utf8) else { return [] }
        var ports: [Int] = []
        for line in out.split(separator: "\n") where line.hasPrefix("n") {
            if let colon = line.lastIndex(of: ":"), let p = Int(line[line.index(after: colon)...]), !ports.contains(p) {
                ports.append(p)
            }
        }
        return ports
    }

    private func callLS(scheme: String, port: Int, csrf: String, method: String, params: [String: Any] = [:]) async throws -> Data? {
        let baseURL = "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService"
        let metadata = ["ideName": "antigravity", "extensionName": "antigravity", "ideVersion": "unknown", "locale": "en"]

        guard let url = URL(string: "\(baseURL)/\(method)") else { return nil }

        var payload: [String: Any] = ["metadata": metadata]
        for (k, v) in params { payload[k] = v }
        let body = try? JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrf, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = body
        request.timeoutInterval = 3

        // Use session that allows insecure localhost (self-signed cert)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.log.debug("Antigravity LS: \(scheme, privacy: .public):\(port, privacy: .public)/\(method, privacy: .public) transport error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            Self.log.debug("Antigravity LS: \(scheme, privacy: .public):\(port, privacy: .public)/\(method, privacy: .public) HTTP \(code, privacy: .public)")
            return nil
        }

        return data
    }

    // MARK: - Token usage from conversation history

    private struct TokenUsageWindows {
        var today = UsageTotals()
        var week = UsageTotals()
        var session = UsageTotals()
    }

    private static let stepDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let stepDatePlain = ISO8601DateFormatter()

    private static func number(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) ?? Int(Double(s) ?? 0) }
        return 0
    }

    private static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        return stepDate.date(from: s) ?? stepDatePlain.date(from: s)
    }

    /// Walks every conversation the language server knows about that was touched in the
    /// last week, reads the per-response `metadata.modelUsage` counters the server records
    /// on each model reply, and prices them like the Claude/Codex log parsers do.
    ///
    /// Model ids in those counters are opaque placeholders ("MODEL_PLACEHOLDER_M298");
    /// `GetUserStatus` maps them to public ids ("gemini-3.7-flash-high") for pricing.
    private func fetchTokenUsage(endpoint: LSEndpoint, now: Date) async throws -> TokenUsageWindows? {
        let weekStart = now.addingTimeInterval(-7 * 86400)
        let sessionStart = now.addingTimeInterval(-5 * 3600)
        let cal = Calendar.current

        var modelIds: [String: String] = [:]
        if let statusData = try await callLS(scheme: endpoint.scheme, port: endpoint.port, csrf: endpoint.csrf, method: "GetUserStatus"),
           let status = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
           let configs = ((status["userStatus"] as? [String: Any])?["cascadeModelConfigData"] as? [String: Any])?["clientModelConfigs"] as? [[String: Any]] {
            for c in configs {
                let alias = c["modelOrAlias"] as? [String: Any]
                guard let placeholder = (alias?["model"] as? String) ?? (alias?["alias"] as? String) else { continue }
                if let id = c["modelId"] as? String, !id.isEmpty { modelIds[placeholder] = id }
            }
        }

        Self.log.debug("Antigravity LS: \(modelIds.count, privacy: .public) model ids mapped")
        guard let listData = try await callLS(scheme: endpoint.scheme, port: endpoint.port, csrf: endpoint.csrf, method: "GetAllCascadeTrajectories") else {
            Self.log.info("Antigravity LS: GetAllCascadeTrajectories failed")
            return nil
        }
        guard let list = try? JSONSerialization.jsonObject(with: listData) as? [String: Any],
              let summaries = list["trajectorySummaries"] as? [String: [String: Any]] else {
            Self.log.info("Antigravity LS: unexpected trajectory list shape (\(listData.count, privacy: .public) bytes)")
            return nil
        }
        Self.log.debug("Antigravity LS: \(summaries.count, privacy: .public) trajectories")

        var windows = TokenUsageWindows()
        var seen = Set<String>()
        var replies = 0

        for (cascadeId, summary) in summaries {
            if let modified = Self.date(summary["lastModifiedTime"]), modified < weekStart { continue }
            let stepCount = Self.number(summary["stepCount"])
            guard stepCount > 0 else { continue }

            var start = 0
            while start < stepCount {
                let end = min(start + 50, stepCount)
                let params: [String: Any] = ["cascadeId": cascadeId, "startIndex": start, "endIndex": end]
                guard let data = try await callLS(scheme: endpoint.scheme, port: endpoint.port, csrf: endpoint.csrf, method: "GetCascadeTrajectorySteps", params: params),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let steps = obj["steps"] as? [[String: Any]] else {
                    Self.log.info("Antigravity LS: steps \(start, privacy: .public)-\(end, privacy: .public) of \(cascadeId, privacy: .public) failed")
                    break
                }

                for step in steps {
                    guard let meta = step["metadata"] as? [String: Any],
                          let usage = meta["modelUsage"] as? [String: Any],
                          let ts = Self.date(meta["createdAt"]), ts >= weekStart else { continue }
                    if let messageId = usage["messageId"] as? String {
                        if seen.contains(messageId) { continue }
                        seen.insert(messageId)
                    }
                    let input = Self.number(usage["inputTokens"])
                    let output = Self.number(usage["outputTokens"])
                    let cacheRead = min(input, Self.number(usage["cacheReadTokens"]))
                    guard input + output > 0 else { continue }

                    let placeholder = usage["model"] as? String ?? "unknown"
                    let model = modelIds[placeholder] ?? placeholder
                    let cost = ModelPricing.cost(model: model, inputTokens: input - cacheRead, outputTokens: output, cacheReadTokens: cacheRead)

                    func add(_ t: inout UsageTotals) {
                        t.inputTokens += input
                        t.outputTokens += output
                        if let cost { t.costUSD += cost } else { t.hasUnpricedModel = true }
                    }
                    add(&windows.week)
                    if cal.isDate(ts, inSameDayAs: now) { add(&windows.today) }
                    if ts >= sessionStart { add(&windows.session) }
                    replies += 1
                }
                if steps.isEmpty { break }
                start = end
            }
        }

        Self.log.info("Antigravity token usage: \(replies, privacy: .public) replies, week \(windows.week.totalTokens, privacy: .public) tokens")
        return windows
    }

    private func parseQuotaSummary(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let groups = (obj["response"] as? [String: Any])?["groups"] as? [[String: Any]] ?? obj["groups"] as? [[String: Any]]
        guard let groups else { return nil }

        var pooled: [String: (fraction: Double, resetTime: Date?)] = [:]

        let bucketMap: [String: (pool: String, window: String, label: String, periodMs: Int)] = [
            "gemini-5h": ("gemini", "session", "Session", 5 * 60 * 60 * 1000),
            "gemini-weekly": ("gemini", "weekly", "Weekly", 7 * 24 * 60 * 60 * 1000),
            "3p-5h": ("claude", "session", "Session", 5 * 60 * 60 * 1000),
            "3p-weekly": ("claude", "weekly", "Weekly", 7 * 24 * 60 * 60 * 1000)
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

                let usedPct = (1 - max(0, min(1, fraction))) * 100
                models.append(ModelUsage(model: spec.label, totals: UsageTotals(
                    inputTokens: Int(usedPct),
                    outputTokens: 0,
                    costUSD: fraction,
                    isPercentage: true
                ), pool: spec.pool, resetsAt: resetTime))
            }
        }

        var snapshot = UsageSnapshot()
        snapshot.lastUpdated = now
        snapshot.models = models

        // Populate limits for gemini pool (primary); claude pool limits would overwrite so skip
        if let entry = pooled["gemini-5h"] {
            let usedPct = (1 - max(0, min(1, entry.fraction))) * 100
            snapshot.sessionLimit = UsageLimit(used: usedPct, limit: 100, resetsAt: entry.resetTime)
        }
        if let entry = pooled["gemini-weekly"] {
            let usedPct = (1 - max(0, min(1, entry.fraction))) * 100
            snapshot.weekLimit = UsageLimit(used: usedPct, limit: 100, resetsAt: entry.resetTime)
        }

        return snapshot
    }

    private func parseUserStatus(_ data: Data, now: Date) -> UsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let userStatus = obj["userStatus"] as? [String: Any] else { return nil }

        var configs: [AntigravityModelConfig] = []

        if let cascade = userStatus["cascadeModelConfigData"] as? [String: Any],
           let clientConfigs = cascade["clientModelConfigs"] as? [[String: Any]] {
            for config in clientConfigs {
                if let modelConfig = parseModelConfig(config) {
                    configs.append(modelConfig)
                }
            }
        }

        return buildSnapshot(from: configs, now: now)
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

        return buildSnapshot(from: configs, now: now)
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
                    if let data = try await self.cloudCodeCall(path: "/v1internal:retrieveUserQuotaSummary", baseURL: baseURL, token: token) {
                        if let parsed = self.parseQuotaSummary(data, now: now) {
                            return parsed
                        }
                    }
                }

                // Fall back to fetchAvailableModels
                for baseURL in baseURLs {
                    if let data = try await self.cloudCodeCall(path: "/v1internal:fetchAvailableModels", baseURL: baseURL, token: token) {
                        if let snapshot = self.parseCloudCodeModels(data, now: now) {
                            return snapshot
                        }
                    }
                }

                throw UsageError.notConfigured("Unable to fetch Antigravity usage")
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000) // 15 second timeout
                throw TimeoutError()
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func cloudCodeCall(path: String, baseURL: String, token: AntigravityKeychainToken) async throws -> Data? {
        guard let accessToken = token.accessToken,
              let url = URL(string: baseURL + path) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
        request.httpBody = "{}".data(using: .utf8)
        request.timeoutInterval = 8

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw UsageError.notConfigured("Antigravity auth expired")
            }
            if (200..<300).contains(http.statusCode) {
                return data
            }
        } catch {
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

        return buildSnapshot(from: configs, now: now)
    }

    private func buildSnapshot(from configs: [AntigravityModelConfig], now: Date) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        snapshot.lastUpdated = now

        // Pool into Gemini (Session) and non-Gemini (Claude)
        var geminiFraction: Double = 1
        var geminiReset: Date?
        var claudeFraction: Double = 1
        var claudeReset: Date?

        var models: [ModelUsage] = []

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

            // Create model usage entry with pool info
            let usedPct = (1 - fraction) * 100
            models.append(ModelUsage(model: config.label, totals: UsageTotals(
                inputTokens: Int(usedPct),
                outputTokens: 0,
                costUSD: fraction,
                isPercentage: true
            ), pool: pool, resetsAt: config.resetTime))
        }

        snapshot.models = models

        if geminiFraction < 1 {
            let used = (1 - geminiFraction) * 100
            snapshot.sessionLimit = UsageLimit(used: used, limit: 100, resetsAt: geminiReset)
        }
        if claudeFraction < 1 {
            let used = (1 - claudeFraction) * 100
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