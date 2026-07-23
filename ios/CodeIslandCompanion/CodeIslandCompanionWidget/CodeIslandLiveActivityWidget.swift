import ActivityKit
import SwiftUI
import WidgetKit

struct CodeIslandLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CodeIslandActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state)
                .activityBackgroundTint(Color(red: 0.04, green: 0.05, blue: 0.07))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AgentBadge(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingStatus(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedMessageView(state: context.state)
                }
            } compactLeading: {
                CompactAgentView(state: context.state)
            } compactTrailing: {
                CompactStatusView(state: context.state)
            } minimal: {
                MinimalMascotBadge(state: context.state)
            }
            .keylineTint(statusColor(context.state.status))
        }
    }
}

private struct MinimalMascotBadge: View {
    let state: CodeIslandActivityAttributes.ContentState

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.09, green: 0.10, blue: 0.12))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                )

            SharedMascotView(
                source: state.source,
                status: MascotAgentStatus(state.status),
                size: 18
            )
        }
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .contentShape(Circle())
    }
}

private struct LockScreenActivityView: View {
    let state: CodeIslandActivityAttributes.ContentState

    private var sessions: [CodeIslandSessionActivityPreview] {
        displaySessions(state)
    }

    var body: some View {
        if sessions.count > 1 {
            MultiSessionLockScreenActivityView(state: state, sessions: sessions)
        } else {
            SingleSessionLockScreenActivityView(state: state)
        }
    }
}

private struct SingleSessionLockScreenActivityView: View {
    let state: CodeIslandActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentBadge(state: state)
                Spacer()
                StatusPill(state: state)
            }

            MetadataRow(state: state)

            if !primaryText(state).isEmpty {
                Text(primaryText(state))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(3)
            } else if let toolName = CompanionDisplayText.tool(state.toolName), !toolName.isEmpty {
                Label(toolName, systemImage: "hammer")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            } else {
                Text(L10n.t(zh: "当前没有新的消息", en: "No new messages"))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .padding(16)
    }
}

private struct MultiSessionLockScreenActivityView: View {
    let state: CodeIslandActivityAttributes.ContentState
    let sessions: [CodeIslandSessionActivityPreview]

