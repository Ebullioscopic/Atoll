import Foundation

public struct ClaudeUsageTotals: Equatable, Sendable {
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheCreationTokens = 0
    public var cacheReadTokens = 0
    public var messageCount = 0

    public var isEmpty: Bool { messageCount == 0 }

    public init() {}

    mutating func add(_ other: ClaudeUsageTotals) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationTokens += other.cacheCreationTokens
        cacheReadTokens += other.cacheReadTokens
        messageCount += other.messageCount
    }
}

/// Token-usage aggregation over the local Claude Code transcripts
/// (~/.claude/projects/**/*.jsonl) — local-first, no provider API calls.
/// Every assistant line carries `message.usage`; `message.id` repeats across
/// tool-use continuation lines of the same API response, so totals dedupe on it.
public enum ClaudeUsageScanner {
    /// Sparkline resolution: one bucket per hour, oldest first.
    public static let sparklineHours = 12

    public struct Snapshot: Equatable, Sendable {
        public let last5h: ClaudeUsageTotals
        public let today: ClaudeUsageTotals
        /// Output tokens per hour for the trailing `sparklineHours` hours,
        /// index 0 oldest, last index = the current hour.
        public let hourlyOutputTokens: [Int]
        public let scannedAt: Date

        public init(last5h: ClaudeUsageTotals, today: ClaudeUsageTotals, hourlyOutputTokens: [Int], scannedAt: Date) {
            self.last5h = last5h
            self.today = today
            self.hourlyOutputTokens = hourlyOutputTokens
            self.scannedAt = scannedAt
        }
    }

    /// Per-file incremental parse state. Transcripts are append-only, so each
    /// rescan reads only the bytes past `consumedBytes` — a day-long multi-MB
    /// transcript is never re-read in full. Value semantics: the caller owns a
    /// copy, hands it to the background scan, and stores the returned state.
    public struct FileCache: Sendable {
        struct CachedMessage: Sendable, Equatable {
            let timestamp: Date
            let usage: ClaudeUsageTotals
        }
        struct FileEntry: Sendable {
            var consumedBytes: UInt64 = 0
            var entries: [CachedMessage] = []
            // Dedupe is per file: an assistant message's continuation lines
            // repeat its id within the same transcript; ids never straddle files.
            var seenIds: Set<String> = []
        }
        var files: [String: FileEntry] = [:]
        public init() {}
    }

    /// One-shot convenience (tests, callers without persistent state).
    public static func scan(
        claudeHome: String = ClaudeConfigPaths.configDir(),
        now: Date = Date()
    ) -> Snapshot {
        var cache = FileCache()
        return scan(claudeHome: claudeHome, now: now, cache: &cache)
    }

    public static func scan(
        claudeHome: String = ClaudeConfigPaths.configDir(),
        now: Date = Date(),
        cache: inout FileCache
    ) -> Snapshot {
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)
        let midnight = Calendar.current.startOfDay(for: now)
        let sparklineStart = now.addingTimeInterval(-Double(sparklineHours) * 3600)
        let cutoff = min(fiveHoursAgo, midnight, sparklineStart)

        var last5h = ClaudeUsageTotals()
        var today = ClaudeUsageTotals()
        var hourly = [Int](repeating: 0, count: sparklineHours)
        var activeFiles = Set<String>()

