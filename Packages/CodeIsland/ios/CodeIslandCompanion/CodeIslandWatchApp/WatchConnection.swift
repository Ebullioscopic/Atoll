import Foundation
import UserNotifications
import WatchKit
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchConnection: NSObject, ObservableObject {
    @Published private(set) var latestState: CompanionStatePayload?
    @Published private(set) var lastError: String?
    @Published private(set) var activationState: WCSessionActivationState = .notActivated
    private var lastHapticSequence: UInt64?
    private var lastNotificationSequence: UInt64?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    override init() {
        super.init()

        guard WCSession.isSupported() else {
            lastError = L10n.t(zh: "这台设备不支持与 iPhone 同步", en: "This device can't sync with iPhone")
            return
        }

#if DEBUG && targetEnvironment(simulator)
        // The smoke-test simulator does not need local notification permission.
#elseif DEBUG
        let isSmokeTest = ProcessInfo.processInfo.arguments.contains("-CodeIslandWatchSmokeState")
        if !isSmokeTest {
            requestNotificationAuthorization()
        }
#else
        requestNotificationAuthorization()
#endif
        WCSession.default.delegate = self
        WCSession.default.activate()

#if DEBUG
        if let state = Self.mockStateFromLaunchArguments() {
            receiveState(state)
        } else if let data = WCSession.default.receivedApplicationContext["state"] as? Data {
            decodeState(data)
        }
#else
        if let data = WCSession.default.receivedApplicationContext["state"] as? Data {
            decodeState(data)
        }
#endif
    }

    func send(_ type: CompanionCommandType, answer: String? = nil) {
        WKInterfaceDevice.current().play(.click)

        guard WCSession.default.isReachable else {
            lastError = L10n.t(zh: "iPhone 暂不可达", en: "iPhone isn't reachable right now")
            WKInterfaceDevice.current().play(.failure)
            return
        }

        let command = CompanionCommandPayload(
            type: type,
            sessionId: latestState?.sessionId,
            source: latestState?.source,
            answer: answer
        )

        do {
            let data = try encoder.encode(command)
            WCSession.default.sendMessage(["command": data], replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.lastError = error.localizedDescription
                    WKInterfaceDevice.current().play(.failure)
                }
            }
        } catch {
            lastError = error.localizedDescription
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private func decodeState(_ data: Data) {
        do {
            let nextState = try decoder.decode(CompanionStatePayload.self, from: data)
            receiveState(nextState)
        } catch {
            lastError = error.localizedDescription
            // A payload we can't decode would come back at every launch via the
            // persisted snapshot / application context — drop it so one poisoned
            // state can't wedge the app in a crash-on-open loop (#246).
            WatchStateStore.clear()
            WKInterfaceDevice.current().play(.failure)
        }
    }

    private func receiveState(_ nextState: CompanionStatePayload) {
        let previousState = latestState
        latestState = nextState
        lastError = nil
        WatchStateStore.save(nextState)
        WidgetCenter.shared.reloadAllTimelines()
        playHapticIfNeeded(previous: previousState, next: nextState)
        scheduleNotificationIfNeeded(previous: previousState, next: nextState)
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func playHapticIfNeeded(previous: CompanionStatePayload?, next: CompanionStatePayload) {
        guard lastHapticSequence != next.sequence else { return }
        lastHapticSequence = next.sequence

        guard let previous else { return }

        if next.pendingAction == .approval || next.pendingAction == .question {
            WKInterfaceDevice.current().play(.notification)
        } else if previous.status != next.status || previous.messages.count != next.messages.count {
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func scheduleNotificationIfNeeded(previous: CompanionStatePayload?, next: CompanionStatePayload) {
        guard previous != nil else { return }
        guard lastNotificationSequence != next.sequence else { return }
        guard next.pendingAction == .approval || next.pendingAction == .question else { return }

        lastNotificationSequence = next.sequence

        let content = UNMutableNotificationContent()
        content.title = "\(CompanionDisplayText.source(next.source)) \(L10n.t(zh: "需要处理", en: "needs your attention"))"
        content.body = next.question?.question
            ?? CompanionDisplayText.message(next.messages.last?.text)
            ?? next.status.label
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "code-island-\(next.sequence)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

#if DEBUG
    private static func mockStateFromLaunchArguments() -> CompanionStatePayload? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-CodeIslandWatchSmokeState"),
              arguments.indices.contains(flagIndex + 1)
        else {
            return nil
        }

        return mockState(named: arguments[flagIndex + 1])
    }

    private static func mockState(named name: String) -> CompanionStatePayload {
        switch name.lowercased() {
        case "question":
            return CompanionStatePayload(
                version: 1,
                sequence: 9202,
                sessionId: "watch-question",
                source: "claude",
                status: .waitingQuestion,
                toolName: "AskUserQuestion",
                workspaceName: "fengye",
                messages: [
                    CompanionMessagePreview(role: .user, text: L10n.t(zh: "帮我写一篇长篇小说", en: "Help me write a full-length novel")),
                    CompanionMessagePreview(role: .assistant, text: L10n.t(zh: "我需要先确认小说类型和基调。", en: "I need to confirm the genre and tone first."))
                ],
                pendingAction: .question,
                question: CompanionQuestionPayload(
                    header: L10n.t(zh: "小说类型", en: "Novel Genre"),
                    question: L10n.t(zh: "你想写什么类型的小说？", en: "What genre of novel do you want to write?"),
                    options: [
                        L10n.t(zh: "科幻", en: "Sci-Fi"),
                        L10n.t(zh: "悬疑推理", en: "Mystery/Thriller"),
                        L10n.t(zh: "都市现实", en: "Urban Realism"),
                        L10n.t(zh: "奇幻冒险", en: "Fantasy Adventure")
                    ],
                    descriptions: [],
                    index: 0,
                    total: 3,
                    allowsMultipleSelection: false
                ),
                updatedAt: Date()
            )
        case "long":
            return CompanionStatePayload(
                version: 1,
                sequence: 9203,
                sessionId: "watch-long",
                source: "codex",
                status: .processing,
                toolName: "WebSearch",
                workspaceName: "workspace",
                messages: [
                    CompanionMessagePreview(role: .user, text: L10n.t(
                        zh: "重点测试退到后台之后灵动岛和手表还能不能收到新消息",
                        en: "Specifically testing whether the Dynamic Island and Watch still receive new messages after backgrounding"
                    )),
                    CompanionMessagePreview(role: .assistant, text: L10n.t(
                        zh: "我会先用模拟器验证 UI 和本地同步路径，再把真机 BLE 后台唤醒列成单独验收项。",
                        en: "I'll verify the UI and local sync path in the simulator first, then list real-device BLE background wake as a separate acceptance item."
                    )),
                    CompanionMessagePreview(role: .assistant, text: L10n.t(
                        zh: "这是一条较长的 watch 动态内容，用来确认滚动页面不会被底部按钮或系统区域裁掉。",
                        en: "This is a longer watch activity entry, to confirm the scroll page isn't clipped by the bottom button or system regions."
                    ))
                ],
                pendingAction: nil,
                question: nil,
                updatedAt: Date()
            )
        default:
            return CompanionStatePayload(
                version: 1,
                sequence: 9201,
                sessionId: "watch-idle",
                source: "codex",
                status: .idle,
                toolName: nil,
                workspaceName: "workspace",
                messages: [],
                pendingAction: nil,
                question: nil,
                updatedAt: Date()
            )
        }
    }
#endif
}

extension WatchConnection: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.activationState = activationState
            self.lastError = error?.localizedDescription
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    private nonisolated func receive(_ message: [String: Any]) {
        guard let data = message["state"] as? Data else { return }

        Task { @MainActor in
            decodeState(data)
        }
    }
}
