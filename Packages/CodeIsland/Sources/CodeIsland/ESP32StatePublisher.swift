import Foundation
import os
import CodeIslandCore

/// Drives the Buddy bridge: pushes the *currently displayed* mascot/status
/// both on every AppState mutation (via `notifyDirty()`) and on a fixed
/// heartbeat so the firmware (60s inactivity timeout) never drops out of
/// AGENT mode and reconnects/power-cycles resync immediately.
///
/// Display selection mirrors `NotchPanelView.CompactLeftWing`:
///     rotatingSessionId ?? activeSessionId ?? first sorted session.
/// Falls back to `appState.primarySource` + `.idle` when no sessions exist.
@MainActor
final class ESP32StatePublisher {
    static let shared = ESP32StatePublisher()

    private static let log = Logger(subsystem: "com.codeisland", category: "esp32-publisher")

    private weak var appState: AppState?
    private let bridge: ESP32BridgeManager
    private var heartbeatTimer: Timer?
    private var heartbeatInterval: TimeInterval = 5.0
    private var brightnessPercent: Double = Double(ESP32Protocol.defaultBrightnessPercent)
    private var screenOrientation: BuddyScreenOrientation = .up
    private var keepAliveActivity: NSObjectProtocol?
    private var interactiveRetryTask: Task<Void, Never>?
    private var lastSentDisplay: SentDisplayState?

    private struct SentDisplayState {
        let identity: String
        let status: MascotStatusCode
    }

    private init() {
        self.bridge = ESP32BridgeManager.shared
    }

    /// Called once from `AppDelegate.applicationDidFinishLaunching`.
    func attach(_ appState: AppState) {
        self.appState = appState
        bridge.onConnected = { [weak self] in
            self?.resetEventState()
            self?.syncConfig()
            self?.flush(reason: "connected")
        }
    }

