import CodeIslandCore
import Foundation

/// A content-free label token for one dashboard group.
public enum CodeIslandDashboardGroupLabel: Equatable, Sendable {
    case none
    case status(CodeIslandDashboardSection)
    case provider(AgentProvider)
}

/// One stable group of already-projected dashboard rows.
public struct CodeIslandDashboardGroup: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: CodeIslandDashboardGroupLabel
    public let items: [CodeIslandDashboardItem]
}

/// Converts urgency-ordered metadata rows into the user's selected grouping.
/// It never re-sorts rows and cannot carry session content beyond the public
/// `CodeIslandDashboardItem` seam.
public struct CodeIslandDashboardLayout: Equatable, Sendable {
    public let groups: [CodeIslandDashboardGroup]

    public init(
        items: [CodeIslandDashboardItem],
        grouping: CodeIslandDashboardGrouping
    ) {
        switch grouping {
        case .all:
            groups = items.isEmpty ? [] : [
                CodeIslandDashboardGroup(id: "all", label: .none, items: items),
            ]

        case .status:
            groups = [
                CodeIslandDashboardSection.waiting,
                .working,
                .recent,
            ].compactMap { section in
                let matching = items.filter { $0.section == section }
                guard !matching.isEmpty else { return nil }
                return CodeIslandDashboardGroup(
                    id: "status:\(section.rawValue)",
                    label: .status(section),
                    items: matching
                )
            }

        case .provider:
            groups = AgentProvider.allCases.compactMap { provider in
                let matching = items.filter { $0.provider == provider }
                guard !matching.isEmpty else { return nil }
                return CodeIslandDashboardGroup(
                    id: "provider:\(provider.rawValue)",
                    label: .provider(provider),
                    items: matching
                )
            }
        }
    }
}
