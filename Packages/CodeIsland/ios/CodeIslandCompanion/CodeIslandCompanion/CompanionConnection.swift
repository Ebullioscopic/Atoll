import Combine
import Foundation
import MultipeerConnectivity
import UIKit

@MainActor
final class CompanionConnection: NSObject, ObservableObject {
    @Published private(set) var discoveredPeers: [MCPeerID] = []
    @Published private(set) var connectedPeer: MCPeerID?
    @Published private(set) var latestState: CompanionStatePayload? {
        didSet {
            watchBridge.publish(latestState)
        }
    }
    @Published private(set) var lastError: String?
    @Published private(set) var browsing = false
    @Published private(set) var bluetoothConnectedPeripheralName: String?
    @Published private(set) var lastStateReceivedAt: Date?
    @Published private(set) var isDemoMode = false

    private static let serviceType = "codeisland"
    private static let refreshAfterSeconds: TimeInterval = 8
    private static let reconnectAfterSeconds: TimeInterval = 24

    private let watchBridge = WatchBridge()
    private let bluetoothBridge = CompanionBluetoothCentral()
    private let peerID = MCPeerID(displayName: UIDevice.current.name)
    private let mockStatePayload = CompanionConnection.mockStateFromLaunchArguments()
    private lazy var session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
    private lazy var browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
    private var stateWatchdogTimer: Timer?
    private var connectedAt: Date?
    private var pendingReconnectPeer: MCPeerID?
    private var demoSequence: UInt64 = 9000
    var onStateReceived: ((CompanionStatePayload) -> Void)?

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
        session.delegate = self
        browser.delegate = self
        watchBridge.commandHandler = { [weak self] command in
            self?.send(command)
        }
        bluetoothBridge.onSummary = { [weak self] summary in
            self?.receiveBluetoothSummary(summary)
        }
        bluetoothBridge.$connectedPeripheralName
            .assign(to: &$bluetoothConnectedPeripheralName)
        bluetoothBridge.$lastError
            .compactMap { $0 }
            .assign(to: &$lastError)

