import MultipeerConnectivity
import SwiftUI
import UIKit

private enum CodeIslandMotion {
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let close = Animation.spring(response: 0.38, dampingFraction: 1.0)
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.65)
    static let micro = Animation.easeOut(duration: 0.12)
}

struct ContentView: View {
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController
    @AppStorage(appAppearanceStorageKey) private var appearanceRaw = AppAppearance.system.rawValue

    private var appearance: AppAppearance {
        AppAppearance(rawValue: appearanceRaw) ?? .system
    }

    var body: some View {
        GeometryReader { proxy in
            // 内容尊重安全区（不再忽略），元素自动避开状态栏 / 刘海 / Home 指示条；
            // 背景由下方 .background 忽略安全区铺满整屏。
            ZStack(alignment: .top) {
                if proxy.size.width > proxy.size.height, let state = connection.latestState {
                    StandByIsland(state: state, availableSize: proxy.size)
                        .environmentObject(connection)
                        .environmentObject(liveActivity)
                } else {
                    PortraitIslandView(topPadding: 40)
                        .environmentObject(connection)
                        .environmentObject(liveActivity)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                }
            }
            .onAppear {
                connection.start()
            }
            .onChange(of: connection.latestState?.sequence) { _, _ in
                guard liveActivity.isRunning, let state = connection.latestState else { return }
                liveActivity.startOrUpdate(with: state)
            }
            .animation(CodeIslandMotion.open, value: connection.connectedPeer)
            .animation(CodeIslandMotion.pop, value: connection.latestState?.status)
            .animation(CodeIslandMotion.micro, value: connection.browsing)
        }
        .background(Color.ciBackground.ignoresSafeArea())
        .preferredColorScheme(appearance.colorScheme)
        .accessibilityIdentifier("companion.root")
    }
}

private struct PortraitIslandView: View {
    let topPadding: CGFloat
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController

    private static let pendingAnchor = "companion.pendingCard"

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroller in
            ScrollView(.vertical) {
                LazyVStack(spacing: 10) {
                    CompactIslandBar()
                        .environmentObject(connection)

                    if let state = connection.latestState {
                        LiveIslandCard(state: state)
                            .environmentObject(connection)
                            .environmentObject(liveActivity)
                            .id(Self.pendingAnchor)
                            .transition(.blurFade.combined(with: .scale(scale: 0.96, anchor: .top)))

                        MessageStrip(messages: state.messages)
                    } else {
                        DiscoveryIsland()
                            .environmentObject(connection)
                            .transition(.blurFade.combined(with: .scale(scale: 0.96, anchor: .top)))

                        DiscoveryFill()
                    }

                    if let error = connection.lastError {
                        DiagnosticStrip(message: error)
                            .transition(.blurFade.combined(with: .move(edge: .top)))
                    }

                    if let error = liveActivity.lastError {
                        LiveActivityDiagnosticStrip(message: error)
                            .environmentObject(liveActivity)
                            .transition(.blurFade.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.top, topPadding)
                .padding(.bottom, max(28, proxy.safeAreaInsets.bottom + 20))
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .accessibilityIdentifier("companion.scroll")
            .onChange(of: connection.latestState?.pendingAction) { _, newValue in
                guard newValue != nil else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    scroller.scrollTo(Self.pendingAnchor, anchor: .top)
                }
            }
            }
        }
    }
}

private struct PrimaryMessageView: View {
    let state: CompanionStatePayload

