import Foundation

public enum CodexTaskStatus: String, Codable, Equatable, Sendable {
    case registered
    case running
    case waitingForApproval
    case completed
    case failedOrInterrupted
    case stale
    case ended
}

public enum PreviewMode: String, Codable, Equatable, Sendable {
    case projectAndPreview
    case projectOnly
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public var previewMode: PreviewMode
    public var staleTimeout: TimeInterval
    public var recentRetention: TimeInterval
    public var maxRecentCompletions: Int
    public var completionSneakPeekEnabled: Bool
    public var approvalReminderEnabled: Bool

    public init(
        previewMode: PreviewMode = .projectAndPreview,
        staleTimeout: TimeInterval = 45 * 60,
        recentRetention: TimeInterval = 7 * 24 * 60 * 60,
        maxRecentCompletions: Int = 100,
        completionSneakPeekEnabled: Bool = true,
        approvalReminderEnabled: Bool = true
    ) {
        self.previewMode = previewMode
        self.staleTimeout = staleTimeout
        self.recentRetention = recentRetention
        self.maxRecentCompletions = max(1, maxRecentCompletions)
        self.completionSneakPeekEnabled = completionSneakPeekEnabled
        self.approvalReminderEnabled = approvalReminderEnabled
    }
}

public struct CodexTaskRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var sessionID: String
    public var currentTurnID: String?
    public var cwd: String?
    public var projectName: String
    public var promptPreview: String?
    public var resultPreview: String?
    public var approvalPreview: String?
    public var toolName: String?
    public var status: CodexTaskStatus
    public var startedAt: Date?
    public var lastActivityAt: Date
    public var completedAt: Date?
    public var endedAt: Date?
    public var model: String?
    public var lastEventID: UUID?
    public var lastEventName: String?

    public init(
        sessionID: String,
        currentTurnID: String? = nil,
        cwd: String? = nil,
        projectName: String = "Codex 会话",
        promptPreview: String? = nil,
        resultPreview: String? = nil,
        approvalPreview: String? = nil,
        toolName: String? = nil,
        status: CodexTaskStatus = .registered,
        startedAt: Date? = nil,
        lastActivityAt: Date,
        completedAt: Date? = nil,
        endedAt: Date? = nil,
        model: String? = nil,
        lastEventID: UUID? = nil,
        lastEventName: String? = nil
    ) {
        self.id = sessionID
        self.sessionID = sessionID
        self.currentTurnID = currentTurnID
        self.cwd = cwd
        self.projectName = projectName
        self.promptPreview = promptPreview
        self.resultPreview = resultPreview
        self.approvalPreview = approvalPreview
        self.toolName = toolName
        self.status = status
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.completedAt = completedAt
        self.endedAt = endedAt
        self.model = model
        self.lastEventID = lastEventID
        self.lastEventName = lastEventName
    }
}

public struct CodexCompletionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: String
    public let projectName: String
    public let promptPreview: String?
    public let resultPreview: String?
    public let completedAt: Date

    public init(
        id: UUID = UUID(),
        sessionID: String,
        projectName: String,
        promptPreview: String?,
        resultPreview: String?,
        completedAt: Date
    ) {
        self.id = id
        self.sessionID = sessionID
        self.projectName = projectName
        self.promptPreview = promptPreview
        self.resultPreview = resultPreview
        self.completedAt = completedAt
    }
}

public struct CodexTaskStoreSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var savedAt: Date
    public var tasks: [CodexTaskRecord]
    public var recentCompletions: [CodexCompletionRecord]
    public var acknowledgedCompletionIDs: [UUID]?
    public var processedEventIDs: [UUID]

    public init(
        schemaVersion: Int = 1,
        savedAt: Date = Date(),
        tasks: [CodexTaskRecord] = [],
        recentCompletions: [CodexCompletionRecord] = [],
        acknowledgedCompletionIDs: [UUID] = [],
        processedEventIDs: [UUID] = []
    ) {
        self.schemaVersion = schemaVersion
        self.savedAt = savedAt
        self.tasks = tasks
        self.recentCompletions = recentCompletions
        self.acknowledgedCompletionIDs = acknowledgedCompletionIDs
        self.processedEventIDs = processedEventIDs
    }

    public var unacknowledgedCompletions: [CodexCompletionRecord] {
        let acknowledged = Set(acknowledgedCompletionIDs ?? [])
        return recentCompletions.filter { !acknowledged.contains($0.id) }
    }

    public static var empty: CodexTaskStoreSnapshot { CodexTaskStoreSnapshot() }
}
