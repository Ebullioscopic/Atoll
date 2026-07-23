import Foundation
import CodeIslandCore

extension AppState {
    /// Start watching a session's transcript file for appended lines. Safe to call
    /// repeatedly with the same (session, path) pair — the tailer reattaches only
    /// when the path actually changed.
    func attachTranscriptTailerIfNeeded(sessionId: String) {
        guard let path = sessions[sessionId]?.transcriptPath, !path.isEmpty else { return }
        if attachedTranscriptPaths[sessionId] == path { return }
        attachedTranscriptPaths[sessionId] = path

        // Backfill messages from the transcript file so recentMessages is populated
        let (_, messages) = Self.readRecentFromTranscript(path: path)
        if !messages.isEmpty, var session = sessions[sessionId] {
            session.recentMessages = messages
            if let lastUser = messages.last(where: { $0.isUser }) {
                session.lastUserPrompt = lastUser.text
            }
            if let lastAssistant = messages.last(where: { !$0.isUser }) {
                session.lastAssistantMessage = lastAssistant.text
            }
            sessions[sessionId] = session
        }

        if sessions[sessionId]?.source == "codex",
           let turnStatus = Self.latestCodexTurnStatus(path: path),
           var session = sessions[sessionId] {
            switch turnStatus {
            case .processing:
                session.status = .processing
                session.interrupted = false
                session.taskRoundEnded = false
            case .idle:
                session.status = .idle
                session.currentTool = nil
                session.toolDescription = nil
            }
            if let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date {
                session.lastActivity = modifiedAt
            }
            sessions[sessionId] = session
        }

        transcriptTailer.attach(sessionId: sessionId, filePath: path)
    }

    private nonisolated static func latestCodexTurnStatus(path: String) -> ConversationTurnStatus? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        // A long Codex turn can place its task_started event well before the
        // final 128 KB after emitting large reasoning/tool rows. Scan in chunks
        // so startup state recovery remains bounded in memory without missing
        // that event.
        handle.seek(toFileOffset: 0)
        let chunkSize = 64 * 1024
        var pendingFragment = Data()
        var latestStatus: ConversationTurnStatus?

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            let result = JSONLTailer.scanLines(pendingFragment + chunk)
            pendingFragment = result.trailingFragment
            if let turnStatus = result.delta.turnStatus {
                latestStatus = turnStatus
            }
        }

        return latestStatus
    }

    /// Stop watching a session's transcript. Called when the session is removed or
    /// when a new transcript path supersedes an older one.
    func detachTranscriptTailer(sessionId: String) {
        attachedTranscriptPaths.removeValue(forKey: sessionId)
        transcriptTailer.detach(sessionId: sessionId)
    }

    /// Apply an incremental update produced by the tailer. Runs on the main actor.
    func applyTranscriptDelta(_ delta: ConversationTailDelta) {
        guard var session = sessions[delta.sessionId] else { return }
        var mutated = false

        if delta.hasActivity {
            session.lastActivity = Date()
            mutated = true
        }

        if let turnStatus = delta.turnStatus {
            switch turnStatus {
            case .processing:
                session.status = .processing
                session.interrupted = false
                session.taskRoundEnded = false
            case .idle:
                session.status = .idle
                session.currentTool = nil
                session.toolDescription = nil
            }
            // A status-only event is still activity. This matters for a long Codex
            // turn whose transcript has not emitted a message yet.
            session.lastActivity = Date()
            mutated = true
        }

        if let prompt = delta.lastUserPrompt, session.lastUserPrompt != prompt {
            session.lastUserPrompt = prompt
            if session.recentMessages.last(where: { $0.isUser })?.text != prompt {
                session.addRecentMessage(ChatMessage(isUser: true, text: prompt))
            }
            mutated = true
        }
        if let reply = delta.lastAssistantMessage, session.lastAssistantMessage != reply {
            session.lastAssistantMessage = reply
            if session.recentMessages.last(where: { !$0.isUser })?.text != reply {
                session.addRecentMessage(ChatMessage(isUser: false, text: reply))
            }
            mutated = true
        }

        if mutated {
            session.lastActivity = Date()
            sessions[delta.sessionId] = session
        }
    }
}
