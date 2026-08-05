import Foundation

/// What happened while attempting to deliver a sanitized observation to Atoll.
public enum ObservationDeliveryOutcome: String, CaseIterable, Codable, Sendable {
    /// Atoll accepted the sanitized observation.
    case delivered

    /// Observation delivery was cancelled before completion.
    case cancelled

    /// The bounded observation delivery deadline elapsed.
    case timedOut

    /// No Atoll observation endpoint was available.
    case hostUnavailable

    /// Atoll had entered pass-through shutdown mode.
    case hostShuttingDown
}

/// The only completion a provider hook can obtain from the runtime.
///
/// The initializer is intentionally not public. The sole non-empty output is
/// Codex's required no-op JSON for `Stop`; no decision can be represented.
public struct ProviderHookCompletion: Equatable, Sendable {
    /// Successful process status that leaves the provider in control.
    public let exitStatus: Int32

    /// Empty pass-through output, or `{}` when Codex requires valid JSON.
    public let standardOutput: Data

    static func continueInOrigin(for event: CodexManagedHookEvent?) -> ProviderHookCompletion {
        ProviderHookCompletion(
            exitStatus: 0,
            standardOutput: event == .stop ? Data("{}".utf8) : Data()
        )
    }
}

/// Makes observation delivery irrelevant to the provider's native flow.
public struct NonOwningHookCompletionPolicy: Sendable {
    /// Creates the stateless completion policy.
    public init() {}

    /// Returns the event-specific no-op completion for every delivery outcome.
    public func completion(
        for event: CodexManagedHookEvent?,
        after outcome: ObservationDeliveryOutcome
    ) -> ProviderHookCompletion {
        _ = outcome
        return .continueInOrigin(for: event)
    }

    /// Retains the Phase 2 unknown-event behavior for historical callers.
    /// Returns the same origin-owned completion for every delivery outcome.
    public func completion(after outcome: ObservationDeliveryOutcome) -> ProviderHookCompletion {
        completion(for: nil, after: outcome)
    }
}
