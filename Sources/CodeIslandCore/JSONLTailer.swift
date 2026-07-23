import Foundation
import Darwin

public enum ConversationTurnStatus: Equatable, Sendable {
    case processing
    case idle
}

/// Trailing-question state derived from a Cursor `role`-keyed transcript.
///
/// Cursor's AskQuestion tool has no hook channel — the question is asked and
/// answered entirely inside Cursor's own UI (issue #265). The only observable
/// signal is the transcript: the asking assistant entry ends the file until the
/// user answers, at which point newer entries are appended. `pending` therefore
/// means "the newest entry contains an unanswered question tool call" and
/// `cleared` means "a newer entry superseded any earlier question".
public enum CursorQuestionSignal: Equatable, Sendable {
    /// The newest transcript entry asks a question that has not been answered.
    /// `prompt` is the extracted question text; empty when the tool call was
    /// recognized but its arguments carried no extractable text.
    case pending(prompt: String)
    /// A newer user/assistant entry exists, so no question is pending.
    case cleared
}

/// A delta emitted by `JSONLTailer` whenever the watched transcript grows.
public struct ConversationTailDelta: Equatable, Sendable {
    public let sessionId: String
    public let lastUserPrompt: String?
    public let lastAssistantMessage: String?
    public let turnStatus: ConversationTurnStatus?
    public let hasActivity: Bool
    public let cursorQuestion: CursorQuestionSignal?

    public init(
        sessionId: String,
        lastUserPrompt: String?,
        lastAssistantMessage: String?,
        turnStatus: ConversationTurnStatus? = nil,
        hasActivity: Bool = false,
        cursorQuestion: CursorQuestionSignal? = nil
    ) {
        self.sessionId = sessionId
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.turnStatus = turnStatus
        self.hasActivity = hasActivity
        self.cursorQuestion = cursorQuestion
    }

    /// A delta only carries signal when at least one field is non-nil.
    public var isEmpty: Bool {
        lastUserPrompt == nil && lastAssistantMessage == nil && turnStatus == nil
            && !hasActivity && cursorQuestion == nil
    }
}

/// Watches one or more Claude-style JSONL transcripts and streams incremental
/// `ConversationTailDelta` events as new lines are appended.
///
/// The tailer attaches at end-of-file so it complements — rather than duplicates —
/// whatever initial backfill the caller already performed via filesystem scanning.
/// When the file's inode changes (e.g. user ran `/clear` or a new session rotated
/// on top of the same path) the watch transparently re-opens from the new file.
///
/// This type is thread-safe. All DispatchSource callbacks run on the tailer's
/// internal queue; the user-supplied `onDelta` closure is invoked there too and
/// must forward to the appropriate actor if it mutates shared state.
public final class JSONLTailer: @unchecked Sendable {
    public typealias DeltaHandler = @Sendable (ConversationTailDelta) -> Void

    private final class Watch {
        let sessionId: String
        var filePath: String
        var fd: Int32
        var offset: off_t
        var inode: ino_t
        var pendingFragment: Data
        var source: DispatchSourceFileSystemObject

        init(sessionId: String, filePath: String, fd: Int32, offset: off_t, inode: ino_t, source: DispatchSourceFileSystemObject) {
            self.sessionId = sessionId
            self.filePath = filePath
            self.fd = fd
            self.offset = offset
            self.inode = inode
            self.pendingFragment = Data()
            self.source = source
        }
    }

    private let queue: DispatchQueue
    private let onDelta: DeltaHandler
    private var watches: [String: Watch] = [:]

    public init(
        queue: DispatchQueue = DispatchQueue(label: "com.codeisland.jsonl-tailer"),
        onDelta: @escaping DeltaHandler
    ) {
        self.queue = queue
        self.onDelta = onDelta
    }

    deinit {
        for watch in watches.values {
            watch.source.cancel()
        }
    }

    // MARK: - Public API

    public func attach(sessionId: String, filePath: String) {
        queue.async { [weak self] in
            self?.detachOnQueue(sessionId: sessionId)
            self?.attachOnQueue(sessionId: sessionId, filePath: filePath, initialOffset: nil)
        }
    }

    public func detach(sessionId: String) {
        queue.async { [weak self] in
            self?.detachOnQueue(sessionId: sessionId)
        }
    }

    public func detachAll() {
        queue.async { [weak self] in
            guard let self else { return }
            for key in Array(self.watches.keys) {
                self.detachOnQueue(sessionId: key)
            }
        }
    }

