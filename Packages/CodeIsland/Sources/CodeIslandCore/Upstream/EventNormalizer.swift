import Foundation

public enum EventNormalizer {
    /// Normalize event names from various CLIs to internal PascalCase names
    public static func normalize(_ name: String) -> String {
        switch name {
        // Cursor (camelCase)
        case "beforeSubmitPrompt":    return "UserPromptSubmit"
        case "beforeShellExecution":  return "PreToolUse"
        case "afterShellExecution":   return "PostToolUse"
        case "beforeReadFile":        return "PreToolUse"
        case "afterFileEdit":         return "PostToolUse"
        case "beforeMCPExecution":    return "PreToolUse"
        case "afterMCPExecution":     return "PostToolUse"
        case "afterAgentThought":     return "Notification"
        case "afterAgentResponse":    return "AfterAgentResponse"
        case "stop":                  return "Stop"
        // Gemini
        case "BeforeTool":            return "PermissionRequest"
        case "AfterTool":             return "PostToolUse"
        case "BeforeAgent":           return "SubagentStart"
        case "AfterAgent":            return "SubagentStop"
        // GitHub Copilot CLI
        case "sessionStart":          return "SessionStart"
        case "sessionEnd":            return "SessionEnd"
        case "userPromptSubmitted":   return "UserPromptSubmit"
        case "preToolUse":            return "PreToolUse"
        case "postToolUse":           return "PostToolUse"
        case "errorOccurred":         return "Notification"
        // Kiro CLI (camelCase, agent-scoped)
        case "agentSpawn":            return "SessionStart"
        case "userPromptSubmit":      return "UserPromptSubmit"
        // Traecli (snake_case)
        case "session_start":         return "SessionStart"
        case "session_end":           return "SessionEnd"
        case "user_prompt_submit":    return "UserPromptSubmit"
        case "pre_tool_use":          return "PreToolUse"
        case "post_tool_use":         return "PostToolUse"
        case "post_tool_use_failure": return "PostToolUseFailure"
        case "permission_request":    return "PermissionRequest"
        case "subagent_start":        return "SubagentStart"
        case "subagent_stop":         return "SubagentStop"
        case "pre_compact":           return "PreCompact"
        case "post_compact":          return "PostCompact"
        case "notification":          return "Notification"
        // Hermes (Nous Research) — snake_case but diverged from Claude/Gemini (#226).
        // `subagent_stop` already maps to SubagentStop in the traecli block above.
        case "pre_tool_call":         return "PreToolUse"
        case "post_tool_call":        return "PostToolUse"
        case "pre_llm_call":          return "UserPromptSubmit"
        case "on_session_start":      return "SessionStart"
        case "on_session_end":        return "SessionEnd"
        case "on_session_reset":      return "SessionEnd"
        // Cline (VSCode extension)
        case "TaskStart":             return "SessionStart"
        case "TaskResume":            return "UserPromptSubmit"
        case "TaskComplete":          return "TaskRoundComplete"
        case "TaskCancel":            return "TaskRoundComplete"
        default:                      return name
        }
    }
}