    /// Invoke when a knob that changes what the island displays may have
    /// changed (new Settings value, toggled enabled flag, etc).
    func configure(
        enabled: Bool,
        heartbeatSeconds: Double,
        brightnessPercent: Double,
        screenOrientation: BuddyScreenOrientation
    ) {
        self.heartbeatInterval = max(1.0, heartbeatSeconds)
        self.brightnessPercent = Double(ESP32Protocol.clampedBrightnessPercent(brightnessPercent))
        self.screenOrientation = screenOrientation
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        interactiveRetryTask?.cancel()
        interactiveRetryTask = nil
        if enabled {
            beginKeepAliveActivityIfNeeded()
            if bridge.status == .off {
                bridge.start()
            }
            syncConfig()
            heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.flush(reason: "heartbeat")
                }
            }
        } else {
            endKeepAliveActivity()
            resetEventState()
            bridge.stop()
        }
    }

    /// Called from `AppState.refreshDerivedState()` after session mutations.
    func notifyDirty() {
        flush(reason: "change")
        scheduleInteractiveRetriesIfNeeded()
    }

    private func flush(reason: String) {
        guard let appState else { return }
        guard bridge.status == .connected else { return }
        guard bridge.selectedBuddyIdentifier != nil else { return }
        let session = appState.esp32DisplaySession()
        let displayIdentity = appState.esp32DisplayIdentity()
        let frame = appState.esp32DisplayFrame(session: session)
        bridge.send(frame)

        if bridge.usesLegacyPairingFallback {
            lastSentDisplay = SentDisplayState(identity: displayIdentity, status: frame.status)
            Self.log.debug("push(\(reason), legacy): mascot=\(frame.mascot.sourceName) status=\(frame.status.rawValue) tool=\(frame.toolName ?? "")")
            return
        }

        bridge.sendWorkspace(appState.esp32WorkspacePayload(session: session))
        appState.esp32MessagePreviewPayloads(session: session).forEach { bridge.sendMessagePreview($0) }
        bridge.sendModel(appState.esp32ModelPayload(session: session))
        bridge.sendTimeHint(BuddyTimeHintPayload(hour: Calendar.current.component(.hour, from: Date())))
        bridge.sendStats(appState.esp32StatsPayload(session: session))
        bridge.sendSubagent(appState.esp32SubagentPayload(session: session))
        let toolHistory = appState.esp32ToolHistoryPayloads(session: session)
        if toolHistory.isEmpty {
            bridge.sendToolHistoryClear()
        } else {
            toolHistory.forEach { bridge.sendToolHistory($0) }
        }

        // Detect status transitions for event animations
        let currentStatus = frame.status
        if let previous = lastSentDisplay,
           previous.identity == displayIdentity,
           previous.status != currentStatus {
            let prev = previous.status
            if (prev == .processing || prev == .running) && currentStatus == .idle {
                if let lastTool = session?.toolHistory.last, !lastTool.success {
                    bridge.sendEvent(.error)
                } else {
                    bridge.sendEvent(.complete)
                }
            }
            if (currentStatus == .waitingApproval || currentStatus == .waitingQuestion)
                && prev != .waitingApproval && prev != .waitingQuestion {
                bridge.sendEvent(.approval)
            }
        }
        lastSentDisplay = SentDisplayState(identity: displayIdentity, status: currentStatus)

        Self.log.debug("push(\(reason)): mascot=\(frame.mascot.sourceName) status=\(frame.status.rawValue) tool=\(frame.toolName ?? "")")
    }

    private func resetEventState() {
        lastSentDisplay = nil
    }

    private func syncConfig() {
        bridge.sendBrightness(percent: brightnessPercent)
        bridge.sendScreenOrientation(screenOrientation)
    }

    private func beginKeepAliveActivityIfNeeded() {
        guard keepAliveActivity == nil else { return }
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Keep Buddy Bluetooth bridge responsive while app is backgrounded"
        )
    }

    private func endKeepAliveActivity() {
        guard let keepAliveActivity else { return }
        ProcessInfo.processInfo.endActivity(keepAliveActivity)
        self.keepAliveActivity = nil
    }

    private func scheduleInteractiveRetriesIfNeeded() {
        interactiveRetryTask?.cancel()
        guard let appState, let deliveryKey = appState.esp32InteractiveDeliveryKey() else { return }
        interactiveRetryTask = Task { [weak self] in
            let delays: [UInt64] = [600_000_000, 1_800_000_000]
            for delayNs in delays {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.appState?.esp32InteractiveDeliveryKey() == deliveryKey else { return }
                    self.flush(reason: "interactive-retry")
                }
            }
        }
    }
}

// MARK: - AppState bridge

extension AppState {
    private struct BuddyDisplayContext {
        let source: String
        let status: AgentStatus
        let tool: String?
        let workspace: String?
        let messages: [ChatMessage]
    }

    func esp32DisplaySessionId() -> String? {
        let sid = rotatingSessionId ?? activeSessionId ?? sessions.keys.sorted().first
        return sid
    }

    func esp32DisplaySession() -> SessionSnapshot? {
        esp32DisplaySessionId().flatMap { sessions[$0] }
    }

    func esp32DisplayIdentity() -> String {
        if let pending = pendingPermission {
            return "session:\(pending.event.sessionId ?? activeSessionId ?? "default")"
        }
        if let pending = pendingQuestion {
            return "session:\(pending.event.sessionId ?? activeSessionId ?? "default")"
        }
        if let sessionId = esp32DisplaySessionId() {
            return "session:\(sessionId)"
        }
        return "fallback:\(SettingsManager.shared.defaultSource)"
    }

