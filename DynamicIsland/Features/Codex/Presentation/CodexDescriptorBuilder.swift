import AtollExtensionKit
import Foundation

public struct CodexPresentation: Equatable, Sendable {
  public let liveActivity: AtollLiveActivityDescriptor?
  public let notchExperience: AtollNotchExperienceDescriptor?

  public init(
    liveActivity: AtollLiveActivityDescriptor?,
    notchExperience: AtollNotchExperienceDescriptor?
  ) {
    self.liveActivity = liveActivity
    self.notchExperience = notchExperience
  }
}

public enum CodexPresentationContext: Equatable, Sendable {
  case steady
  case completionPulse(sessionID: String, completedCount: Int)

  fileprivate var phaseName: String {
    switch self {
    case .steady:
      return "steady"
    case .completionPulse:
      return "completion-pulse"
    }
  }

  fileprivate var completedCount: Int {
    switch self {
    case .steady:
      return 0
    case .completionPulse(_, let completedCount):
      return max(1, completedCount)
    }
  }

  fileprivate var sessionID: String? {
    switch self {
    case .steady:
      return nil
    case .completionPulse(let sessionID, _):
      return sessionID
    }
  }
}

public struct CodexPresentationBuilder: Sendable {
  public let bundleIdentifier: String

  public nonisolated init(bundleIdentifier: String = CodexPresentationConstants.defaultBundleIdentifier) {
    self.bundleIdentifier = bundleIdentifier
  }

  public func build(
    from snapshot: CodexTaskStoreSnapshot,
    context: CodexPresentationContext = .steady,
    ignoredSessionIDs: Set<String> = []
  ) -> CodexPresentation {
    let active = snapshot.tasks.filter {
      !ignoredSessionIDs.contains($0.sessionID)
        && ($0.status == .running || $0.status == .waitingForApproval)
    }
    let waiting = active.filter { $0.status == .waitingForApproval }
    let running = active.filter { $0.status == .running }
    let recent = snapshot.recentCompletions
      .filter { !ignoredSessionIDs.contains($0.sessionID) }
      .sorted { $0.completedAt > $1.completedAt }
    let unacknowledged = snapshot.unacknowledgedCompletions
      .filter { !ignoredSessionIDs.contains($0.sessionID) }
      .sorted {
      $0.completedAt > $1.completedAt
      }
    let compactStatus = CodexCompactStatus(
      lines: compactStatusLines(
        waiting: waiting,
        running: running,
        completions: unacknowledged
      )
    )
    let trailingContent = compactTrailingContent(status: compactStatus)
    let pulseCompletion =
      context.sessionID.flatMap { sessionID in
        unacknowledged.first { $0.sessionID == sessionID }
      } ?? (context == .steady ? nil : unacknowledged.first)
    var statusMetadata = [
      "codex_waiting_count": String(waiting.count),
      "codex_running_count": String(running.count),
      "codex_completed_count": String(unacknowledged.count),
      "codex_status_layout": "single",
      "codex_presentation_phase": context.phaseName,
    ]
    statusMetadata.merge(compactStatus.metadata) { _, new in new }

    let live: AtollLiveActivityDescriptor?
    switch (waiting.isEmpty, running.isEmpty, unacknowledged.first) {
    case (false, _, _):
      let first = waiting.first
      live = makeLive(
        title: "Codex 等待批准",
        subtitle: statusSummary(
          waitingCount: waiting.count,
          runningCount: running.count,
          completedCount: unacknowledged.count
        ),
        icon: .symbol(name: "exclamationmark.triangle.fill"),
        color: .orange,
        trailingContent: trailingContent,
        sneakTitle: pulseCompletion?.projectName ?? first?.projectName,
        sneakSubtitle: pulseCompletion?.resultPreview ?? first?.approvalPreview ?? "需要用户批准",
        metadata: statusMetadata,
        triggersSneakPeekOnUpdate: context != .steady,
        context: context
      )
    case (true, false, _):
      let isCompletionPulse = context != .steady
      live = makeLive(
        title: "Codex",
        subtitle: statusSummary(
          waitingCount: 0,
          runningCount: running.count,
          completedCount: unacknowledged.count
        ),
        icon: .symbol(name: isCompletionPulse ? "checkmark.circle.fill" : "terminal.fill"),
        color: isCompletionPulse ? .green : .blue,
        trailingContent: trailingContent,
        sneakTitle: pulseCompletion?.projectName ?? running.first?.projectName,
        sneakSubtitle: pulseCompletion?.resultPreview ?? running.first?.promptPreview,
        metadata: statusMetadata,
        triggersSneakPeekOnUpdate: isCompletionPulse,
        context: context
      )
    case (true, true, let completion?):
      live = makeLive(
        title: completion.projectName,
        subtitle: "最近 10 分钟完成 \(unacknowledged.count) 个任务",
        icon: .symbol(name: "checkmark.circle.fill"),
        color: .green,
        trailingContent: trailingContent,
        sneakTitle: pulseCompletion?.projectName ?? completion.projectName,
        sneakSubtitle: pulseCompletion?.resultPreview ?? completion.resultPreview,
        metadata: statusMetadata,
        triggersSneakPeekOnUpdate: context != .steady,
        context: context
      )
    default:
      live = nil
    }

    let conversationItems = makeConversationItems(
      waiting: waiting,
      running: running,
      recent: recent
    )
    let sections = makeSections(from: conversationItems)
    var metadata = [
      CodexPresentationConstants.targetExperienceMetadataKey: CodexPresentationConstants.experienceID,
      "tab_id": CodexPresentationConstants.tabID,
    ]
    metadata.merge(
      makeCodexThreadActionMetadata(from: conversationItems)
    ) { _, new in new }
    let tab = AtollNotchExperienceDescriptor.TabConfiguration(
      title: "Codex",
      iconSymbolName: "terminal.fill",
      preferredHeight: CodexPresentationConstants.expandedTabPreferredHeight,
      sections: sections
    )
    let notch = AtollNotchExperienceDescriptor(
      id: CodexPresentationConstants.experienceID,
      bundleIdentifier: bundleIdentifier,
      accentColor: .blue,
      metadata: metadata,
      tab: tab
    )
    return CodexPresentation(liveActivity: live, notchExperience: notch)
  }

