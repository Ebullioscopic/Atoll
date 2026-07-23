import SwiftUI
import WatchKit

struct WatchContentView: View {
    @EnvironmentObject private var connection: WatchConnection
    @State private var selectedPage = WatchPage.initial

    var body: some View {
        Group {
            if let state = connection.latestState {
                TabView(selection: $selectedPage) {
                    WatchStatusPage(state: state)
                        .tag(WatchPage.status)
                    WatchMessagePage(state: state)
                        .tag(WatchPage.message)
                    WatchActionsPage(state: state)
                        .tag(WatchPage.actions)
                    WatchActivityPage(messages: state.messages)
                        .tag(WatchPage.activity)
                }
                .tabViewStyle(.verticalPage)
                .onChange(of: selectedPage) { _, _ in
                    WKInterfaceDevice.current().play(.click)
                }
            } else {
                WatchEmptyView(error: connection.lastError)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private enum WatchPage: Hashable {
    case status
    case message
    case actions
    case activity

    static var initial: WatchPage {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-CodeIslandWatchSmokePage"),
              arguments.indices.contains(flagIndex + 1)
        else {
            return .status
        }

        switch arguments[flagIndex + 1].lowercased() {
        case "message":
            return .message
        case "actions":
            return .actions
        case "activity":
            return .activity
        default:
            return .status
        }
#else
        return .status
#endif
    }
}

private struct WatchStatusPage: View {
    let state: CompanionStatePayload

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 430
            let mascotSize: CGFloat = isCompact ? 64 : 90
            VStack(spacing: isCompact ? 5 : 10) {
                Spacer(minLength: 0)

                SharedMascotView(
                    source: state.source,
                    status: MascotAgentStatus(state.status.rawValue),
                    size: mascotSize
                )
                .frame(height: mascotSize + 4)

                VStack(spacing: 2) {
                    Text(CompanionDisplayText.source(state.source))
                        .font(.system(size: isCompact ? 18 : 25, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(CompanionDisplayText.subtitle(
                        workspaceName: state.workspaceName,
                        toolName: state.toolName,
                        fallback: "Mac"
                    ))
                    .font(.system(size: isCompact ? 11 : 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
                }

                WatchStatusBadge(status: state.status)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 8)
            .padding(.top, isCompact ? 24 : 14)
            .padding(.bottom, isCompact ? 8 : 10)
        }
    }
}

private struct WatchMessagePage: View {
    let state: CompanionStatePayload
    @EnvironmentObject private var connection: WatchConnection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchPageTitle(title: messageTitle, systemImage: messageIcon, color: messageColor)

                Text(primaryText)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 5) {
                    WatchChip(text: CompanionDisplayText.workspace(state.workspaceName) ?? L10n.t(zh: "工作区", en: "Workspace"), icon: "folder")
                    if let toolText = CompanionDisplayText.tool(state.toolName) {
                        WatchChip(text: toolText, icon: "hammer")
                    }
                }

                if let question = state.question, !question.options.isEmpty {
                    WatchQuestionOptions(question: question)
                }
            }
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .padding(.horizontal, 5)
        )
    }

    private var primaryText: String {
        if let question = state.question?.question {
            return question
        }
        if let message = CompanionDisplayText.message(state.messages.last?.text) {
            return message
        }
        return L10n.t(zh: "当前没有新的消息", en: "No new messages")
    }

    private var messageTitle: String {
        state.pendingAction == .question ? L10n.t(zh: "需要回答", en: "Needs Answer") : L10n.t(zh: "当前消息", en: "Current Message")
    }

    private var messageIcon: String {
        state.pendingAction == .question ? "questionmark.bubble.fill" : "text.bubble.fill"
    }

    private var messageColor: Color {
        state.pendingAction == .question ? .orange : .blue
    }
}

private struct WatchActionsPage: View {
    let state: CompanionStatePayload
    @EnvironmentObject private var connection: WatchConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WatchPageTitle(title: L10n.t(zh: "快捷操作", en: "Quick Actions"), systemImage: "bolt.fill", color: .green)

            Spacer(minLength: 0)

            WatchActionStrip(state: state)

            Spacer(minLength: 0)
        }
        .padding(10)
    }
}

private struct WatchActivityPage: View {
    let messages: [CompanionMessagePreview]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                WatchPageTitle(title: L10n.t(zh: "最近动态", en: "Recent Activity"), systemImage: "waveform.path.ecg", color: .purple)
                WatchRecentView(messages: messages)
            }
            .padding(10)
        }
    }
}

private struct WatchPageTitle: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.16), in: Capsule())
    }
}

private struct WatchIslandHeader: View {
    let state: CompanionStatePayload

