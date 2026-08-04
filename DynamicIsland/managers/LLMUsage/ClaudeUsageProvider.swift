import Foundation

struct ClaudeUsageProvider: UsageProvider {
    let id: ProviderID = .claude
    let root: URL
    let quotaClient: ClaudeQuotaClient

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"), quotaClient: ClaudeQuotaClient = ClaudeQuotaClient()) {
        self.root = root
        self.quotaClient = quotaClient
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw UsageError.notFound("No ~/.claude/projects — Claude Code not detected")
        }
        let files = jsonlFiles(under: root)
        guard !files.isEmpty else { throw UsageError.notFound("No Claude usage logs found") }
        var snapshot = JSONLUsageParser.aggregate(files: files, now: now)
        let quota = await quotaClient.fetchLimits()
        snapshot.sessionLimit = quota.session
        snapshot.weekLimit = quota.week
        snapshot.plan = Self.readPlanLabel()
        return snapshot
    }

    private func jsonlFiles(under dir: URL) -> [URL] {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return en.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    /// Reads the subscription plan from the plaintext `oauthAccount` fields in `~/.claude.json`
    /// (not a credential, no token). Prefers `organizationRateLimitTier` (distinguishes Max 5x / 20x),
    /// falling back to `organizationType`. Returns nil if the file is missing or malformed, so the
    /// badge simply does not render — this is best-effort and never fails the snapshot.
    private static func readPlanLabel() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = obj["oauthAccount"] as? [String: Any] else { return nil }
        // Prefer the rate-limit tier, but fall back to organizationType when it is
        // absent OR blank/whitespace (a present-but-empty string must not short-circuit
        // the fallback). Return nil if neither yields a non-empty label so the badge
        // isn't rendered as an empty capsule.
        let raw = [account["organizationRateLimitTier"], account["organizationType"]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let raw else { return nil }
        let label = prettyPlan(raw)
        return label.isEmpty ? nil : label
    }

    /// "default_claude_max_5x" → "Max 5x"; "claude_max" → "Max"; "claude_pro" → "Pro".
    private static func prettyPlan(_ raw: String) -> String {
        var s = raw
        for prefix in ["default_claude_", "claude_", "default_"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
            break
        }
        let parts = s.split(separator: "_").map { seg -> String in
            // Keep multiplier tokens like "5x" / "20x" as-is; capitalize the rest.
            if seg.range(of: "^[0-9]+x$", options: .regularExpression) != nil { return String(seg) }
            return seg.prefix(1).uppercased() + seg.dropFirst()
        }
        return parts.joined(separator: " ")
    }
}

enum UsageError: LocalizedError {
    case notFound(String)
    case notConfigured(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let m), .notConfigured(let m): return m
        }
    }
}
