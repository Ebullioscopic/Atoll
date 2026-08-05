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

/// The only completion a provider hook can obtain from the Phase 2 runtime.
///
/// The initializer is intentionally not public: callers cannot construct a
/// completion carrying provider control output.
public struct ProviderHookCompletion: Equatable, Sendable {
    /// Successful process status that leaves the provider in control.
    public let exitStatus: Int32

    /// Always-empty output; no provider decision can be encoded here.
    public let standardOutput: Data

    static let continueInOrigin = ProviderHookCompletion(
        exitStatus: 0,
        standardOutput: Data()
    )
}

/// Makes observation delivery irrelevant to the provider's native flow.
public struct NonOwningHookCompletionPolicy: Sendable {
    /// Creates the stateless completion policy.
    public init() {}

    /// Returns the same origin-owned completion for every delivery outcome.
    public func completion(after outcome: ObservationDeliveryOutcome) -> ProviderHookCompletion {
        _ = outcome
        return .continueInOrigin
    }
}
