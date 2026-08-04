import Foundation

public enum CLIProcessResolver {
    public static func sourceMatchesExecutablePath(_ path: String, source: String?) -> Bool {
        guard let normalizedSource = SessionSnapshot.normalizedSupportedSource(source) else { return false }
        let lowercasedPath = path.lowercased()

        switch normalizedSource {
        case "traecli":
            return lowercasedPath.hasSuffix("/coco")
                || lowercasedPath.hasSuffix("/traecli")
                || lowercasedPath.contains("/coco ")
                || lowercasedPath.contains("/traecli ")
        case "codex":
            return lowercasedPath.hasSuffix("/codex") || lowercasedPath.contains("/codex ")
        case "claude":
            return lowercasedPath.hasSuffix("/claude") || lowercasedPath.contains("/claude ")
        case "qwen":
            return lowercasedPath.hasSuffix("/qwen")
                || lowercasedPath.hasSuffix("/qwen-code")
                || lowercasedPath.contains("/qwen ")
                || lowercasedPath.contains("/qwen-code ")
        case "gemini":
            return lowercasedPath.hasSuffix("/gemini") || lowercasedPath.contains("/gemini ")
        case "cursor-cli":
            // Cursor's CLI agent installs to ~/.local/share/cursor-agent/versions/<v>/cursor-agent
            // and is also referenced by /cursor-agent/index.js when invoked via Node.
            return lowercasedPath.contains("/cursor-agent")
        case "qoder-cli":
            // npm @qoder-ai/qodercli installs as `qodercli` in PATH (Homebrew/npm-global)
            return lowercasedPath.hasSuffix("/qodercli")
                || lowercasedPath.contains("/qodercli ")
                || lowercasedPath.contains("/@qoder-ai/qodercli")
        case "google-antigravity":
            return lowercasedPath.hasSuffix("/agy")
                || lowercasedPath.contains("/agy ")
                || lowercasedPath.contains("/google-antigravity")
        default:
            return lowercasedPath.contains("/\(normalizedSource)")
        }
    }

    /// When the caller passed `--source cursor` or `--source qoder` but the
    /// process ancestry actually came from the CLI agent rather than the
    /// desktop IDE (both write to the same hooks file — see issue #134),
    /// promote the source to its `-cli` variant so CodeIsland renders it
    /// as "Cursor CLI" / "Qoder CLI" and routes terminal jumps correctly.
    public static func cliVariantOverride(
        declaredSource: String?,
        ancestry: [(pid: Int32, executablePath: String?)]
    ) -> String? {
        guard let normalized = SessionSnapshot.normalizedSupportedSource(declaredSource) else {
            return nil
        }
        switch normalized {
        case "cursor":
            if ancestry.contains(where: { sourceMatchesExecutablePath($0.executablePath ?? "", source: "cursor-cli") }) {
                return "cursor-cli"
            }
        case "qoder":
            if ancestry.contains(where: { sourceMatchesExecutablePath($0.executablePath ?? "", source: "qoder-cli") }) {
                return "qoder-cli"
            }
        default:
            break
        }
        return nil
    }

    public static func resolvedTrackedPID(
        immediateParentPID: Int32,
        source: String?,
        ancestry: [(pid: Int32, executablePath: String?)]
    ) -> Int32 {
        guard immediateParentPID > 0 else { return immediateParentPID }

        if let directMatch = ancestry.first(where: {
            sourceMatchesExecutablePath($0.executablePath ?? "", source: source)
        }) {
            return directMatch.pid
        }

        return immediateParentPID
    }

    /// Stable per-session PID for fallback session_id generation. Walks the
    /// ancestry from root downward and picks the *highest* binary matching
    /// the source, so sub-agent processes spawned by the same parent CLI
    /// (e.g. Cursor IDE running multiple parallel agent subprocesses, #148)
    /// collapse onto a single session card instead of fanning out into one
    /// card per sub-agent ppid.
    ///
    /// Falls back to `immediateParentPID` when no source-matching binary is
    /// in the ancestry — preserves prior behavior for everything else.
    public static func resolvedSessionPID(
        immediateParentPID: Int32,
        source: String?,
        ancestry: [(pid: Int32, executablePath: String?)]
    ) -> Int32 {
        guard immediateParentPID > 0 else { return immediateParentPID }

        if let rootMatch = ancestry.last(where: {
            sourceMatchesExecutablePath($0.executablePath ?? "", source: source)
        }) {
            return rootMatch.pid
        }

        return immediateParentPID
    }

