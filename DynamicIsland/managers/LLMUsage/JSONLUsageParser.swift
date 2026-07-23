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

    static func aggregate(files: [URL], now: Date) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        var perModel: [String: UsageTotals] = [:]
        var seen = Set<String>()
        let cal = Calendar.current
        let sessionStart = now.addingTimeInterval(-5 * 3600)
        let weekStart = now.addingTimeInterval(-7 * 86400)

        for file in files {
            // Stream the file line-by-line instead of loading the whole JSONL log
            // (potentially many MB) into a String plus a full array of substrings.
            enumerateLines(of: file) { line in
                guard let rec = parseLine(line) else { return }
                if let key = rec.dedupKey {
                    if seen.contains(key) { return }
                    seen.insert(key)
                }
                guard rec.timestamp >= weekStart else { return }
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
            .map { ModelUsage(model: $0.key, totals: $0.value) }
            .sorted { $0.totals.costUSD > $1.totals.costUSD }
        snapshot.lastUpdated = now
        return snapshot
    }

    /// Reads a file in fixed-size chunks and invokes `handler` once per non-empty
    /// line, without ever holding the entire file in memory. Runs synchronously on
    /// the caller's thread (aggregation already happens off the main thread).
    private static func enumerateLines(of file: URL, _ handler: (String) -> Void) {
        guard let fh = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? fh.close() }

        let chunkSize = 1 << 16 // 64 KB
        let newline = UInt8(0x0A)
        var buffer = Data()

        while let chunk = try? fh.read(upToCount: chunkSize), !chunk.isEmpty {
            buffer.append(chunk)
            // Scan the whole chunk advancing a cursor, then trim the consumed
            // prefix once. The previous per-line removeSubrange shifted the rest
            // of the buffer for every newline → quadratic on newline-dense JSONL.
            var searchStart = buffer.startIndex
            while let newlineIndex = buffer[searchStart...].firstIndex(of: newline) {
                let lineData = buffer[searchStart..<newlineIndex]
                if !lineData.isEmpty, let line = String(data: lineData, encoding: .utf8) {
                    handler(line)
                }
                searchStart = buffer.index(after: newlineIndex)
            }
            if searchStart != buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<searchStart)
            }
        }

        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            handler(line)
        }
    }
}