    private func esp32DisplayContext(session: SessionSnapshot? = nil) -> BuddyDisplayContext {
        if let pending = pendingPermission {
            let sessionId = pending.event.sessionId ?? activeSessionId ?? "default"
            let pendingSession = sessions[sessionId]
            var messages = pendingSession?.recentMessages ?? []
            let detailText = (pending.event.toolDescription ?? pendingSession?.toolDescription)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let detailText, !detailText.isEmpty, messages.last?.text != detailText {
                messages.append(ChatMessage(isUser: false, text: detailText))
            }
            return BuddyDisplayContext(
                source: pendingSession?.source ?? primarySource,
                status: .waitingApproval,
                tool: pending.event.toolName ?? pendingSession?.currentTool,
                workspace: pendingSession?.projectDisplayName,
                messages: Array(messages.suffix(3)),
            )
        }

        if let pending = pendingQuestion {
            let sessionId = pending.event.sessionId ?? activeSessionId ?? "default"
            let pendingSession = sessions[sessionId]
            var messages = pendingSession?.recentMessages ?? []
            // Secret prompts (Codex `isSecret`) must not stream their text off-device. (#209)
            let rawQuestionText = pending.question.isSecret
                ? Self.secretQuestionPlaceholder
                : pending.question.question
            let questionText = rawQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !questionText.isEmpty && messages.last?.text != questionText {
                messages.append(ChatMessage(isUser: true, text: questionText))
            }
            return BuddyDisplayContext(
                source: pendingSession?.source ?? primarySource,
                status: .waitingQuestion,
                tool: pending.event.toolName ?? "AskUserQuestion",
                workspace: pendingSession?.projectDisplayName,
                messages: Array(messages.suffix(3)),
            )
        }

        let sessionStatus = session?.status ?? .idle
        let effectiveSource: String
        if sessionStatus == .idle {
            effectiveSource = SettingsManager.shared.defaultSource
        } else {
            effectiveSource = session?.source ?? primarySource
        }

        return BuddyDisplayContext(
            source: effectiveSource,
            status: sessionStatus,
            tool: (sessionStatus == .running || sessionStatus == .processing || sessionStatus == .waitingApproval || sessionStatus == .waitingQuestion)
                ? session?.currentTool
                : nil,
            workspace: session?.projectDisplayName,
            messages: Array((session?.recentMessages ?? []).suffix(3)),
        )
    }

    /// The `MascotFramePayload` that matches what the notch currently shows.
    /// Keep in sync with `NotchPanelView.CompactLeftWing.displaySession`.
    func esp32DisplayFrame(session: SessionSnapshot? = nil) -> MascotFramePayload {
        let context = esp32DisplayContext(session: session)
        let mascot = MascotID(sourceName: context.source) ?? .claude
        return MascotFramePayload(mascot: mascot, status: MascotStatusCode(context.status), toolName: context.tool)
    }

    func esp32WorkspacePayload(session: SessionSnapshot? = nil) -> BuddyWorkspacePayload {
        BuddyWorkspacePayload(workspaceName: esp32DisplayContext(session: session).workspace)
    }

    func esp32MessagePreviewPayloads(session: SessionSnapshot? = nil) -> [BuddyMessagePreviewPayload] {
        let previews = esp32DisplayContext(session: session).messages
        let flattened = previews.flatMap { message in
            esp32MessagePreviewSegments(text: message.text).map { ChatMessage(isUser: message.isUser, text: $0) }
        }
        guard !flattened.isEmpty else {
            return [BuddyMessagePreviewPayload(index: 0, total: 0, isUser: false, text: nil)]
        }
        let total = flattened.count
        return flattened.enumerated().map { index, message in
            BuddyMessagePreviewPayload(index: index, total: total, isUser: message.isUser, text: message.text)
        }
    }

    func esp32InteractiveDeliveryKey(session: SessionSnapshot? = nil) -> String? {
        let context = esp32DisplayContext(session: session)
        guard context.status == .waitingApproval || context.status == .waitingQuestion else { return nil }
        let messageKey = context.messages
            .flatMap { esp32MessagePreviewSegments(text: $0.text) }
            .joined(separator: "\n")
        return [
            context.source,
            String(MascotStatusCode(context.status).rawValue),
            context.tool ?? "",
            context.workspace ?? "",
            messageKey,
        ].joined(separator: "|")
    }

    func esp32ModelPayload(session: SessionSnapshot? = nil) -> BuddyModelPayload {
        BuddyModelPayload(modelName: session?.shortModelName)
    }