    private var visibleSessions: ArraySlice<CodeIslandSessionActivityPreview> {
        sessions.prefix(2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                MultiSessionOverviewBadge(state: state)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CODE ISLAND")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(sessionSummary)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                CompactSessionCountPill(count: sessions.count, activeCount: state.activeSessionCount)
            }

            VStack(spacing: 5) {
                ForEach(visibleSessions) { session in
                    MultiSessionLockScreenRow(session: session)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var sessionSummary: String {
        if state.activeSessionCount > 0 {
            return L10n.t(
                zh: "\(sessions.count) 个会话 · \(state.activeSessionCount) 个活跃",
                en: "\(sessions.count) sessions · \(state.activeSessionCount) active"
            )
        }
        return L10n.t(zh: "\(sessions.count) 个会话同步中", en: "Syncing \(sessions.count) sessions")
    }
}

private struct MultiSessionOverviewBadge: View {
    let state: CodeIslandActivityAttributes.ContentState

    var body: some View {
        SharedMascotView(
            source: state.source,
            status: MascotAgentStatus(state.status),
            size: 24
        )
        .frame(width: 28, height: 28)
    }
}

private struct CompactSessionCountPill: View {
    let count: Int
    let activeCount: Int

    var body: some View {
        HStack(spacing: 5) {
            StatusDot(status: activeCount > 0 ? "running" : "idle", size: 7)
            Text(activeCount > 0
                ? L10n.t(zh: "\(activeCount) 活跃", en: "\(activeCount) active")
                : L10n.t(zh: "\(count) 会话", en: "\(count) sessions"))
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.10), in: Capsule())
    }
}

private struct MultiSessionLockScreenRow: View {
    let session: CodeIslandSessionActivityPreview

    var body: some View {
        HStack(spacing: 8) {
            SharedMascotView(
                source: session.source,
                status: MascotAgentStatus(session.status),
                size: 22
            )
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(session.sourceLabel)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let workspace = CompanionDisplayText.workspace(session.workspaceName) {
                        Text(workspace)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.54))
                            .lineLimit(1)
                    }
                }

                Text(sessionText(session))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(session.statusLabel)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(statusColor(session.status))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(statusColor(session.status).opacity(0.18), in: Capsule())
        }
        .frame(height: 38)
        .padding(.horizontal, 9)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct ExpandedMessageView: View {
    let state: CodeIslandActivityAttributes.ContentState

    var body: some View {
        if displaySessions(state).count > 1 {
            ExpandedSessionOverview(state: state)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(state.compactStatusLabel)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(statusColor(state.status))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(statusColor(state.status).opacity(0.18), in: Capsule())
                    Text(CompanionDisplayText.workspace(state.workspaceName) ?? "CodeIsland")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let toolName = CompanionDisplayText.tool(state.toolName), !toolName.isEmpty {
                        Text(toolName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(toolColor(toolName))
                            .lineLimit(1)
                    }
                    if let progress = state.questionProgress {
                        Text(progress)
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.white.opacity(0.62))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.10), in: Capsule())
                    }
                }
                Text(primaryText(state))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ExpandedSessionOverview: View {
    let state: CodeIslandActivityAttributes.ContentState

    private var sessions: [CodeIslandSessionActivityPreview] {
        displaySessions(state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(L10n.t(zh: "\(sessions.count) 个会话", en: "\(sessions.count) sessions"))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.12), in: Capsule())
                if state.activeSessionCount > 0 {
                    Text(L10n.t(zh: "\(state.activeSessionCount) 活跃", en: "\(state.activeSessionCount) active"))
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.14), in: Capsule())
                }
                if let progress = state.questionProgress {
                    Text(progress)
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
                Spacer(minLength: 0)
            }

            SessionStackView(sessions: sessions, compact: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CompactAgentView: View {
    let state: CodeIslandActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            SharedMascotView(source: state.source, status: MascotAgentStatus(state.status), size: 20)
            Text(displaySessions(state).count > 1 ? "\(displaySessions(state).count)" : state.sourceLabel)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct ExpandedStatusDot: View {
    let state: CodeIslandActivityAttributes.ContentState

    var body: some View {
        StatusDot(status: state.status, size: 8)
            .padding(8)
            .background(statusColor(state.status).opacity(0.22), in: Circle())
            .accessibilityLabel(state.statusLabel)
    }
}

private struct ExpandedTrailingStatus: View {
    let state: CodeIslandActivityAttributes.ContentState

    var body: some View {
        if displaySessions(state).count > 1 {
            SessionCountPill(count: displaySessions(state).count, activeCount: state.activeSessionCount)
        } else {
            ExpandedStatusDot(state: state)
        }
    }
}

private struct CompactStatusView: View {
    let state: CodeIslandActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 3) {
            StatusDot(status: state.status, size: 6)
            Text(displaySessions(state).count > 1 ? L10n.t(zh: "会话", en: "Sessions") : state.compactStatusLabel)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
    }
}

private struct AgentBadge: View {
    let state: CodeIslandActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            SharedMascotView(source: state.source, status: MascotAgentStatus(state.status), size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.sourceLabel)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(CompanionDisplayText.subtitle(
                    workspaceName: state.workspaceName,
                    toolName: state.toolName,
                    fallback: "CodeIsland"
                ))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
        }
    }
}

private struct SessionCountPill: View {
    let count: Int
    let activeCount: Int

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(status: activeCount > 0 ? "running" : "idle", size: 8)
            Text(activeCount > 0
                ? L10n.t(zh: "\(activeCount) 个活跃", en: "\(activeCount) active")
                : L10n.t(zh: "\(count) 个会话", en: "\(count) sessions"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.10), in: Capsule())
    }
}

private struct StatusPill: View {
    let state: CodeIslandActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(status: state.status, size: 8)
            Text(state.statusLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusColor(state.status).opacity(0.2), in: Capsule())
    }
}

private struct SessionStackView: View {
    let sessions: [CodeIslandSessionActivityPreview]
    var compact: Bool

    var body: some View {
        VStack(spacing: compact ? 4 : 6) {
            ForEach(sessions.prefix(compact ? 2 : 3)) { session in
                SessionPreviewRow(session: session, compact: compact)
            }
        }
    }
}

