import Foundation

public enum CodexStateEffect: Equatable, Sendable {
  case persist
  case refreshPresentation
  case showCompletion(sessionID: String)
  case log(String)
}

public struct CodexEventReducer: Sendable {
  public init() {}

  public func reduce(
    state: inout CodexTaskStoreSnapshot,
    envelope: CodexHookEnvelope,
    preferences: AppPreferences
  ) -> [CodexStateEffect] {
    guard !state.processedEventIDs.contains(envelope.eventID) else { return [] }
    state.processedEventIDs.append(envelope.eventID)
    if state.processedEventIDs.count > 256 {
      state.processedEventIDs.removeFirst(state.processedEventIDs.count - 256)
    }

    let event = envelope.payload
    let now = envelope.receivedAt
    var task =
      state.tasks.first(where: { $0.sessionID == event.sessionID })
      ?? CodexTaskRecord(
        sessionID: event.sessionID,
        cwd: event.cwd,
        projectName: projectName(from: event.cwd),
        lastActivityAt: now,
        model: event.model
      )

    if let currentTurnID = task.currentTurnID,
      let eventTurnID = event.turnID,
      currentTurnID != eventTurnID,
      event.hookEventName != "UserPromptSubmit"
    {
      return [.persist]
    }
    if event.hookEventName != "UserPromptSubmit", now < task.lastActivityAt {
      return [.persist]
    }

    var effects: [CodexStateEffect] = [.persist]
    switch event.hookEventName {
    case "SessionStart":
      task.cwd = event.cwd ?? task.cwd
      task.projectName = projectName(from: task.cwd)
      task.model = event.model ?? task.model
      task.status = task.status == .ended ? .registered : task.status
      task.lastActivityAt = max(task.lastActivityAt, now)
      if event.source == "resume" {
        _ = acknowledgeCompletionIDs(sessionID: event.sessionID, state: &state, now: now)
      }

    case "UserPromptSubmit":
      _ = acknowledgeCompletionIDs(sessionID: event.sessionID, state: &state, now: now)
      if task.status == .running || task.status == .waitingForApproval {
        task.status = .failedOrInterrupted
      }
      task.currentTurnID = event.turnID
      task.cwd = event.cwd ?? task.cwd
      task.projectName = projectName(from: task.cwd)
      task.promptPreview =
        preferences.previewMode == .projectOnly ? nil : PreviewSanitizer.sanitizePrompt(event.prompt)
      task.resultPreview = nil
      task.approvalPreview = nil
      task.toolName = nil
      task.status = .running
      task.startedAt = now
      task.completedAt = nil
      task.endedAt = nil
      task.lastActivityAt = now
      task.model = event.model ?? task.model

    case "PermissionRequest":
      task.status = .waitingForApproval
      task.toolName = event.toolName
      task.approvalPreview =
        preferences.previewMode == .projectOnly
        ? nil
        : PreviewSanitizer.sanitize(permissionDescription(event), maxLength: 60)
      task.lastActivityAt = now

    case "PostToolUse":
      if task.status == .waitingForApproval {
        task.status = .running
        task.approvalPreview = nil
      }
      task.toolName = event.toolName ?? task.toolName
      task.lastActivityAt = now

    case "Stop":
      task.status = .completed
      task.resultPreview =
        preferences.previewMode == .projectOnly
        ? nil
        : PreviewSanitizer.sanitize(event.lastAssistantMessage)
      task.completedAt = now
      task.lastActivityAt = now
      state.recentCompletions.append(
        CodexCompletionRecord(
          sessionID: task.sessionID,
          projectName: task.projectName,
          promptPreview: task.promptPreview,
          resultPreview: task.resultPreview,
          completedAt: now
        )
      )
      effects.append(.showCompletion(sessionID: task.sessionID))

    case "SessionEnd":
      task.status = .ended
      task.endedAt = now
      task.lastActivityAt = now

    default:
      effects.append(.log("ignored unknown hook event: \(event.hookEventName)"))
    }

    task.lastEventID = envelope.eventID
    task.lastEventName = event.hookEventName
    upsert(task, into: &state.tasks)
    _ = pruneCompletions(state: &state, now: now, preferences: preferences)
    state.savedAt = now
    effects.append(.refreshPresentation)
    return effects
  }

  public func markStale(
    state: inout CodexTaskStoreSnapshot,
    now: Date,
    preferences: AppPreferences
  ) -> [CodexStateEffect] {
    let changed = markStaleTasks(state: &state, now: now, preferences: preferences)
    guard changed else { return [] }
    state.savedAt = now
    return [.persist, .refreshPresentation]
  }

  public func performMaintenance(
    state: inout CodexTaskStoreSnapshot,
    now: Date,
    preferences: AppPreferences
  ) -> [CodexStateEffect] {
    let staleChanged = markStaleTasks(state: &state, now: now, preferences: preferences)
    let completionsChanged = pruneCompletions(state: &state, now: now, preferences: preferences)
    guard staleChanged || completionsChanged else { return [] }
    state.savedAt = now
    return [.persist, .refreshPresentation]
  }