    func esp32StatsPayload(session: SessionSnapshot? = nil) -> BuddyStatsPayload {
        let toolCount = esp32TotalToolCallCount()
        let durationMin: Int
        if let start = session?.startTime {
            durationMin = Int(Date().timeIntervalSince(start) / 60.0)
        } else {
            durationMin = 0
        }
        return BuddyStatsPayload(
            activeSessionCount: activeSessionCount,
            totalSessionCount: totalSessionCount,
            toolCallCount: toolCount,
            sessionDurationMinutes: durationMin
        )
    }

    func esp32TotalToolCallCount() -> Int {
        sessions.values.reduce(0) { $0 + $1.totalToolCallCount }
    }

    func esp32SubagentPayload(session: SessionSnapshot? = nil) -> BuddySubagentPayload {
        BuddySubagentPayload(count: session?.activeSubagentCount ?? 0)
    }

    func esp32ToolHistoryPayloads(session: SessionSnapshot? = nil) -> [BuddyToolHistoryPayload] {
        guard let history = session?.toolHistory, !history.isEmpty else { return [] }
        return history.suffix(10).enumerated().map { index, entry in
            BuddyToolHistoryPayload(index: index, success: entry.success, toolName: entry.tool)
        }
    }

    func appleCompanionStatePayload(sequence: UInt64, session: SessionSnapshot? = nil) -> AppleCompanionStatePayload {
        let displaySession = session ?? esp32DisplaySession()
        let context = esp32DisplayContext(session: displaySession)
        let displaySessionId = rotatingSessionId ?? activeSessionId ?? sessions.keys.sorted().first
        let sessionId = pendingPermission?.event.sessionId
            ?? pendingQuestion?.event.sessionId
            ?? displaySessionId
        let pendingAction: AppleCompanionPendingAction?
        switch context.status {
        case .waitingApproval:
            pendingAction = .approval
        case .waitingQuestion:
            pendingAction = .question
        default:
            pendingAction = nil
        }
        let messages = context.messages.suffix(3).compactMap { message -> AppleCompanionMessagePreview? in
            let text = Self.appleCompanionPreviewText(message.text)
            guard !text.isEmpty else { return nil }
            return AppleCompanionMessagePreview(
                role: message.isUser ? .user : .assistant,
                text: text
            )
        }
        let questionPayload = appleCompanionQuestionPayload()
        return AppleCompanionStatePayload(
            sequence: sequence,
            sessionId: sessionId,
            source: context.source,
            status: AppleCompanionStatus(context.status),
            toolName: context.tool,
            workspaceName: context.workspace,
            messages: messages,
            pendingAction: pendingAction,
            question: questionPayload,
            sessions: appleCompanionSessionPreviews(primarySessionId: sessionId)
        )
    }

    private func appleCompanionSessionPreviews(primarySessionId: String?) -> [AppleCompanionSessionPreview] {
        let sorted = sessions.sorted { lhs, rhs in
            let leftPrimary = lhs.key == primarySessionId
            let rightPrimary = rhs.key == primarySessionId
            if leftPrimary != rightPrimary { return leftPrimary }

            let leftPriority = appleCompanionSessionPriority(lhs.value.status)
            let rightPriority = appleCompanionSessionPriority(rhs.value.status)
            if leftPriority != rightPriority { return leftPriority > rightPriority }

            return lhs.value.lastActivity > rhs.value.lastActivity
        }

        return sorted.prefix(5).map { sessionId, session in
            let messages = session.recentMessages.suffix(2).compactMap { message -> AppleCompanionMessagePreview? in
                let text = Self.appleCompanionPreviewText(message.text)
                guard !text.isEmpty else { return nil }
                return AppleCompanionMessagePreview(role: message.isUser ? .user : .assistant, text: text)
            }
            return AppleCompanionSessionPreview(
                sessionId: sessionId,
                source: session.source,
                status: AppleCompanionStatus(session.status),
                toolName: session.status == .idle ? nil : session.currentTool,
                workspaceName: session.projectDisplayName,
                message: appleCompanionSessionMessage(sessionId: sessionId, session: session),
                messages: messages,
                updatedAt: session.lastActivity
            )
        }
    }