    /// Walk the process ancestry and return the first known CLI source whose binary
    /// appears along the chain. Used when a hook event reaches the bridge without a
    /// `--source` tag (e.g. omo plugin firing Claude hooks from inside OpenCode), so
    /// we can recover the real source instead of letting the event default to Claude.
    public static func inferSource(ancestry: [(pid: Int32, executablePath: String?)]) -> String? {
        // Try `-cli` variants first so `cursor-agent` doesn't get mis-attributed
        // to the desktop `cursor` source (see issue #134).
        //
        // Exclude desktop-IDE *host* sources entirely: their GUI host/helper
        // processes appear in the ancestry of any CLI run from the IDE's
        // integrated terminal and would be greedily matched by the loose
        // `/<source>` substring rule, mis-attributing e.g. Claude Code run in
        // Cursor's terminal to "cursor". Desktop IDEs always report themselves
        // via `--source`, so they never need ancestry inference. (#220)
        let all = SessionSnapshot.supportedSources.subtracting(SessionSnapshot.ideHostSources)
        let cliFirst = all.filter { $0.hasSuffix("-cli") }.sorted()
            + all.filter { !$0.hasSuffix("-cli") }.sorted()
        for entry in ancestry {
            guard let path = entry.executablePath, !path.isEmpty else { continue }
            for source in cliFirst {
                if sourceMatchesExecutablePath(path, source: source) {
                    return source
                }
            }
        }
        return nil
    }
}

public enum AgentStatus: Sendable {
    case idle
    case processing
    case running
    case waitingApproval
    case waitingQuestion
}

public struct HookEvent {
    public let eventName: String
    public let sessionId: String?
    public let toolName: String?
    public let toolUseId: String?
    public let agentId: String?
    public let toolInput: [String: Any]?
    public let rawJSON: [String: Any]  // Full payload for event-specific fields

    public init?(from data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventName = HookEvent.firstString(in: json, keys: ["hook_event_name", "hookEventName", "event_name", "eventName"]) else {
            return nil
        }
        self.eventName = eventName
        let rawSessionId = HookEvent.firstString(in: json, keys: ["session_id", "sessionId"])
        if let rawSessionId,
           let remoteHostId = json["_remote_host_id"] as? String,
           !remoteHostId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.sessionId = "remote:\(remoteHostId):\(rawSessionId)"
        } else {
            self.sessionId = rawSessionId
        }
        self.toolName = HookEvent.firstString(in: json, keys: ["tool_name", "toolName", "tool", "name"])
            ?? HookEvent.firstString(inNestedDictionary: json, containerKeys: ["tool", "payload", "data"], keys: ["name", "tool_name", "toolName"])
            ?? HookEvent.firstString(inNestedDictionary: json, containerKeys: ["toolCall"], keys: ["name"])
        // `toolCallId` is ZCode's flat spelling of the same invocation id (its
        // kernel emits {toolCallId, toolName, toolInput} on every tool event).
        // Parsing it keeps zcode permission requests correlated by id so they
        // are never mistaken for orphans and auto-resolved on session activity.
        self.toolUseId = HookEvent.firstString(in: json, keys: ["tool_use_id", "toolUseId", "toolCallId"])
            ?? HookEvent.firstString(inNestedDictionary: json, containerKeys: ["tool", "tool_use", "toolUse", "payload", "data"], keys: ["id", "tool_use_id", "toolUseId"])
        self.toolInput = HookEvent.firstDictionary(in: json, keys: ["tool_input", "toolInput", "input", "arguments", "args", "params"])
            ?? HookEvent.firstDictionary(inNestedDictionary: json, containerKeys: ["tool", "payload", "data"], keys: ["input", "tool_input", "toolInput", "arguments", "args", "params"])
            ?? HookEvent.firstDictionary(inNestedDictionary: json, containerKeys: ["toolCall"], keys: ["args"])
        self.agentId = json["agent_id"] as? String
        self.rawJSON = json
    }

    public var toolDescription: String? {
        if let input = toolInput {
            switch toolName {
            case "Bash", "execute_command", "run_command":
                let desc = HookEvent.normalizedMultilineString(input["description"])
                let cmd = HookEvent.normalizedMultilineString(input["CommandLine"] ?? input["command"])
                if let desc, let cmd {
                    if desc == cmd || desc.contains(cmd) {
                        return desc
                    }
                    return "\(desc)\nCommand:\n\(cmd)"
                }
                if let desc { return desc }
                if let cmd { return cmd }
            case "Read", "read_file", "view_file":
                if let fp = (input["AbsolutePath"] ?? input["file_path"]) as? String {
                    let name = (fp as NSString).lastPathComponent
                    if let start = input["StartLine"] as? Int, let end = input["EndLine"] as? Int {
                        return "\(name):\(start)-\(end)"
                    }
                    if let offset = input["offset"] as? Int {
                        return "\(name):\(offset)"
                    }
                    return name
                }
            case "Edit", "apply_diff", "replace_file_content", "multi_replace_file_content":
                if let fp = (input["TargetFile"] ?? input["file_path"]) as? String {
                    return (fp as NSString).lastPathComponent
                }
            case "Write", "write_to_file":
                if let fp = (input["TargetFile"] ?? input["file_path"]) as? String {
                    return (fp as NSString).lastPathComponent
                }
            case "Grep", "search_files", "grep_search":
                if let pattern = (input["Query"] ?? input["pattern"]) as? String {
                    let path = ((input["SearchPath"] ?? input["path"]) as? String).map { " in \(($0 as NSString).lastPathComponent)" } ?? ""
                    return "\(pattern)\(path)"
                }
            case "Glob":
                if let pattern = input["pattern"] as? String { return pattern }
            case "WebSearch":
                if let query = input["query"] as? String { return query }
            case "WebFetch":
                if let url = input["url"] as? String {
                    // Show domain only
                    if let host = URL(string: url)?.host { return host }
                    return String(url.prefix(40))
                }
            case "Task", "Agent":
                if let desc = input["description"] as? String, !desc.isEmpty { return desc }
                if let prompt = input["prompt"] as? String { return String(prompt.prefix(40)) }
            case "TodoWrite":
                return "Updating tasks"
            default:
                // Generic: try common fields
                if let fp = input["file_path"] as? String { return (fp as NSString).lastPathComponent }
                if let pattern = input["pattern"] as? String { return pattern }
                if let command = input["command"] as? String { return String(command.prefix(60)) }
                if let prompt = input["prompt"] as? String { return String(prompt.prefix(40)) }
            }
        }
        // Fall back to top-level fields
        if let msg = HookEvent.firstString(in: rawJSON, keys: ["message", "text", "summary", "status", "detail", "content"]) {
            return msg
        }
        if let msg = HookEvent.firstString(inNestedDictionary: rawJSON, containerKeys: ["payload", "data"], keys: ["message", "text", "summary", "status", "detail", "content"]) {
            return msg
        }
        if let agentType = rawJSON["agent_type"] as? String { return agentType }
        if let prompt = rawJSON["prompt"] as? String { return String(prompt.prefix(40)) }
        return nil
    }

    private static func normalizedMultilineString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func firstDictionary(in dict: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = dict[key] as? [String: Any] { return value }
        }
        return nil
    }

    private static func firstString(
        inNestedDictionary dict: [String: Any],
        containerKeys: [String],
        keys: [String]
    ) -> String? {
        for containerKey in containerKeys {
            if let nested = dict[containerKey] as? [String: Any],
               let value = firstString(in: nested, keys: keys) {
                return value
            }
        }
        return nil
    }

    private static func firstDictionary(
        inNestedDictionary dict: [String: Any],
        containerKeys: [String],
        keys: [String]
    ) -> [String: Any]? {
        for containerKey in containerKeys {
            if let nested = dict[containerKey] as? [String: Any],
               let value = firstDictionary(in: nested, keys: keys) {
                return value
            }
        }
        return nil
    }
}