    var body: some View {
        let text = state.question?.question
            ?? CompanionDisplayText.message(state.messages.last?.text)
            ?? L10n.t(zh: "当前没有新的消息", en: "No new messages")

        MorphText(
            text: text,
            font: .system(size: 16, weight: .medium),
            color: .ciForeground.opacity(state.messages.isEmpty && state.question == nil ? 0.55 : 0.86),
            lineLimit: state.question == nil ? 5 : 3,
            markdown: true
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MetadataChipRow: View {
    let workspaceName: String?
    let toolName: String?

    private var workspaceText: String? {
        CompanionDisplayText.workspace(workspaceName)
    }

    private var toolText: String? {
        CompanionDisplayText.tool(toolName)
    }

    var body: some View {
        if workspaceText != nil || toolText != nil {
            HStack(spacing: 8) {
                if let workspaceText {
                    TinyChip(icon: "folder", text: workspaceText)
                }
                if let toolText {
                    TinyChip(icon: "hammer", text: toolText)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

private struct QuestionOptionsView: View {
    let question: CompanionQuestionPayload
    @EnvironmentObject private var connection: CompanionConnection

    @State private var selected: Set<Int> = []
    @State private var showOther = false
    @State private var textInput = ""

    private let accent = Color(red: 0.38, green: 0.68, blue: 1.0)

    var body: some View {
        if question.options.isEmpty {
            // 纯文本题：直接输入并提交
            VStack(spacing: 8) {
                answerField(placeholder: L10n.t(zh: "输入你的回答", en: "Type your answer"))
                submitButton(title: L10n.t(zh: "提交回答", en: "Submit Answer"), enabled: !trimmed.isEmpty) {
                    connection.sendAnswer(trimmed)
                }
            }
        } else if question.allowsMultipleSelection {
            LazyVStack(spacing: 7) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    optionRow(index: index, option: option, multiSelect: true)
                }
                otherToggleRow
                if showOther {
                    answerField(placeholder: L10n.t(zh: "其他（请输入）", en: "Other (type here)"))
                }
                submitButton(title: L10n.t(zh: "提交所选", en: "Submit Selection"), enabled: canSubmitMulti) {
                    connection.sendAnswer(multiAnswer)
                }
            }
        } else {
            LazyVStack(spacing: 7) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    optionRow(index: index, option: option, multiSelect: false)
                }
                otherToggleRow
                if showOther {
                    VStack(spacing: 8) {
                        answerField(placeholder: L10n.t(zh: "其他（请输入）", en: "Other (type here)"))
                        submitButton(title: L10n.t(zh: "提交", en: "Submit"), enabled: !trimmed.isEmpty) {
                            connection.sendAnswer(trimmed)
                        }
                    }
                }
            }
        }
    }

    private var trimmed: String {
        textInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitMulti: Bool {
        !selected.isEmpty || (showOther && !trimmed.isEmpty)
    }

    // 多选答案与 Mac 端 notch 一致：所选项标签按下标排序后用 ", " 拼接，"其他" 文本追加在末尾。
    private var multiAnswer: String {
        var parts = selected.sorted().compactMap { question.options.indices.contains($0) ? question.options[$0] : nil }
        if showOther && !trimmed.isEmpty {
            parts.append(trimmed)
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func optionRow(index: Int, option: String, multiSelect: Bool) -> some View {
        let isSelected = selected.contains(index)
        Button {
            if multiSelect {
                if isSelected { selected.remove(index) } else { selected.insert(index) }
            } else {
                connection.sendAnswer(option)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if multiSelect {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(isSelected ? accent : .ciForeground.opacity(0.4))
                        .frame(width: 24, alignment: .leading)
                } else {
                    Text("\(index + 1).")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundStyle(accent)
                        .frame(width: 24, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(option)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.ciForeground.opacity(0.86))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if question.descriptions.indices.contains(index) {
                        Text(question.descriptions[index])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.ciForeground.opacity(0.45))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ciForeground.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(isSelected ? accent.opacity(0.5) : Color.ciForeground.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    private var otherToggleRow: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { showOther.toggle() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: showOther ? "chevron.down" : "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 24, alignment: .leading)
                Text(L10n.t(zh: "其他…", en: "Other…"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.ciForeground.opacity(0.7))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ciForeground.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func answerField(placeholder: String) -> some View {
        TextField("", text: $textInput, prompt: Text(placeholder).foregroundColor(.ciForeground.opacity(0.4)), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.ciForeground)
            .lineLimit(1...4)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.ciForeground.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.ciForeground.opacity(0.1)))
            .accessibilityIdentifier("companion.question.textField")
    }

    private func submitButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(enabled ? .black : .ciForeground.opacity(0.4))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(enabled ? accent : Color.ciForeground.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier("companion.question.submit")
    }
}

private struct DiscoveryFill: View {
    @EnvironmentObject private var connection: CompanionConnection

    var body: some View {
        VStack(spacing: 12) {
            DividerLine()
                .padding(.top, 2)

            Text(L10n.t(
                zh: "保持 iPhone 与 Mac 在同一网络，CodeIsland 会持续同步当前状态。",
                en: "Keep your iPhone and Mac on the same network — CodeIsland will keep syncing the current status."
            ))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.ciForeground.opacity(0.42))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)

            IslandButton(
                title: L10n.t(zh: "进入演示模式", en: "Enter Demo Mode"),
                icon: "play.rectangle.fill",
                tint: Color(red: 0.25, green: 0.76, blue: 1.0),
                accessibilityIdentifier: "companion.enterDemoMode"
            ) {
                connection.enterDemoMode()
            }
            .padding(.horizontal, 14)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct CompactIslandBar: View {
    @EnvironmentObject private var connection: CompanionConnection

    var body: some View {
        HStack(spacing: 8) {
            CompanionMascotView(source: connection.latestState?.source ?? "codex", status: compactStatus, size: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                MorphText(
                    text: connection.latestState?.source.uppercased() ?? "CODEISLAND",
                    font: .system(size: 12, weight: .black, design: .rounded),
                    color: .ciForeground
                )
                MorphText(
                    text: compactSubtitle,
                    font: .system(size: 10, weight: .medium, design: .monospaced),
                    color: .ciForeground.opacity(0.52)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Spacer()

            ConnectionDot(active: connection.connectedPeer != nil, browsing: connection.browsing)

            Button {
                connection.browsing ? connection.stop() : connection.start()
            } label: {
                Image(systemName: connection.browsing ? "stop.circle.fill" : "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.ciForeground.opacity(0.86))
                    .frame(width: 38, height: 38)
                    .background(Color.ciForeground.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(connection.browsing ? L10n.t(zh: "停止搜索 Mac", en: "Stop Searching for Mac") : L10n.t(zh: "搜索 Mac", en: "Search for Mac"))
            .accessibilityIdentifier("companion.search.toggle")

            AppearanceMenu()
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 46)
        .background(IslandShellShape().fill(Color.ciSurface))
        .overlay(IslandShellShape().stroke(Color.ciForeground.opacity(0.08), lineWidth: 1))
    }

    private var compactStatus: CompanionStatus {
        connection.latestState?.status ?? (connection.browsing ? .processing : .idle)
    }

    private var compactSubtitle: String {
        if let state = connection.latestState {
            if let toolName = state.toolName, !toolName.isEmpty {
                return CompanionDisplayText.tool(toolName) ?? toolName
            }
            if let workspaceName = state.workspaceName, !workspaceName.isEmpty {
                return CompanionDisplayText.workspace(workspaceName) ?? workspaceName
            }
            return state.status.label
        }
        if let peer = connection.connectedPeer {
            return peer.displayName
        }
        return connection.browsing ? L10n.t(zh: "搜索中", en: "Searching") : L10n.t(zh: "离线", en: "Offline")
    }
}

private struct LiveIslandCard: View {
    let state: CompanionStatePayload
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    MorphText(
                        text: state.source.isEmpty ? "CodeIsland" : state.source.uppercased(),
                        font: .system(size: 15, weight: .bold, design: .rounded),
                        color: .ciForeground
                    )
                    MorphText(
                        text: CompanionDisplayText.subtitle(
                            workspaceName: state.workspaceName,
                            toolName: state.toolName,
                            fallback: L10n.t(zh: "Mac 已连接", en: "Mac Connected")
                        ),
                        font: .system(size: 12, weight: .medium),
                        color: .ciForeground.opacity(0.58)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 10)

                if state.pendingAction != nil {
                    StatusPill(status: state.status)
                } else {
                    HeaderStatusDot(status: state.status)
                }
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            DividerLine()

            VStack(alignment: .leading, spacing: state.question == nil ? 14 : 10) {
                PrimaryMessageView(state: state)

                MetadataChipRow(workspaceName: state.workspaceName, toolName: state.toolName)

                if let question = state.question {
                    QuestionPromptCard(question: question)
                        .environmentObject(connection)
                        .transition(.blurFade.combined(with: .move(edge: .top)))
                }

                CommandRow(state: state)
                    .environmentObject(connection)
                    .environmentObject(liveActivity)
            }
            .padding(14)
            .transition(.blurFade.combined(with: .scale(scale: 0.96, anchor: .top)))
        }
        .background(IslandShellShape().fill(Color.ciSurface))
        .overlay(IslandShellShape().stroke(pendingTint ?? Color.ciForeground.opacity(0.08), lineWidth: pendingTint == nil ? 1 : 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t(zh: "CodeIsland 状态", en: "CodeIsland Status"))
        .accessibilityIdentifier("companion.statusCard")
    }

    // 待处理时给卡片描边与光晕：审批=橙、提问=蓝。
    private var pendingTint: Color? {
        switch state.pendingAction {
        case .approval: return .orange
        case .question: return Color(red: 0.38, green: 0.68, blue: 1.0)
        case nil: return nil
        }
    }
}

private struct QuestionPromptCard: View {
    let question: CompanionQuestionPayload
    @EnvironmentObject private var connection: CompanionConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("?")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.38, green: 0.68, blue: 1.0))
                if let header = question.header, !header.isEmpty {
                    Text(header)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Color(red: 0.38, green: 0.68, blue: 1.0))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.38, green: 0.68, blue: 1.0).opacity(0.14), in: Capsule())
                }
                Spacer()
                if question.total > 1 {
                    Text("\(question.index)/\(question.total)")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.ciForeground.opacity(0.48))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.ciForeground.opacity(0.08), in: Capsule())
                }
            }

            Text(CompanionDisplayText.inlineMarkdown(question.question))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.ciForeground.opacity(0.9))
                .lineLimit(5)

            QuestionOptionsView(question: question)
                .environmentObject(connection)
                .id("\(question.index)/\(question.total)·\(question.question)")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.ciForeground.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.orange.opacity(0.24)))
        .accessibilityIdentifier("companion.questionCard")
    }
}

private struct DiscoveryIsland: View {
    @EnvironmentObject private var connection: CompanionConnection

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    MorphText(
                        text: connection.connectedPeer == nil ? L10n.t(zh: "等待 Mac", en: "Waiting for Mac") : L10n.t(zh: "已连接 Mac", en: "Mac Connected"),
                        font: .system(size: 15, weight: .bold, design: .rounded),
                        color: .ciForeground
                    )
                    MorphText(
                        text: subtitle,
                        font: .system(size: 12, weight: .medium),
                        color: .ciForeground.opacity(0.58)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                ConnectionDot(active: connection.connectedPeer != nil, browsing: connection.browsing)
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            DividerLine()

            VStack(spacing: 10) {
                if connection.discoveredPeers.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.green)
                        Text(connection.browsing ? L10n.t(zh: "正在搜索附近的 CodeIsland", en: "Searching for nearby CodeIsland") : L10n.t(zh: "搜索已停止", en: "Search stopped"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.ciForeground.opacity(0.72))
                        Spacer()
                    }
                    .frame(minHeight: 48)
                } else {
                    ForEach(connection.discoveredPeers, id: \.self) { peer in
                        Button {
                            connection.connect(to: peer)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "macbook")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                    .frame(width: 32, height: 32)
                                    .background(Color.ciForeground.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                Text(peer.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.ciForeground)

                                Spacer()

                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.ciForeground.opacity(0.5))
                            }
                            .frame(minHeight: 48)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
        }
        .background(IslandShellShape().fill(Color.ciSurface))
        .overlay(IslandShellShape().stroke(Color.ciForeground.opacity(0.08), lineWidth: 1))
        .accessibilityIdentifier("companion.discoveryCard")
    }

    private var subtitle: String {
        if let peer = connection.connectedPeer {
            return peer.displayName
        }
        if connection.discoveredPeers.isEmpty {
            return connection.browsing ? L10n.t(zh: "广播握手中", en: "Broadcasting handshake") : L10n.t(zh: "点右上角继续搜索", en: "Tap the top-right icon to search again")
        }
        return L10n.t(zh: "发现 \(connection.discoveredPeers.count) 台设备", en: "Found \(connection.discoveredPeers.count) device(s)")
    }
}

private struct CommandRow: View {
    let state: CompanionStatePayload
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController

    var body: some View {
        VStack(spacing: 8) {
            if connection.isDemoMode {
                HStack(spacing: 8) {
                    IslandButton(
                        title: L10n.t(zh: "切换演示状态", en: "Cycle Demo State"),
                        icon: "arrow.triangle.2.circlepath",
                        tint: Color(red: 0.25, green: 0.76, blue: 1.0),
                        accessibilityIdentifier: "companion.demo.nextState"
                    ) {
                        connection.cycleDemoState()
                    }
                    IslandButton(
                        title: L10n.t(zh: "退出演示", en: "Exit Demo"),
                        icon: "xmark",
                        tint: .red,
                        accessibilityIdentifier: "companion.demo.exit"
                    ) {
                        connection.exitDemoMode()
                    }
                }
            }

            if state.pendingAction == .question {
                HStack(spacing: 8) {
                    IslandButton(
                        title: L10n.t(zh: "在 Mac 回答", en: "Answer on Mac"),
                        icon: "arrow.up.forward.app.fill",
                        tint: Color(red: 0.35, green: 0.85, blue: 0.45),
                        accessibilityIdentifier: "companion.command.focus"
                    ) {
                        connection.send(.focus)
                    }
                    IslandButton(
                        title: L10n.t(zh: "跳过", en: "Skip"),
                        icon: "forward.fill",
                        tint: .orange,
                        accessibilityIdentifier: "companion.command.skip"
                    ) {
                        connection.send(.skipCurrentQuestion)
                    }
                }
                .transition(.blurFade.combined(with: .move(edge: .top)))

                LiveActivityInlineButton(state: state)
            } else {
                HStack(spacing: 8) {
                    IslandButton(
                        title: L10n.t(zh: "打开 Mac 会话", en: "Open Mac Session"),
                        icon: "arrow.up.forward.app.fill",
                        tint: Color(red: 0.35, green: 0.85, blue: 0.45),
                        accessibilityIdentifier: "companion.command.focus"
                    ) {
                        connection.send(.focus)
                    }

                    IslandButton(
                        title: liveActivity.isRunning ? L10n.t(zh: "更新实时活动", en: "Update Live Activity") : L10n.t(zh: "开启实时活动", en: "Start Live Activity"),
                        icon: liveActivity.isRunning ? "arrow.clockwise" : "bolt.horizontal.fill",
                        tint: Color(red: 0.25, green: 0.76, blue: 1.0),
                        accessibilityIdentifier: "companion.liveActivity.primaryButton"
                    ) {
                        liveActivity.startOrUpdate(with: state)
                    }
                }

                if state.pendingAction == .approval {
                    HStack(spacing: 8) {
                        IslandButton(title: L10n.t(zh: "批准", en: "Approve"), icon: "checkmark", tint: .orange, accessibilityIdentifier: "companion.command.approve") {
                            connection.send(.approveCurrentPermission)
                        }
                        IslandButton(title: L10n.t(zh: "拒绝", en: "Deny"), icon: "xmark", tint: .red, accessibilityIdentifier: "companion.command.deny") {
                            connection.send(.denyCurrentPermission)
                        }
                    }
                    .transition(.blurFade.combined(with: .move(edge: .top)))
                }

                if liveActivity.isRunning {
                    LiveActivityInlineButton(state: state)
                }
            }
        }
    }
}

private struct LiveActivityInlineButton: View {
    let state: CompanionStatePayload
    @EnvironmentObject private var liveActivity: LiveActivityController

    var body: some View {
        Button {
            if liveActivity.isRunning {
                liveActivity.stop()
            } else {
                liveActivity.startOrUpdate(with: state)
            }
        } label: {
            Label(
                liveActivity.isRunning ? L10n.t(zh: "停止实时活动", en: "Stop Live Activity") : L10n.t(zh: "同步到实时活动", en: "Sync to Live Activity"),
                systemImage: liveActivity.isRunning ? "stop.circle.fill" : "bolt.horizontal.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(liveActivity.isRunning ? .ciForeground.opacity(0.62) : Color(red: 0.25, green: 0.76, blue: 1.0).opacity(0.86))
            .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("companion.liveActivity.inlineButton")
    }
}

private struct MessageStrip: View {
    let messages: [CompanionMessagePreview]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                    Text(L10n.t(zh: "最近动态", en: "Recent Activity"))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.ciForeground.opacity(0.45))
                    .textCase(.uppercase)
                Rectangle()
                    .fill(.ciForeground.opacity(0.10))
                    .frame(height: 0.5)
            }

            if messages.isEmpty {
                HStack(spacing: 8) {
                    PulseDot(status: .idle)
                    Text(L10n.t(zh: "等待下一条同步消息", en: "Waiting for the next synced message"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.ciForeground.opacity(0.5))
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(messages.suffix(3))) { message in
                        HStack(alignment: .top, spacing: 12) {
                            Text(message.role.label)
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(message.role == .user ? Color.ciSurface : Color.ciForeground)
                                .frame(width: 42, height: 28)
                                .background(message.role == .user ? Color.ciForeground.opacity(0.86) : Color.ciForeground.opacity(0.12), in: Capsule())

                            Text(CompanionDisplayText.messageMarkdown(CompanionDisplayText.message(message.text) ?? message.text, isUser: message.role == .user))
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.ciForeground.opacity(0.76))
                                .lineLimit(6)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .transition(.blurFade.combined(with: .move(edge: .top)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.ciForeground.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.ciForeground.opacity(0.06)))
        .accessibilityIdentifier("companion.messages")
    }
}

// 横屏 hero 的主会话多轮转写，对齐 notch ChatMessageRow（$ 助手 / > 用户）。
// iPhone（横向紧凑）显示最近 1 条，iPad 显示最近 3 条。
private struct HeroTranscript: View {
    let messages: [CompanionMessagePreview]
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var maxMessages: Int { sizeClass == .compact ? 1 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(messages.suffix(maxMessages).enumerated()), id: \.offset) { _, message in
                HStack(alignment: .top, spacing: 6) {
                    Text(message.role == .user ? ">" : "$")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(message.role == .user
                            ? Color(red: 0.3, green: 0.85, blue: 0.4)
                            : Color(red: 0.85, green: 0.47, blue: 0.34))
                    Text(CompanionDisplayText.messageMarkdown(
                        CompanionDisplayText.message(message.text) ?? message.text,
                        isUser: message.role == .user
                    ))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.ciForeground.opacity(0.82))
                    .lineLimit(message.role == .user ? 1 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StandByIsland: View {
    let state: CompanionStatePayload
    let availableSize: CGSize
    @EnvironmentObject private var connection: CompanionConnection
    @EnvironmentObject private var liveActivity: LiveActivityController

    private var sessions: [CompanionSessionPreview] {
        standbySessions(for: state)
    }

    private var activeCount: Int {
        sessions.filter { $0.status != .idle }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    CompanionMascotView(source: state.source, status: state.status, size: 78)

                    VStack(alignment: .leading, spacing: 5) {
                        MorphText(
                            text: sessions.count > 1 ? "CODE ISLAND" : (state.source.isEmpty ? "CODEISLAND" : state.source.uppercased()),
                            font: .system(size: 32, weight: .black, design: .rounded),
                            color: .ciForeground
                        )
                        MorphText(
                            text: sessions.count > 1 ? L10n.t(zh: "\(sessions.count) 个会话 · \(activeCount) 个活跃", en: "\(sessions.count) sessions · \(activeCount) active") : state.status.label,
                            font: .system(size: 22, weight: .semibold, design: .rounded),
                            color: activeCount > 0 ? .green : statusColor(state.status)
                        )
                    }

                    Spacer(minLength: 12)

                    AppearanceMenu()
                }

                if !state.messages.isEmpty {
                    // 主会话多轮转写（对齐 notch：$ 助手 / > 用户）
                    HeroTranscript(messages: state.messages)
                } else {
                    MorphText(
                        text: CompanionDisplayText.workspace(state.workspaceName) ?? L10n.t(zh: "CodeIsland 已连接", en: "CodeIsland Connected"),
                        font: .system(size: 24, weight: .medium, design: .rounded),
                        color: .ciForeground.opacity(0.82),
                        lineLimit: 4
                    )
                    .minimumScaleFactor(0.72)
                }

                HStack(spacing: 10) {
                    if let workspaceText = CompanionDisplayText.workspace(state.workspaceName) {
                        TinyChip(icon: "folder", text: workspaceText)
                    }
                    if let toolText = CompanionDisplayText.tool(state.toolName) {
                        TinyChip(icon: "hammer", text: toolText)
                    }
                }
            }
            .frame(maxWidth: sessions.count > 1 ? availableSize.width * 0.34 : .infinity, alignment: .leading)
            .padding(24)

            DividerLine(vertical: true)

            if sessions.count > 1 {
                StandBySessionBoard(sessions: sessions, activeCount: activeCount)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(20)
            } else {
                VStack(spacing: 10) {
                    IconIslandButton(icon: "arrow.up.forward.app.fill", tint: Color(red: 0.35, green: 0.85, blue: 0.45)) {
                        connection.send(.focus)
                    }
                    IconIslandButton(icon: liveActivity.isRunning ? "arrow.clockwise" : "bolt.horizontal.fill", tint: Color(red: 0.25, green: 0.76, blue: 1.0)) {
                        liveActivity.startOrUpdate(with: state)
                    }
                    if state.pendingAction != nil {
                        IconIslandButton(icon: "checkmark", tint: .orange) {
                            connection.send(.approveCurrentPermission)
                        }
                        IconIslandButton(icon: "xmark", tint: .red) {
                            connection.send(.denyCurrentPermission)
                        }
                    }
                }
                .padding(18)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 260,
            maxHeight: .infinity
        )
    }
}

private enum StandByGrouping: CaseIterable {
    case none, status, cli

    var label: String {
        switch self {
        case .none: return L10n.t(zh: "全部", en: "All")
        case .status: return L10n.t(zh: "按状态", en: "By Status")
        case .cli: return L10n.t(zh: "按 CLI", en: "By CLI")
        }
    }

    var next: StandByGrouping {
        let all = Self.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

private struct StandByGroup: Identifiable {
    let id: String
    let items: [CompanionSessionPreview]
}

private struct StandBySessionBoard: View {
    let sessions: [CompanionSessionPreview]
    let activeCount: Int
    @State private var grouping: StandByGrouping = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(groupedSessions) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            if grouping != .none {
                                Text("\(group.id) · \(group.items.count)")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundStyle(.ciForeground.opacity(0.5))
                            }
                            ForEach(group.items) { session in
                                StandBySessionRow(session: session)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .accessibilityIdentifier("companion.standby.scroll")
        }
        .accessibilityIdentifier("companion.standby.board")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(L10n.t(zh: "会话", en: "Sessions"))
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.ciForeground)
            StandByCountBadge(count: sessions.count, activeCount: activeCount)
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeOut(duration: 0.15)) { grouping = grouping.next }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.3.group")
                    Text(grouping.label)
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.ciForeground.opacity(0.72))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.ciForeground.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("companion.standby.groupToggle")
        }
    }

    private var groupedSessions: [StandByGroup] {
        switch grouping {
        case .none:
            return [StandByGroup(id: L10n.t(zh: "全部", en: "All"), items: sessions)]
        case .status:
            let order: [CompanionStatus] = [.waitingApproval, .waitingQuestion, .running, .processing, .idle]
            return order.compactMap { status in
                let items = sessions.filter { $0.status == status }
                return items.isEmpty ? nil : StandByGroup(id: status.label, items: items)
            }
        case .cli:
            let grouped = Dictionary(grouping: sessions) { $0.source.isEmpty ? "CODEISLAND" : $0.source.uppercased() }
            return grouped.keys.sorted().map { StandByGroup(id: $0, items: grouped[$0] ?? []) }
        }
    }
}

// 会话卡内的多轮转写（紧凑版），$ 助手 / > 用户，含 markdown。
// iPhone（横向紧凑）每卡只显示最近 1 条，iPad 显示最近 3 条。
private struct SessionTranscript: View {
    let messages: [CompanionMessagePreview]
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var maxMessages: Int { sizeClass == .compact ? 1 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(messages.suffix(maxMessages).enumerated()), id: \.offset) { _, message in
                HStack(alignment: .top, spacing: 5) {
                    Text(message.role == .user ? ">" : "$")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(message.role == .user
                            ? Color(red: 0.3, green: 0.85, blue: 0.4)
                            : Color(red: 0.85, green: 0.47, blue: 0.34))
                    Text(CompanionDisplayText.messageMarkdown(
                        CompanionDisplayText.message(message.text) ?? message.text,
                        isUser: message.role == .user
                    ))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.ciForeground.opacity(0.66))
                    .lineLimit(message.role == .user ? 1 : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct StandBySessionRow: View {
    let session: CompanionSessionPreview
    var messageLineLimit: Int = 1

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            CompanionMascotView(source: session.source, status: session.status, size: 32)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                // 身份行：项目名（最左、按状态着色）+ #短id … 右侧 time-ago + 工具徽标
                HStack(spacing: 6) {
                    Text(sessionName)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(statusNameColor)
                        .lineLimit(1)
                        .layoutPriority(2)
                    if let shortId = shortSessionId {
                        Text("#\(shortId)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.ciForeground.opacity(0.4))
                            .fixedSize()
                    }
                    Spacer(minLength: 6)
                    SessionTag(standbyTimeAgo(session.updatedAt))
                    HStack(spacing: 3) {
                        CompanionMascotView(source: session.source, status: session.status, size: 12)
                        Text(CompanionDisplayText.source(session.source))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.ciForeground.opacity(0.7))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.ciForeground.opacity(0.1)))
                    .fixedSize()
                }

                // 多轮转写（每会话最近几条，$ 助手 / > 用户）；旧 Mac 无此数据时回退单条。
                if !session.messages.isEmpty {
                    SessionTranscript(messages: session.messages)
                } else if let message = CompanionDisplayText.message(session.message) {
                    Text(CompanionDisplayText.messageMarkdown(message, isUser: false))
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.ciForeground.opacity(0.6))
                        .lineLimit(messageLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 工作指示行：$ 工具 / $ thinking（对齐 notch SessionCard 底部）
                if session.status != .idle {
                    HStack(spacing: 4) {
                        Text("$")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                        if let tool = CompanionDisplayText.tool(session.toolName) {
                            Text(tool)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.ciForeground.opacity(0.75))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            ThinkingLabel()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background((highlightTint ?? Color.ciForeground).opacity(highlightTint == nil ? 0.055 : 0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(highlightTint?.opacity(0.55) ?? Color.ciForeground.opacity(0.07), lineWidth: highlightTint == nil ? 1 : 1.5))
        .accessibilityIdentifier("companion.standby.sessionRow")
    }

    // 名称按状态着色，对齐 notch SessionCard：运行/处理=绿，待办=橙，空闲=白。
    private var statusNameColor: Color {
        switch session.status {
        case .processing, .running: return Color(red: 0.3, green: 0.85, blue: 0.4)
        case .waitingApproval, .waitingQuestion: return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .idle: return .ciForeground
        }
    }

    // 短会话 id（去掉连字符取末 4 位），对齐 notch 的 #id。
    private var shortSessionId: String? {
        guard let id = session.sessionId else { return nil }
        let clean = id.replacingOccurrences(of: "-", with: "")
        return clean.isEmpty ? nil : String(clean.suffix(4))
    }

    // 会话名称：项目/工作区名优先，缺省回退来源（对齐 notch 以项目名为标题）。
    private var sessionName: String {
        CompanionDisplayText.workspace(session.workspaceName)
            ?? (session.source.isEmpty ? "CODEISLAND" : session.source.uppercased())
    }

    // 待处理状态高亮：审批=橙、提问=蓝；其余不高亮。
    private var highlightTint: Color? {
        switch session.status {
        case .waitingApproval: return .orange
        case .waitingQuestion: return Color(red: 0.38, green: 0.68, blue: 1.0)
        default: return nil
        }
    }
}

// 小标签胶囊，对齐 notch SessionCard 的 SessionTag。
private struct SessionTag: View {
    let text: String
    var color: Color = .ciForeground.opacity(0.7)

    init(_ text: String, color: Color = .ciForeground.opacity(0.7)) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.12)))
    }
}

// 「思考中」标签：一束高光沿文字横向循环扫过（巡逻扫光）。
private struct ThinkingLabel: View {
    var text: String = "thinking"
    private let font = Font.system(size: 12, weight: .medium, design: .monospaced)
    private let period: TimeInterval = 1.6

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = (timeline.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: period)) / period
            Text(text)
                .font(font)
                .foregroundStyle(.ciForeground.opacity(0.35))
                .overlay {
                    GeometryReader { geo in
                        let width = geo.size.width
                        let band = max(22, width * 0.5)
                        LinearGradient(
                            colors: [.clear, .ciForeground.opacity(0.95), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: band)
                        .offset(x: phase * (width + band) - band)
                    }
                    .mask(Text(text).font(font))
                    .allowsHitTesting(false)
                }
        }
        .fixedSize()
    }
}

// 相对时间，对齐 notch timeAgo 格式。
private func standbyTimeAgo(_ date: Date) -> String {
    let seconds = Int(-date.timeIntervalSinceNow)
    if seconds < 60 { return "<1m" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    if seconds < 86400 { return "\(seconds / 3600)h" }
    return "\(seconds / 86400)d"
}

private struct StandByCountBadge: View {
    let count: Int
    let activeCount: Int

    var body: some View {
        Text(activeCount > 0 ? L10n.t(zh: "\(activeCount) 活跃", en: "\(activeCount) active") : L10n.t(zh: "\(count) 总计", en: "\(count) total"))
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(activeCount > 0 ? .green : .ciForeground.opacity(0.64))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background((activeCount > 0 ? Color.green : Color.ciForeground).opacity(0.12), in: Capsule())
    }
}

private func standbySessions(for state: CompanionStatePayload) -> [CompanionSessionPreview] {
    guard !state.sessions.isEmpty else {
        return [
            CompanionSessionPreview(
                sessionId: state.sessionId,
                source: state.source,
                status: state.status,
                toolName: state.toolName,
                workspaceName: state.workspaceName,
                message: state.question?.question ?? state.messages.last?.text,
                updatedAt: state.updatedAt
            )
        ]
    }
    // 待处理项自动聚焦：按状态优先级（审批>提问>运行>处理>空闲）排序，同级按最近更新。
    return state.sessions.sorted { lhs, rhs in
        if lhs.status.priority != rhs.status.priority {
            return lhs.status.priority > rhs.status.priority
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}

// 外观切换菜单：跟随系统 / 浅色 / 深色。
private struct AppearanceMenu: View {
    @AppStorage(appAppearanceStorageKey) private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        Menu {
            Picker(L10n.t(zh: "外观", en: "Appearance"), selection: $appearanceRaw) {
                ForEach(AppAppearance.allCases) { mode in
                    Label(mode.label, systemImage: mode.icon).tag(mode.rawValue)
                }
            }
        } label: {
            Image(systemName: (AppAppearance(rawValue: appearanceRaw) ?? .system).icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.ciForeground.opacity(0.86))
                .frame(width: 38, height: 38)
                .background(Color.ciForeground.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t(zh: "外观", en: "Appearance"))
        .accessibilityIdentifier("companion.appearance.menu")
    }
}

private struct MorphText: View {
    let text: String
    var font: Font = .system(size: 12)
    var color: Color = .ciForeground
    var lineLimit: Int? = 1
    var markdown: Bool = false

    @State private var displayed: String
    @State private var blur: CGFloat = 0
    @State private var generation = 0

    init(text: String, font: Font = .system(size: 12), color: Color = .ciForeground, lineLimit: Int? = 1, markdown: Bool = false) {
        self.text = text
        self.font = font
        self.color = color
        self.lineLimit = lineLimit
        self.markdown = markdown
        _displayed = State(initialValue: text)
    }

    private var renderedText: Text {
        markdown ? Text(CompanionDisplayText.messageMarkdown(displayed, isUser: false)) : Text(displayed)
    }

    var body: some View {
        renderedText
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .blur(radius: blur * 4)
            .opacity(1 - blur * 0.15)
            .animation(CodeIslandMotion.micro, value: blur)
            .onChange(of: text) { _, newText in
                guard newText != displayed else { return }
                // 流式增量（前缀增长/回退）直接更新，不做模糊变形，
                // 避免逐字更新时持续闪烁。仅对“整段换内容”才做变形过渡。
                if newText.hasPrefix(displayed) || displayed.hasPrefix(newText) {
                    generation += 1
                    displayed = newText
                    if blur != 0 { withAnimation(.easeOut(duration: 0.12)) { blur = 0 } }
                    return
                }
                generation += 1
                let current = generation
                withAnimation(.easeOut(duration: 0.1)) { blur = 1 }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    guard current == generation else { return }
                    displayed = newText
                    withAnimation(.easeOut(duration: 0.15)) { blur = 0 }
                }
            }
    }
}

private struct IslandShellShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: 18, style: .continuous).path(in: rect)
    }
}

private struct DividerLine: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Color.ciForeground.opacity(0.12))
            .frame(width: vertical ? 0.5 : nil, height: vertical ? nil : 0.5)
    }
}

