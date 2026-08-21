import AtollExtensionKit
import CoreGraphics
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
    context: CodexPresentationContext = .steady
  ) -> CodexPresentation {
    let active = snapshot.tasks.filter {
      $0.status == .running || $0.status == .waitingForApproval
    }
    let waiting = active.filter { $0.status == .waitingForApproval }
    let running = active.filter { $0.status == .running }
    let recent = snapshot.recentCompletions.sorted { $0.completedAt > $1.completedAt }
    let currentLines = compactStatusLines(
      waitingCount: waiting.count,
      runningCount: running.count,
      completedCount: recent.count
    )
    let previousLines: [CompactStatusLine]? = {
      guard case .completionPulse = context else { return nil }
      return compactStatusLines(
        waitingCount: waiting.count,
        runningCount: running.count + context.completedCount,
        completedCount: max(0, recent.count - context.completedCount)
      )
    }()
    let trailingContent = compactTrailingContent(
      currentLines: currentLines,
      previousLines: previousLines,
      animated: context != .steady
    )
    let pulseCompletion =
      context.sessionID.flatMap { sessionID in
        recent.first { $0.sessionID == sessionID }
      } ?? (context == .steady ? nil : recent.first)
    let statusMetadata = [
      "codex_waiting_count": String(waiting.count),
      "codex_running_count": String(running.count),
      "codex_completed_count": String(recent.count),
      "codex_status_layout": currentLines.count > 1 ? "stacked" : "single",
      "codex_presentation_phase": context.phaseName,
    ]

    let live: AtollLiveActivityDescriptor?
    switch (waiting.isEmpty, running.isEmpty, recent.first) {
    case (false, _, _):
      let first = waiting.first
      live = makeLive(
        title: "Codex 等待批准",
        subtitle: statusSummary(
          waitingCount: waiting.count, runningCount: running.count, completedCount: recent.count),
        icon: .symbol(name: "exclamationmark.triangle.fill"),
        color: .orange,
        trailingContent: trailingContent,
        sneakTitle: pulseCompletion?.projectName ?? first?.projectName,
        sneakSubtitle: pulseCompletion?.resultPreview ?? first?.approvalPreview ?? "需要用户批准",
        metadata: statusMetadata,
        triggersSneakPeekOnUpdate: context != .steady
      )
    case (true, false, _):
      let isCompletionPulse = context != .steady
      live = makeLive(
        title: "Codex",
        subtitle: statusSummary(
          waitingCount: 0, runningCount: running.count, completedCount: recent.count),
        icon: .symbol(name: isCompletionPulse ? "checkmark.circle.fill" : "terminal.fill"),
        color: isCompletionPulse ? .green : .blue,
        trailingContent: trailingContent,
        sneakTitle: pulseCompletion?.projectName ?? running.first?.projectName,
        sneakSubtitle: pulseCompletion?.resultPreview ?? running.first?.promptPreview,
        metadata: statusMetadata,
        triggersSneakPeekOnUpdate: isCompletionPulse
      )
    case (true, true, let completion?):
      live = makeLive(
        title: completion.projectName,
        subtitle: "最近 10 分钟完成 \(recent.count) 个任务",
        icon: .symbol(name: "checkmark.circle.fill"),
        color: .green,
        trailingContent: trailingContent,
        sneakTitle: pulseCompletion?.projectName ?? completion.projectName,
        sneakSubtitle: pulseCompletion?.resultPreview ?? completion.resultPreview,
        metadata: statusMetadata,
        triggersSneakPeekOnUpdate: context != .steady
      )
    default:
      live = nil
    }

    let sections = makeSections(waiting: waiting, running: running, recent: recent)
    var metadata = [
      CodexPresentationConstants.targetExperienceMetadataKey: CodexPresentationConstants.experienceID,
      "tab_id": CodexPresentationConstants.tabID,
    ]
    metadata.merge(
      makeCodexThreadActionMetadata(waiting: waiting, running: running, recent: recent)
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
    triggersSneakPeekOnUpdate: Bool
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
        duration: 3.5,
        showOnUpdate: triggersSneakPeekOnUpdate
      ),
      sneakPeekTitle: sneakTitle ?? title,
      sneakPeekSubtitle: sneakSubtitle ?? subtitle
    )
  }

  private func compactTrailingContent(
    currentLines: [CompactStatusLine],
    previousLines: [CompactStatusLine]?,
    animated: Bool
  ) -> AtollTrailingContent {
    guard let first = currentLines.first else { return .none }
    if currentLines.count == 1, !animated {
      return .text(
        first.text,
        font: .system(size: 11, weight: .semibold),
        color: first.atollColor
      )
    }
    return .animation(
      data: CompactStatusAnimation.make(
        currentLines: currentLines,
        previousLines: animated ? previousLines : nil
      ),
      size: CGSize(width: 104, height: 34)
    )
  }

  private func compactStatusLines(
    waitingCount: Int,
    runningCount: Int,
    completedCount: Int
  ) -> [CompactStatusLine] {
    if waitingCount > 0 {
      var lines = [CompactStatusLine(text: "\(waitingCount) 个等待批准", color: .orange)]
      let secondary: CompactStatusLine?
      switch (runningCount > 0, completedCount > 0) {
      case (true, true):
        secondary = CompactStatusLine(
          text: "\(runningCount) 进行中 · \(completedCount) 已完成", color: .blue)
      case (true, false):
        secondary = CompactStatusLine(text: "\(runningCount) 个进行中", color: .blue)
      case (false, true):
        secondary = CompactStatusLine(text: "\(completedCount) 个已完成", color: .green)
      default:
        secondary = nil
      }
      if let secondary { lines.append(secondary) }
      return lines
    }
    if runningCount > 0 {
      var lines = [CompactStatusLine(text: "\(runningCount) 个进行中", color: .blue)]
      if completedCount > 0 {
        lines.append(CompactStatusLine(text: "\(completedCount) 个已完成", color: .green))
      }
      return lines
    }
    if completedCount > 0 {
      return [CompactStatusLine(text: "\(completedCount) 个已完成", color: .green)]
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

  private func makeSections(
    waiting: [CodexTaskRecord],
    running: [CodexTaskRecord],
    recent: [CodexCompletionRecord]
  ) -> [AtollNotchContentSection] {
    var sections: [AtollNotchContentSection] = []
    if !waiting.isEmpty {
      sections.append(makeTaskSection(id: "waiting", title: "等待批准", tasks: waiting, status: "等待批准"))
    }
    if !running.isEmpty {
      sections.append(makeTaskSection(id: "running", title: "进行中", tasks: running, status: "运行中"))
    }
    if !recent.isEmpty {
      let elements = recent.prefix(CodexPresentationConstants.visibleRecentConversationLimit).map {
        completion in
        text("✓ \(completion.projectName) — \(completion.resultPreview ?? "已完成")")
      }
      sections.append(
        AtollNotchContentSection(
          id: "recent",
          title: "最近 10 分钟完成",
          layout: .stack,
          elements: elements
        )
      )
    }
    if sections.isEmpty {
      sections.append(
        AtollNotchContentSection(
          id: "empty-state",
          title: "暂无 Codex 任务",
          layout: .stack,
          elements: [text("新任务开始后会自动显示在这里")]
        )
      )
    }
    return sections
  }

  private func makeTaskSection(
    id: String,
    title: String,
    tasks: [CodexTaskRecord],
    status: String
  ) -> AtollNotchContentSection {
    var elements: [AtollWidgetContentElement] = []
    for task in tasks.prefix(5) {
      let preview = task.promptPreview ?? task.approvalPreview ?? "Codex 会话"
      elements.append(
        text("● \(task.projectName) — \(preview) · \(statusLine(task: task, status: status))"))
    }
    if tasks.count > 5 {
      elements.append(text("还有 \(tasks.count - 5) 个任务…"))
    }
    return AtollNotchContentSection(id: id, title: title, elements: elements)
  }

  private func makeCodexThreadActionMetadata(
    waiting: [CodexTaskRecord],
    running: [CodexTaskRecord],
    recent: [CodexCompletionRecord]
  ) -> [String: String] {
    var metadata: [String: String] = [:]

    for (index, task) in waiting.prefix(5).enumerated() {
      addActionMetadata(
        for: "waiting",
        elementIndex: index,
        sessionID: task.sessionID,
        to: &metadata
      )
    }
    for (index, task) in running.prefix(5).enumerated() {
      addActionMetadata(
        for: "running",
        elementIndex: index,
        sessionID: task.sessionID,
        to: &metadata
      )
    }
    for (index, completion) in recent.prefix(CodexPresentationConstants.visibleRecentConversationLimit).enumerated() {
      addActionMetadata(
        for: "recent",
        elementIndex: index,
        sessionID: completion.sessionID,
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

}

private struct CompactStatusLine: Equatable, Sendable {
  let text: String
  let color: CompactStatusColor

  var atollColor: AtollColorDescriptor {
    switch color {
    case .blue: return .blue
    case .green: return .green
    case .orange: return .orange
    }
  }
}

private enum CompactStatusColor: Equatable, Sendable {
  case blue
  case green
  case orange

  var lottieRGB: [Double] {
    switch self {
    case .blue: return [0.22, 0.56, 1.0]
    case .green: return [0.24, 0.82, 0.43]
    case .orange: return [1.0, 0.60, 0.16]
    }
  }
}

private enum CompactStatusAnimation {
  private static let width = 104.0
  private static let height = 34.0
  private static let framesPerSecond = 30.0
  private static let outputFrame = 300.0

  static func make(
    currentLines: [CompactStatusLine],
    previousLines: [CompactStatusLine]?
  ) -> Data {
    var layers: [[String: Any]] = []
    var layerIndex = 1

    if let previousLines {
      for (index, line) in previousLines.enumerated() {
        layers.append(
          textLayer(
            line,
            name: "Previous status \(index)",
            index: layerIndex,
            startY: lineY(lineCount: previousLines.count, index: index),
            endY: lineY(lineCount: previousLines.count, index: index),
            appearance: .disappearing
          )
        )
        layerIndex += 1
      }
    }

    for (index, line) in currentLines.enumerated() {
      let targetY = lineY(lineCount: currentLines.count, index: index)
      let sourceY: Double
      if let previousLines, previousLines.indices.contains(index) {
        sourceY = lineY(lineCount: previousLines.count, index: index)
      } else {
        sourceY = targetY + 4
      }
      layers.append(
        textLayer(
          line,
          name: "Current status \(index)",
          index: layerIndex,
          startY: sourceY,
          endY: targetY,
          appearance: previousLines == nil ? .static : .appearing
        )
      )
      layerIndex += 1
    }

    let object: [String: Any] = [
      "v": "5.10.0",
      "fr": framesPerSecond,
      "ip": 0,
      "op": outputFrame,
      "w": width,
      "h": height,
      "nm": "Atoll Codex compact stacked status",
      "ddd": 0,
      "assets": [],
      "fonts": [
        "list": [
          [
            "fName": "PingFangSC-Semibold",
            "fFamily": "PingFang SC",
            "fStyle": "Semibold",
            "ascent": 75,
          ]
        ]
      ],
      "layers": layers,
      "meta": [
        "codex_status_lines": currentLines.map(\.text),
        "codex_previous_status_lines": previousLines?.map(\.text) ?? [],
      ],
    ]

    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
  }

  private enum Appearance {
    case `static`
    case appearing
    case disappearing
  }

  private static func textLayer(
    _ line: CompactStatusLine,
    name: String,
    index: Int,
    startY: Double,
    endY: Double,
    appearance: Appearance
  ) -> [String: Any] {
    let fontSize = line.text.count > 13 ? 8.5 : 10.0
    return [
      "ddd": 0,
      "ind": index,
      "ty": 5,
      "nm": name,
      "sr": 1,
      "ks": [
        "o": opacityProperty(for: appearance),
        "r": ["a": 0, "k": 0],
        "p": positionProperty(startY: startY, endY: endY, animated: appearance == .appearing),
        "a": ["a": 0, "k": [0, 0, 0]],
        "s": ["a": 0, "k": [100, 100, 100]],
      ],
      "ao": 0,
      "t": [
        "d": [
          "k": [
            [
              "s": [
                "s": fontSize,
                "f": "PingFangSC-Semibold",
                "t": line.text,
                "j": 0,
                "tr": 0,
                "lh": 12,
                "ls": 0,
                "fc": line.color.lottieRGB,
              ],
              "t": 0,
            ]
          ]
        ],
        "p": [:],
        "m": ["g": 1, "a": ["a": 0, "k": [0, 0]]],
      ],
      "ip": 0,
      "op": outputFrame,
      "st": 0,
      "bm": 0,
    ]
  }

  private static func opacityProperty(for appearance: Appearance) -> [String: Any] {
    switch appearance {
    case .static:
      return ["a": 0, "k": 100]
    case .appearing:
      return [
        "a": 1,
        "k": [
          keyframe(time: 0, start: [0], end: [0]),
          keyframe(time: 5, start: [0], end: [100]),
          ["t": 14, "s": [100]],
        ],
      ]
    case .disappearing:
      return [
        "a": 1,
        "k": [
          keyframe(time: 0, start: [100], end: [0]),
          ["t": 8, "s": [0]],
        ],
      ]
    }
  }

  private static func positionProperty(startY: Double, endY: Double, animated: Bool) -> [String:
    Any]
  {
    guard animated else { return ["a": 0, "k": [2, endY, 0]] }
    return [
      "a": 1,
      "k": [
        keyframe(time: 0, start: [2, startY, 0], end: [2, endY, 0]),
        ["t": 14, "s": [2, endY, 0]],
      ],
    ]
  }

  private static func keyframe(time: Double, start: [Double], end: [Double]) -> [String: Any] {
    [
      "i": ["x": 0.67, "y": 1.0],
      "o": ["x": 0.33, "y": 0.0],
      "t": time,
      "s": start,
      "e": end,
    ]
  }

  private static func lineY(lineCount: Int, index: Int) -> Double {
    guard lineCount > 1 else { return 20 }
    return index == 0 ? 12 : 27
  }
}
