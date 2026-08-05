/// Boundary marker for provider-neutral, sanitized Code Island state.
public enum CodeIslandCoreBoundary {
    /// Phase 2 exposes only metadata-safe contracts and is ready for the host
    /// shell to consume in Phase 3. This does not activate any provider.
    public static let isReadyForHostIntegration = true
}