private struct StatusPill: View {
    let status: CompanionStatus

    var body: some View {
        HStack(spacing: 6) {
            PulseDot(status: status)
            Text(status.shortLabel)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.ciForeground.opacity(0.9))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.ciForeground.opacity(0.08), in: Capsule())
    }
}

private struct HeaderStatusDot: View {
    let status: CompanionStatus

    var body: some View {
        PulseDot(status: status)
            .frame(width: 30, height: 30)
            .background(Color.ciForeground.opacity(0.07), in: Capsule())
            .accessibilityLabel(status.label)
    }
}

private struct PulseDot: View {
    let status: CompanionStatus

    var body: some View {
        TimelineView(.animation) { timeline in
            let scale = pulseScale(timeline.date.timeIntervalSinceReferenceDate)
            Circle()
                .fill(statusColor(status))
                .frame(width: 8, height: 8)
                .overlay {
                    Circle()
                        .stroke(statusColor(status).opacity(0.5), lineWidth: 1)
                        .scaleEffect(scale)
                        .opacity(max(0, 1.2 - scale))
                }
        }
        .frame(width: 14, height: 14)
    }

    private func pulseScale(_ phase: TimeInterval) -> CGFloat {
        switch status {
        case .idle:
            return 1
        case .processing, .running:
            return 1 + CGFloat((sin(phase * 4.2) + 1) * 0.28)
        case .waitingApproval, .waitingQuestion:
            return 1 + CGFloat((sin(phase * 7.0) + 1) * 0.42)
        }
    }
}