public struct SubagentState: Sendable {
    public let agentId: String
    public let agentType: String
    public var status: AgentStatus = .running
    public var currentTool: String?
    public var toolDescription: String?
    public var startTime: Date = Date()
    public var lastActivity: Date = Date()

    public init(agentId: String, agentType: String) {
        self.agentId = agentId
        self.agentType = agentType
    }
}

public struct ToolHistoryEntry: Identifiable, Sendable {
    public let id = UUID()
    public let tool: String
    public let description: String?
    public let timestamp: Date
    public let success: Bool
    public let agentType: String?  // nil = main thread

    public init(tool: String, description: String?, timestamp: Date, success: Bool, agentType: String?) {
        self.tool = tool
        self.description = description
        self.timestamp = timestamp
        self.success = success
        self.agentType = agentType
    }
}

public struct ChatMessage: Identifiable, Sendable {
    public let id = UUID()
    public let isUser: Bool
    public let text: String

    public init(isUser: Bool, text: String) {
        self.isUser = isUser
        self.text = text
    }
}

public struct QuestionPayload {
    public let question: String
    public let options: [String]?
    public let descriptions: [String]?
    public let header: String?
    /// When true the answer is sensitive (e.g. a Codex `isSecret` plan-mode
    /// prompt). Remote peripherals (companion / ESP32) must not stream the
    /// question text or options to avoid leaking secrets off-device.
    public let isSecret: Bool

    public init(
        question: String,
        options: [String]?,
        descriptions: [String]? = nil,
        header: String? = nil,
        isSecret: Bool = false
    ) {
        self.question = question
        self.options = options
        self.descriptions = descriptions
        self.header = header
        self.isSecret = isSecret
    }

    /// Try to extract question from a Notification hook event
    public static func from(event: HookEvent) -> QuestionPayload? {
        if let question = event.rawJSON["question"] as? String {
            let options = event.rawJSON["options"] as? [String]
            return QuestionPayload(question: question, options: options)
        }
        // Don't use "?" heuristic — normal status text like "Should I update tests?"
        // would be misclassified as a blocking question, stalling the hook.
        return nil
    }
}