  private func makeLive(
    title: String,
    subtitle: String?,
    icon: AtollIconDescriptor,
    color: AtollColorDescriptor,
    trailingContent: AtollTrailingContent,
    sneakTitle: String?,
    sneakSubtitle: String?,
    metadata: [String: String],
    triggersSneakPeekOnUpdate: Bool,
    context: CodexPresentationContext
  ) -> AtollLiveActivityDescriptor {
    var liveMetadata = metadata
    liveMetadata[CodexPresentationConstants.targetExperienceMetadataKey] = CodexPresentationConstants.experienceID
    return AtollLiveActivityDescriptor(
      id: CodexPresentationConstants.liveActivityID,
      bundleIdentifier: bundleIdentifier,
      title: title,
      subtitle: subtitle,
      leadingIcon: icon,
      trailingContent: trailingContent,
      accentColor: color,
      allowsMusicCoexistence: true,
      metadata: liveMetadata,
      centerTextStyle: .inheritUser,
      sneakPeekConfig: AtollSneakPeekConfig(
        enabled: true,
        duration: context == .steady
          ? CodexPresentationConstants.runningSneakPeekDuration
          : CodexPresentationConstants.completionPulseDuration,
        style: .standard,
        showOnUpdate: triggersSneakPeekOnUpdate
      ),
      sneakPeekTitle: sneakTitle ?? title,
      sneakPeekSubtitle: sneakSubtitle ?? subtitle
    )
  }

  private func compactTrailingContent(status: CodexCompactStatus) -> AtollTrailingContent {
    guard let first = status.lines.first else { return .none }
    return .text(
      status.fallbackText,
      font: .system(size: 12, weight: .semibold),
      color: first.atollColor
    )
  }