private struct ConnectionDot: View {
    let active: Bool
    let browsing: Bool

    var body: some View {
        PulseDot(status: active ? .running : (browsing ? .processing : .idle))
        .frame(width: 30, height: 30)
        .background(Color.ciForeground.opacity(0.08), in: Capsule())
        .accessibilityLabel(active ? L10n.t(zh: "Mac 已连接", en: "Mac Connected") : (browsing ? L10n.t(zh: "正在搜索 Mac", en: "Searching for Mac") : L10n.t(zh: "Mac 未连接", en: "Mac Not Connected")))
    }
}

private struct TinyChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.ciForeground.opacity(0.64))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.ciForeground.opacity(0.07), in: Capsule())
    }
}

private struct IslandButton: View {
    let title: String
    let icon: String
    let tint: Color
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(tint == .orange ? .black : tint)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(buttonBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(tint.opacity(0.42)))
        }
        .buttonStyle(.plain)
        .optionalAccessibilityIdentifier(accessibilityIdentifier)
    }

    private var buttonBackground: Color {
        tint == .orange ? .orange : tint.opacity(0.20)
    }
}

private extension View {
    @ViewBuilder
    func optionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

private struct IconIslandButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint == .orange ? .black : tint)
                .frame(width: 52, height: 52)
                .background(tint == .orange ? .orange : tint.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(tint.opacity(0.45)))
        }
        .buttonStyle(.plain)
    }
}

