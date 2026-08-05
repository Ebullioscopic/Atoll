import CodeIslandCore

/// The highest provider behavior backed by its verified contract.
public enum ProviderCapability: String, Codable, Sendable {
    /// Session lifecycle, meaningful transitions, and origin handoff only.
    case monitoring

    /// Monitoring plus verified non-owning approval and question observation.
    case nativeAttention
}

/// A typed product limitation that settings can present without free-form drift.
public enum ProviderLimitation: String, Codable, Hashable, Sendable {
    /// Provider activation is unavailable until the activation phase.
    case activationDeferred

    /// The safe observer cannot see interactive provider questions.
    case interactiveQuestionObservationUnavailable

    /// Codex's documented PostToolUse wire format has no stable success flag.
    case toolFailureObservationUnavailable
}

/// The capability statement exposed for one provider.
public struct ProviderCapabilityProfile: Equatable, Sendable {
    /// Provider described by the profile.
    public let provider: AgentProvider

    /// Highest end-to-end behavior verified for the provider.
    public let verifiedCapability: ProviderCapability

    /// Whether the current product phase permits activation.
    public let isActivationAvailable: Bool

    /// Typed limitations that host settings can present.
    public let limitations: Set<ProviderLimitation>

    /// Creates one explicit provider capability statement.
    public init(
        provider: AgentProvider,
        verifiedCapability: ProviderCapability,
        isActivationAvailable: Bool,
        limitations: Set<ProviderLimitation>
    ) {
        self.provider = provider
        self.verifiedCapability = verifiedCapability
        self.isActivationAvailable = isActivationAvailable
        self.limitations = limitations
    }
}

/// Capability claims are data, not assumptions spread throughout the runtime.
public struct ProviderCapabilityRegistry: Sendable {
    private let profiles: [AgentProvider: ProviderCapabilityProfile]

    /// Creates a registry, keeping the final profile for duplicate providers.
    public init(profiles: [ProviderCapabilityProfile]) {
        self.profiles = Dictionary(
            profiles.map { ($0.provider, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// Returns the explicit profile for a provider, or `nil` when unverified.
    public func profile(for provider: AgentProvider) -> ProviderCapabilityProfile? {
        profiles[provider]
    }

    /// Phase 2 verifies Codex lifecycle monitoring while deliberately excluding
    /// its app-server question responder. Activation is introduced later.
    public static let phaseTwo = ProviderCapabilityRegistry(profiles: [
        ProviderCapabilityProfile(
            provider: .codex,
            verifiedCapability: .monitoring,
            isActivationAvailable: false,
            limitations: [
                .activationDeferred,
                .interactiveQuestionObservationUnavailable,
                .toolFailureObservationUnavailable,
            ]
        ),
    ])
}