    private func appleCompanionSessionMessage(sessionId: String, session: SessionSnapshot) -> String? {
        if let pending = questionQueue.first(where: { ($0.event.sessionId ?? "default") == sessionId }) {
            return Self.appleCompanionPreviewText(pending.question.question)
        }
        if let pending = permissionQueue.first(where: { ($0.event.sessionId ?? "default") == sessionId }) {
            return Self.appleCompanionPreviewText(pending.event.toolDescription ?? session.toolDescription)
        }
        if let text = session.recentMessages.last?.text {
            return Self.appleCompanionPreviewText(text)
        }
        return Self.appleCompanionPreviewText(session.lastAssistantMessage ?? session.lastUserPrompt)
    }

    private func appleCompanionSessionPriority(_ status: AgentStatus) -> Int {
        switch status {
        case .waitingApproval: return 5
        case .waitingQuestion: return 4
        case .running: return 3
        case .processing: return 2
        case .idle: return 0
        }
    }

    private func appleCompanionQuestionPayload() -> AppleCompanionQuestionPayload? {
        guard let pending = pendingQuestion else { return nil }

        if let askState = pending.askUserQuestionState, !askState.items.isEmpty {
            let index = askState.items.firstIndex { askState.answers[$0.answerKey] == nil } ?? 0
            let item = askState.items[index]
            // Secret prompts (Codex `isSecret`) must not stream their text/options
            // off-device — answer on the Mac instead. (#209)
            if item.payload.isSecret {
                return AppleCompanionQuestionPayload(
                    header: item.payload.header,
                    question: Self.secretQuestionPlaceholder,
                    options: [],
                    descriptions: [],
                    index: index + 1,
                    total: askState.items.count,
                    allowsMultipleSelection: item.multiSelect
                )
            }
            return AppleCompanionQuestionPayload(
                header: item.payload.header,
                question: item.payload.question,
                options: item.payload.options ?? [],
                descriptions: item.payload.descriptions ?? [],
                index: index + 1,
                total: askState.items.count,
                allowsMultipleSelection: item.multiSelect
            )
        }

        if pending.question.isSecret {
            return AppleCompanionQuestionPayload(
                header: pending.question.header,
                question: Self.secretQuestionPlaceholder,
                options: [],
                descriptions: [],
                index: 1,
                total: 1,
                allowsMultipleSelection: false
            )
        }

        return AppleCompanionQuestionPayload(
            header: pending.question.header,
            question: pending.question.question,
            options: pending.question.options ?? [],
            descriptions: pending.question.descriptions ?? [],
            index: 1,
            total: 1,
            allowsMultipleSelection: false
        )
    }

    /// Shown to remote peripherals in place of a secret prompt's real text.
    private static let secretQuestionPlaceholder = "Sensitive prompt — answer on Mac"

    private static func appleCompanionPreviewText(_ text: String?) -> String {
        guard let text else { return "" }
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > 240 else { return collapsed }
        return String(collapsed.prefix(237)) + "..."
    }
    func esp32MessagePreviewSegments(text: String?) -> [String] {
        guard let text else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var segments: [String] = []
        var current = ""
        var currentCount = 0

        for character in trimmed {
            let scalar = String(character)
            let byteCount = scalar.lengthOfBytes(using: .utf8)
            if currentCount > 0 && currentCount + byteCount > ESP32Protocol.maxMessagePreviewBytes {
                segments.append(current)
                current = scalar
                currentCount = byteCount
            } else if byteCount > ESP32Protocol.maxMessagePreviewBytes {
                if !current.isEmpty {
                    segments.append(current)
                    current = ""
                    currentCount = 0
                }
                segments.append(String(bytes: scalar.utf8.prefix(ESP32Protocol.maxMessagePreviewBytes), encoding: .utf8) ?? scalar)
            } else {
                current.append(character)
                currentCount += byteCount
            }
        }

        if !current.isEmpty {
            segments.append(current)
        }

        return segments
    }
}
