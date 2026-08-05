import CodeIslandCore
import SwiftUI

/// The two dashboard states available before provider presentation ships.
///
/// Both cases are derived from sanitized host state. They deliberately carry
/// no prompt, response, command, question, tool input, or provider payload.
public enum CodeIslandDashboardState: Equatable, Sendable {
    /// Code Island is present in Atoll, but the provider has not been activated.
    case setupRequired(provider: AgentProvider)

    /// The provider is activated and has no active sessions.
    case idle(provider: AgentProvider)

    /// Provider represented by this dashboard state.
    public var provider: AgentProvider {
        switch self {
        case .setupRequired(let provider), .idle(let provider):
            return provider
        }
    }

    /// Whether the host should direct the user to provider setup.
    public var requiresActivation: Bool {
        if case .setupRequired = self { return true }
        return false
    }
}

/// Atoll-hosted setup and idle dashboard.
///
/// Windowing, tab selection, sizing, and settings navigation remain owned by
/// Atoll. This reusable view only renders a sanitized dashboard state.
public struct CodeIslandDashboardView: View {
    private let state: CodeIslandDashboardState
    private let openSettings: (() -> Void)?

    /// Creates the setup or idle dashboard.
    /// - Parameters:
    ///   - state: Content-free state selected by the Atoll host.
    ///   - openSettings: Optional Atoll-owned settings navigation action.
    public init(
        state: CodeIslandDashboardState,
        openSettings: (() -> Void)? = nil
    ) {
        self.state = state
        self.openSettings = openSettings
    }

    public var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    private var detailText: String {
        switch state {
        case .setupRequired:
            return "Code Island is built into Atoll. Review Codex availability in Settings; no coding-tool configuration has been changed."
        case .idle:
            return "Connected Codex sessions will appear here when they become active."
        }
    }
}
