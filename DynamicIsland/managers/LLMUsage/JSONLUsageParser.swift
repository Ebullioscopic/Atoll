import Foundation

struct UsageRecord {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let dedupKey: String?
}

struct JSONLUsageParser {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseDate(_ s: String) -> Date? {
        if let d = iso.date(from: s) { return d }
        return isoPlain.date(from: s)
    }

    static func parseLine(_ line: String) -> UsageRecord? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if let codexRecord = parseCodexTokenCount(obj) {
            return codexRecord
        }

        let message = obj["message"] as? [String: Any]
        let usage = (message?["usage"] as? [String: Any]) ?? (obj["usage"] as? [String: Any])
        guard let usage else { return nil }
        let input = (usage["input_tokens"] as? Int ?? 0)
            + (usage["cache_creation_input_tokens"] as? Int ?? 0)
            + (usage["cache_read_input_tokens"] as? Int ?? 0)
        let output = usage["output_tokens"] as? Int ?? 0
        guard input + output > 0 else { return nil }
        let model = (message?["model"] as? String) ?? (obj["model"] as? String) ?? "unknown"
        let tsString = (obj["timestamp"] as? String) ?? (message?["timestamp"] as? String) ?? ""
        guard let ts = parseDate(tsString) else { return nil }
        let messageId = message?["id"] as? String
        let requestId = (obj["requestId"] as? String) ?? (obj["request_id"] as? String)
        let dedupKey = (messageId != nil || requestId != nil) ? "\(messageId ?? "")-\(requestId ?? "")" : nil
        return UsageRecord(timestamp: ts, model: model, inputTokens: input, outputTokens: output, dedupKey: dedupKey)
    }

    private static func parseCodexTokenCount(_ obj: [String: Any]) -> UsageRecord? {
        guard obj["type"] as? String == "event_msg",
              let payload = obj["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = info["last_token_usage"] as? [String: Any],
              let timestamp = obj["timestamp"] as? String,
              let date = parseDate(timestamp) else { return nil }

        // Codex emits a per-event delta and a session cumulative total. Only the delta is additive.
        // Token-count events have no stable identifier and are written once per session log.
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        guard input >= 0, output >= 0, (input > 0 || output > 0) else { return nil }

        return UsageRecord(
            timestamp: date,
            model: "codex",
            inputTokens: input,
            outputTokens: output,
            dedupKey: nil
        )
    }

    /// Session logs are append-only, so a file whose last write predates the
    /// window cannot contain a record inside it. Returns `true` when the date is
    /// unreadable, so an unexpected filesystem keeps the file rather than
    /// silently dropping its records.
    private static func mayContainRecords(after cutoff: Date, _ file: URL) -> Bool {
        guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        else { return true }
        return modified >= cutoff
    }

    static func aggregate(files: [URL], now: Date) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        var perModel: [String: UsageTotals] = [:]
        var seen = Set<String>()
        let cal = Calendar.current
        let sessionStart = now.addingTimeInterval(-5 * 3600)
        let weekStart = now.addingTimeInterval(-7 * 86400)

        for file in files where mayContainRecords(after: weekStart, file) {
            guard let content = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n") {
                guard let rec = parseLine(String(line)) else { continue }
                // Window first, then dedup: a record outside the window can no
                // longer claim a key and suppress an in-window record that
                // repeats it. That also makes the totals independent of which
                // files were read, which is what lets the skip above be sound.
                guard rec.timestamp >= weekStart else { continue }
                if let key = rec.dedupKey {
                    if seen.contains(key) { continue }
                    seen.insert(key)
                }
                let cost = ModelPricing.cost(model: rec.model, inputTokens: rec.inputTokens, outputTokens: rec.outputTokens)
                func add(_ t: inout UsageTotals) {
                    t.inputTokens += rec.inputTokens
                    t.outputTokens += rec.outputTokens
                    if let cost { t.costUSD += cost } else { t.hasUnpricedModel = true }
                }
                add(&snapshot.week)
                if cal.isDate(rec.timestamp, inSameDayAs: now) { add(&snapshot.today) }
                if rec.timestamp >= sessionStart { add(&snapshot.session) }
                var mt = perModel[rec.model] ?? UsageTotals()
                add(&mt)
                perModel[rec.model] = mt
            }
        }
        snapshot.models = perModel
            .map { ModelUsage(model: $0.key, totals: $0.value, pool: nil) }
            .sorted { $0.totals.costUSD > $1.totals.costUSD }
        snapshot.lastUpdated = now
        return snapshot
    }
}
