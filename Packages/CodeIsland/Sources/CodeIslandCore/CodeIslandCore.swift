/// Phase 1 boundary for provider-neutral, sanitized Code Island state.
///
/// The imported upstream models remain quarantined until the safety-first
/// runtime phase replaces their rich payload and provider-specific fields.
public enum CodeIslandCoreBoundary {
    /// Whether the Core API is ready to be linked into the Atoll host.
    public static let isReadyForHostIntegration = false
}
