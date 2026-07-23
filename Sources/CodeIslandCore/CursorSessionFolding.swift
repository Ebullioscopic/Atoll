import Foundation

/// Maps Cursor Task/subagent hooks onto their parent chat card.
///
/// Child hooks use a different `session_id`, but `transcript_path` still points at
/// `…/agent-transcripts/<parentId>/…`. Without rewriting, each Task appears as a
/// duplicate Cursor card for the same IDE conversation.
public enum CursorSessionFolding {
    /// UUID segment under `agent-transcripts/`.
    private static let uuidDirPattern = #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#

    /// Parent conversation id from a Cursor `transcript_path`, when present.
    ///
    /// Recognized layouts:
    /// - `…/agent-transcripts/<parentId>/<parentId>.jsonl`
    /// - `…/agent-transcripts/<parentId>/subagents/<childId>.jsonl`
    public static func parentConversationId(fromTranscriptPath path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = (trimmed as NSString).pathComponents
        guard let transcriptsIdx = parts.lastIndex(of: "agent-transcripts"),
              transcriptsIdx + 1 < parts.count else {
            return nil
        }

        let parentCandidate = parts[transcriptsIdx + 1]
        guard parentCandidate.range(of: uuidDirPattern, options: .regularExpression) != nil else {
            return nil
        }
        return parentCandidate
    }

    /// Parent id when `childSessionId` is a Task of that conversation
    /// (`transcript_path` parent ≠ `childSessionId`).
    public static func foldTarget(childSessionId: String, transcriptPath: String?) -> String? {
        let child = childSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !child.isEmpty,
              let path = transcriptPath,
              let parentId = parentConversationId(fromTranscriptPath: path),
              parentId != child else {
            return nil
        }
        return parentId
    }
}

/// How to handle a Cursor Task/subagent hook under Agent Sub-Sessions.
public enum CursorSubsessionRouteDecision: Equatable {
    case leave
    case hide
    case merge(parentSessionId: String, childSessionId: String)
}

public enum CursorSubsessionRouter {
    /// Apply Agent Sub-Sessions (`separate` / `merge` / `hide`) to Cursor hooks.
    /// Same three modes as Codex and plugin children.
    public static func decide(raw: [String: Any], mode: String) -> CursorSubsessionRouteDecision {
        let normalizedSource = SessionSnapshot.normalizedSupportedSource(
            (raw["_source"] as? String) ?? (raw["source"] as? String)
        )
        guard normalizedSource == "cursor" || normalizedSource == "cursor-cli" else {
            return .leave
        }

        let childSessionId = nonEmptyString(raw["session_id"]) ?? nonEmptyString(raw["sessionId"])
        guard let childSessionId else { return .leave }

        let transcriptPath = nonEmptyString(raw["transcript_path"]) ?? nonEmptyString(raw["transcriptPath"])
        guard let parentId = CursorSessionFolding.foldTarget(
            childSessionId: childSessionId,
            transcriptPath: transcriptPath
        ) else {
            return .leave
        }

        switch mode {
        case "hide":
            return .hide
        case "merge":
            return .merge(parentSessionId: parentId, childSessionId: childSessionId)
        default:
            // separate (or unknown): leave as its own session card
            return .leave
        }
    }

    /// Rewrite the hook onto the parent session and attach `agent_id` = child.
    public static func applyMerge(
        to raw: inout [String: Any],
        parentSessionId: String,
        childSessionId: String
    ) {
        raw["session_id"] = parentSessionId
        raw["agent_id"] = nonEmptyString(raw["agent_id"]) ?? childSessionId
        if nonEmptyString(raw["agent_type"]) == nil {
            raw["agent_type"] = "cursor-subagent"
        }
        raw["_cursor_subagent"] = true
        raw["_cursor_subagent_session_id"] = childSessionId
        if let eventName = nonEmptyString(raw["hook_event_name"])
            ?? nonEmptyString(raw["hookEventName"])
            ?? nonEmptyString(raw["event_name"])
            ?? nonEmptyString(raw["eventName"]) {
            raw["_cursor_subagent_event"] = EventNormalizer.normalize(eventName)
        }
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
