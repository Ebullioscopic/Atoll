import CodeIslandCore
import Foundation

/// The highest-priority Atoll activity currently occupying the notch.
public enum CodeIslandNotchOccupancy: Equatable, Sendable {
    /// No other Atoll activity needs the compact presentation area.
    case available

    /// Media, timers, recording, transfers, or similar noncritical activity.
    case noncritical

    /// A system, lock-screen, or privacy presentation that must win.
    case systemOrPrivacy
}

/// Result of checking the visible origin against one particular session.
public enum CodeIslandExactOriginMatch: Equatable, Sendable {
    /// Atoll positively matched the exact visible tab, pane, or native window.
    case exactSession

    /// Atoll positively observed a different origin surface.
    case different

    /// The origin could not be checked precisely. This never suppresses UI.
    case unknown
}

/// Session-navigation handles observed from the currently visible origin.
///
/// This is intentionally shaped like `OriginNavigation` but represents a
/// transient observation, never a value persisted by the runtime.
public struct CodeIslandVisibleOrigin: Equatable, Sendable {
    public let applicationBundleIdentifier: String?
    public let terminalSessionIdentifier: String?
    public let workspaceIdentifier: String?
    public let paneIdentifier: String?
    public let tty: String?

    public init(
        applicationBundleIdentifier: String?,
        terminalSessionIdentifier: String?,
        workspaceIdentifier: String?,
        paneIdentifier: String?,
        tty: String?
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.terminalSessionIdentifier = terminalSessionIdentifier
        self.workspaceIdentifier = workspaceIdentifier
        self.paneIdentifier = paneIdentifier
        self.tty = tty
    }
}

/// Conservative exact-session matcher used by Atoll's AppKit adapter.
public struct CodeIslandExactOriginMatcher: Sendable {
    public init() {}

    /// Application identity alone is never enough for positive suppression.
    /// A terminal-session ID or TTY is treated as globally precise. A pane ID
    /// also requires matching application identity, and no known handle may
    /// conflict.
    public func match(
        expected: OriginNavigation?,
        visible: CodeIslandVisibleOrigin?
    ) -> CodeIslandExactOriginMatch {
        guard let expected, let visible else { return .unknown }

        if let expectedBundle = expected.applicationBundleIdentifier,
           let visibleBundle = visible.applicationBundleIdentifier,
           expectedBundle.caseInsensitiveCompare(visibleBundle) != .orderedSame {
            return .different
        }
        if expected.applicationBundleIdentifier != nil,
           visible.applicationBundleIdentifier == nil {
            return .unknown
        }

        let allHandles: [(String?, String?)] = [
            (expected.terminalSessionIdentifier, visible.terminalSessionIdentifier),
            (expected.workspaceIdentifier, visible.workspaceIdentifier),
            (expected.paneIdentifier, visible.paneIdentifier),
            (expected.tty, visible.tty),
        ]
        if allHandles.contains(where: { expectedValue, visibleValue in
            guard let expectedValue, let visibleValue else { return false }
            return expectedValue != visibleValue
        }) {
            return .different
        }

        func handlesMatch(_ expectedValue: String?, _ visibleValue: String?) -> Bool {
            guard let expectedValue, let visibleValue else { return false }
            return expectedValue == visibleValue
        }
        let terminalSessionMatches = handlesMatch(
            expected.terminalSessionIdentifier,
            visible.terminalSessionIdentifier
        )
        let ttyMatches = handlesMatch(expected.tty, visible.tty)
        let applicationMatches: Bool = {
            guard let expectedBundle = expected.applicationBundleIdentifier,
                  let visibleBundle = visible.applicationBundleIdentifier else {
                return false
            }
            return expectedBundle.caseInsensitiveCompare(visibleBundle) == .orderedSame
        }()
        let paneMatches = applicationMatches
            && handlesMatch(expected.paneIdentifier, visible.paneIdentifier)

        return terminalSessionMatches || ttyMatches || paneMatches
            ? .exactSession
            : .unknown
    }
}

