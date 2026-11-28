import Foundation

/// Stable preference identifiers; independent of the displayed tab labels.
enum NotchOpenDestination: String, CaseIterable {
    case automatic, lastUsed, home, shelf, timer, stats, llmUsage, notes, terminal

    var isFixed: Bool { self != .automatic && self != .lastUsed }

    static func selected(_ raw: String, rememberLast: Bool) -> Self {
        guard !raw.isEmpty else { return rememberLast ? .lastUsed : .automatic }
        return Self(rawValue: raw) ?? .automatic
    }

    /// Returns nil for the existing automatic and last-used paths.
    func resolved(available: [Self]) -> Self? {
        guard isFixed else { return nil }
        return available.contains(self) ? self : (available.contains(.home) ? .home : available.first)
    }
}

struct StandardNotchTabAvailability {
    var home: Bool
    var shelf: Bool
    var timer: Bool
    var stats: Bool
    var llmUsage: Bool
    var notes: Bool
    var terminal: Bool

    var available: [NotchOpenDestination] {
        let tabs: [(NotchOpenDestination, Bool)] = [(.home, home), (.shelf, shelf), (.timer, timer), (.stats, stats),
         (.llmUsage, llmUsage), (.notes, notes), (.terminal, terminal)]
        return tabs.compactMap { $0.1 ? $0.0 : nil }
    }
}
