import Foundation

enum CompanionStatus: String, Codable, Hashable {
    case idle
    case processing
    case running
    case waitingApproval
    case waitingQuestion

    /// Tolerant decoding: a newer Mac app may ship status values this build has
    /// never heard of. Falling back to .idle keeps the payload renderable instead
    /// of failing the whole decode (and, on watchOS, re-crashing on the persisted
    /// application context at every launch — #246).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CompanionStatus(rawValue: raw) ?? .idle
    }

    var label: String {
        switch self {
        case .idle: return L10n.t(zh: "空闲", en: "Idle")
        case .processing: return L10n.t(zh: "处理中", en: "Processing")
        case .running: return L10n.t(zh: "运行中", en: "Running")
        case .waitingApproval: return L10n.t(zh: "等待批准", en: "Waiting Approval")
        case .waitingQuestion: return L10n.t(zh: "等待回答", en: "Waiting Answer")
        }
    }

    var shortLabel: String {
        switch self {
        case .idle: return L10n.t(zh: "空闲", en: "Idle")
        case .processing: return L10n.t(zh: "处理", en: "Working")
        case .running: return L10n.t(zh: "运行", en: "Running")
        case .waitingApproval: return L10n.t(zh: "批准", en: "Approve")
        case .waitingQuestion: return L10n.t(zh: "问题", en: "Question")
        }
    }

    /// 与 Mac notch 一致的展示优先级：审批 > 提问 > 运行 > 处理 > 空闲。
    var priority: Int {
        switch self {
        case .waitingApproval: return 5
        case .waitingQuestion: return 4
        case .running: return 3
        case .processing: return 2
        case .idle: return 0
        }
    }
}

enum CompanionPendingAction: String, Codable {
    case approval
    case question
}

enum CompanionMessageRole: String, Codable {
    case user
    case assistant

    /// Tolerant decoding — unknown roles from a newer Mac app read as assistant (#246).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CompanionMessageRole(rawValue: raw) ?? .assistant
    }

    var label: String {
        switch self {
        case .user: return L10n.t(zh: "你", en: "You")
        case .assistant: return L10n.t(zh: "助手", en: "Assistant")
        }
    }
}

struct CompanionMessagePreview: Codable, Identifiable, Hashable {
    let id = UUID()
    let role: CompanionMessageRole
    let text: String

    init(role: CompanionMessageRole, text: String) {
        self.role = role
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case role
        case text
    }
}

struct CompanionQuestionPayload: Codable {
    let header: String?
    let question: String
    let options: [String]
    let descriptions: [String]
    let index: Int
    let total: Int
    let allowsMultipleSelection: Bool

    init(
        header: String?,
        question: String,
        options: [String],
        descriptions: [String],
        index: Int,
        total: Int,
        allowsMultipleSelection: Bool
    ) {
        self.header = header
        self.question = question
        self.options = options
        self.descriptions = descriptions
        self.index = index
        self.total = total
        self.allowsMultipleSelection = allowsMultipleSelection
    }

    private enum CodingKeys: String, CodingKey {
        case header, question, options, descriptions, index, total, allowsMultipleSelection
    }

    /// Tolerant decoding: only `question` is required. Everything else falls back to
    /// safe defaults so a payload from a newer/older Mac app never fails the decode (#246).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        header = try? c.decodeIfPresent(String.self, forKey: .header)
        question = try c.decode(String.self, forKey: .question)
        options = (try? c.decodeIfPresent([String].self, forKey: .options)) ?? []
        descriptions = (try? c.decodeIfPresent([String].self, forKey: .descriptions)) ?? []
        index = max(0, (try? c.decodeIfPresent(Int.self, forKey: .index)) ?? 0)
        total = max(1, (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 1)
        allowsMultipleSelection = (try? c.decodeIfPresent(Bool.self, forKey: .allowsMultipleSelection)) ?? false
    }
}