/// Atoll-owned facts used to evaluate one sanitized presentation intent.
public struct CodeIslandPresentationContext: Equatable, Sendable {
    public let occupancy: CodeIslandNotchOccupancy
    public let supportsSecondaryIndicator: Bool
    public let originMatch: CodeIslandExactOriginMatch

    public init(
        occupancy: CodeIslandNotchOccupancy,
        supportsSecondaryIndicator: Bool,
        originMatch: CodeIslandExactOriginMatch
    ) {
        self.occupancy = occupancy
        self.supportsSecondaryIndicator = supportsSecondaryIndicator
        self.originMatch = originMatch
    }
}

/// Content-free visual treatment selected by Atoll.
public enum CodeIslandPresentationStyle: Equatable, Sendable {
    /// Persistent live activity; secondary is allowed only by an explicit layout.
    case compact(isSecondary: Bool)

    /// Brief mascot animation for a newly observed session.
    case sessionStarted

    /// Persistent origin handoff for a provider-owned blocking request.
    case attention(SessionWaitingReason)

    /// Brief successful completion pop-out.
    case completed

    /// Brief failure pop-out for providers with a verified failure signal.
    case failed
}

/// Pure policy result. Atoll's host owns timing, tab selection, and rendering.
public enum CodeIslandPresentationDisposition: Equatable, Sendable {
    case present(CodeIslandPresentationStyle)
    case enqueue
    case suppress
    case stateOnly
    case dismiss
}

/// Deterministic, provider-neutral presentation policy.
///
/// It accepts sanitized intents and Atoll occupancy facts only. It cannot open
/// windows, change tabs, play sounds, or activate another application.
public struct CodeIslandPresentationPolicy: Sendable {
    public init() {}

    public func disposition(
        for intent: CodeIslandActivityIntent,
        context: CodeIslandPresentationContext
    ) -> CodeIslandPresentationDisposition {
        switch intent.kind {
        case .processing:
            switch context.occupancy {
            case .available:
                return .present(.compact(isSecondary: false))
            case .noncritical where context.supportsSecondaryIndicator:
                return .present(.compact(isSecondary: true))
            case .noncritical, .systemOrPrivacy:
                return .stateOnly
            }

        case .sessionStarted:
            return context.occupancy == .available
                ? .present(.sessionStarted)
                : .enqueue

        case .attentionRequired(let reason):
            guard context.originMatch != .exactSession else { return .suppress }
            return context.occupancy == .systemOrPrivacy
                ? .enqueue
                : .present(.attention(reason))

        case .completed:
            guard context.originMatch != .exactSession else { return .suppress }
            return context.occupancy == .available
                ? .present(.completed)
                : .enqueue

        case .failed:
            guard context.originMatch != .exactSession else { return .suppress }
            return context.occupancy == .available
                ? .present(.failed)
                : .enqueue

        case .dismissed:
            return .dismiss
        }
    }

    /// Orders deferred work by semantic urgency, timestamp, then identity.
    public func orderedQueue(
        _ intents: [CodeIslandActivityIntent]
    ) -> [CodeIslandActivityIntent] {
        intents.sorted { lhs, rhs in
            let lhsRank = rank(lhs.kind)
            let rhsRank = rank(rhs.kind)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
            if lhs.subject.provider != rhs.subject.provider {
                return lhs.subject.provider.rawValue < rhs.subject.provider.rawValue
            }
            return lhs.subject.sessionID.rawValue < rhs.subject.sessionID.rawValue
        }
    }

    private func rank(_ kind: CodeIslandActivityIntentKind) -> Int {
        switch kind {
        case .attentionRequired:
            return 0
        case .failed:
            return 1
        case .completed:
            return 2
        case .sessionStarted:
            return 3
        case .processing:
            return 4
        case .dismissed:
            return 5
        }
    }
}
