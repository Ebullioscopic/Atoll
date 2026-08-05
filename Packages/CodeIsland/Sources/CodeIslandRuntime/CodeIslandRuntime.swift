import CodeIslandCore

/// Atoll-owned Code Island runtime boundary.
///
/// Phase 4 adds read-only discovery and consent-bound activation machinery,
/// while retaining an inert provider lifecycle. No live listener or installer
/// is constructed until a provider completes the Phase 5 rollout gate.
public final class CodeIslandRuntime: @unchecked Sendable {
    /// Code Island never activates a provider without explicit user consent.
    public static let isEnabledByDefault = false

    /// Whether any provider listener or monitoring service is currently active.
    public var isRunning: Bool { false }

    /// Creates the inert runtime boundary without starting services.
    public init() {}
}
