import CoreGraphics
import Foundation

public enum CodexActivityBucket: String, CaseIterable, Equatable, Hashable, Sendable {
    case needsAttention
    case blocked
    case unreadCompleted
    case running
    case readHistory

    public var title: String {
        switch self {
        case .needsAttention: return "需要处理"
        case .blocked: return "异常 / 可能失联"
        case .unreadCompleted: return "最新完成"
        case .running: return "进行中"
        case .readHistory: return "历史完成"
        }
    }

    public var symbolName: String {
        switch self {
        case .needsAttention: return "exclamationmark.triangle.fill"
        case .blocked: return "bolt.trianglebadge.exclamationmark.fill"
        case .unreadCompleted: return "checkmark.circle.fill"
        case .running: return "terminal.fill"
        case .readHistory: return "checkmark.circle"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .needsAttention: return 0
        case .blocked: return 1
        case .unreadCompleted: return 2
        case .running: return 3
        case .readHistory: return 4
        }
    }
}

public struct CodexActivityTrayPreferences: Equatable, Sendable {
    public var pinnedProjectNames: Set<String>
    public var ignoredSessionIDs: Set<String>
    public var showContentPreviews: Bool

    public init(
        pinnedProjectNames: Set<String> = [],
        ignoredSessionIDs: Set<String> = [],
        showContentPreviews: Bool = true
    ) {
        self.pinnedProjectNames = pinnedProjectNames
        self.ignoredSessionIDs = ignoredSessionIDs
        self.showContentPreviews = showContentPreviews
    }
}

public struct CodexActivityTrayItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let sessionID: String
    public let projectName: String
    public let title: String
    public let statusText: String
    public let detailText: String
    public let nextAction: String
    public let bucket: CodexActivityBucket
    public let lastActivityAt: Date
    public let completedAt: Date?
    public let completionID: UUID?
    public let isRead: Bool

    public init(
        id: String,
        sessionID: String,
        projectName: String,
        title: String,
        statusText: String,
        detailText: String,
        nextAction: String,
        bucket: CodexActivityBucket,
        lastActivityAt: Date,
        completedAt: Date? = nil,
        completionID: UUID? = nil,
        isRead: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.projectName = projectName
        self.title = title
        self.statusText = statusText
        self.detailText = detailText
        self.nextAction = nextAction
        self.bucket = bucket
        self.lastActivityAt = lastActivityAt
        self.completedAt = completedAt
        self.completionID = completionID
        self.isRead = isRead
    }
}

public struct CodexActivityTrayProjectGroup: Equatable, Identifiable, Sendable {
    public let id: String
    public let projectName: String
    public let items: [CodexActivityTrayItem]
    public let isPinned: Bool
    public let isCollapsed: Bool

    public init(
        projectName: String,
        items: [CodexActivityTrayItem],
        isPinned: Bool,
        isCollapsed: Bool
    ) {
        self.id = projectName
        self.projectName = projectName
        self.items = items
        self.isPinned = isPinned
        self.isCollapsed = isCollapsed
    }
}

public struct CodexActivityTrayBucketGroup: Equatable, Identifiable, Sendable {
    public let id: CodexActivityBucket
    public let bucket: CodexActivityBucket
    public let groups: [CodexActivityTrayProjectGroup]

    public init(bucket: CodexActivityBucket, groups: [CodexActivityTrayProjectGroup]) {
        self.id = bucket
        self.bucket = bucket
        self.groups = groups
    }

    public var itemCount: Int {
        groups.reduce(0) { $0 + $1.items.count }
    }

    public var items: [CodexActivityTrayItem] {
        groups
            .flatMap(\.items)
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    public func limited(to limit: Int) -> CodexActivityTrayBucketGroup {
        guard limit >= 0, itemCount > limit else { return self }
        let allowedIDs = Set(items.prefix(limit).map(\.id))
        let limitedGroups = groups.compactMap { group -> CodexActivityTrayProjectGroup? in
            let limitedItems = group.items.filter { allowedIDs.contains($0.id) }
            guard !limitedItems.isEmpty else { return nil }
            return CodexActivityTrayProjectGroup(
                projectName: group.projectName,
                items: limitedItems,
                isPinned: group.isPinned,
                isCollapsed: group.isCollapsed
            )
        }
        return CodexActivityTrayBucketGroup(bucket: bucket, groups: limitedGroups)
    }
}

public struct CodexActivityTrayModel: Equatable, Sendable {
    public let buckets: [CodexActivityTrayBucketGroup]
    public let ignoredItems: [CodexActivityTrayItem]

