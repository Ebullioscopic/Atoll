import CodeIslandCore
import SwiftUI

/// Atoll's metadata-only Code Island dashboard state.
///
/// Both cases are derived from sanitized host state. They deliberately carry
/// no prompt, response, command, question, tool input, or provider payload.
public enum CodeIslandDashboardState: Equatable, Sendable {
    /// Code Island is present in Atoll, but the provider has not been activated.
    case setupRequired(provider: AgentProvider)

    /// The provider is activated and has no active sessions.
    case idle(provider: AgentProvider)

    /// Urgency-ordered, metadata-only session rows.
    case sessions(provider: AgentProvider, items: [CodeIslandDashboardItem])

    /// Provider represented by this dashboard state.
    public var provider: AgentProvider {
        switch self {
        case .setupRequired(let provider), .idle(let provider), .sessions(let provider, _):
            return provider
        }
    }

    /// Whether the host should direct the user to provider setup.
    public var requiresActivation: Bool {
        if case .setupRequired = self { return true }
        return false
    }

    /// Safe row projections carried by the active state.
    public var items: [CodeIslandDashboardItem] {
        if case .sessions(_, let items) = self { return items }
        return []
    }
}

/// Atoll-hosted setup, idle, and multi-session dashboard.
///
/// Windowing, tab selection, sizing, and settings navigation remain owned by
/// Atoll. This reusable view only renders a sanitized dashboard state.
public struct CodeIslandDashboardView: View {
    private let state: CodeIslandDashboardState
    private let grouping: CodeIslandDashboardGrouping
    private let openSettings: (() -> Void)?
    private let openOrigin: ((CodeIslandDashboardItem) -> Void)?

    /// Creates the Atoll-native dashboard.
    /// - Parameters:
    ///   - state: Content-free state selected by the Atoll host.
    ///   - openSettings: Optional Atoll-owned settings navigation action.
    public init(
        state: CodeIslandDashboardState,
        grouping: CodeIslandDashboardGrouping = .status,
        openSettings: (() -> Void)? = nil,
        openOrigin: ((CodeIslandDashboardItem) -> Void)? = nil
    ) {
        self.state = state
        self.grouping = grouping
        self.openSettings = openSettings
        self.openOrigin = openOrigin
    }

    public var body: some View {
        Group {
            switch state {
            case .setupRequired, .idle:
                emptyState
            case .sessions(_, let items):
                sessionDashboard(items)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: state.requiresActivation ? "point.3.connected.trianglepath.dotted" : "checkmark.circle")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(state.requiresActivation ? Color.secondary : Color.green)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text(
                    state.requiresActivation
                        ? ci("Set up Code Island")
                        : ci("No active sessions")
                )
                    .font(.headline)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.requiresActivation, let openSettings {
                Button(ci("Open Code Island Settings"), action: openSettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func sessionDashboard(_ items: [CodeIslandDashboardItem]) -> some View {
        let layout = CodeIslandDashboardLayout(items: items, grouping: grouping)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ci("Agent sessions"))
                        .font(.headline)
                    Text(
                        "\(items.count) \(items.count == 1 ? ci("session") : ci("sessions"))"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(layout.groups) { group in
                        if let title = groupTitle(group.label) {
                            Text(title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.top, group.id == layout.groups.first?.id ? 0 : 3)
                        }

                        ForEach(group.items) { item in
                            sessionRow(item)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sessionRow(_ item: CodeIslandDashboardItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbol(item.state))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor(item.state))
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.projectDisplayName ?? ci("Codex session"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(ci("Codex"))
                    Text(verbatim: "·")
                    Text(statusText(item.state))
                    Text(verbatim: "·")
                    Text(item.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if item.origin != nil, let openOrigin {
                Button(ci("Open in origin")) { openOrigin(item) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help(ci("Return to this session in Codex or its terminal"))
                    .accessibilityLabel(ci("Open in origin"))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.projectDisplayName ?? ci("Codex session")), \(statusText(item.state))")
    }

    private var detailText: String {
        switch state {
        case .setupRequired:
            return ci("Code Island is built into Atoll. Review Codex availability in Settings; no coding-tool configuration has been changed.")
        case .idle:
            return ci("Connected Codex sessions will appear here when they become active.")
        case .sessions:
            return ""
        }
    }

    private func sectionTitle(_ section: CodeIslandDashboardSection) -> String {
        switch section {
        case .waiting: return ci("Waiting")
        case .working: return ci("Working")
        case .recent: return ci("Recent")
        }
    }

    private func groupTitle(_ label: CodeIslandDashboardGroupLabel) -> String? {
        switch label {
        case .none: return nil
        case .status(let section): return sectionTitle(section)
        case .provider(.codex): return ci("Codex")
        }
    }

    private func statusText(_ state: SessionState) -> String {
        switch state {
        case .working: return ci("Working")
        case .waitingForApproval: return ci("Needs approval in origin")
        case .waitingForQuestion: return ci("Needs input in origin")
        case .recentlyCompleted: return ci("Completed")
        case .failed: return ci("Failed")
        case .cancelled: return ci("Cancelled")
        case .ended: return ci("Ended")
        }
    }

    private func statusSymbol(_ state: SessionState) -> String {
        switch state {
        case .working: return "ellipsis"
        case .waitingForApproval, .waitingForQuestion: return "exclamationmark"
        case .recentlyCompleted: return "checkmark"
        case .failed: return "xmark"
        case .cancelled, .ended: return "minus"
        }
    }

    private func statusColor(_ state: SessionState) -> Color {
        switch state {
        case .working: return .cyan
        case .waitingForApproval, .waitingForQuestion: return .orange
        case .recentlyCompleted: return .green
        case .failed: return .red
        case .cancelled, .ended: return .secondary
        }
    }
}

private func ci(_ key: String.LocalizationValue) -> String {
    CodeIslandLocalization.string(key)
}
