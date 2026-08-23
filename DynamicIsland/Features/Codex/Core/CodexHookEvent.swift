import Foundation

public struct CodexHookEvent: Codable, Equatable, Sendable {
    public let hookEventName: String
    public let sessionID: String
    public let source: String?
    public let turnID: String?
    public let transcriptPath: String?
    public let cwd: String?
    public let model: String?
    public let permissionMode: String?
    public let prompt: String?
    public let toolName: String?
    public let toolInput: JSONValue?
    public let lastAssistantMessage: String?
    public let reason: String?

    public init(
        hookEventName: String,
        sessionID: String,
        source: String? = nil,
        turnID: String? = nil,
        transcriptPath: String? = nil,
        cwd: String? = nil,
        model: String? = nil,
        permissionMode: String? = nil,
        prompt: String? = nil,
        toolName: String? = nil,
        toolInput: JSONValue? = nil,
        lastAssistantMessage: String? = nil,
        reason: String? = nil
    ) {
        self.hookEventName = hookEventName
        self.sessionID = sessionID
        self.source = source
        self.turnID = turnID
        self.transcriptPath = transcriptPath
        self.cwd = cwd
        self.model = model
        self.permissionMode = permissionMode
        self.prompt = prompt
        self.toolName = toolName
        self.toolInput = toolInput
        self.lastAssistantMessage = lastAssistantMessage
        self.reason = reason
    }

    private enum CodingKeys: String, CodingKey {
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case source
        case turnID = "turn_id"
        case transcriptPath = "transcript_path"
        case cwd
        case model
        case permissionMode = "permission_mode"
        case prompt
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case lastAssistantMessage = "last_assistant_message"
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hookEventName = try container.decode(String.self, forKey: .hookEventName)
        let sessionID = try container.decode(String.self, forKey: .sessionID)
        guard !hookEventName.isEmpty, !sessionID.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .sessionID,
                in: container,
                debugDescription: "hook_event_name and session_id must not be empty"
            )
        }
        self.init(
            hookEventName: hookEventName,
            sessionID: sessionID,
            source: try container.decodeIfPresent(String.self, forKey: .source),
            turnID: try container.decodeIfPresent(String.self, forKey: .turnID),
            transcriptPath: try container.decodeIfPresent(String.self, forKey: .transcriptPath),
            cwd: try container.decodeIfPresent(String.self, forKey: .cwd),
            model: try container.decodeIfPresent(String.self, forKey: .model),
            permissionMode: try container.decodeIfPresent(String.self, forKey: .permissionMode),
            prompt: try container.decodeIfPresent(String.self, forKey: .prompt),
            toolName: try container.decodeIfPresent(String.self, forKey: .toolName),
            toolInput: try container.decodeIfPresent(JSONValue.self, forKey: .toolInput),
            lastAssistantMessage: try container.decodeIfPresent(String.self, forKey: .lastAssistantMessage),
            reason: try container.decodeIfPresent(String.self, forKey: .reason)
        )
    }
}
