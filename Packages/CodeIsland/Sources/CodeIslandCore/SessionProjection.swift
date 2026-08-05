import Foundation

/// The content-free reason an agent is waiting at its origin surface.
public enum SessionWaitingReason: String, Codable, Sendable {
    /// The provider's origin surface is waiting for authorization.
    case approval

    /// The provider's origin surface is waiting for information.
    case question
}

/// A provider-neutral transition containing no provider payload content.
public enum SessionTransition: Equatable, Sendable {
    /// A provider session began.
    case started

    /// A provider session performed meaningful work.
    case active

    /// The provider is waiting for its own origin UI.
    case waitingForOrigin(SessionWaitingReason)

    /// The current agent turn completed.
    case completed

    /// A meaningful operation failed.
    case failed

    /// Work was cancelled at the origin.
    case cancelled

    /// The provider session ended.
    case ended

    /// Persistable state produced by this transition.
    public var resultingState: SessionState {
        switch self {
        case .started, .active:
            return .working
        case .waitingForOrigin(.approval):
            return .waitingForApproval
        case .waitingForOrigin(.question):
            return .waitingForQuestion
        case .completed:
            return .recentlyCompleted
        case .failed:
            return .failed
        case .cancelled:
            return .cancelled
        case .ended:
            return .ended
        }
    }
}

/// A transient, already-sanitized observation accepted by the Core projector.
public struct SessionObservation: Equatable, Sendable {
    /// Provider that emitted the lifecycle event.
    public let provider: AgentProvider

    /// Validated provider-owned session key.
    public let sessionID: OpaqueSessionID

    /// Project identity derived without retaining provider content.
    public let project: ProjectIdentity?

    /// Navigation handles derived without retaining provider content.
    public let origin: OriginNavigation?

    /// Content-free lifecycle transition.
    public let transition: SessionTransition

    /// Time the runtime observed the transition.
    public let observedAt: Date

    /// Creates a transient observation accepted by the metadata projector.
    public init(
        provider: AgentProvider,
        sessionID: OpaqueSessionID,
        project: ProjectIdentity?,
        origin: OriginNavigation?,
        transition: SessionTransition,
        observedAt: Date
    ) {
        self.provider = provider
        self.sessionID = sessionID
        self.project = project
        self.origin = origin?.isEmpty == true ? nil : origin
        self.transition = transition
        self.observedAt = observedAt
    }
}

/// Reduces sanitized observations into the sole persistable session shape.
public struct SessionMetadataProjector: Sendable {
    /// Creates a stateless metadata projector.
    public init() {}

    /// Applies an in-order observation while retaining safe identity handles.
    /// Older observations and metadata for a different session are ignored as
    /// prior state.
    public func applying(
        _ observation: SessionObservation,
        to current: SessionMetadata?
    ) -> SessionMetadata {
        let matchingCurrent = current.flatMap { metadata in
            metadata.provider == observation.provider && metadata.sessionID == observation.sessionID
                ? metadata
                : nil
        }

        if let matchingCurrent, observation.observedAt < matchingCurrent.updatedAt {
            return matchingCurrent
        }

        let state = observation.transition.resultingState
        // SessionStart is also emitted for resume/clear, and compaction emits a
        // SessionStart-shaped event for the same provider session. Once a
        // matching projection exists, no lifecycle event may rewrite its
        // original observation time.
        let startedAt = matchingCurrent?.startedAt ?? observation.observedAt

        return SessionMetadata(
            provider: observation.provider,
            sessionID: observation.sessionID,
            project: observation.project ?? matchingCurrent?.project,
            origin: observation.origin ?? matchingCurrent?.origin,
            state: state,
            startedAt: startedAt,
            updatedAt: observation.observedAt,
            endedAt: state.isTerminal ? observation.observedAt : nil
        )
    }
}
