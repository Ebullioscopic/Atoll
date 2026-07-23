import Foundation
import CodeIslandCore

/// Outcome of applying a `CursorQuestionSignal` to a session snapshot.
enum CursorQuestionApplication: Equatable {
    /// Session is now display-waiting on a Cursor-side question.
    /// `fresh` is false when it was already waiting (prompt refresh only).
    case markedWaiting(fresh: Bool)
    /// A previously pending question was superseded; normal flow resumed.
    case clearedWaiting
    /// Signal did not apply (wrong source, subagent transcript, approval in flight, …).
    case ignored
}

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

        // Cursor stuck-question recovery (#265): if the transcript already ends
        // with an unanswered AskQuestion (e.g. CodeIsland launched or the session
        // was discovered while Cursor sat on a question), surface the wait now
        // instead of showing an endless "thinking". Recency-gated so an idle card
        // over a long-abandoned transcript doesn't resurrect as waiting.
        if let session = sessions[sessionId],
           session.source == "cursor" || session.source == "cursor-cli",
           CursorSessionFolding.parentConversationId(fromTranscriptPath: path) == sessionId,
           let signal = Self.latestCursorTailQuestion(path: path) {
            let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            let isRecent = modifiedAt.map { Date().timeIntervalSince($0) < Self.cursorQuestionBackfillMaxAge } ?? false
            let skipStalePending: Bool
            if case .pending = signal, !isRecent {
                skipStalePending = true
            } else {
                skipStalePending = false
            }
            if !skipStalePending, var mutable = sessions[sessionId] {
                if Self.applyCursorQuestionSignal(
                    signal,
                    to: &mutable,
                    sessionId: sessionId,
                    transcriptPath: path
                ) != .ignored {
                    sessions[sessionId] = mutable
                }
            }
        }

        transcriptTailer.attach(sessionId: sessionId, filePath: path)
    }

    /// Backfill freshness bound for flipping a session into the display-only
    /// question wait from a cold start. Live tail deltas are not age-gated.
    nonisolated static let cursorQuestionBackfillMaxAge: TimeInterval = 30 * 60

    /// Trailing Cursor question state for a whole transcript file, scanned in
    /// bounded chunks (same pattern as `latestCodexTurnStatus`).
    nonisolated static func latestCursorTailQuestion(path: String) -> CursorQuestionSignal? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: 0)
        let chunkSize = 64 * 1024
        var pendingFragment = Data()
        var latestSignal: CursorQuestionSignal?

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }

            let result = JSONLTailer.scanLines(pendingFragment + chunk)
            pendingFragment = result.trailingFragment
            if let signal = result.delta.cursorQuestion {
                latestSignal = signal
            }
        }

        return latestSignal
    }

    /// Apply a Cursor trailing-question signal to one session snapshot.
    ///
    /// Pure state transition (no side effects) so both the live tail path and the
    /// attach-time backfill share identical rules, and tests can drive it directly:
    /// - `.pending` flips a **main-agent** Cursor session (transcript parent ==
    ///   session id, so folded Task/subagent transcripts never qualify) into
    ///   `.waitingQuestion` with the question text stored for the card. A real
    ///   approval wait is never stomped.
    /// - `.cleared` erases the stored question; if the session was in the
    ///   display-only wait it resumes as `.processing` (follow-up hooks or tail
    ///   deltas refine from there).
    nonisolated static func applyCursorQuestionSignal(
        _ signal: CursorQuestionSignal,
        to session: inout SessionSnapshot,
        sessionId: String,
        transcriptPath: String?
    ) -> CursorQuestionApplication {
        guard session.source == "cursor" || session.source == "cursor-cli" else { return .ignored }

        switch signal {
        case .pending(let prompt):
            guard let transcriptPath,
                  CursorSessionFolding.parentConversationId(fromTranscriptPath: transcriptPath) == sessionId else {
                return .ignored
            }
            // An interactive approval outranks the display-only wait.
            guard session.status != .waitingApproval else { return .ignored }
            let fresh = session.status != .waitingQuestion || session.cursorPendingQuestion == nil
            session.status = .waitingQuestion
            session.cursorPendingQuestion = prompt
            session.currentTool = nil
            session.toolDescription = nil
            session.lastActivity = Date()
            return .markedWaiting(fresh: fresh)

        case .cleared:
            guard session.cursorPendingQuestion != nil else { return .ignored }
            session.cursorPendingQuestion = nil
            if session.status == .waitingQuestion {
                session.status = .processing
            }
            session.lastActivity = Date()
            return .clearedWaiting
        }
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

        // Cursor question tool has no hook channel (#265) — the transcript tail is
        // the only signal that the agent is blocked on (or resumed from) a question
        // answered inside Cursor's own UI.
        var questionStateChanged = false
        if let signal = delta.cursorQuestion {
            let application = Self.applyCursorQuestionSignal(
                signal,
                to: &session,
                sessionId: delta.sessionId,
                transcriptPath: attachedTranscriptPaths[delta.sessionId]
            )
            if application != .ignored {
                mutated = true
                questionStateChanged = true
            }
            if application == .markedWaiting(fresh: true) {
                SoundManager.shared.handleEvent("PermissionRequest")
            }
        }

        if mutated {
            session.lastActivity = Date()
            sessions[delta.sessionId] = session
        }
        if questionStateChanged {
            // Hooks stay silent while Cursor waits on its question, so nothing
            // else recomputes the aggregated pill/mascot state for this flip.
            refreshDerivedState()
        }
    }
}