struct CompanionSessionPreview: Codable, Identifiable, Hashable {
    let sessionId: String?
    let source: String
    let status: CompanionStatus
    let toolName: String?
    let workspaceName: String?
    let message: String?
    /// 该会话最近若干条消息（含角色），用于逐会话显示多轮转写。
    let messages: [CompanionMessagePreview]
    let updatedAt: Date

    var id: String {
        sessionId ?? "\(source)-\(workspaceName ?? "session")-\(updatedAt.timeIntervalSince1970)"
    }

    init(
        sessionId: String?,
        source: String,
        status: CompanionStatus,
        toolName: String?,
        workspaceName: String?,
        message: String?,
        messages: [CompanionMessagePreview] = [],
        updatedAt: Date
    ) {
        self.sessionId = sessionId
        self.source = source
        self.status = status
        self.toolName = toolName
        self.workspaceName = workspaceName
        self.message = message
        self.messages = messages
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, source, status, toolName, workspaceName, message, messages, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        source = try c.decode(String.self, forKey: .source)
        status = try c.decode(CompanionStatus.self, forKey: .status)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        workspaceName = try c.decodeIfPresent(String.self, forKey: .workspaceName)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        messages = try c.decodeIfPresent([CompanionMessagePreview].self, forKey: .messages) ?? []
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

struct CompanionStatePayload: Codable {
    let version: Int
    let sequence: UInt64
    let sessionId: String?
    let source: String
    let status: CompanionStatus
    let toolName: String?
    let workspaceName: String?
    let messages: [CompanionMessagePreview]
    let pendingAction: CompanionPendingAction?
    let question: CompanionQuestionPayload?
    let sessions: [CompanionSessionPreview]
    let updatedAt: Date

    init(
        version: Int,
        sequence: UInt64,
        sessionId: String?,
        source: String,
        status: CompanionStatus,
        toolName: String?,
        workspaceName: String?,
        messages: [CompanionMessagePreview],
        pendingAction: CompanionPendingAction?,
        question: CompanionQuestionPayload?,
        sessions: [CompanionSessionPreview] = [],
        updatedAt: Date
    ) {
        self.version = version
        self.sequence = sequence
        self.sessionId = sessionId
        self.source = source
        self.status = status
        self.toolName = toolName
        self.workspaceName = workspaceName
        self.messages = messages
        self.pendingAction = pendingAction
        self.question = question
        self.sessions = sessions
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case sequence
        case sessionId
        case source
        case status
        case toolName
        case workspaceName
        case messages
        case pendingAction
        case question
        case sessions
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        source = try container.decode(String.self, forKey: .source)
        status = try container.decode(CompanionStatus.self, forKey: .status)
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        workspaceName = try container.decodeIfPresent(String.self, forKey: .workspaceName)
        messages = (try? container.decodeIfPresent([CompanionMessagePreview].self, forKey: .messages)) ?? []
        // Unknown pending actions / malformed question payloads from a different app
        // version degrade to nil instead of failing the whole state decode (#246).
        pendingAction = (try? container.decodeIfPresent(CompanionPendingAction.self, forKey: .pendingAction)) ?? nil
        question = (try? container.decodeIfPresent(CompanionQuestionPayload.self, forKey: .question)) ?? nil
        sessions = (try? container.decodeIfPresent([CompanionSessionPreview].self, forKey: .sessions)) ?? []
        updatedAt = (try? container.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? Date()
    }
}

enum CompanionCommandType: String, Codable {
    case requestCurrentState
    case approveCurrentPermission
    case denyCurrentPermission
    case skipCurrentQuestion
    case answerQuestion
    case focus
}

struct CompanionCommandPayload: Codable {
    let version: Int
    let type: CompanionCommandType
    let sessionId: String?
    let source: String?
    let answer: String?

    init(version: Int = 1, type: CompanionCommandType, sessionId: String? = nil, source: String? = nil, answer: String? = nil) {
        self.version = version
        self.type = type
        self.sessionId = sessionId
        self.source = source
        self.answer = answer
    }
}
