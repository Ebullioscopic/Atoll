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
    private let openSettings: (() -> Void)?
    private let openOrigin: ((CodeIslandDashboardItem) -> Void)?

    /// Creates the Atoll-native dashboard.
    /// - Parameters:
    ///   - state: Content-free state selected by the Atoll host.
    ///   - openSettings: Optional Atoll-owned settings navigation action.
    public init(
        state: CodeIslandDashboardState,
        openSettings: (() -> Void)? = nil,
        openOrigin: ((CodeIslandDashboardItem) -> Void)? = nil
    ) {
        self.state = state
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
                Text(state.requiresActivation ? "Set up Code Island" : "No active sessions")
                    .font(.headline)

                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if state.requiresActivation, let openSettings {
                Button("Open Code Island Settings", action: openSettings)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func sessionDashboard(_ items: [CodeIslandDashboardItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent sessions")
                        .font(.headline)
                    Text("\(items.count) \(items.count == 1 ? "session" : "sessions")")
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
                    ForEach([
                        CodeIslandDashboardSection.waiting,
                        .working,
                        .recent,
                    ], id: \.rawValue) { section in
                        let sectionItems = items.filter { $0.section == section }
                        if !sectionItems.isEmpty {
                            Text(sectionTitle(section))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.top, section == .waiting ? 0 : 3)

                            ForEach(sectionItems) { item in
                                sessionRow(item)
                            }
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
                Text(item.projectDisplayName ?? "Codex session")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text("Codex")
                    Text("·")
                    Text(statusText(item.state))
                    Text("·")
                    Text(item.updatedAt, style: .relative)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if item.origin != nil, let openOrigin {
                Button("Open in origin") { openOrigin(item) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Return to this session in Codex or its terminal")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.projectDisplayName ?? "Codex session"), \(statusText(item.state))")
    }

    private var detailText: String {
        switch state {
        case .setupRequired:
            return "Code Island is built into Atoll. Review Codex availability in Settings; no coding-tool configuration has been changed."
        case .idle:
            return "Connected Codex sessions will appear here when they become active."
        case .sessions:
            return ""
        }
    }

    private func sectionTitle(_ section: CodeIslandDashboardSection) -> String {
        switch section {
        case .waiting: return "Waiting"
        case .working: return "Working"
        case .recent: return "Recent"
        }
    }

    private func statusText(_ state: SessionState) -> String {
        switch state {
        case .working: return "Working"
        case .waitingForApproval: return "Needs approval in origin"
        case .waitingForQuestion: return "Needs input in origin"
        case .recentlyCompleted: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .ended: return "Ended"
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
