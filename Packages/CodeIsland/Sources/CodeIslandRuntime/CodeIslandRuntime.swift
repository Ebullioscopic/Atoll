import CodeIslandCore

/// Phase 1 package boundary for Atoll-owned Code Island runtime services.
///
/// The runtime is deliberately inert until the safety-first runtime phase adds
/// explicit, per-provider activation.
public final class CodeIslandRuntime: @unchecked Sendable {
    /// Code Island never activates a provider without explicit user consent.
    public static let isEnabledByDefault = false

    /// Whether any provider listener or monitoring service is currently active.
    public var isRunning: Bool { false }

    /// Creates the inert Phase 1 runtime boundary without starting services.
    public init() {}
}
