import Foundation

/// Stable preference identifiers; independent of the displayed tab labels.
enum NotchOpenDestination: String, CaseIterable {
    case automatic, lastUsed, home, nowPlaying, shelf, timer, stats, llmUsage, notes, terminal

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

    /// The tab Automatic opens to: Now Playing while music plays, Home otherwise.
    /// Each stands in for the other when it is not available -- Home is gone when
    /// the calendar and the mirror are both off, Now Playing when the media
    /// controls are. Nil when neither is, which leaves the choice to the tab bar.
    static func automaticTab(isPlaying: Bool, available: [Self]) -> Self? {
        let preferred: [Self] = isPlaying ? [.nowPlaying, .home] : [.home, .nowPlaying]
        return preferred.first(where: available.contains)
    }

    /// The notch view this tab opens. Nil for the two modes that are not a tab.
    var notchView: NotchViews? {
        switch self {
        case .home: return .home
        case .nowPlaying: return .nowPlaying
        case .shelf: return .shelf
        case .timer: return .timer
        case .stats: return .stats
        case .llmUsage: return .llmUsage
        case .notes: return .notes
        case .terminal: return .terminal
        case .automatic, .lastUsed: return nil
        }
    }
}

struct StandardNotchTabAvailability {
    var home: Bool
    var nowPlaying: Bool
    var shelf: Bool
    var timer: Bool
    var stats: Bool
    var llmUsage: Bool
    var notes: Bool
    var terminal: Bool

    var available: [NotchOpenDestination] {
        let tabs: [(NotchOpenDestination, Bool)] = [(.home, home), (.nowPlaying, nowPlaying), (.shelf, shelf), (.timer, timer),
         (.stats, stats), (.llmUsage, llmUsage), (.notes, notes), (.terminal, terminal)]
        return tabs.compactMap { $0.1 ? $0.0 : nil }
    }
}