  private func compactStatusLines(
    waiting: [CodexTaskRecord],
    running: [CodexTaskRecord],
    completions: [CodexCompletionRecord]
  ) -> [CodexCompactStatusLine] {
    if !completions.isEmpty {
      return [
        CodexCompactStatusLine(
          label: "\(completions.count) · 已完成",
          detail: nil,
          tone: .green
        )
      ]
    }
    if !waiting.isEmpty {
      return [
        CodexCompactStatusLine(
          label: "\(waiting.count) · 等待批准",
          detail: nil,
          tone: .orange
        )
      ]
    }
    if !running.isEmpty {
      return [
        CodexCompactStatusLine(
          label: "\(running.count) · 进行中",
          detail: nil,
          tone: .blue
        )
      ]
    }
    return []
  }

  private func statusSummary(waitingCount: Int, runningCount: Int, completedCount: Int) -> String {
    var parts: [String] = []
    if waitingCount > 0 { parts.append("\(waitingCount) 个等待批准") }
    if runningCount > 0 { parts.append("\(runningCount) 个任务进行中") }
    if completedCount > 0 { parts.append("最近完成 \(completedCount) 个") }
    return parts.joined(separator: " · ")
  }

  private func makeConversationItems(
    waiting: [CodexTaskRecord],
    running: [CodexTaskRecord],
    recent: [CodexCompletionRecord]
  ) -> [CodexConversationPresentationItem] {
    var items: [CodexConversationPresentationItem] = []

    for (index, task) in waiting.enumerated() {
      let title = conversationTitle(
        from: task.promptPreview ?? task.approvalPreview,
        fallback: task.projectName
      )
      items.append(
        CodexConversationPresentationItem(
          sectionID: "waiting-\(index)",
          sessionID: task.sessionID,
          title: title,
          status: statusLine(task: task, status: "等待批准"),
          content: conversationContent(
            preferred: task.approvalPreview,
            title: title,
            projectName: task.projectName,
            fallback: "需要用户批准"
          )
        )
      )
    }

    for (index, task) in running.enumerated() {
      let title = conversationTitle(from: task.promptPreview, fallback: task.projectName)
      items.append(
        CodexConversationPresentationItem(
          sectionID: "running-\(index)",
          sessionID: task.sessionID,
          title: title,
          status: statusLine(task: task, status: "运行中"),
          content: conversationContent(
            preferred: nil,
            title: title,
            projectName: task.projectName,
            fallback: "Codex 会话"
          )
        )
      )
    }

    for (index, completion) in recent.enumerated() {
      let title = conversationTitle(from: completion.promptPreview, fallback: completion.projectName)
      items.append(
        CodexConversationPresentationItem(
          sectionID: "recent-\(index)",
          sessionID: completion.sessionID,
          title: title,
          status: "已完成",
          content: conversationContent(
            preferred: completion.resultPreview,
            title: title,
            projectName: completion.projectName,
            fallback: "Codex 会话已完成"
          )
        )
      )
    }

    return Array(items.prefix(CodexPresentationConstants.visibleConversationLimit))
  }

  private func makeSections(
    from items: [CodexConversationPresentationItem]
  ) -> [AtollNotchContentSection] {
    guard !items.isEmpty else {
      return [
        AtollNotchContentSection(
          id: "empty-state",
          title: "暂无 Codex 任务",
          layout: .stack,
          elements: [text("新任务开始后会自动显示在这里")]
        )
      ]
    }

    return items.map { item in
      AtollNotchContentSection(
        id: item.sectionID,
        title: item.title,
        subtitle: item.status,
        layout: .stack,
        elements: [text(item.content)]
      )
    }
  }

  private func makeCodexThreadActionMetadata(
    from items: [CodexConversationPresentationItem]
  ) -> [String: String] {
    var metadata: [String: String] = [:]
    for item in items {
      addActionMetadata(
        for: item.sectionID,
        elementIndex: 0,
        sessionID: item.sessionID,
        to: &metadata
      )
    }
    return metadata
  }

  private func addActionMetadata(
    for sectionID: String,
    elementIndex: Int,
    sessionID: String,
    to metadata: inout [String: String]
  ) {
    guard let url = CodexAppLink.url(forSessionID: sessionID) else { return }
    metadata["\(CodexPresentationConstants.openCodexThreadMetadataPrefix)\(sectionID).\(elementIndex)"] =
      url.absoluteString
  }

  private func statusLine(task: CodexTaskRecord, status: String) -> String {
    let duration = task.startedAt.map { formatDuration(from: $0, to: task.lastActivityAt) }
    return duration.map { "\(status) · \($0)" } ?? status
  }

