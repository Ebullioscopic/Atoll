/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import CodeIslandCore
import CodeIslandRuntime
import Combine
import Foundation

/// Atoll's sole persistence owner for Code Island feature preferences.
///
/// The package supplies a content-free value type; this application store owns
/// every UserDefaults key and never reads or writes standalone CodeIsland keys.
@MainActor
final class CodeIslandFeaturePreferenceStore: ObservableObject {
    static let shared = CodeIslandFeaturePreferenceStore()

    @Published private(set) var snapshot: CodeIslandFeaturePreferences

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = Self.load(from: defaults)
    }

    /// Replaces the complete content-free snapshot after a local settings edit
    /// or the user's explicit guided-adoption confirmation.
    func replace(with preferences: CodeIslandFeaturePreferences) {
        let normalized = Self.normalized(preferences)
        defaults.set(normalized.dashboardGrouping.rawValue, forKey: Key.dashboardGrouping)
        defaults.set(normalized.retentionMinutes, forKey: Key.retentionMinutes)
        defaults.set(
            normalized.presentation.smartSuppressionEnabled,
            forKey: Key.smartSuppression
        )
        defaults.set(
            normalized.presentation.completionPresentation.rawValue,
            forKey: Key.completionPresentation
        )
        defaults.set(normalized.mascotsEnabled, forKey: Key.mascotsEnabled)
        defaults.set(normalized.mascotSpeedPercent, forKey: Key.mascotSpeed)
        defaults.set(normalized.soundEffectsEnabled, forKey: Key.soundEffects)
        defaults.set(normalized.soundVolumePercent, forKey: Key.soundVolume)
        defaults.set(normalized.sessionStartSoundEnabled, forKey: Key.soundSessionStart)
        defaults.set(normalized.completionSoundEnabled, forKey: Key.soundCompletion)
        defaults.set(normalized.failureSoundEnabled, forKey: Key.soundFailure)
        defaults.set(normalized.attentionSoundEnabled, forKey: Key.soundAttention)
        snapshot = normalized
    }

    /// Applies one Atoll settings edit and persists the resulting normalized
    /// snapshot through the same ownership boundary as guided adoption.
    func update(
        _ edit: (inout CodeIslandFeaturePreferences) -> Void
    ) {
        var preferences = snapshot
        edit(&preferences)
        replace(with: preferences)
    }

    private static func load(from defaults: UserDefaults) -> CodeIslandFeaturePreferences {
        let fallback = CodeIslandFeaturePreferences.defaults
        let grouping = defaults.string(forKey: Key.dashboardGrouping)
            .flatMap(CodeIslandDashboardGrouping.init(rawValue:))
            ?? fallback.dashboardGrouping
        let completion = defaults.string(forKey: Key.completionPresentation)
            .flatMap(CodeIslandCompletionPresentation.init(rawValue:))
            ?? fallback.presentation.completionPresentation

        return normalized(CodeIslandFeaturePreferences(
            dashboardGrouping: grouping,
            retentionMinutes: integer(
                in: defaults,
                key: Key.retentionMinutes,
                fallback: fallback.retentionMinutes
            ),
            presentation: CodeIslandPresentationPreferences(
                smartSuppressionEnabled: boolean(
                    in: defaults,
                    key: Key.smartSuppression,
                    fallback: fallback.presentation.smartSuppressionEnabled
                ),
                completionPresentation: completion
            ),
            mascotsEnabled: boolean(
                in: defaults,
                key: Key.mascotsEnabled,
                fallback: fallback.mascotsEnabled
            ),
            mascotSpeedPercent: integer(
                in: defaults,
                key: Key.mascotSpeed,
                fallback: fallback.mascotSpeedPercent
            ),
            soundEffectsEnabled: boolean(
                in: defaults,
                key: Key.soundEffects,
                fallback: fallback.soundEffectsEnabled
            ),
            soundVolumePercent: integer(
                in: defaults,
                key: Key.soundVolume,
                fallback: fallback.soundVolumePercent
            ),
            sessionStartSoundEnabled: boolean(
                in: defaults,
                key: Key.soundSessionStart,
                fallback: fallback.sessionStartSoundEnabled
            ),
            completionSoundEnabled: boolean(
                in: defaults,
                key: Key.soundCompletion,
                fallback: fallback.completionSoundEnabled
            ),
            failureSoundEnabled: boolean(
                in: defaults,
                key: Key.soundFailure,
                fallback: fallback.failureSoundEnabled
            ),
            attentionSoundEnabled: boolean(
                in: defaults,
                key: Key.soundAttention,
                fallback: fallback.attentionSoundEnabled
            )
        ))
    }

    private static func normalized(
        _ preferences: CodeIslandFeaturePreferences
    ) -> CodeIslandFeaturePreferences {
        let retention = [0, 10, 30, 60, 120].contains(preferences.retentionMinutes)
            ? preferences.retentionMinutes
            : CodeIslandFeaturePreferences.defaults.retentionMinutes
        return CodeIslandFeaturePreferences(
            dashboardGrouping: preferences.dashboardGrouping,
            retentionMinutes: retention,
            presentation: preferences.presentation,
            mascotsEnabled: preferences.mascotsEnabled,
            mascotSpeedPercent: preferences.mascotSpeedPercent,
            soundEffectsEnabled: preferences.soundEffectsEnabled,
            soundVolumePercent: preferences.soundVolumePercent,
            sessionStartSoundEnabled: preferences.sessionStartSoundEnabled,
            completionSoundEnabled: preferences.completionSoundEnabled,
            failureSoundEnabled: preferences.failureSoundEnabled,
            attentionSoundEnabled: preferences.attentionSoundEnabled
        )
    }

    private static func boolean(
        in defaults: UserDefaults,
        key: String,
        fallback: Bool
    ) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func integer(
        in defaults: UserDefaults,
        key: String,
        fallback: Int
    ) -> Int {
        defaults.object(forKey: key) == nil ? fallback : defaults.integer(forKey: key)
    }

    private enum Key {
        static let dashboardGrouping = "atoll.codeIsland.dashboardGrouping"
        static let retentionMinutes = "atoll.codeIsland.retentionMinutes"
        static let smartSuppression = "atoll.codeIsland.smartSuppression"
        static let completionPresentation = "atoll.codeIsland.completionPresentation"
        static let mascotsEnabled = "atoll.codeIsland.mascotsEnabled"
        static let mascotSpeed = "atoll.codeIsland.mascotSpeedPercent"
        static let soundEffects = "atoll.codeIsland.soundEffectsEnabled"
        static let soundVolume = "atoll.codeIsland.soundVolumePercent"
        static let soundSessionStart = "atoll.codeIsland.sound.sessionStart"
        static let soundCompletion = "atoll.codeIsland.sound.completion"
        static let soundFailure = "atoll.codeIsland.sound.failure"
        static let soundAttention = "atoll.codeIsland.sound.attention"
    }
}
