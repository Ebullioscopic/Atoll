import Foundation

/// User-facing ways Atoll can group the same urgency-ordered dashboard rows.
public enum CodeIslandDashboardGrouping: String, Codable, CaseIterable, Hashable, Sendable {
    /// Show one urgency-ordered list without section headers.
    case all

    /// Group rows into waiting, working, and recent sections.
    case status

    /// Group rows by provider while preserving urgency order within each group.
    case provider
}

/// Stable dashboard groups ordered by user urgency.
public enum CodeIslandDashboardSection: Int, Equatable, Sendable {
    /// The provider is blocked at its own origin surface.
    case waiting = 0

    /// The provider is actively running or processing.
    case working = 1

    /// A recent terminal transition remains useful as short-lived context.
    case recent = 2
}

/// The metadata-only row model accepted by CodeIslandUI.
///
/// This type cannot carry prompt text, commands, answers, or raw hook payloads.
public struct CodeIslandDashboardItem: Equatable, Identifiable, Sendable {
    /// Stable provider/session identity for SwiftUI diffing and handoff.
    public var id: String { "\(provider.rawValue):\(sessionID.rawValue)" }

    public let provider: AgentProvider
    public let sessionID: OpaqueSessionID
    public let projectDisplayName: String?
    public let origin: OriginNavigation?
    public let state: SessionState
    public let section: CodeIslandDashboardSection
    public let startedAt: Date
    public let updatedAt: Date

    init(metadata: SessionMetadata, section: CodeIslandDashboardSection) {
        provider = metadata.provider
        sessionID = metadata.sessionID
        projectDisplayName = metadata.project?.displayName
        origin = metadata.origin
        state = metadata.state
        self.section = section
        startedAt = metadata.startedAt
        updatedAt = metadata.updatedAt
    }
}

/// Produces the dashboard's deterministic urgency ordering from safe metadata.
public struct CodeIslandDashboardProjection: Equatable, Sendable {
    public let items: [CodeIslandDashboardItem]

    /// Filters ended/cancelled sessions and orders waiting, working, then recent.
    public init(sessions: [SessionMetadata]) {
        items = sessions.compactMap(Self.item).sorted(by: Self.precedes)
    }

    private static func item(for metadata: SessionMetadata) -> CodeIslandDashboardItem? {
        let section: CodeIslandDashboardSection
        switch metadata.state {
        case .waitingForApproval, .waitingForQuestion:
            section = .waiting
        case .working:
            section = .working
        case .recentlyCompleted, .failed:
            section = .recent
        case .cancelled, .ended:
            return nil
        }
        return CodeIslandDashboardItem(metadata: metadata, section: section)
    }

    private static func precedes(
        _ lhs: CodeIslandDashboardItem,
        _ rhs: CodeIslandDashboardItem
    ) -> Bool {
        if lhs.section != rhs.section {
            return lhs.section.rawValue < rhs.section.rawValue
        }

        if lhs.updatedAt != rhs.updatedAt {
            switch lhs.section {
            case .waiting:
                // Surface the session that has waited longest first.
                return lhs.updatedAt < rhs.updatedAt
            case .working, .recent:
                return lhs.updatedAt > rhs.updatedAt
            }
        }

        if lhs.provider != rhs.provider {
            return lhs.provider.rawValue < rhs.provider.rawValue
        }
        return lhs.sessionID.rawValue < rhs.sessionID.rawValue
    }
}
