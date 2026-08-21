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

    /// Stream a JSONL file line by line, calling `process` for each valid record.
    /// Avoids loading the entire file into memory.
    private static func streamLines(
        from file: URL,
        weekStart: Date,
        sessionStart: Date,
        now: Date,
        seen: inout Set<String>,
        perModel: inout [String: UsageTotals],
        snapshot: inout UsageSnapshot
    ) {
        let cal = Calendar.current
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        var buffer = Data()
        let chunkSize = 64 * 1024 // 64 KB chunks
        let maxRecordSize = 1024 * 1024 // 1 MB max per record
        var discardingOversized = false

        func processRecord(_ rec: UsageRecord) {
            guard rec.timestamp >= weekStart else { return }
            if let key = rec.dedupKey {
                if seen.contains(key) { return }
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

        func processLine(_ line: String) {
            guard !line.isEmpty, let rec = parseLine(line) else { return }
            processRecord(rec)
        }

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            buffer.append(chunk)

            // Process complete lines from buffer
            while let newlineRange = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange)
                buffer.removeSubrange(buffer.startIndex...newlineRange)

                if discardingOversized {
                    // We were discarding an oversized record; this newline ends it.
                    discardingOversized = false
                    continue
                }

                // Skip oversized terminated records before decoding
                if lineData.count > maxRecordSize {
                    continue
                }

                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                processLine(line)
            }

            // Bound buffer growth: if buffer exceeds maxRecordSize without a newline,
            // discard data up to the next newline when it arrives
            if buffer.count > maxRecordSize {
                discardingOversized = true
                buffer.removeFirst(buffer.count - maxRecordSize)
            }
        }

        // Process any remaining data in buffer (last line without trailing newline)
        // but only if it's within the size limit and we're not discarding
        if !buffer.isEmpty && buffer.count <= maxRecordSize && !discardingOversized,
           let line = String(data: buffer, encoding: .utf8) {
            processLine(line)
        }
    }

    static func aggregate(files: [URL], now: Date) -> UsageSnapshot {
        var snapshot = UsageSnapshot()
        var perModel: [String: UsageTotals] = [:]
        var seen = Set<String>()
        let sessionStart = now.addingTimeInterval(-5 * 3600)
        let weekStart = now.addingTimeInterval(-7 * 86400)

        for file in files where mayContainRecords(after: weekStart, file) {
            streamLines(
                from: file,
                weekStart: weekStart,
                sessionStart: sessionStart,
                now: now,
                seen: &seen,
                perModel: &perModel,
                snapshot: &snapshot
            )
        }
        snapshot.models = perModel
            .map { ModelUsage(model: $0.key, totals: $0.value, pool: nil) }
            .sorted { $0.totals.costUSD > $1.totals.costUSD }
        snapshot.lastUpdated = now
        return snapshot
    }
}