    public init(
        buckets: [CodexActivityTrayBucketGroup],
        ignoredItems: [CodexActivityTrayItem] = []
    ) {
        self.buckets = buckets
        self.ignoredItems = ignoredItems
    }

    public var visibleItemCount: Int {
        buckets.reduce(0) { $0 + $1.itemCount }
    }
}

struct CodexActivityTrayExpansionPolicy {
    static func defaultCollapsedBuckets() -> Set<CodexActivityBucket> {
        [.readHistory]
    }

    static func isExpandedByDefault(_ bucket: CodexActivityBucket) -> Bool {
        bucket != .readHistory
    }
}

struct CodexActivityTrayVisibilityPolicy {
    static func visibleItemIDs(
        itemFrames: [String: CGRect],
        viewportBounds: CGRect,
        minimumVisibleFraction: CGFloat = 0.5
    ) -> Set<String> {
        let threshold = min(max(minimumVisibleFraction, 0), 1)
        return Set(itemFrames.compactMap { itemID, frame in
            guard frame.width > 0, frame.height > 0 else { return nil }
            let intersection = frame.intersection(viewportBounds)
            guard !intersection.isNull, intersection.width > 0 else { return nil }
            return intersection.height / frame.height >= threshold ? itemID : nil
        })
    }
}

struct CodexActivityTrayPresentationExposure: Equatable, Sendable {
    let presentationID: UUID
    let visibleItemIDs: Set<String>
}

struct CodexActivityTrayPresentationVisibility: Equatable, Sendable {
    private var presentationID: UUID?
    private var itemFrames: [String: CGRect] = [:]
    private var viewportSize: CGSize = .zero

    mutating func updateLayout(
        itemFrames: [String: CGRect],
        viewportSize: CGSize
    ) {
        self.itemFrames = itemFrames
        self.viewportSize = viewportSize
    }

    mutating func beginPresentation(id: UUID) {
        presentationID = id
    }

    mutating func finishPresentation() -> UUID? {
        let finishedPresentationID = presentationID
        self = CodexActivityTrayPresentationVisibility()
        return finishedPresentationID
    }

    var activeExposure: CodexActivityTrayPresentationExposure? {
        guard let presentationID else { return nil }
        return CodexActivityTrayPresentationExposure(
            presentationID: presentationID,
            visibleItemIDs: CodexActivityTrayVisibilityPolicy.visibleItemIDs(
                itemFrames: itemFrames,
                viewportBounds: CGRect(origin: .zero, size: viewportSize)
            )
        )
    }
}

struct CodexActivityTrayExposureDecision: Equatable {
    let completionIDsToRecord: Set<UUID>
    // Kept in the decision shape for callers that already consume it. Read
    // acknowledgement is committed when the tray is dismissed, never while
    // the current presentation is still open.
    let sessionIDsToAcknowledge: Set<String>
    let handledCompletionIDs: Set<UUID>
}

struct CodexActivityTrayExposurePolicy {
    static func decision(
        for visibleItems: [CodexActivityTrayItem],
        previouslyPresentedIDs: Set<UUID>,
        handledCompletionIDs: Set<UUID>
    ) -> CodexActivityTrayExposureDecision {
        let eligibleItems = visibleItems.filter { item in
            guard let completionID = item.completionID else { return false }
            return !handledCompletionIDs.contains(completionID)
        }
        let eligibleCompletionIDs = Set(eligibleItems.compactMap(\.completionID))
        return CodexActivityTrayExposureDecision(
            completionIDsToRecord: eligibleCompletionIDs.subtracting(previouslyPresentedIDs),
            sessionIDsToAcknowledge: [],
            handledCompletionIDs: eligibleCompletionIDs
        )
    }

    static func sessionIDsToAcknowledgeOnDismiss(
        for exposedItems: [CodexActivityTrayItem]
    ) -> Set<String> {
        Set(
            exposedItems.compactMap { item in
                guard item.bucket == .unreadCompleted,
                      item.completionID != nil,
                      !item.sessionID.isEmpty else { return nil }
                return item.sessionID
            }
        )
    }
}

struct CodexActivityTrayReadSession: Equatable, Sendable {
    private(set) var handledCompletionIDs: Set<UUID> = []
    private(set) var exposedSessionIDs: Set<String> = []