  public func acknowledgeCompletions(
    state: inout CodexTaskStoreSnapshot,
    now: Date
  ) -> [CodexStateEffect] {
    let visibleCompletionIDs = state.recentCompletions.map(\.id)
    let acknowledgedCompletionIDs = state.acknowledgedCompletionIDs ?? []
    guard Set(visibleCompletionIDs) != Set(acknowledgedCompletionIDs) else { return [] }

    state.acknowledgedCompletionIDs = visibleCompletionIDs
    state.savedAt = now
    return [.persist, .refreshPresentation]
  }

  public func acknowledgeCompletion(
    sessionID: String,
    state: inout CodexTaskStoreSnapshot,
    now: Date
  ) -> [CodexStateEffect] {
    guard acknowledgeCompletionIDs(sessionID: sessionID, state: &state, now: now) else {
      return []
    }
    return [.persist, .refreshPresentation]
  }

  private func upsert(_ task: CodexTaskRecord, into tasks: inout [CodexTaskRecord]) {
    if let index = tasks.firstIndex(where: { $0.sessionID == task.sessionID }) {
      tasks[index] = task
    } else {
      tasks.append(task)
    }
  }

  private func acknowledgeCompletionIDs(
    sessionID: String,
    state: inout CodexTaskStoreSnapshot,
    now: Date
  ) -> Bool {
    guard !sessionID.isEmpty else { return false }
    let completionIDs = state.recentCompletions
      .filter { $0.sessionID == sessionID }
      .map(\.id)
    guard !completionIDs.isEmpty else { return false }

    var acknowledged = state.acknowledgedCompletionIDs ?? []
    let existing = Set(acknowledged)
    let newIDs = completionIDs.filter { !existing.contains($0) }
    guard !newIDs.isEmpty else { return false }

    acknowledged.append(contentsOf: newIDs)
    state.acknowledgedCompletionIDs = acknowledged
    state.savedAt = now
    return true
  }

  private func markStaleTasks(
    state: inout CodexTaskStoreSnapshot,
    now: Date,
    preferences: AppPreferences
  ) -> Bool {
    var changed = false
    for index in state.tasks.indices {
      let task = state.tasks[index]
      guard task.status == .running || task.status == .waitingForApproval,
        now.timeIntervalSince(task.lastActivityAt) >= preferences.staleTimeout
      else { continue }
      state.tasks[index].status = .stale
      changed = true
    }
    return changed
  }

  private func pruneCompletions(
    state: inout CodexTaskStoreSnapshot,
    now: Date,
    preferences: AppPreferences
  ) -> Bool {
    let previous = state.recentCompletions
    let previousAcknowledgedCompletionIDs = state.acknowledgedCompletionIDs ?? []
    let cutoff = now.addingTimeInterval(-preferences.recentRetention)
    state.recentCompletions = state.recentCompletions
      .filter { $0.completedAt > cutoff }
      .sorted { $0.completedAt > $1.completedAt }
      .prefix(preferences.maxRecentCompletions)
      .map { $0 }
    let retainedCompletionIDs = Set(state.recentCompletions.map(\.id))
    state.acknowledgedCompletionIDs = previousAcknowledgedCompletionIDs.filter {
      retainedCompletionIDs.contains($0)
    }
    return state.recentCompletions != previous
      || state.acknowledgedCompletionIDs != previousAcknowledgedCompletionIDs
  }

  private func projectName(from cwd: String?) -> String {
    guard let cwd, !cwd.isEmpty else { return "Codex 会话" }
    let name = URL(fileURLWithPath: cwd).lastPathComponent
    return name.isEmpty ? "Codex 会话" : name
  }

  private func permissionDescription(_ event: CodexHookEvent) -> String {
    if case .object(let values)? = event.toolInput,
      case .string(let description)? = values["description"],
      !description.isEmpty
    {
      return description
    }
    return event.toolName.map { "需要批准使用 \($0)" } ?? "需要批准执行操作"
  }
}

public struct CodexTaskStore: Sendable {
  public private(set) var snapshot: CodexTaskStoreSnapshot
  public var preferences: AppPreferences
  private let reducer: CodexEventReducer

  public init(
    snapshot: CodexTaskStoreSnapshot = .empty,
    preferences: AppPreferences = AppPreferences()
  ) {
    self.snapshot = snapshot
    self.preferences = preferences
    self.reducer = CodexEventReducer()
  }

  @discardableResult
  public mutating func apply(_ envelope: CodexHookEnvelope) -> [CodexStateEffect] {
    reducer.reduce(state: &snapshot, envelope: envelope, preferences: preferences)
  }

  @discardableResult
  public mutating func markStale(now: Date = Date()) -> [CodexStateEffect] {
    reducer.markStale(state: &snapshot, now: now, preferences: preferences)
  }

  @discardableResult
  public mutating func performMaintenance(now: Date = Date()) -> [CodexStateEffect] {
    reducer.performMaintenance(state: &snapshot, now: now, preferences: preferences)
  }

  @discardableResult
  public mutating func acknowledgeCompletions(now: Date = Date()) -> [CodexStateEffect] {
    reducer.acknowledgeCompletions(state: &snapshot, now: now)
  }

  @discardableResult
  public mutating func acknowledgeCompletion(
    sessionID: String,
    now: Date = Date()
  ) -> [CodexStateEffect] {
    reducer.acknowledgeCompletion(sessionID: sessionID, state: &snapshot, now: now)
  }
}
