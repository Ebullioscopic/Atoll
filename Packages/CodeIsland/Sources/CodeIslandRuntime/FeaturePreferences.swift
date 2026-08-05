import CodeIslandCore
import Foundation

public extension CodeIslandLegacyFeaturePreferences {
    /// Whether the first merged release can apply at least one discovered
    /// value. The legacy default-provider value is intentionally excluded:
    /// Codex is the only active provider, so importing it would be a no-op.
    var hasImportableFeaturePreferences: Bool {
        sessionGrouping != nil
            || smartSuppressionEnabled != nil
            || completionPresentation != nil
            || mascotSpeedPercent != nil
            || soundEffectsEnabled != nil
            || soundVolumePercent != nil
    }
}

/// The complete, content-free preference snapshot that Atoll supplies to Code Island.
///
/// Persistence remains owned by the Atoll application. Keeping this value type in the
/// package gives the host, policy, and tests one explicit boundary without allowing the
/// subsystem to create a second settings lifecycle.
public struct CodeIslandFeaturePreferences: Equatable, Sendable {
    public var dashboardGrouping: CodeIslandDashboardGrouping
    public var retentionMinutes: Int
    public var presentation: CodeIslandPresentationPreferences
    public var mascotsEnabled: Bool
    public var mascotSpeedPercent: Int
    public var soundEffectsEnabled: Bool
    public var soundVolumePercent: Int
    public var sessionStartSoundEnabled: Bool
    public var completionSoundEnabled: Bool
    public var failureSoundEnabled: Bool
    public var attentionSoundEnabled: Bool

    public static let defaults = CodeIslandFeaturePreferences()

    public init(
        dashboardGrouping: CodeIslandDashboardGrouping = .status,
        retentionMinutes: Int = 30,
        presentation: CodeIslandPresentationPreferences = CodeIslandPresentationPreferences(),
        mascotsEnabled: Bool = true,
        mascotSpeedPercent: Int = 100,
        soundEffectsEnabled: Bool = false,
        soundVolumePercent: Int = 50,
        sessionStartSoundEnabled: Bool = true,
        completionSoundEnabled: Bool = true,
        failureSoundEnabled: Bool = true,
        attentionSoundEnabled: Bool = true
    ) {
        self.dashboardGrouping = dashboardGrouping
        self.retentionMinutes = retentionMinutes
        self.presentation = presentation
        self.mascotsEnabled = mascotsEnabled
        self.mascotSpeedPercent = min(max(mascotSpeedPercent, 0), 300)
        self.soundEffectsEnabled = soundEffectsEnabled
        self.soundVolumePercent = min(max(soundVolumePercent, 0), 100)
        self.sessionStartSoundEnabled = sessionStartSoundEnabled
        self.completionSoundEnabled = completionSoundEnabled
        self.failureSoundEnabled = failureSoundEnabled
        self.attentionSoundEnabled = attentionSoundEnabled
    }

    /// Returns a new snapshot containing only the legacy settings whitelisted by
    /// read-only discovery. The Atoll host decides whether the user consented to
    /// apply this mapping; this function performs no persistence or system writes.
    public func importing(
        _ legacy: CodeIslandLegacyFeaturePreferences
    ) -> CodeIslandFeaturePreferences {
        let grouping: CodeIslandDashboardGrouping
        switch legacy.sessionGrouping {
        case .all: grouping = .all
        case .status: grouping = .status
        case .provider: grouping = .provider
        case nil: grouping = dashboardGrouping
        }

        let completion: CodeIslandCompletionPresentation
        switch legacy.completionPresentation {
        case .expand: completion = .expand
        case .glance: completion = .glance
        case .off: completion = .off
        case nil: completion = presentation.completionPresentation
        }

        return CodeIslandFeaturePreferences(
            dashboardGrouping: grouping,
            retentionMinutes: retentionMinutes,
            presentation: CodeIslandPresentationPreferences(
                smartSuppressionEnabled: legacy.smartSuppressionEnabled
                    ?? presentation.smartSuppressionEnabled,
                completionPresentation: completion
            ),
            mascotsEnabled: mascotsEnabled,
            mascotSpeedPercent: legacy.mascotSpeedPercent ?? mascotSpeedPercent,
            soundEffectsEnabled: legacy.soundEffectsEnabled ?? soundEffectsEnabled,
            soundVolumePercent: legacy.soundVolumePercent ?? soundVolumePercent,
            sessionStartSoundEnabled: sessionStartSoundEnabled,
            completionSoundEnabled: completionSoundEnabled,
            failureSoundEnabled: failureSoundEnabled,
            attentionSoundEnabled: attentionSoundEnabled
        )
    }
}