    var body: some View {
        HStack(spacing: 8) {
            SharedMascotView(source: state.source, status: MascotAgentStatus(state.status.rawValue), size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(CompanionDisplayText.source(state.source))
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(CompanionDisplayText.subtitle(
                    workspaceName: state.workspaceName,
                    toolName: state.toolName,
                    fallback: "Mac"
                ))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
            WatchStatusBadge(status: state.status, compact: true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.055), in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct WatchQuestionOptions: View {
    let question: CompanionQuestionPayload
    @EnvironmentObject private var connection: WatchConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let header = question.header, !header.isEmpty {
                    Text(header)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.18), in: Capsule())
                }

                Text("\(question.index + 1)/\(question.total)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.10), in: Capsule())
            }

            ForEach(Array(question.options.prefix(4).enumerated()), id: \.offset) { index, option in
                Button {
                    connection.send(.answerQuestion, answer: option)
                } label: {
                    HStack(spacing: 7) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.blue)
                            .frame(width: 18, alignment: .leading)

                        Text(option)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.90))
                            .lineLimit(2)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WatchSessionCard: View {
    let state: CompanionStatePayload
    @EnvironmentObject private var connection: WatchConnection

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                SharedMascotView(source: state.source, status: MascotAgentStatus(state.status.rawValue), size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(CompanionDisplayText.source(state.source))
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text(CompanionDisplayText.subtitle(
                        workspaceName: state.workspaceName,
                        toolName: state.toolName,
                        fallback: "Mac"
                    ))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
                WatchStatusBadge(status: state.status)
            }

            Text(primaryText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                WatchChip(text: CompanionDisplayText.workspace(state.workspaceName) ?? L10n.t(zh: "工作区", en: "Workspace"), icon: "folder")
                if let toolText = CompanionDisplayText.tool(state.toolName) {
                    WatchChip(text: toolText, icon: "hammer")
                }
            }

            if let question = state.question, !question.options.isEmpty {
                WatchQuestionOptions(question: question)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(statusColor(state.status).opacity(0.38), lineWidth: 1)
        )
    }

    private var primaryText: String {
        if let question = state.question?.question {
            return question
        }
        if let message = CompanionDisplayText.message(state.messages.last?.text) {
            return message
        }
        return L10n.t(zh: "当前没有新的消息", en: "No new messages")
    }
}

private struct WatchActionStrip: View {
    let state: CompanionStatePayload
    @EnvironmentObject private var connection: WatchConnection

    var body: some View {
        VStack(spacing: 6) {
            Button {
                connection.send(.focus)
            } label: {
                WatchActionLabel(title: L10n.t(zh: "打开 Mac", en: "Open on Mac"), systemImage: "arrow.up.forward.app.fill", color: .green)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            if state.pendingAction == .approval {
                HStack(spacing: 6) {
                    Button {
                        connection.send(.approveCurrentPermission)
                    } label: {
                        WatchActionLabel(title: L10n.t(zh: "批准", en: "Approve"), systemImage: "checkmark", color: .orange)
                    }
                    .buttonStyle(.plain)

                    Button {
                        connection.send(.denyCurrentPermission)
                    } label: {
                        WatchActionLabel(title: L10n.t(zh: "拒绝", en: "Deny"), systemImage: "xmark", color: .red)
                    }
                    .buttonStyle(.plain)
                }
            } else if state.pendingAction == .question {
                Button {
                    connection.send(.focus)
                } label: {
                    WatchActionLabel(title: L10n.t(zh: "去 iPhone 回答", en: "Answer on iPhone"), systemImage: "questionmark.bubble.fill", color: .blue)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct WatchRecentView: View {
    let messages: [CompanionMessagePreview]

    var body: some View {
        let recent = messages.suffix(2)

        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t(zh: "最近动态", en: "Recent Activity"))
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))

                ForEach(Array(recent.enumerated()), id: \.offset) { _, message in
                    HStack(alignment: .top, spacing: 6) {
                        Text(message.role.label)
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.white.opacity(message.role == .user ? 0.9 : 0.22), in: Capsule())

                        Text(CompanionDisplayText.message(message.text) ?? message.text)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(4)
                    }
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct WatchEmptyView: View {
    let error: String?

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 220
            ScrollView {
                VStack(alignment: .center, spacing: isCompact ? 8 : 11) {
                    HStack(spacing: 7) {
                        SharedMascotView(source: "codex", status: .idle, size: isCompact ? 26 : 30)
                        Text("Code Island")
                            .font(.system(size: isCompact ? 14 : 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.055), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )

                    SharedMascotView(source: "codex", status: .idle, size: isCompact ? 48 : 56)

                    Text(L10n.t(zh: "等待 iPhone 同步", en: "Waiting for iPhone to sync"))
                        .font(.system(size: isCompact ? 15 : 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(error ?? L10n.t(zh: "打开 iPhone 上的 Code Island，并连接 Mac", en: "Open Code Island on your iPhone and connect to a Mac"))
                        .font(.system(size: isCompact ? 10 : 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.76)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, isCompact ? 4 : 8)
            }
        }
    }
}

private struct WatchChip: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.68))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: Capsule())
    }
}

private struct WatchStatusBadge: View {
    let status: CompanionStatus
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor(status))
                .frame(width: compact ? 7 : 8, height: compact ? 7 : 8)
            if !compact {
                Text(status.shortLabel)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, compact ? 7 : 8)
        .padding(.vertical, compact ? 6 : 7)
        .background(statusColor(status).opacity(0.16), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.label)
    }
}

private struct WatchActionLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(color.opacity(0.34), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.72), lineWidth: 1)
            )
            .accessibilityLabel(title)
    }
}

private func statusColor(_ status: CompanionStatus) -> Color {
    switch status {
    case .idle:
        return Color(red: 0.62, green: 0.68, blue: 0.76)
    case .processing, .running:
        return Color(red: 0.25, green: 0.86, blue: 0.38)
    case .waitingApproval, .waitingQuestion:
        return Color.orange
    }
}
