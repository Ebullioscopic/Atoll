import CodeIslandCore
import CodeIslandRuntime
import Foundation

@main
struct CodeIslandPhaseSevenPreferencesRegression {
    @MainActor
    static func main() {
        let suiteName = "com.ebullioscopic.atoll.tests.code-island-phase-seven"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated preference suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CodeIslandFeaturePreferenceStore(defaults: defaults)
        let original = store.snapshot
        guard original == .defaults else {
            fatalError("An upgrade with no feature keys must load the approved Phase 7 defaults")
        }
        let compatible = CodeIslandLegacyFeaturePreferences(
            sessionGrouping: .all,
            smartSuppressionEnabled: false,
            completionPresentation: .glance,
            mascotSpeedPercent: 150,
            soundEffectsEnabled: true,
            soundVolumePercent: 65,
            defaultMascotProvider: .codex
        )

        _ = original.importing(compatible)
        guard store.snapshot == original else {
            fatalError("Read-only discovery must not apply compatible preferences")
        }

        store.replace(with: original.importing(compatible))
        let restored = CodeIslandFeaturePreferenceStore(defaults: defaults)
        let persistedKeys = Set(
            (defaults.persistentDomain(forName: suiteName) ?? [:]).keys
        )

        guard restored.snapshot == store.snapshot,
              !persistedKeys.isEmpty,
              persistedKeys.allSatisfy({ $0.hasPrefix("atoll.codeIsland.") }) else {
            fatalError("Atoll must persist an explicitly applied snapshot in its own namespace")
        }
    }
}