private struct DiagnosticStrip: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.12)))
    }
}

private struct LiveActivityDiagnosticStrip: View {
    let message: String
    @EnvironmentObject private var liveActivity: LiveActivityController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "bolt.horizontal.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color(red: 0.35, green: 0.75, blue: 1.0))

            Button {
                liveActivity.stopAll()
            } label: {
                Label(L10n.t(zh: "清理已有实时活动后重试", en: "Clear existing Live Activities and retry"), systemImage: "trash")
                    .font(.caption.weight(.bold))
                    // 这张通知卡固定为深蓝底（两个主题一致），内部文字保持浅色以保证对比。
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(red: 0.10, green: 0.18, blue: 0.24)))
    }
}

private struct BlurFadeModifier: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: active ? 5 : 0)
            .opacity(active ? 0 : 1)
    }
}

private extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(active: true),
            identity: BlurFadeModifier(active: false)
        )
    }
}

private func statusColor(_ status: CompanionStatus) -> Color {
    switch status {
    case .idle:
        return Color(red: 0.55, green: 0.60, blue: 0.68)
    case .processing, .running:
        return Color(red: 0.30, green: 0.85, blue: 0.40)
    case .waitingApproval, .waitingQuestion:
        return Color(red: 1.0, green: 0.55, blue: 0.0)
    }
}

