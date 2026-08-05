import CodeIslandCore

/// Atoll-owned Code Island runtime boundary.
///
/// Phase 2 provides pure adapters and persistence contracts while retaining an
/// inert lifecycle. Provider discovery and activation arrive in later phases.
public final class CodeIslandRuntime: @unchecked Sendable {
    /// Code Island never activates a provider without explicit user consent.
    public static let isEnabledByDefault = false

    /// Whether any provider listener or monitoring service is currently active.
    public var isRunning: Bool { false }

    /// Creates the inert Phase 2 runtime boundary without starting services.
    public init() {}
}