    mutating func recordExposure(
        for visibleItems: [CodexActivityTrayItem],
        previouslyPresentedIDs: Set<UUID>
    ) -> CodexActivityTrayExposureDecision {
        let decision = CodexActivityTrayExposurePolicy.decision(
            for: visibleItems,
            previouslyPresentedIDs: previouslyPresentedIDs,
            handledCompletionIDs: handledCompletionIDs
        )
        guard !decision.handledCompletionIDs.isEmpty else { return decision }

        handledCompletionIDs.formUnion(decision.handledCompletionIDs)
        exposedSessionIDs.formUnion(
            CodexActivityTrayExposurePolicy.sessionIDsToAcknowledgeOnDismiss(
                for: visibleItems
            )
        )
        return decision
    }

    mutating func finish() -> Set<String> {
        let sessionIDs = exposedSessionIDs
        handledCompletionIDs.removeAll()
        exposedSessionIDs.removeAll()
        return sessionIDs
    }
}

public struct CodexActivityTrayBuilder: Sendable {
    public init() {}

    public func build(
        from snapshot: CodexTaskStoreSnapshot,
        preferences: CodexActivityTrayPreferences = .init()
    ) -> CodexActivityTrayModel {
        var itemsByBucket: [CodexActivityBucket: [CodexActivityTrayItem]] = [:]
        var currentSessionIDs: Set<String> = []

        for task in snapshot.tasks {
            guard let bucket = bucket(for: task.status) else { continue }
            currentSessionIDs.insert(task.sessionID)
            let item = makeItem(
                for: task,
                bucket: bucket,
                showContentPreviews: preferences.showContentPreviews
            )
            itemsByBucket[bucket, default: []].append(item)
        }

        let acknowledgedCompletionIDs = Set(snapshot.acknowledgedCompletionIDs ?? [])
        let unacknowledgedSessionIDs = Set(
            snapshot.recentCompletions
                .filter { !acknowledgedCompletionIDs.contains($0.id) }
                .map(\.sessionID)
        )
        let recentCompletions = snapshot.latestRecentCompletions(
            excludingSessionIDs: currentSessionIDs
        )
        for completion in recentCompletions {
            let isRead = !unacknowledgedSessionIDs.contains(completion.sessionID)
            let item = makeItem(
                for: completion,
                bucket: isRead ? .readHistory : .unreadCompleted,
                isRead: isRead,
                showContentPreviews: preferences.showContentPreviews
            )
            itemsByBucket[item.bucket, default: []].append(item)
        }

        // Older builds retained completed tasks in `tasks` but pruned the
        // separate completion summaries after ten minutes. Recover those
        // records for display when no newer completion summary exists.
        let recentSessionIDs = Set(recentCompletions.map(\.sessionID))
        let historyCutoff = snapshot.savedAt.addingTimeInterval(-(7 * 24 * 60 * 60))
        for task in snapshot.tasks {
            guard (task.status == .completed || task.status == .ended),
                  let completedAt = task.completedAt,
                  completedAt > historyCutoff,
                  !recentSessionIDs.contains(task.sessionID) else { continue }
            itemsByBucket[.readHistory, default: []].append(
                makeItem(
                    for: task,
                    bucket: .readHistory,
                    isRead: true,
                    showContentPreviews: preferences.showContentPreviews
                )
            )
        }

        let ignoredIDs = preferences.ignoredSessionIDs
        let ignoredItems = itemsByBucket.values
            .flatMap { $0 }
            .filter { ignoredIDs.contains($0.sessionID) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }

        let buckets = CodexActivityBucket.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { bucket -> CodexActivityTrayBucketGroup? in
                let items = itemsByBucket[bucket, default: []]
                    .filter { !ignoredIDs.contains($0.sessionID) }
                    .sorted { $0.lastActivityAt > $1.lastActivityAt }
                guard !items.isEmpty else { return nil }
                return CodexActivityTrayBucketGroup(
                    bucket: bucket,
                    groups: projectGroups(
                        from: items,
                        preferences: preferences
                    )
                )
            }

        return CodexActivityTrayModel(buckets: buckets, ignoredItems: ignoredItems)
    }

    private func bucket(for status: CodexTaskStatus) -> CodexActivityBucket? {
        switch status {
        case .waitingForApproval:
            return .needsAttention
        case .failedOrInterrupted, .stale:
            return .blocked
        case .running:
            return .running
        case .registered, .completed, .ended:
            return nil
        }
    }