        if let mockStatePayload {
            connectedPeer = MCPeerID(displayName: "CodeIsland Mock Mac")
            receiveState(mockStatePayload)
        }
    }

    deinit {
        stateWatchdogTimer?.invalidate()
    }

    func start() {
        guard !isDemoMode else { return }
        bluetoothBridge.start()
        guard mockStatePayload == nil else { return }
        startStateWatchdog()
        guard !browsing else { return }
        lastError = nil
        browsing = true
        browser.startBrowsingForPeers()
    }

    func stop() {
        if isDemoMode {
            exitDemoMode()
            return
        }
        guard mockStatePayload == nil else { return }
        browsing = false
        stateWatchdogTimer?.invalidate()
        stateWatchdogTimer = nil
        browser.stopBrowsingForPeers()
        session.disconnect()
        discoveredPeers = []
        connectedPeer = nil
        connectedAt = nil
        pendingReconnectPeer = nil
    }

    /// MultipeerConnectivity sessions are torn down by iOS while the app is
    /// backgrounded — unlike Bluetooth, Wi-Fi/Bonjour connectivity has no
    /// platform-level background continuation, so this is expected, not a bug
    /// (#261). The problem is that nothing ever told the browser to restart:
    /// `ContentView`'s `.onAppear { connection.start() }` only fires once, when
    /// the view first appears, not on every return to the foreground, and
    /// `start()` no-ops while `browsing` is already (stale-)true. So once the
    /// session drops in the background, the app was stuck showing
    /// "disconnected" until the user manually tapped the search toggle.
    ///
    /// Call this from a scene-phase observer whenever the app becomes active
    /// again; it forces a clean restart of discovery only when we're not
    /// already connected, so it's a no-op for an already-healthy connection.
    func reconnectIfNeeded() {
        guard !isDemoMode, mockStatePayload == nil else { return }
        guard connectedPeer == nil else { return }
        stop()
        start()
    }

    func connect(to peer: MCPeerID) {
        exitDemoMode()
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 12)
    }

    func enterDemoMode() {
        guard mockStatePayload == nil else { return }
        browser.stopBrowsingForPeers()
        session.disconnect()
        browsing = false
        discoveredPeers = []
        connectedAt = Date()
        connectedPeer = MCPeerID(displayName: "Code Island Demo")
        isDemoMode = true
        receiveState(Self.mockState(named: "question", sequence: nextDemoSequence()))
    }

    func cycleDemoState() {
        guard isDemoMode else { return }
        let states = ["question", "long", "interrupted", "idle"]
        let nextIndex = Int((demoSequence - 9000) % UInt64(states.count))
        receiveState(Self.mockState(named: states[nextIndex], sequence: nextDemoSequence()))
    }

    func exitDemoMode() {
        guard isDemoMode else { return }
        isDemoMode = false
        latestState = nil
        connectedPeer = nil
        connectedAt = nil
        lastStateReceivedAt = nil
        lastError = nil
    }

    func send(_ type: CompanionCommandType) {
        send(type, answer: nil)
    }

    func sendAnswer(_ answer: String) {
        send(.answerQuestion, answer: answer)
    }

    private func send(_ command: CompanionCommandPayload) {
        guard !session.connectedPeers.isEmpty else { return }

        do {
            let data = try encoder.encode(command)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func send(_ type: CompanionCommandType, answer: String?) {
        guard !session.connectedPeers.isEmpty else { return }
        let command = CompanionCommandPayload(
            type: type,
            sessionId: latestState?.sessionId,
            source: latestState?.source,
            answer: answer
        )
        send(command)
    }

    private func requestCurrentState(reason: String) {
        guard !session.connectedPeers.isEmpty else { return }
        let command = CompanionCommandPayload(type: .requestCurrentState)
        send(command)
    }

    private func receiveState(_ state: CompanionStatePayload) {
        lastStateReceivedAt = Date()
        latestState = state
        onStateReceived?(state)
    }

    private func startStateWatchdog() {
        guard stateWatchdogTimer == nil else { return }
        stateWatchdogTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkStateFreshness()
            }
        }
    }

    private func checkStateFreshness() {
        guard mockStatePayload == nil else { return }
        guard !isDemoMode else { return }
        guard let connectedPeer else { return }

        let now = Date()
        let reference = lastStateReceivedAt ?? connectedAt ?? now
        let age = now.timeIntervalSince(reference)

        if age >= Self.reconnectAfterSeconds {
            lastError = L10n.t(zh: "连接在线但长时间没有状态更新，正在重新连接 Mac", en: "Connection is idle with no updates — reconnecting to the Mac")
            pendingReconnectPeer = connectedPeer
            session.disconnect()
            self.connectedPeer = nil
            connectedAt = nil
            if !browsing {
                browsing = true
                browser.startBrowsingForPeers()
            }
            if discoveredPeers.contains(connectedPeer) {
                browser.invitePeer(connectedPeer, to: session, withContext: nil, timeout: 12)
            }
            return
        }

        if age >= Self.refreshAfterSeconds {
            requestCurrentState(reason: "stale-\(Int(age))s")
        }
    }

    func injectMockState(named name: String) {
        receiveState(Self.mockState(named: name, sequence: nextDemoSequence()))
    }

    private func nextDemoSequence() -> UInt64 {
        demoSequence += 1
        return demoSequence
    }

    private func receiveBluetoothSummary(_ summary: CompanionBluetoothSummary) {
        guard !isDemoMode else { return }

        if let current = latestState, current.sequence > summary.sequence {
            return
        }

        receiveState(summary.statePayload)
    }

    private static func mockStateFromLaunchArguments() -> CompanionStatePayload? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-CodeIslandCompanionMockState"),
              arguments.indices.contains(flagIndex + 1)
        else {
            return nil
        }

        return mockState(named: arguments[flagIndex + 1])
    }

    private static func mockState(named name: String, sequence: UInt64? = nil) -> CompanionStatePayload {
        let baseMessages = [
            CompanionMessagePreview(role: .user, text: L10n.t(zh: "帮我生成一篇长篇小说", en: "Help me write a full-length novel")),
            CompanionMessagePreview(role: .assistant, text: L10n.t(
                zh: "好的，我先确认一下类型和篇幅，再开始组织结构。",
                en: "Sure — let me confirm the genre and length first, then start outlining the structure."
            ))
        ]
        let resolvedSequence = sequence ?? 1000

        switch name.lowercased() {
        case "question":
            return CompanionStatePayload(
                version: 1,
                sequence: resolvedSequence,
                sessionId: "mock-question",
                source: "claude",
                status: .waitingQuestion,
                toolName: "AskUserQuestion",
                workspaceName: "workspace",
                messages: baseMessages,
                pendingAction: .question,
                question: CompanionQuestionPayload(
                    header: L10n.t(zh: "小说类型", en: "Novel Genre"),
                    question: L10n.t(zh: "你想看什么类型的小说？", en: "What genre of novel would you like?"),
                    options: [
                        L10n.t(zh: "都市 / 现实", en: "Urban / Realistic"),
                        L10n.t(zh: "科幻", en: "Sci-Fi"),
                        L10n.t(zh: "悬疑 / 推理", en: "Mystery / Thriller"),
                        L10n.t(zh: "奇幻 / 玄幻", en: "Fantasy")
                    ],
                    descriptions: [
                        L10n.t(zh: "现代都市、职场情感、现实生活", en: "Modern city life, workplace drama, everyday realism"),
                        L10n.t(zh: "未来科技、AI、太空、时间旅行", en: "Future tech, AI, space, time travel"),
                        L10n.t(zh: "犯罪侦查、谜团解谜、心理悬疑", en: "Crime investigation, puzzles, psychological suspense"),
                        L10n.t(zh: "魔法世界、修真、异世界冒险", en: "Magic worlds, cultivation, otherworldly adventure")
                    ],
                    index: 1,
                    total: 4,
                    allowsMultipleSelection: false
                ),
                updatedAt: Date()
            )
        case "interrupted":
            return CompanionStatePayload(
                version: 1,
                sequence: resolvedSequence,
                sessionId: "mock-interrupted",
                source: "claude",
                status: .idle,
                toolName: nil,
                workspaceName: "workspace",
                messages: [
                    CompanionMessagePreview(role: .user, text: L10n.t(zh: "帮我生成一篇长篇小说", en: "Help me write a full-length novel")),
                    CompanionMessagePreview(role: .assistant, text: "[Request interrupted by user]")
                ],
                pendingAction: nil,
                question: nil,
                updatedAt: Date()
            )
        case "long":
            return CompanionStatePayload(
                version: 1,
                sequence: resolvedSequence,
                sessionId: "mock-long",
                source: "codex",
                status: .processing,
                toolName: "WebSearch",
                workspaceName: "workspace",
                messages: [
                    CompanionMessagePreview(role: .user, text: L10n.t(
                        zh: "把 iPhone 端所有容易截断的状态都自己跑一遍",
                        en: "Run through every iPhone-side state that's easy to truncate, yourself"
                    )),
                    CompanionMessagePreview(role: .assistant, text: L10n.t(
                        zh: "我会用模拟数据覆盖中断、提问、长文本和实时活动展示，重点检查中文化、滚动区域、最近动态字号以及按钮是否挤压。",
                        en: "I'll cover interrupted, question, long-text, and Live Activity states with mock data — checking localization, scroll regions, Recent Activity type size, and whether buttons get squeezed."
                    )),
                    CompanionMessagePreview(role: .assistant, text: L10n.t(
                        zh: "这是一条故意很长的最近动态，用来确认 iPhone 竖屏里不会被卡片裁掉，也不会因为内部嵌套滚动导致内容看不全。",
                        en: "This is a deliberately long Recent Activity entry, to confirm the card doesn't clip it in iPhone portrait, and nested scrolling doesn't hide any of it."
                    ))
                ],
                pendingAction: nil,
                question: nil,
                updatedAt: Date()
            )
        case "multi":
            let now = Date()
            let previews = [
                CompanionSessionPreview(sessionId: "s1", source: "claude", status: .waitingQuestion, toolName: "AskUserQuestion", workspaceName: "code-island", message: L10n.t(zh: "你想看什么类型的小说？", en: "What genre of novel would you like?"), messages: [
                    CompanionMessagePreview(role: .user, text: L10n.t(zh: "帮我生成一篇长篇小说", en: "Help me write a full-length novel")),
                    CompanionMessagePreview(role: .assistant, text: L10n.t(
                        zh: "好的，先确认**类型**和篇幅。你想看什么类型的小说？",
                        en: "Sure — let's nail down the **genre** and length first. What genre of novel would you like?"
                    ))
                ], updatedAt: now),
                CompanionSessionPreview(sessionId: "s2", source: "codex", status: .processing, toolName: "WebSearch", workspaceName: "apple-companion", message: L10n.t(zh: "正在检索资料", en: "Searching for references"), messages: [
                    CompanionMessagePreview(role: .user, text: L10n.t(zh: "查一下 SwiftUI `safeAreaInsets` 的用法", en: "Look up how SwiftUI `safeAreaInsets` works")),
                    CompanionMessagePreview(role: .assistant, text: L10n.t(zh: "正在检索资料，稍等。", en: "Searching for references, one moment."))
                ], updatedAt: now),
                CompanionSessionPreview(sessionId: "s3", source: "cursor", status: .running, toolName: "Edit", workspaceName: "ios", message: L10n.t(zh: "正在修改 ContentView", en: "Editing ContentView"), messages: [
                    CompanionMessagePreview(role: .user, text: L10n.t(zh: "把会话卡改成 notch 风格", en: "Restyle the session card to match the notch")),
                    CompanionMessagePreview(role: .assistant, text: L10n.t(
                        zh: "正在修改 `ContentView.swift`，对齐状态着色与多轮转写。",
                        en: "Editing `ContentView.swift`, aligning status colors and the multi-turn transcript."
                    ))
                ], updatedAt: now),
                CompanionSessionPreview(sessionId: "s4", source: "gemini", status: .waitingApproval, toolName: "Bash", workspaceName: "scripts", message: L10n.t(zh: "请求执行命令", en: "Requesting to run a command"), messages: [
                    CompanionMessagePreview(role: .assistant, text: L10n.t(zh: "请求执行 `npm run build`，是否批准？", en: "Requesting to run `npm run build` — approve?"))
                ], updatedAt: now),
                CompanionSessionPreview(sessionId: "s5", source: "kimi", status: .idle, toolName: nil, workspaceName: "docs", message: nil, updatedAt: now),
                CompanionSessionPreview(sessionId: "s6", source: "qwen", status: .processing, toolName: "Read", workspaceName: "server", message: L10n.t(zh: "读取配置", en: "Reading config"), messages: [
                    CompanionMessagePreview(role: .user, text: L10n.t(zh: "看下服务端配置", en: "Check the server config")),
                    CompanionMessagePreview(role: .assistant, text: L10n.t(zh: "正在读取 `config.yaml`…", en: "Reading `config.yaml`…"))
                ], updatedAt: now)
            ]
            return CompanionStatePayload(
                version: 1,
                sequence: resolvedSequence,
                sessionId: "mock-multi",
                source: "claude",
                status: .processing,
                toolName: "AskUserQuestion",
                workspaceName: "code-island",
                messages: [
                    CompanionMessagePreview(role: .user, text: L10n.t(
                        zh: "帮我把看板的会话卡做成和 notch 一致",
                        en: "Make the board's session cards match the notch style"
                    )),
                    CompanionMessagePreview(role: .assistant, text: L10n.t(
                        zh: "好的，我会对齐**状态着色**、`#id`、time-ago 和 `$ thinking` 工作行。",
                        en: "Sure, I'll align **status colors**, `#id`, time-ago, and the `$ thinking` work line."
                    )),
                    CompanionMessagePreview(role: .assistant, text: L10n.t(
                        zh: "已提交并推送，横屏 hero 现在显示主会话最近 3 条转写。",
                        en: "Committed and pushed — the landscape hero now shows the primary session's last 3 turns."
                    ))
                ],
                pendingAction: nil,
                question: nil,
                sessions: previews,
                updatedAt: now
            )
        default:
            return CompanionStatePayload(
                version: 1,
                sequence: resolvedSequence,
                sessionId: "mock-idle",
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
}

extension CompanionConnection: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard !self.discoveredPeers.contains(peerID) else { return }
            self.discoveredPeers.append(peerID)
            if self.pendingReconnectPeer == peerID {
                self.pendingReconnectPeer = nil
                self.connect(to: peerID)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredPeers.removeAll { $0 == peerID }
            if self.connectedPeer == peerID {
                self.connectedPeer = nil
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.browsing = false
            self.lastError = error.localizedDescription
        }
    }
}

extension CompanionConnection: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.connectedPeer = peerID
                self.connectedAt = Date()
                self.requestCurrentState(reason: "peer-connected")
            case .notConnected:
                if self.connectedPeer == peerID {
                    self.connectedPeer = nil
                }
                self.connectedAt = nil
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                self.receiveState(try self.decoder.decode(CompanionStatePayload.self, from: data))
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}
