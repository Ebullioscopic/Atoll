import Foundation
import CodeIslandCore

/// Content-free identity attached to an Atoll presentation request.
public struct CodeIslandActivitySubject: Equatable, Sendable {
    /// Provider that owns the origin session.
    public let provider: AgentProvider

    /// Opaque provider-owned identity used only for correlation.
    public let sessionID: OpaqueSessionID

    /// Sanitized project label, when one is known.
    public let projectDisplayName: String?

    /// Navigation-only handles for returning to the originating surface.
    public let origin: OriginNavigation?

    /// Creates a subject from the metadata-only session projection.
    public init(metadata: SessionMetadata) {
        provider = metadata.provider
        sessionID = metadata.sessionID
        projectDisplayName = metadata.project?.displayName
        origin = metadata.origin
    }
}

/// A presentation request emitted by Code Island for Atoll to arbitrate.
public enum CodeIslandActivityIntentKind: Equatable, Sendable {
    /// Briefly acknowledge that a new session started.
    case sessionStarted

    /// Resume or retain compact processing presentation.
    case processing

    /// Keep a content-free handoff visible while the origin needs attention.
    case attentionRequired(SessionWaitingReason)

    /// Offer a short completion presentation.
    case completed

    /// Offer a short failure presentation.
    case failed

    /// Remove presentation for a cancelled or ended session.
    case dismissed
}

/// A sanitized intent. It contains no provider payload or user decision.
public struct CodeIslandActivityIntent: Equatable, Sendable {
    /// Requested presentation behavior.
    public let kind: CodeIslandActivityIntentKind

    /// Minimal subject needed for correlation and origin handoff.
    public let subject: CodeIslandActivitySubject

    /// Timestamp of the metadata transition that created the intent.
    public let occurredAt: Date

    /// Creates a content-free activity intent.
    public init(
        kind: CodeIslandActivityIntentKind,
        subject: CodeIslandActivitySubject,
        occurredAt: Date
    ) {
        self.kind = kind
        self.subject = subject
        self.occurredAt = occurredAt
    }
}

/// Converts sanitized state transitions into requests without presenting UI.
///
/// The adapter never changes an Atoll view. Atoll remains responsible for
/// arbitration, suppression, tab selection, sound, and timing.
public struct CodeIslandActivityIntentAdapter: Sendable {
    /// Creates the stateless adapter.
    public init() {}

    /// Returns an intent only when the sanitized state meaningfully changes.
    public func intent(
        for current: SessionMetadata,
        previous: SessionMetadata?
    ) -> CodeIslandActivityIntent? {
        let matchingPrevious = previous.flatMap { metadata in
            metadata.provider == current.provider && metadata.sessionID == current.sessionID
                ? metadata
                : nil
        }

        guard matchingPrevious?.state != current.state else { return nil }

        let kind: CodeIslandActivityIntentKind
        switch current.state {
        case .working:
            kind = matchingPrevious == nil ? .sessionStarted : .processing
        case .waitingForApproval:
            kind = .attentionRequired(.approval)
        case .waitingForQuestion:
            kind = .attentionRequired(.question)
        case .recentlyCompleted:
            kind = .completed
        case .failed:
            kind = .failed
        case .cancelled, .ended:
            kind = .dismissed
        }

        return CodeIslandActivityIntent(
            kind: kind,
            subject: CodeIslandActivitySubject(metadata: current),
            occurredAt: current.updatedAt
        )
    }
}