#Preview {
    ContentView()
        .environmentObject(CompanionConnection())
        .environmentObject(LiveActivityController())
}

// MARK: - 外观偏好（跟随系统 / 浅色 / 深色）

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L10n.t(zh: "跟随系统", en: "System")
        case .light: return L10n.t(zh: "浅色", en: "Light")
        case .dark: return L10n.t(zh: "深色", en: "Dark")
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// 传给 `.preferredColorScheme`；nil 表示跟随系统。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// AppStorage 键，App 与各视图共用。
let appAppearanceStorageKey = "appAppearance"

// MARK: - 自适应主题色
//
// 用 dynamic UIColor 按 light/dark 自动解析，视图侧无需注入环境，
// 颜色随 `.preferredColorScheme` 决定的有效外观自动切换。
// 深色保持原有「灵动岛」纯黑观感；浅色为暖白护眼米色。
//
// 定义在 `ShapeStyle where Self == Color` 上：点语法在 `.foregroundStyle(.ciX)`
// / `.fill(.ciX)` 等 ShapeStyle 位置以及纯 `Color` 位置（`color: .ciX`）都能解析。

private enum CITheme {
    /// 应用背景：深色近黑 / 浅色暖米白。
    static let background = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.015, green: 0.016, blue: 0.018, alpha: 1)
            : UIColor(red: 0.945, green: 0.925, blue: 0.880, alpha: 1)
    }

    /// 卡片 / 胶囊表面：深色纯黑 / 浅色暖白（略亮于背景，使卡片浮起）。
    static let surface = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0, green: 0, blue: 0, alpha: 1)
            : UIColor(red: 0.995, green: 0.985, blue: 0.960, alpha: 1)
    }

    /// 主前景（文字 / 图标 / 描边与浅填充的基色）：深色白 / 浅色暖深棕。
    static let foreground = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 1)
            : UIColor(red: 0.16, green: 0.13, blue: 0.10, alpha: 1)
    }
}

extension ShapeStyle where Self == Color {
    static var ciBackground: Color { Color(CITheme.background) }
    static var ciSurface: Color { Color(CITheme.surface) }
    /// 替换原先的 `.white` 与 `.white.opacity(x)`，透明度沿用不变。
    static var ciForeground: Color { Color(CITheme.foreground) }
}
