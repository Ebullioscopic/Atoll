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

/// Turns a raw agent hook payload into an `AgentHookEvent`.
///
/// Every supported CLI writes a slightly different JSON shape and none of them
/// promise stability, so this reads defensively: each field is looked up under
/// every spelling seen in the wild and a miss is `nil` rather than a failure.
/// The one hard requirement is a session identifier — without it there is no
/// session to attribute the event to.
///
/// Pure and synchronous on purpose: this is the unit-tested seam of the feature.
enum AgentEventAdapter {
    /// Reads a hook body plus the hints the shim passes as query parameters.
    ///
    /// - Parameters:
    ///   - agentHint: the `agent=` query value; authoritative, because Atoll
    ///     wrote it into the hook config itself.
    ///   - eventHint: the `event=` query value, used only when the body omits
    ///     `hook_event_name`.
    /// - Returns: `nil` when the body is not a JSON object or carries no session id.
    static func makeEvent(
        body: Data,
        agentHint: String?,
        eventHint: String?,
        terminalProgram: String?,
        terminalBundleID: String?,
        now: Date
    ) -> AgentHookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: body),
              let root = object as? [String: Any]
        else { return nil }

        guard let sessionID = firstString(in: root, keys: [
            "session_id", "sessionId", "sessionID", "session", "conversation_id", "conversationId"
        ]) else { return nil }

        let kind = AgentKind(rawValue: agentHint ?? "") ?? inferKind(from: root) ?? .claudeCode

        let rawEventName = firstString(in: root, keys: [
            "hook_event_name", "hookEventName", "event", "event_name", "eventName", "type"
        ]) ?? eventHint ?? ""

        let toolInput = firstDictionary(in: root, keys: [
            "tool_input", "toolInput", "input", "arguments", "args"
        ]) ?? [:]

        return AgentHookEvent(
            kind: kind,
            name: normalizedName(for: rawEventName),
            rawEventName: rawEventName,
            sessionID: sessionID,
            cwd: firstString(in: root, keys: ["cwd", "workspace", "workspace_root", "project_dir", "projectDir", "workingDirectory"]),
            transcriptPath: firstString(in: root, keys: ["transcript_path", "transcriptPath", "transcript"]),
            permissionMode: firstString(in: root, keys: ["permission_mode", "permissionMode", "mode"]),
            toolName: firstString(in: root, keys: ["tool_name", "toolName", "tool"]),
            toolUseID: firstString(in: root, keys: ["tool_use_id", "toolUseId", "toolUseID", "call_id", "callId"]),
            command: firstString(in: toolInput, keys: ["command", "cmd", "shell_command", "script"]),
            toolDescription: firstString(in: toolInput, keys: ["description", "title", "summary"]),
            filePath: firstString(in: toolInput, keys: ["file_path", "filePath", "path", "target_file", "notebook_path"]),
            plan: firstString(in: toolInput, keys: ["plan", "content", "text"]),
            message: firstString(in: root, keys: ["message", "notification", "reason", "text"]),
            agentID: firstString(in: root, keys: ["agent_id", "agentId", "agentID"]),
            agentType: firstString(in: root, keys: ["agent_type", "agentType"]),
            terminalProgram: normalizedHint(terminalProgram),
            terminalBundleID: normalizedHint(terminalBundleID),
            receivedAt: now
        )
    }

    /// Maps a wire event name onto Atoll's vocabulary.
    ///
    /// Comparison is case- and separator-insensitive so `PreToolUse`,
    /// `pre_tool_use` and `pretooluse` all land on the same case. Gemini CLI's
    /// `BeforeTool` / `AfterTool` spellings are folded in here too.
    static func normalizedName(for rawEventName: String) -> AgentHookEvent.Name {
        switch canonicalKey(rawEventName) {
        case "sessionstart", "startsession":
            return .sessionStart
        case "sessionend", "endsession", "sessionstop":
            return .sessionEnd
        case "stop", "turnend", "responsecomplete":
            return .stop
        case "notification", "notify":
            return .notification
        case "userpromptsubmit", "beforeprompt", "prompt":
            return .userPromptSubmit
        case "pretooluse", "beforetool", "pretool", "tooluse", "beforeshellexecution":
            return .preToolUse
        case "permissionrequest", "permission", "approvalrequest":
            return .permissionRequest
        case "posttooluse", "aftertool", "posttool", "posttoolusefailure":
            return .postToolUse
        case "subagentstart", "taskstart":
            return .subagentStart
        case "subagentstop", "taskcompleted", "taskcomplete":
            return .subagentStop
        default:
            return .unknown
        }
    }

    // MARK: - Field lookup

    private static func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstDictionary(in dictionary: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = dictionary[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    /// Best-effort agent detection for payloads that arrive without the shim's
    /// `agent=` hint — for instance if a user wires the hook up by hand.
    private static func inferKind(from root: [String: Any]) -> AgentKind? {
        if root["transcript_path"] is String { return .claudeCode }
        if root["conversation_id"] is String || root["conversationId"] is String { return .codex }
        return nil
    }

    /// Drops empty and placeholder query values. An unset shell variable expands
    /// to the empty string, so the shim's URL can legitimately carry `term=`.
    private static func normalizedHint(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Lowercases and strips every non-alphanumeric character.
    private static func canonicalKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