    private func projectGroups(
        from items: [CodexActivityTrayItem],
        preferences: CodexActivityTrayPreferences
    ) -> [CodexActivityTrayProjectGroup] {
        let grouped = Dictionary(grouping: items, by: \.projectName)
        return grouped
            .map { projectName, projectItems in
                CodexActivityTrayProjectGroup(
                    projectName: projectName,
                    items: projectItems.sorted { $0.lastActivityAt > $1.lastActivityAt },
                    isPinned: preferences.pinnedProjectNames.contains(projectName),
                    isCollapsed: false
                )
            }
            .sorted { lhs, rhs in
                if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                let leftDate = lhs.items.map(\.lastActivityAt).max() ?? .distantPast
                let rightDate = rhs.items.map(\.lastActivityAt).max() ?? .distantPast
                if leftDate != rightDate { return leftDate > rightDate }
                return lhs.projectName.localizedStandardCompare(rhs.projectName) == .orderedAscending
            }
    }

    private func makeItem(
        for task: CodexTaskRecord,
        bucket: CodexActivityBucket,
        isRead: Bool = false,
        showContentPreviews: Bool
    ) -> CodexActivityTrayItem {
        let title = showContentPreviews
            ? PreviewSanitizer.sanitizePrompt(task.promptPreview ?? task.approvalPreview, maxLength: 36)
            ?? PreviewSanitizer.sanitize(task.projectName, maxLength: 36)
            ?? "Codex 会话"
            : PreviewSanitizer.sanitize(task.projectName, maxLength: 36) ?? "Codex 会话"
        let detail: String
        let nextAction: String
        let statusText: String

        switch bucket {
        case .needsAttention:
            detail = showContentPreviews
                ? PreviewSanitizer.sanitize(task.approvalPreview ?? task.toolName, maxLength: 72)
                    ?? "需要你的决定"
                : "需要你的决定"
            nextAction = "打开 Codex 处理"
            statusText = durationStatus(for: task, label: "等待批准")
        case .blocked:
            detail = task.status == .stale ? "长时间没有收到新的 Hook 事件" : "任务已中断"
            nextAction = "检查会话"
            statusText = task.status == .stale ? "可能失联" : "已中断"
        case .running:
            detail = showContentPreviews
                ? PreviewSanitizer.sanitize(task.toolName, maxLength: 72) ?? "Codex 正在执行"
                : "Codex 正在执行"
            nextAction = "继续等待"
            statusText = durationStatus(for: task, label: "运行中")
        case .unreadCompleted, .readHistory:
            detail = showContentPreviews
                ? PreviewSanitizer.sanitize(task.resultPreview, maxLength: 72) ?? "任务已完成"
                : "任务已完成"
            nextAction = "查看完成结果"
            statusText = "已完成"
        }

        return CodexActivityTrayItem(
            id: task.sessionID,
            sessionID: task.sessionID,
            projectName: task.projectName,
            title: title,
            statusText: statusText,
            detailText: detail,
            nextAction: nextAction,
            bucket: bucket,
            lastActivityAt: task.completedAt ?? task.lastActivityAt,
            completedAt: task.completedAt,
            isRead: isRead || bucket == .readHistory
        )
    }

    private func makeItem(
        for completion: CodexCompletionRecord,
        bucket: CodexActivityBucket,
        isRead: Bool,
        showContentPreviews: Bool
    ) -> CodexActivityTrayItem {
        let title = showContentPreviews
            ? PreviewSanitizer.sanitizePrompt(completion.promptPreview, maxLength: 36)
            ?? PreviewSanitizer.sanitize(completion.projectName, maxLength: 36)
            ?? "Codex 会话"
            : PreviewSanitizer.sanitize(completion.projectName, maxLength: 36) ?? "Codex 会话"
        let detail = showContentPreviews
            ? PreviewSanitizer.sanitize(completion.resultPreview, maxLength: 72) ?? "任务已完成"
            : "任务已完成"
        return CodexActivityTrayItem(
            id: "completion-\(completion.id.uuidString)",
            sessionID: completion.sessionID,
            projectName: completion.projectName,
            title: title,
            statusText: "已完成",
            detailText: detail,
            nextAction: "查看完成结果",
            bucket: bucket,
            lastActivityAt: completion.completedAt,
            completedAt: completion.completedAt,
            completionID: completion.id,
            isRead: isRead
        )
    }

    private func durationStatus(for task: CodexTaskRecord, label: String) -> String {
        guard let startedAt = task.startedAt else { return label }
        let total = max(0, Int(task.lastActivityAt.timeIntervalSince(startedAt)))
        return String(format: "%@ · %02d:%02d", label, total / 60, total % 60)
    }
}
