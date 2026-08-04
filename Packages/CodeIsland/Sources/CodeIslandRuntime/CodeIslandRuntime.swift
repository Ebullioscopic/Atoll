import CodeIslandCore

/// Phase 1 package boundary for Atoll-owned Code Island runtime services.
///
/// The runtime is deliberately inert until the safety-first runtime phase adds
/// explicit, per-provider activation.
public final class CodeIslandRuntime: @unchecked Sendable {
    public static let isEnabledByDefault = false

    public var isRunning: Bool { false }

    public init() {}
}