    public var activeSessionCount: Int {
        queue.sync { watches.count }
    }

    // MARK: - Watch lifecycle

    private func attachOnQueue(sessionId: String, filePath: String, initialOffset: off_t?) {
        let fd = open(filePath, O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { return }
        var fileStat = stat()
        guard fstat(fd, &fileStat) == 0 else {
            close(fd)
            return
        }

        let offset = initialOffset ?? fileStat.st_size
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.extend, .write, .delete, .rename, .revoke],
            queue: queue
        )
        let watch = Watch(
            sessionId: sessionId,
            filePath: filePath,
            fd: fd,
            offset: offset,
            inode: fileStat.st_ino,
            source: source
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            self.handleEvents(events, watch: watch)
        }
        source.setCancelHandler {
            close(fd)
        }

        watches[sessionId] = watch
        source.resume()
    }

    private func detachOnQueue(sessionId: String) {
        guard let watch = watches.removeValue(forKey: sessionId) else { return }
        watch.source.cancel()
    }

    // MARK: - Event handling

    private func handleEvents(_ events: DispatchSource.FileSystemEvent, watch: Watch) {
        // A rotate or delete means the file has been replaced underneath us (e.g. /clear).
        // Re-attach from a fresh fd so future writes reach our handler.
        if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
            let path = watch.filePath
            let sid = watch.sessionId
            detachOnQueue(sessionId: sid)
            // Give the writer a moment to finish writing the new file before we reopen.
            queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
                self?.attachOnQueue(sessionId: sid, filePath: path, initialOffset: 0)
            }
            return
        }

        var fileStat = stat()
        if stat(watch.filePath, &fileStat) == 0 {
            if fileStat.st_ino != watch.inode {
                // Inode swap without a delete/rename event — reopen from scratch.
                let path = watch.filePath
                let sid = watch.sessionId
                detachOnQueue(sessionId: sid)
                attachOnQueue(sessionId: sid, filePath: path, initialOffset: 0)
                return
            }
            if fileStat.st_size < watch.offset {
                // Truncation — rewind so we don't miss the new prefix.
                watch.offset = 0
                watch.pendingFragment.removeAll(keepingCapacity: true)
            }
        }

        guard let appended = readFromOffset(watch: watch) else { return }
        let combined = watch.pendingFragment + appended

        let scan = JSONLTailer.scanLines(combined)
        watch.pendingFragment = scan.trailingFragment
        // Advance by the bytes actually read from disk — the trailing fragment is
        // carried purely in memory and its file bytes are already consumed here.
        // Mixing the fragment into the offset math (the previous
        // `combined.count - trailingFragment.count`) drifted the offset past EOF
        // after every fragment episode; the next small append then looked like a
        // truncation and re-scanned the whole file from byte 0 on each event,
        // pinning a core on overnight-grown transcripts (#278).
        watch.offset += off_t(appended.count)

        if !scan.delta.isEmpty {
            let delta = ConversationTailDelta(
                sessionId: watch.sessionId,
                lastUserPrompt: scan.delta.lastUserPrompt,
                lastAssistantMessage: scan.delta.lastAssistantMessage,
                turnStatus: scan.delta.turnStatus,
                hasActivity: scan.delta.hasActivity,
                cursorQuestion: scan.delta.cursorQuestion
            )
            onDelta(delta)
        }
    }

    private func readFromOffset(watch: Watch) -> Data? {
        guard lseek(watch.fd, watch.offset, SEEK_SET) >= 0 else { return nil }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBufferPointer { ptr in
                read(watch.fd, ptr.baseAddress, ptr.count)
            }
            if n > 0 {
                data.append(buffer, count: n)
            } else if n == 0 {
                break
            } else {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { break }
                return nil
            }
        }
        return data
    }

    // MARK: - Pure parsing (exposed for tests)

    public struct ScanResult: Equatable {
        public struct Delta: Equatable {
            public var lastUserPrompt: String?
            public var lastAssistantMessage: String?
            public var turnStatus: ConversationTurnStatus?
            public var hasActivity = false
            public var cursorQuestion: CursorQuestionSignal?
            public var isEmpty: Bool {
                lastUserPrompt == nil && lastAssistantMessage == nil && turnStatus == nil
                    && !hasActivity && cursorQuestion == nil
            }
        }
        public let delta: Delta
        public let trailingFragment: Data
    }

    /// Split the given byte blob on newline boundaries and surface the latest user /
    /// assistant text observed. Bytes after the final newline are returned as a
    /// fragment that the caller should prepend on the next call.
    public static func scanLines(_ data: Data) -> ScanResult {
        var delta = ScanResult.Delta()
        var lineStart = data.startIndex
        var cursor = data.startIndex
        let newline: UInt8 = 0x0A

        while cursor < data.endIndex {
            if data[cursor] == newline {
                let line = data[lineStart..<cursor]
                if !line.isEmpty {
                    apply(line: line, into: &delta)
                }
                lineStart = data.index(after: cursor)
            }
            cursor = data.index(after: cursor)
        }

        let fragment = Data(data[lineStart..<data.endIndex])
        return ScanResult(delta: delta, trailingFragment: fragment)
    }

    /// Return the most recent Codex turn state in a transcript blob.
    public static func latestTurnStatus(in data: Data) -> ConversationTurnStatus? {
        scanLines(data).delta.turnStatus
    }

    /// Return the trailing Cursor question state in a transcript blob, or nil
    /// when the blob contained no role-keyed user/assistant entries at all.
    public static func latestCursorQuestion(in data: Data) -> CursorQuestionSignal? {
        scanLines(data).delta.cursorQuestion
    }

    private static func apply(line: Data.SubSequence, into delta: inout ScanResult.Delta) {
        // Materialize the slice once so the byte probe and the JSON parser share a
        // single allocation. Going through `Data(line)` also sidesteps a Foundation
        // quirk where `Data.SubSequence.withUnsafeBytes` occasionally surfaces the
        // parent's full buffer rather than the slice's view.
        let lineData = Data(line)

        // Fast path: realistic Claude transcripts are ~75% tool_use / tool_result /
        // meta rows we don't care about. Skipping the JSON parse for those saves a
        // measurable chunk of CPU per byte during streaming bursts.
        let kind = quickTypeProbe(lineBytes: lineData)
        guard kind != .irrelevant else { return }

        guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { return }
        if json["isMeta"] as? Bool == true { return }

        // Re-verify the type after a real parse — the byte probe can be fooled by
        // nested content that happens to contain the literal `"type":"assistant"`.
        let type = json["type"] as? String
        let message = (json["message"] as? [String: Any]) ?? json

        switch type {
        case "user", "USER_INPUT":
            if let text = extractText(from: message["content"]) {
                delta.lastUserPrompt = text
            }
        case "assistant", "PLANNER_RESPONSE":
            if let text = extractText(from: message["content"]) {
                delta.lastAssistantMessage = text
            } else if let thinking = message["thinking"] as? String {
                let trimmed = thinking.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    delta.lastAssistantMessage = trimmed
                }
            }
        case "event_msg":
            delta.hasActivity = true
            guard let payload = json["payload"] as? [String: Any],
                  let eventType = payload["type"] as? String else { return }
            switch eventType {
            case "task_started":
                delta.turnStatus = .processing
            // "turn_failed" is not in today's codex EventMsg enum — kept as a
            // forward-compatible guess at the obvious name for a failed turn.
            case "task_complete", "turn_aborted", "turn_failed":
                delta.turnStatus = .idle
            default:
                break
            }
        default:
            // Cursor agent transcripts key their entries on a top-level `role`
            // instead of `type`: `{"role":"user","message":{"content":[...]}}`.
            // Restrict the branch to lines with no `type` at all so type-keyed
            // formats (Claude, CodeBuddy `"type":"message"`, …) never route here.
            if type == nil, let role = json["role"] as? String {
                applyCursorRoleLine(role: role, message: message, into: &delta)
            }
        }
    }

    /// Handle one Cursor `role`-keyed transcript entry.
    ///
    /// Only the trailing-question state is derived here: an assistant entry
    /// carrying an unanswered AskQuestion tool call marks the question pending,
    /// and any other user/assistant entry supersedes it — last writer wins, so
    /// only the newest entry in a scan determines the state.
    ///
    /// Chat text is deliberately NOT extracted from this shape: Cursor hooks
    /// (`beforeSubmitPrompt` / `afterAgentResponse`) already stream the same
    /// messages, and the transcript copies differ cosmetically (`<user_query>`
    /// wrappers, redaction markers), so a second source would produce
    /// near-duplicate chat rows.
    private static func applyCursorRoleLine(
        role: String,
        message: [String: Any],
        into delta: inout ScanResult.Delta
    ) {
        switch role {
        case "user":
            delta.cursorQuestion = .cleared
        case "assistant":
            if let prompt = cursorQuestionPrompt(inContent: message["content"]) {
                delta.cursorQuestion = .pending(prompt: prompt)
            } else {
                delta.cursorQuestion = .cleared
            }
        default:
            break
        }
    }

    /// Extract the question text when a Cursor assistant `content` array carries a
    /// blocking question tool call. Returns nil when the entry asks no question
    /// (including `run_async` questions, which don't block the agent). An empty
    /// string means "a question is pending but its text could not be extracted".
    static func cursorQuestionPrompt(inContent content: Any?) -> String? {
        guard let blocks = content as? [[String: Any]] else { return nil }
        for block in blocks {
            guard (block["type"] as? String) == "tool_use",
                  let name = block["name"] as? String,
                  isCursorQuestionToolName(name) else { continue }
            let input = block["input"] as? [String: Any]
            // Async questions let the agent keep working — not a blocking wait.
            // The args casing follows the model-facing schema, which has been
            // observed as both snake_case and camelCase across tool versions.
            if (input?["run_async"] as? Bool) == true || (input?["runAsync"] as? Bool) == true {
                continue
            }
            return cursorQuestionText(fromInput: input)
        }
        return nil
    }

    /// True when `name` is Cursor's question tool. Matched loosely (case- and
    /// separator-insensitive) because the transcript records the model-facing
    /// tool name, which Cursor has renamed across releases.
    static func isCursorQuestionToolName(_ name: String) -> Bool {
        let normalized = name.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch normalized {
        case "askquestion", "askquestions", "askuserquestion", "askfollowupquestion":
            return true
        default:
            return false
        }
    }

    /// Compose display text from AskQuestion tool args:
    /// `{title, questions: [{id, prompt, options: [{id, label}], allow_multiple}]}`.
    /// Prefers the first question's prompt (with a numeric `(+N)` suffix when more
    /// follow), falls back to the title, then to a flat `question`/`prompt` field,
    /// and finally to "" so the caller still knows a question is pending.
    private static func cursorQuestionText(fromInput input: [String: Any]?) -> String {
        guard let input else { return "" }

        var prompts: [String] = []
        if let questions = input["questions"] as? [[String: Any]] {
            for question in questions {
                let raw = (question["prompt"] as? String) ?? (question["question"] as? String)
                if let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    prompts.append(text)
                }
            }
        }
        if let first = prompts.first {
            return prompts.count > 1 ? "\(first) (+\(prompts.count - 1))" : first
        }

        if let title = (input["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        // Forward-compatible flat shape.
        let flat = (input["question"] as? String) ?? (input["prompt"] as? String)
        if let text = flat?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text
        }
        return ""
    }

    /// Types we care about for the panel: `"user"` and `"assistant"`. Anything
    /// else — including unknown types and absent-type lines — can be skipped
    /// without bothering the JSON parser. `cursorRole` marks lines that carry
    /// no interesting `type` value but do contain a `"role":"user|assistant"`
    /// marker (Cursor's transcript shape) and therefore still deserve a parse.
    enum QuickTypeKind: Equatable {
        case user
        case assistant
        case codexEvent
        case cursorRole
        case irrelevant
    }

    /// Byte-scan the line for the first `"type":"` occurrence and peek at the
    /// character that follows the opening quote. A single pass that gives up
    /// as soon as it sees something that isn't `u`, `a`, or an escape. Returns
    /// `.irrelevant` when neither `"user"` nor `"assistant"` appears as a
    /// `type` value, letting the caller skip the JSON parser entirely.
    ///
    /// Limitations: does not tolerate whitespace between the colon and the
    /// opening quote (e.g. `"type" : "user"`). Claude's JSONL writer never
    /// emits that shape, so lines which do fall through to the parser via the
    /// `.irrelevant` path get a correct — if slightly more expensive — answer
    /// by returning nothing, which is safe (we just miss those updates).
    static func quickTypeProbe(lineBytes: Data) -> QuickTypeKind {
        guard lineBytes.count >= typeMarker.count + 2 else { return .irrelevant }

        return lineBytes.withUnsafeBytes { rawBuffer -> QuickTypeKind in
            guard let base = rawBuffer.baseAddress else { return .irrelevant }
            let ptr = base.assumingMemoryBound(to: UInt8.self)
            let total = rawBuffer.count
            let markerLen = typeMarker.count
            var index = 0
            // Every `"type":"..."` occurrence in the line gets checked, not only the
            // first — JSONSerialization is free to reorder top-level keys so the
            // outer type we care about may sit behind nested `"type":"text"` rows.
            while index <= total - markerLen {
                var matched = true
                for offset in 0..<markerLen where ptr[index + offset] != typeMarker[offset] {
                    matched = false
                    break
                }
                if matched {
                    let valueStart = index + markerLen
                    if valueStart < total {
                        switch ptr[valueStart] {
                        case 0x75:  // 'u'
                            if hasExactValue(ptr, at: valueStart, total: total, expect: userBytes) {
                                return .user
                            }
                        case 0x55:  // 'U'
                            if hasExactValue(ptr, at: valueStart, total: total, expect: userInputBytes) {
                                return .user
                            }
                        case 0x61:  // 'a'
                            if hasExactValue(ptr, at: valueStart, total: total, expect: assistantBytes) {
                                return .assistant
                            }
                        case 0x50:  // 'P'
                            if hasExactValue(ptr, at: valueStart, total: total, expect: plannerResponseBytes) {
                                return .assistant
                            }
                        case 0x65:  // 'e'
                            if hasExactValue(ptr, at: valueStart, total: total, expect: eventMsgBytes) {
                                return .codexEvent
                            }
                        default:
                            break
                        }
                    }
                    // Skip past this marker and keep looking — nested objects
                    // often carry their own `type` key we don't care about.
                    index = valueStart + 1
                } else {
                    index += 1
                }
            }

            // No interesting `type` value — check for Cursor's `role`-keyed shape
            // before giving up. Cursor's writer serializes `{role, message}` with
            // `role` as the first key, so an O(1) prefix check suffices. Scanning
            // the whole line instead would misroute the bulk of Codex rollouts
            // (`response_item` lines carry a nested `"role":"assistant"`) into
            // the JSON parser and regress streaming CPU. `apply` re-verifies the
            // shape against the parsed JSON.
            let roleLen = roleMarker.count
            if total > roleLen + 1, ptr[0] == 0x7B {  // '{'
                var prefixMatched = true
                for offset in 0..<roleLen where ptr[1 + offset] != roleMarker[offset] {
                    prefixMatched = false
                    break
                }
                if prefixMatched {
                    let valueStart = 1 + roleLen
                    if hasExactValue(ptr, at: valueStart, total: total, expect: userBytes)
                        || hasExactValue(ptr, at: valueStart, total: total, expect: assistantBytes) {
                        return .cursorRole
                    }
                }
            }
            return .irrelevant
        }
    }

    /// The `"type":"` prefix before the type value. Placed in the header so
    /// the scanner can bail early on typical tool/meta lines.
    private static let typeMarker: [UInt8] = Array(#""type":""#.utf8)
    /// The `"role":"` prefix — Cursor transcripts key entries on `role` only.
    private static let roleMarker: [UInt8] = Array(#""role":""#.utf8)
    private static let userBytes: [UInt8] = Array(#"user""#.utf8)
    private static let assistantBytes: [UInt8] = Array(#"assistant""#.utf8)
    private static let userInputBytes: [UInt8] = Array(#"USER_INPUT""#.utf8)
    private static let plannerResponseBytes: [UInt8] = Array(#"PLANNER_RESPONSE""#.utf8)

    private static let eventMsgBytes: [UInt8] = Array(#"event_msg""#.utf8)

    private static func hasExactValue(
        _ ptr: UnsafePointer<UInt8>,
        at start: Int,
        total: Int,
        expect: [UInt8]
    ) -> Bool {
        guard start + expect.count <= total else { return false }
        for offset in 0..<expect.count where ptr[start + offset] != expect[expect.startIndex + offset] {
            return false
        }
        return true
    }

    /// Concatenate every `text` block from a Claude-style `content` value. Accepts
    /// either a bare string or an array of content blocks.
    public static func extractText(from content: Any?) -> String? {
        if let raw = content as? String {
            var text = raw
            if let startRange = text.range(of: "<USER_REQUEST>"),
               let endRange = text.range(of: "</USER_REQUEST>", range: startRange.upperBound..<text.endIndex) {
                text = String(text[startRange.upperBound..<endRange.lowerBound])
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let blocks = content as? [[String: Any]] {
            var parts: [String] = []
            for block in blocks {
                guard (block["type"] as? String) == "text" else { continue }
                if let text = block["text"] as? String {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { parts.append(trimmed) }
                }
            }
            if parts.isEmpty { return nil }
            return parts.joined(separator: "\n")
        }
        return nil
    }
}
