/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

/// What an observed agent session is doing right now.
enum AgentSessionStatus: String, Codable, Sendable {
    /// Working on its own; nothing is expected from the user.
    case working
    /// Blocked on a decision or a question.
    case waitingOnUser
    /// Finished its turn and has not been acknowledged yet.
    case finished
    /// Alive but quiet, or restored from disk after an Atoll restart.
    case idle

    var displayName: String {
        switch self {
        case .working: return String(localized: "Working")
        case .waitingOnUser: return String(localized: "Waiting for you")
        case .finished: return String(localized: "Done")
        case .idle: return String(localized: "Idle")
        }
    }
}

/// One agent CLI session, as reconstructed from its hook events.
///
/// `Codable` because sessions survive an Atoll restart (they are reloaded as
/// `.idle`); the live `pendingRequestIDs` deliberately does not persist, since
/// the hook processes that were blocked die with the app.
struct AgentSession: Identifiable, Codable, Equatable, Sendable {
    /// `"<kind>:<session_id>"` — see `AgentHookEvent.sessionKey`.
    let id: String
    let kind: AgentKind

    var cwd: String?
    var projectName: String?
    /// The title the agent gave itself, used to find its terminal tab.
    var title: String?

    var status: AgentSessionStatus
    var startedAt: Date
    var lastActivityAt: Date
    /// Set when the session reports finishing, so elapsed time stops climbing.
    var endedAt: Date?

    var contextTokens: Int?
    var contextWindow: Int?
    /// Running maximum context this session has held. Context collapses after a
    /// compaction, so the peak — not the current value — is what identifies the
    /// window size. Persisted so a relaunch does not lose the calibration.
    var observedMaxContextTokens: Int?
    var contextWindowConfidence: ContextWindowConfidence?
    /// Model identifier from the last assistant turn.
    var model: String?

    var subagentsStarted: Int
    var subagentsFinished: Int

    var permissionMode: String?
    var transcriptPath: String?

    var terminalProgram: String?
    var terminalBundleID: String?
    /// The agent process, learned from the hook shim's own parent pid. Used to
    /// tell a dead session from a quiet one, and later to find its terminal.
    var agentPID: Int32?

    /// Notch-visible label: the title the agent gave itself, falling back to the
    /// project directory, then the agent name.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let projectName, !projectName.isEmpty { return projectName }
        return kind.displayName
    }

    /// 0...1 context fill, or `nil` when no transcript has been read yet.
    var contextFraction: Double? {
        guard let contextTokens, let contextWindow, contextWindow > 0 else { return nil }
        return min(1.0, max(0.0, Double(contextTokens) / Double(contextWindow)))
    }

    /// Wall-clock the session has been alive, frozen once it ends.
    func elapsed(now: Date) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    /// Folds a transcript tail read into the session.
    ///
    /// The observed maximum only ever grows: that is what lets the window size be
    /// calibrated from data instead of guessed from a model identifier.
    mutating func apply(_ snapshot: AgentTranscriptSnapshot) {
        contextTokens = snapshot.contextTokens
        observedMaxContextTokens = max(observedMaxContextTokens ?? 0, snapshot.contextTokens)
        if let model = snapshot.model, !model.isEmpty { self.model = model }
        // The agent's own title beats the directory name.
        if let agentTitle = snapshot.title, !agentTitle.isEmpty { title = agentTitle }
        if let mode = snapshot.permissionMode, !mode.isEmpty { permissionMode = mode }

        let window = ContextWindowResolver.resolve(
            model: self.model,
            observedTokens: observedMaxContextTokens ?? snapshot.contextTokens,
            kind: kind
        )
        contextWindow = window.tokens
        contextWindowConfidence = window.confidence
    }

    /// Whether a percentage is trustworthy enough to draw as a ring.
    var showsContextFraction: Bool {
        guard let contextWindow, let contextTokens, let contextWindowConfidence else { return false }
        return ContextWindowResolver.shouldShowFraction(
            ContextWindow(tokens: contextWindow, confidence: contextWindowConfidence),
            usedTokens: contextTokens
        )
    }

    /// `"2 of 5"` style progress, only once at least one subagent has been seen.
    var subagentProgressText: String? {
        guard subagentsStarted > 0 else { return nil }
        return "\(subagentsFinished)/\(subagentsStarted)"
    }

    init(event: AgentHookEvent) {
        self.id = event.sessionKey
        self.kind = event.kind
        self.cwd = event.cwd
        self.projectName = event.projectName
        self.title = event.projectName
        self.status = .working
        self.startedAt = event.receivedAt
        self.lastActivityAt = event.receivedAt
        self.endedAt = nil
        self.contextTokens = nil
        self.contextWindow = nil
        self.observedMaxContextTokens = nil
        self.contextWindowConfidence = nil
        self.model = nil
        self.subagentsStarted = 0
        self.subagentsFinished = 0
        self.permissionMode = event.permissionMode
        self.transcriptPath = event.transcriptPath
        self.terminalProgram = event.terminalProgram
        self.terminalBundleID = event.terminalBundleID
        self.agentPID = nil
    }

    /// Folds a newly-received event into the session, leaving fields the event
    /// does not carry untouched.
    mutating func apply(_ event: AgentHookEvent) {
        lastActivityAt = event.receivedAt
        if let cwd = event.cwd, !cwd.isEmpty {
            self.cwd = cwd
            self.projectName = event.projectName
            if title?.isEmpty ?? true { title = event.projectName }
        }
        if let transcriptPath = event.transcriptPath, !transcriptPath.isEmpty {
            self.transcriptPath = transcriptPath
        }
        if let permissionMode = event.permissionMode, !permissionMode.isEmpty {
            self.permissionMode = permissionMode
        }
        if let terminalProgram = event.terminalProgram, !terminalProgram.isEmpty {
            self.terminalProgram = terminalProgram
        }
        if let terminalBundleID = event.terminalBundleID, !terminalBundleID.isEmpty {
            self.terminalBundleID = terminalBundleID
        }

        switch event.name {
        case .sessionStart:
            // A resumed session re-emits SessionStart; keep the original clock
            // only if this session was already running.
            if status == .finished || status == .idle {
                startedAt = event.receivedAt
                endedAt = nil
                subagentsStarted = 0
                subagentsFinished = 0
            }
            status = .working
        case .sessionEnd:
            status = .finished
            endedAt = event.receivedAt
        case .stop:
            status = .finished
            endedAt = event.receivedAt
        case .notification:
            // Claude Code emits Notification both when it needs input and for
            // idle nudges; the manager decides which, so only bump activity here.
            status = .waitingOnUser
            endedAt = nil
        case .userPromptSubmit, .preToolUse, .postToolUse:
            status = .working
            endedAt = nil
        case .permissionRequest:
            status = .waitingOnUser
            endedAt = nil
        case .subagentStart:
            subagentsStarted += 1
            status = .working
            endedAt = nil
        case .subagentStop:
            subagentsFinished = min(subagentsStarted, subagentsFinished + 1)
            status = .working
        case .unknown:
            break
        }
    }
}