  private func formatDuration(from start: Date, to end: Date) -> String {
    let total = max(0, Int(end.timeIntervalSince(start)))
    return String(format: "%02d:%02d", total / 60, total % 60)
  }

  private func text(_ value: String) -> AtollWidgetContentElement {
    .text(value, font: .system(size: 12, weight: .regular), color: .white)
  }

  private func conversationTitle(from preview: String?, fallback: String) -> String {
    PreviewSanitizer.sanitizePrompt(preview, maxLength: 24)
      ?? PreviewSanitizer.sanitize(fallback, maxLength: 24)
      ?? "Codex 会话"
  }

  private func conversationContent(
    preferred: String?,
    title: String,
    projectName: String,
    fallback: String
  ) -> String {
    if let preferred = PreviewSanitizer.sanitize(preferred), preferred != title {
      return preferred
    }
    if let projectName = PreviewSanitizer.sanitize(projectName), projectName != title {
      return projectName
    }
    return fallback
  }

}

private struct CodexConversationPresentationItem: Equatable, Sendable {
  let sectionID: String
  let sessionID: String
  let title: String
  let status: String
  let content: String
}

enum CodexConversationVisualState: Equatable, Sendable {
  case waitingForApproval
  case running
  case completed

  init?(sectionID: String?) {
    guard let sectionID else { return nil }
    if sectionID.hasPrefix("waiting-") {
      self = .waitingForApproval
    } else if sectionID.hasPrefix("running-") {
      self = .running
    } else if sectionID.hasPrefix("recent-") {
      self = .completed
    } else {
      return nil
    }
  }
}

struct CodexCompactStatus: Equatable, Sendable {
  static let lineCountMetadataKey = "codex_compact_line_count"
  static let lineMetadataPrefix = "codex_compact_line_"
  static let compactTrailingWidth: CGFloat = 84
  static let additionalHeightPerRow: CGFloat = 16

  let lines: [CodexCompactStatusLine]

  init(lines: [CodexCompactStatusLine]) {
    self.lines = lines
  }

  init?(metadata: [String: String]) {
    guard let countValue = metadata[Self.lineCountMetadataKey],
          let count = Int(countValue),
          count > 0 else {
      return nil
    }
    let decoded = (0..<count).compactMap { index -> CodexCompactStatusLine? in
      let prefix = "\(Self.lineMetadataPrefix)\(index)_"
      guard let label = metadata["\(prefix)label"],
            let toneValue = metadata["\(prefix)tone"],
            let tone = CodexCompactStatusTone(rawValue: toneValue) else {
        return nil
      }
      return CodexCompactStatusLine(
        label: label,
        detail: metadata["\(prefix)detail"],
        tone: tone
      )
    }
    guard decoded.count == count else { return nil }
    lines = decoded
  }

  var fallbackText: String {
    lines.map(\.displayText).joined(separator: "  ")
  }

  var preferredTrailingWidth: CGFloat {
    Self.compactTrailingWidth
  }

  var additionalClosedHeight: CGFloat {
    CGFloat(max(0, lines.count - 1)) * Self.additionalHeightPerRow
  }

  var metadata: [String: String] {
    var values = [Self.lineCountMetadataKey: String(lines.count)]
    for (index, line) in lines.enumerated() {
      let prefix = "\(Self.lineMetadataPrefix)\(index)_"
      values["\(prefix)label"] = line.label
      values["\(prefix)tone"] = line.tone.rawValue
      if let detail = line.detail {
        values["\(prefix)detail"] = detail
      }
    }
    return values
  }
}

struct CodexCompactStatusLine: Equatable, Sendable {
  let label: String
  let detail: String?
  let tone: CodexCompactStatusTone

  var displayText: String {
    guard let detail, !detail.isEmpty else { return label }
    return "\(label) · \(detail)"
  }

  var atollColor: AtollColorDescriptor {
    switch tone {
    case .blue: return .blue
    case .green: return .green
    case .orange: return .orange
    }
  }
}

enum CodexCompactStatusTone: String, Equatable, Sendable {
  case blue
  case green
  case orange
}