private struct SessionPreviewRow: View {
    let session: CodeIslandSessionActivityPreview
    var compact: Bool

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            SharedMascotView(
                source: session.source,
                status: MascotAgentStatus(session.status),
                size: compact ? 18 : 22
            )
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(session.sourceLabel)
                        .font(.system(size: compact ? 10 : 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let workspace = CompanionDisplayText.workspace(session.workspaceName) {
                        Text(workspace)
                            .font(.system(size: compact ? 9 : 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
                Text(sessionText(session))
                    .font(.system(size: compact ? 9 : 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(session.statusLabel)
                .font(.system(size: compact ? 9 : 10, weight: .black, design: .rounded))
                .foregroundStyle(statusColor(session.status))
                .padding(.horizontal, compact ? 6 : 7)
                .padding(.vertical, compact ? 3 : 4)
                .background(statusColor(session.status).opacity(0.16), in: Capsule())
        }
        .padding(.horizontal, compact ? 0 : 8)
        .padding(.vertical, compact ? 0 : 6)
        .background(compact ? Color.clear : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StatusDot: View {
    let status: String
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: size, height: size)
    }
}

private struct MetadataRow: View {
    let state: CodeIslandActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if let workspaceName = CompanionDisplayText.workspace(state.workspaceName), !workspaceName.isEmpty {
                CompactChip(icon: "folder", text: workspaceName)
            }
            if let toolName = CompanionDisplayText.tool(state.toolName), !toolName.isEmpty {
                CompactChip(icon: "hammer", text: toolName, tint: toolColor(toolName))
            }
            Spacer(minLength: 0)
        }
    }
}

private struct CompactChip: View {
    let icon: String
    let text: String
    var tint: Color = .white.opacity(0.64)

    var body: some View {
        Label {
            Text(text)
                .lineLimit(1)
        } icon: {
            Image(systemName: icon)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.08), in: Capsule())
    }
}

private func compactStatusText(_ state: CodeIslandActivityAttributes.ContentState) -> String {
    switch state.status {
    case "waitingApproval": return L10n.t(zh: "批", en: "OK")
    case "waitingQuestion": return L10n.t(zh: "问", en: "Q")
    case "processing": return L10n.t(zh: "跑", en: "Run")
    case "running": return state.toolName?.prefix(1).uppercased() ?? L10n.t(zh: "跑", en: "Run")
    default: return ""
    }
}

private func primaryText(_ state: CodeIslandActivityAttributes.ContentState) -> String {
    if state.status == "waitingQuestion", let questionText = CompanionDisplayText.message(state.questionText), !questionText.isEmpty {
        return questionText
    }
    if let message = CompanionDisplayText.message(state.message), !message.isEmpty {
        return message
    }
    if let toolName = CompanionDisplayText.tool(state.toolName), !toolName.isEmpty {
        return toolName
    }
    return state.statusLabel
}

private func displaySessions(_ state: CodeIslandActivityAttributes.ContentState) -> [CodeIslandSessionActivityPreview] {
    guard !state.sessions.isEmpty else {
        return [
            CodeIslandSessionActivityPreview(
                sessionId: nil,
                source: state.source,
                status: state.status,
                toolName: state.toolName,
                workspaceName: state.workspaceName,
                message: primaryText(state),
                updatedAt: state.updatedAt
            )
        ]
    }
    return state.sessions
}

private func sessionText(_ session: CodeIslandSessionActivityPreview) -> String {
    if let message = CompanionDisplayText.message(session.message), !message.isEmpty {
        return message
    }
    if let toolName = CompanionDisplayText.tool(session.toolName), !toolName.isEmpty {
        return toolName
    }
    return session.statusLabel
}

private func toolColor(_ tool: String) -> Color {
    switch tool.lowercased() {
    case "bash": return Color(red: 0.4, green: 1.0, blue: 0.5)
    case "edit", "write": return Color(red: 0.5, green: 0.7, blue: 1.0)
    case "read": return Color(red: 0.9, green: 0.8, blue: 0.4)
    case "grep", "glob": return Color(red: 0.8, green: 0.6, blue: 1.0)
    case "agent": return Color(red: 1.0, green: 0.6, blue: 0.4)
    default: return .white.opacity(0.7)
    }
}

private func statusColor(_ status: String) -> Color {
    switch status {
    case "waitingApproval", "waitingQuestion":
        return Color(red: 1.0, green: 0.74, blue: 0.25)
    case "processing", "running":
        return Color(red: 0.30, green: 0.72, blue: 1.0)
    default:
        return Color(red: 0.55, green: 0.60, blue: 0.68)
    }
}
