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

/// A hook payload from any supported agent, flattened into the subset of fields
/// Agent Tower actually uses.
///
/// Everything is extracted eagerly at parse time so no `[String: Any]` ever
/// crosses a concurrency boundary. Unknown agents and unknown events still
/// produce a value — `name` simply lands on `.unknown`, which the manager
/// records as activity but never answers with a decision.
struct AgentHookEvent: Sendable {
    /// Normalised event name. Agents disagree on spelling (Gemini calls it
    /// `BeforeTool`), so the adapter maps onto this list rather than the wire name.
    enum Name: String, Sendable {
        case sessionStart
        case sessionEnd
        case stop
        case notification
        case userPromptSubmit
        case preToolUse
        case permissionRequest
        case postToolUse
        case subagentStart
        case subagentStop
        case unknown

        /// Whether the agent is blocked on this hook's stdout waiting for a decision.
        var expectsDecision: Bool {
            switch self {
            case .preToolUse, .permissionRequest:
                return true
            case .sessionStart, .sessionEnd, .stop, .notification,
                 .userPromptSubmit, .postToolUse, .subagentStart,
                 .subagentStop, .unknown:
                return false
            }
        }
    }

    let kind: AgentKind
    let name: Name
    /// The wire event name exactly as the agent wrote it, needed to echo back a
    /// correctly-shaped `hookSpecificOutput`.
    let rawEventName: String
    let sessionID: String
    let cwd: String?
    let transcriptPath: String?
    let permissionMode: String?

    let toolName: String?
    let toolUseID: String?
    /// `tool_input.command` for shell tools.
    let command: String?
    /// `tool_input.description`, or the notification message.
    let toolDescription: String?
    /// `tool_input.file_path` for edit/write tools.
    let filePath: String?
    /// `tool_input.plan` for plan presentation.
    let plan: String?
    /// Free-form message carried by `Notification`-style events.
    let message: String?

    let agentID: String?
    let agentType: String?

    let terminalProgram: String?
    let terminalBundleID: String?
    let receivedAt: Date

    /// Stable identity for the session this event belongs to. Agents reuse plain
    /// UUIDs, so the kind is folded in to keep two CLIs from colliding.
    var sessionKey: String {
        "\(kind.rawValue):\(sessionID)"
    }

    /// Last path component of `cwd`, which is what users recognise as the project.
    var projectName: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? nil : name
    }
}