        let fm = FileManager.default
        let projectsDir = claudeHome + "/projects"
        for project in (try? fm.contentsOfDirectory(atPath: projectsDir)) ?? [] {
            let projectPath = projectsDir + "/" + project
            for file in (try? fm.contentsOfDirectory(atPath: projectPath)) ?? [] {
                guard file.hasSuffix(".jsonl") else { continue }
                let path = projectPath + "/" + file
                // mtime gate: untouched-since-cutoff transcripts can't contain
                // in-window lines, so the scan stays cheap on big histories.
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let mtime = attrs[.modificationDate] as? Date,
                      mtime >= cutoff else { continue }
                activeFiles.insert(path)
                let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0

                var entry = cache.files[path] ?? FileCache.FileEntry()
                if size < entry.consumedBytes {
                    // Truncated or replaced — start over.
                    entry = FileCache.FileEntry()
                }
                if size > entry.consumedBytes {
                    consumeNewLines(path: path, into: &entry)
                }
                entry.entries.removeAll { $0.timestamp < cutoff }
                cache.files[path] = entry

                for message in entry.entries where message.timestamp <= now {
                    if message.timestamp >= fiveHoursAgo { last5h.add(message.usage) }
                    if message.timestamp >= midnight { today.add(message.usage) }
                    let hoursAgo = Int(now.timeIntervalSince(message.timestamp) / 3600)
                    if hoursAgo >= 0 && hoursAgo < sparklineHours {
                        hourly[sparklineHours - 1 - hoursAgo] += message.usage.outputTokens
                    }
                }
            }
        }
        // Files that fell out of the mtime window carry no in-window entries.
        cache.files = cache.files.filter { activeFiles.contains($0.key) }
        return Snapshot(last5h: last5h, today: today, hourlyOutputTokens: hourly, scannedAt: now)
    }

    /// Read bytes past `entry.consumedBytes` and parse the COMPLETE lines only —
    /// a partial trailing line (writer mid-append) is left for the next scan.
    private static func consumeNewLines(path: String, into entry: inout FileCache.FileEntry) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { handle.closeFile() }
        handle.seek(toFileOffset: entry.consumedBytes)
        let data = handle.readDataToEndOfFile()
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let consumable = data[data.startIndex...lastNewline]
        entry.consumedBytes += UInt64(consumable.count)
        guard let text = String(data: consumable, encoding: .utf8) else { return }

        for line in text.split(separator: "\n") {
            guard let parsed = parseAssistantUsage(String(line)),
                  !entry.seenIds.contains(parsed.messageId) else { continue }
            entry.seenIds.insert(parsed.messageId)
            entry.entries.append(.init(timestamp: parsed.timestamp, usage: parsed.usage))
        }
    }

    /// Parse one transcript line into (timestamp, message id, usage) — nil for
    /// non-assistant lines and lines without usage.
    static func parseAssistantUsage(_ line: String) -> (timestamp: Date, messageId: String, usage: ClaudeUsageTotals)? {
        // Cheap pre-filter before full JSON decoding: assistant lines only.
        guard line.contains("\"assistant\""), line.contains("\"usage\"") else { return nil }
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "assistant",
              let timestampRaw = obj["timestamp"] as? String,
              let timestamp = parseISO8601(timestampRaw),
              let message = obj["message"] as? [String: Any],
              let messageId = message["id"] as? String,
              let usage = message["usage"] as? [String: Any]
        else { return nil }

        var totals = ClaudeUsageTotals()
        totals.inputTokens = usage["input_tokens"] as? Int ?? 0
        totals.outputTokens = usage["output_tokens"] as? Int ?? 0
        totals.cacheCreationTokens = usage["cache_creation_input_tokens"] as? Int ?? 0
        totals.cacheReadTokens = usage["cache_read_input_tokens"] as? Int ?? 0
        totals.messageCount = 1
        return (timestamp, messageId, totals)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plainFormatter = ISO8601DateFormatter()

    static func parseISO8601(_ raw: String) -> Date? {
        fractionalFormatter.date(from: raw) ?? plainFormatter.date(from: raw)
    }

    /// Compact human token count: 950, 32.5K, 1.4M. Unit selection uses the
    /// rounded value so 999,950 rolls over to "1M" instead of "1000K".
    public static func formatTokens(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        func fmt(_ value: Double, _ unit: String) -> String {
            String(format: "%.1f\(unit)", value).replacingOccurrences(of: ".0\(unit)", with: unit)
        }
        let thousands = Double(count) / 1000
        if thousands < 999.95 { return fmt(thousands, "K") }
        let millions = Double(count) / 1_000_000
        if millions < 999.95 { return fmt(millions, "M") }
        return fmt(Double(count) / 1_000_000_000, "B")
    }
}
