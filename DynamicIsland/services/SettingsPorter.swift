/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import Defaults
import SwiftUI

// MARK: - File-format constants

enum SettingsPorter {

    static let fileExtension = "atollsettings"
    static let utType = "com.ebullioscopic.atoll.settings"

    // MARK: - Export

    /// Captures current `Defaults` values and encodes them as pretty-printed JSON.
    static func exportData() throws -> Data {
        let snapshot = captureSnapshot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    // MARK: - Import

    /// Decodes a previously exported JSON blob and writes every value back into `Defaults`.
    /// Unknown / missing keys are silently skipped so files from older Atoll versions still import.
    static func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(AtollSettingsSnapshot.self, from: data)
        applySnapshot(snapshot)
    }

    // MARK: - Snapshot capture

    // swiftlint:disable:next function_body_length
    private static func captureSnapshot() -> AtollSettingsSnapshot {
        AtollSettingsSnapshot(
            // General / Behavior
            menubarIcon: Defaults[.menubarIcon],
            showOnAllDisplays: Defaults[.showOnAllDisplays],
            automaticallySwitchDisplay: Defaults[.automaticallySwitchDisplay],
            hideDynamicIslandFromScreenCapture: Defaults[.hideDynamicIslandFromScreenCapture],
            minimumHoverDuration: Defaults[.minimumHoverDuration],
            enableHaptics: Defaults[.enableHaptics],
            openNotchOnHover: Defaults[.openNotchOnHover],
            extendHoverArea: Defaults[.extendHoverArea],
            externalDisplayStyle: Defaults[.externalDisplayStyle],
            hideNonNotchUntilHover: Defaults[.hideNonNotchUntilHover],
            enableMinimalisticUI: Defaults[.enableMinimalisticUI],
            updateChannel: Defaults[.updateChannel],
            logLevel: Defaults[.logLevel],
            notchHeightMode: Defaults[.notchHeightMode],
            nonNotchHeightMode: Defaults[.nonNotchHeightMode],
            nonNotchHeight: Defaults[.nonNotchHeight],
            notchHeight: Defaults[.notchHeight],
            openNotchWidth: Defaults[.openNotchWidth],
            closedNotchWidth: Defaults[.closedNotchWidth],
            customizePhysicalNotchWidth: Defaults[.customizePhysicalNotchWidth],
            // Appearance
            showEmojis: Defaults[.showEmojis],
            showMirror: Defaults[.showMirror],
            mirrorShape: Defaults[.mirrorShape],
            settingsIconInNotch: Defaults[.settingsIconInNotch],
            lightingEffect: Defaults[.lightingEffect],
            accentColor: Defaults[.accentColor],
            enableShadow: Defaults[.enableShadow],
            cornerRadiusScaling: Defaults[.cornerRadiusScaling],
            useModernCloseAnimation: Defaults[.useModernCloseAnimation],
            showNotHumanFace: Defaults[.showNotHumanFace],
            tileShowLabels: Defaults[.tileShowLabels],
            showCalendar: Defaults[.showCalendar],
            hideCompletedReminders: Defaults[.hideCompletedReminders],
            hideAllDayEvents: Defaults[.hideAllDayEvents],
            sliderColor: Defaults[.sliderColor],
            playerColorTinting: Defaults[.playerColorTinting],
            useMusicVisualizer: Defaults[.useMusicVisualizer],
            visualizerBarCount: Defaults[.visualizerBarCount],
            enableWaveformScrubber: Defaults[.enableWaveformScrubber],
            colorExtractionMode: Defaults[.colorExtractionMode],
            enableWobbleAnimation: Defaults[.enableWobbleAnimation],
            // Gestures
            enableGestures: Defaults[.enableGestures],
            closeGestureEnabled: Defaults[.closeGestureEnabled],
            gestureSensitivity: Defaults[.gestureSensitivity],
            enableHorizontalMusicGestures: Defaults[.enableHorizontalMusicGestures],
            musicGestureBehavior: Defaults[.musicGestureBehavior],
            reverseSwipeGestures: Defaults[.reverseSwipeGestures],
            reverseScrollGestures: Defaults[.reverseScrollGestures],
            // Media Playback
            coloredSpectrogram: Defaults[.coloredSpectrogram],
            enableRealTimeWaveform: Defaults[.enableRealTimeWaveform],
            enableSneakPeek: Defaults[.enableSneakPeek],
            sneakPeekStyles: Defaults[.sneakPeekStyles],
            showSneakPeekOnTrackChange: Defaults[.showSneakPeekOnTrackChange],
            enableFullscreenMediaDetection: Defaults[.enableFullscreenMediaDetection],
            parallaxEffectIntensity: Defaults[.parallaxEffectIntensity],
            waitInterval: Defaults[.waitInterval],
            showShuffleAndRepeat: Defaults[.showShuffleAndRepeat],
            showMediaOutputControl: Defaults[.showMediaOutputControl],
            alwaysShowLockScreenVolume: Defaults[.alwaysShowLockScreenVolume],
            musicSkipBehavior: Defaults[.musicSkipBehavior],
            musicControlWindowEnabled: Defaults[.musicControlWindowEnabled],
            showStandardMediaControls: Defaults[.showStandardMediaControls],
            autoHideInactiveNotchMediaPlayer: Defaults[.autoHideInactiveNotchMediaPlayer],
            enableLockScreenMediaWidget: Defaults[.enableLockScreenMediaWidget],
            enableLockScreenWeatherWidget: Defaults[.enableLockScreenWeatherWidget],
            enableLockScreenFocusWidget: Defaults[.enableLockScreenFocusWidget],
            siriResponsivenessMode: Defaults[.siriResponsivenessMode],
            enableLockScreenReminderWidget: Defaults[.enableLockScreenReminderWidget],
            enableLockScreenTimerWidget: Defaults[.enableLockScreenTimerWidget],
            mediaController: Defaults[.mediaController],
            showSongMetadataInClosedNotch: Defaults[.showSongMetadataInClosedNotch],
            // Lock Screen
            lockScreenWeatherRefreshInterval: Defaults[.lockScreenWeatherRefreshInterval],
            lockScreenWeatherShowsLocation: Defaults[.lockScreenWeatherShowsLocation],
            lockScreenWeatherShowsSunrise: Defaults[.lockScreenWeatherShowsSunrise],
            lockScreenWeatherWidgetStyle: Defaults[.lockScreenWeatherWidgetStyle],
            lockScreenWeatherTemperatureUnit: Defaults[.lockScreenWeatherTemperatureUnit],
            lockScreenWeatherShowsAQI: Defaults[.lockScreenWeatherShowsAQI],
            lockScreenWeatherAQIScale: Defaults[.lockScreenWeatherAQIScale],
            lockScreenWeatherUsesGaugeTint: Defaults[.lockScreenWeatherUsesGaugeTint],
            lockScreenWeatherProviderSource: Defaults[.lockScreenWeatherProviderSource],
            lockScreenWeatherVerticalOffset: Defaults[.lockScreenWeatherVerticalOffset],
            lockScreenMusicVerticalOffset: Defaults[.lockScreenMusicVerticalOffset],
            lockScreenMusicPanelWidth: Defaults[.lockScreenMusicPanelWidth],
            lockScreenMusicAlbumParallaxEnabled: Defaults[.lockScreenMusicAlbumParallaxEnabled],
            lockScreenTimerVerticalOffset: Defaults[.lockScreenTimerVerticalOffset],
            lockScreenTimerWidgetWidth: Defaults[.lockScreenTimerWidgetWidth],
            lockScreenWidgetAppearance: Defaults[.lockScreenWidgetAppearance],
            lockScreenGlassStyle: Defaults[.lockScreenGlassStyle],
            lockScreenGlassCustomizationMode: Defaults[.lockScreenGlassCustomizationMode],
            lockScreenTimerGlassStyle: Defaults[.lockScreenTimerGlassStyle],
            lockScreenTimerGlassCustomizationMode: Defaults[.lockScreenTimerGlassCustomizationMode],
            lockScreenMusicLiquidGlassVariant: Defaults[.lockScreenMusicLiquidGlassVariant],
            lockScreenTimerLiquidGlassVariant: Defaults[.lockScreenTimerLiquidGlassVariant],
            lockScreenShowAppIcon: Defaults[.lockScreenShowAppIcon],
            lockScreenPanelShowsBorder: Defaults[.lockScreenPanelShowsBorder],
            lockScreenMusicUsesEnhancedLiquidBorder: Defaults[.lockScreenMusicUsesEnhancedLiquidBorder],
            lockScreenPanelUsesBlur: Defaults[.lockScreenPanelUsesBlur],
            lockScreenMusicMergedAirPlayOutput: Defaults[.lockScreenMusicMergedAirPlayOutput],
            lockScreenMusicFullscreenArtworkEnabled: Defaults[.lockScreenMusicFullscreenArtworkEnabled],
            lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork: Defaults[.lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork],
            lockScreenMusicFullscreenVideoArtwork: Defaults[.lockScreenMusicFullscreenVideoArtwork],
            lockScreenUseArtworkLayoutOverFullscreenCanvas: Defaults[.lockScreenUseArtworkLayoutOverFullscreenCanvas],
            lockScreenTimerWidgetUsesBlur: Defaults[.lockScreenTimerWidgetUsesBlur],
            lockScreenReminderChipStyle: Defaults[.lockScreenReminderChipStyle],
            lockScreenReminderWidgetHorizontalAlignment: Defaults[.lockScreenReminderWidgetHorizontalAlignment],
            lockScreenReminderWidgetVerticalOffset: Defaults[.lockScreenReminderWidgetVerticalOffset],
            lockScreenShowCalendarEvent: Defaults[.lockScreenShowCalendarEvent],
            lockScreenCalendarEventLookaheadWindow: Defaults[.lockScreenCalendarEventLookaheadWindow],
            lockScreenCalendarSelectionMode: Defaults[.lockScreenCalendarSelectionMode],
            lockScreenSelectedCalendarIDs: Defaults[.lockScreenSelectedCalendarIDs],
            lockScreenShowCalendarCountdown: Defaults[.lockScreenShowCalendarCountdown],
            lockScreenShowCalendarEventEntireDuration: Defaults[.lockScreenShowCalendarEventEntireDuration],
            lockScreenShowCalendarEventAfterStartEnabled: Defaults[.lockScreenShowCalendarEventAfterStartEnabled],
            lockScreenShowCalendarEventAfterStartWindow: Defaults[.lockScreenShowCalendarEventAfterStartWindow],
            lockScreenShowCalendarTimeRemaining: Defaults[.lockScreenShowCalendarTimeRemaining],
            lockScreenShowCalendarStartTimeAfterBegins: Defaults[.lockScreenShowCalendarStartTimeAfterBegins],
            lockScreenWeatherWidgetRowOrder: Defaults[.lockScreenWeatherWidgetRowOrder],
            lockScreenBatteryShowsBatteryGauge: Defaults[.lockScreenBatteryShowsBatteryGauge],
            lockScreenBatteryUsesLaptopSymbol: Defaults[.lockScreenBatteryUsesLaptopSymbol],
            lockScreenBatteryShowsCharging: Defaults[.lockScreenBatteryShowsCharging],
            lockScreenBatteryShowsChargingPercentage: Defaults[.lockScreenBatteryShowsChargingPercentage],
            lockScreenBatteryShowsBluetooth: Defaults[.lockScreenBatteryShowsBluetooth],
            lockScreenLiveActivityIconStyle: Defaults[.lockScreenLiveActivityIconStyle],
            enableLockScreenLiveActivity: Defaults[.enableLockScreenLiveActivity],
            enableLockSounds: Defaults[.enableLockSounds],
            // Third-party Calendar
            enableThirdPartyCalendarApp: Defaults[.enableThirdPartyCalendarApp],
            selectedCalendarApp: Defaults[.selectedCalendarApp],
            fantasticalDefaultView: Defaults[.fantasticalDefaultView],
            // Battery
            showPowerStatusNotifications: Defaults[.showPowerStatusNotifications],
            showBatteryIndicator: Defaults[.showBatteryIndicator],
            showBatteryPercentage: Defaults[.showBatteryPercentage],
            showBatteryPercentInside: Defaults[.showBatteryPercentInside],
            showMinimalisticBatteryIndicator: Defaults[.showMinimalisticBatteryIndicator],
            showPowerStatusIcons: Defaults[.showPowerStatusIcons],
            playLowBatteryAlertSound: Defaults[.playLowBatteryAlertSound],
            showChargingBatteryHUD: Defaults[.showChargingBatteryHUD],
            showLowBatteryHUD: Defaults[.showLowBatteryHUD],
            showFullBatteryHUD: Defaults[.showFullBatteryHUD],
            chargingBatteryHUDDuration: Defaults[.chargingBatteryHUDDuration],
            lowBatteryHUDDuration: Defaults[.lowBatteryHUDDuration],
            fullBatteryHUDDuration: Defaults[.fullBatteryHUDDuration],
            lowBatteryHUDThreshold: Defaults[.lowBatteryHUDThreshold],
            fullBatteryHUDThreshold: Defaults[.fullBatteryHUDThreshold],
            lowBatteryHUDStyle: Defaults[.lowBatteryHUDStyle],
            fullBatteryHUDStyle: Defaults[.fullBatteryHUDStyle],
            // Downloads
            enableDownloadListener: Defaults[.enableDownloadListener],
            enableSafariDownloads: Defaults[.enableSafariDownloads],
            selectedDownloadIndicatorStyle: Defaults[.selectedDownloadIndicatorStyle],
            showDownloadSpeed: Defaults[.showDownloadSpeed],
            selectedDownloadIconStyle: Defaults[.selectedDownloadIconStyle],
            // HUD / OSD
            inlineHUD: Defaults[.inlineHUD],
            progressBarStyle: Defaults[.progressBarStyle],
            systemEventIndicatorShadow: Defaults[.systemEventIndicatorShadow],
            systemEventIndicatorUseAccent: Defaults[.systemEventIndicatorUseAccent],
            showProgressPercentages: Defaults[.showProgressPercentages],
            enableSystemHUD: Defaults[.enableSystemHUD],
            enableVolumeHUD: Defaults[.enableVolumeHUD],
            enableBrightnessHUD: Defaults[.enableBrightnessHUD],
            enableKeyboardBacklightHUD: Defaults[.enableKeyboardBacklightHUD],
            systemHUDSensitivity: Defaults[.systemHUDSensitivity],
            playVolumeChangeFeedback: Defaults[.playVolumeChangeFeedback],
            volumeStepPercent: Defaults[.volumeStepPercent],
            volumeFineStepPercent: Defaults[.volumeFineStepPercent],
            brightnessStepPercent: Defaults[.brightnessStepPercent],
            brightnessFineStepPercent: Defaults[.brightnessFineStepPercent],
            enableCustomOSD: Defaults[.enableCustomOSD],
            enableVerticalHUD: Defaults[.enableVerticalHUD],
            enableCircularHUD: Defaults[.enableCircularHUD],
            verticalHUDPosition: Defaults[.verticalHUDPosition],
            verticalHUDShowValue: Defaults[.verticalHUDShowValue],
            verticalHUDInteractive: Defaults[.verticalHUDInteractive],
            verticalHUDHeight: Defaults[.verticalHUDHeight],
            verticalHUDWidth: Defaults[.verticalHUDWidth],
            verticalHUDPadding: Defaults[.verticalHUDPadding],
            verticalHUDUseAccentColor: Defaults[.verticalHUDUseAccentColor],
            verticalHUDMaterial: Defaults[.verticalHUDMaterial],
            verticalHUDLiquidGlassCustomizationMode: Defaults[.verticalHUDLiquidGlassCustomizationMode],
            verticalHUDLiquidGlassVariant: Defaults[.verticalHUDLiquidGlassVariant],
            circularHUDShowValue: Defaults[.circularHUDShowValue],
            circularHUDSize: Defaults[.circularHUDSize],
            circularHUDStrokeWidth: Defaults[.circularHUDStrokeWidth],
            circularHUDUseAccentColor: Defaults[.circularHUDUseAccentColor],
            osdMaterial: Defaults[.osdMaterial],
            osdLiquidGlassCustomizationMode: Defaults[.osdLiquidGlassCustomizationMode],
            osdLiquidGlassVariant: Defaults[.osdLiquidGlassVariant],
            osdIconColorStyle: Defaults[.osdIconColorStyle],
            useColorCodedVolumeDisplay: Defaults[.useColorCodedVolumeDisplay],
            useSmoothColorGradient: Defaults[.useSmoothColorGradient],
            enableOSDVolume: Defaults[.enableOSDVolume],
            enableOSDBrightness: Defaults[.enableOSDBrightness],
            enableOSDKeyboardBacklight: Defaults[.enableOSDKeyboardBacklight],
            // Shelf
            dynamicShelf: Defaults[.dynamicShelf],
            openShelfByDefault: Defaults[.openShelfByDefault],
            quickShareProvider: Defaults[.quickShareProvider],
            copyOnDrag: Defaults[.copyOnDrag],
            allowMoveOnDrag: Defaults[.allowMoveOnDrag],
            autoRemoveShelfItems: Defaults[.autoRemoveShelfItems],
            expandedDragDetection: Defaults[.expandedDragDetection],
            // Calendar
            calendarSelectionState: Defaults[.calendarSelectionState],
            showFullEventTitles: Defaults[.showFullEventTitles],
            autoScrollToNextEvent: Defaults[.autoScrollToNextEvent],
            alwaysHideInFullscreen: Defaults[.alwaysHideInFullscreen],
            hideNotchOption: Defaults[.hideNotchOption],
            // Bluetooth / Devices
            showBluetoothDeviceConnections: Defaults[.showBluetoothDeviceConnections],
            useColorCodedBatteryDisplay: Defaults[.useColorCodedBatteryDisplay],
            useCircularBluetoothBatteryIndicator: Defaults[.useCircularBluetoothBatteryIndicator],
            showBluetoothBatteryPercentageText: Defaults[.showBluetoothBatteryPercentageText],
            showBluetoothDeviceNameMarquee: Defaults[.showBluetoothDeviceNameMarquee],
            useBluetoothHUD3DIcon: Defaults[.useBluetoothHUD3DIcon],
            showAirPodsListeningModeChanges: Defaults[.showAirPodsListeningModeChanges],
            // Stats
            enableStatsFeature: Defaults[.enableStatsFeature],
            enableLLMUsageFeature: Defaults[.enableLLMUsageFeature],
            enableClaudeProvider: Defaults[.enableClaudeProvider],
            enableCodexProvider: Defaults[.enableCodexProvider],
            enableCursorProvider: Defaults[.enableCursorProvider],
            enableAntigravityProvider: Defaults[.enableAntigravityProvider],
            autoStartStatsMonitoring: Defaults[.autoStartStatsMonitoring],
            statsStopWhenNotchCloses: Defaults[.statsStopWhenNotchCloses],
            statsUpdateInterval: Defaults[.statsUpdateInterval],
            showCpuGraph: Defaults[.showCpuGraph],
            showMemoryGraph: Defaults[.showMemoryGraph],
            showGpuGraph: Defaults[.showGpuGraph],
            showNetworkGraph: Defaults[.showNetworkGraph],
            showDiskGraph: Defaults[.showDiskGraph],
            cpuTemperatureUnit: Defaults[.cpuTemperatureUnit],
            // Terminal
            enableTerminalFeature: Defaults[.enableTerminalFeature],
            terminalShellPath: Defaults[.terminalShellPath],
            terminalFontFamily: Defaults[.terminalFontFamily],
            terminalFontSize: Defaults[.terminalFontSize],
            terminalOpacity: Defaults[.terminalOpacity],
            terminalMaxHeightFraction: Defaults[.terminalMaxHeightFraction],
            terminalCursorStyle: Defaults[.terminalCursorStyle],
            terminalScrollbackLines: Defaults[.terminalScrollbackLines],
            terminalOptionAsMeta: Defaults[.terminalOptionAsMeta],
            terminalMouseReporting: Defaults[.terminalMouseReporting],
            terminalBoldAsBright: Defaults[.terminalBoldAsBright],
            terminalBackgroundColor: Defaults[.terminalBackgroundColor],
            terminalForegroundColor: Defaults[.terminalForegroundColor],
            terminalCursorColor: Defaults[.terminalCursorColor],
            terminalStickyMode: Defaults[.terminalStickyMode],
            // Timer
            enableTimerFeature: Defaults[.enableTimerFeature],
            timerDisplayMode: Defaults[.timerDisplayMode],
            showTimerPresetsInNotchTab: Defaults[.showTimerPresetsInNotchTab],
            timerIconColorMode: Defaults[.timerIconColorMode],
            timerSolidColor: Defaults[.timerSolidColor],
            timerShowsCountdown: Defaults[.timerShowsCountdown],
            timerShowsLabel: Defaults[.timerShowsLabel],
            timerShowsProgress: Defaults[.timerShowsProgress],
            timerProgressStyle: Defaults[.timerProgressStyle],
            mirrorSystemTimer: Defaults[.mirrorSystemTimer],
            timerInputStyle: Defaults[.timerInputStyle],
            timerControlWindowEnabled: Defaults[.timerControlWindowEnabled],
            // Reminder Live Activity
            enableReminderLiveActivity: Defaults[.enableReminderLiveActivity],
            reminderPresentationStyle: Defaults[.reminderPresentationStyle],
            reminderLeadTime: Defaults[.reminderLeadTime],
            reminderSneakPeekDuration: Defaults[.reminderSneakPeekDuration],
            // Per-App Volume
            enablePerAppVolume: Defaults[.enablePerAppVolume],
            showPerAppVolumeIcon: Defaults[.showPerAppVolumeIcon],
            // Caffeinate
            enableCaffeinate: Defaults[.enableCaffeinate],
            showCaffeinateIcon: Defaults[.showCaffeinateIcon],
            caffeinateDefaultDuration: Defaults[.caffeinateDefaultDuration],
            caffeinateKeepsDisplayAwake: Defaults[.caffeinateKeepsDisplayAwake],
            // Color Picker
            enableColorPickerFeature: Defaults[.enableColorPickerFeature],
            showColorFormats: Defaults[.showColorFormats],
            colorPickerDisplayMode: Defaults[.colorPickerDisplayMode],
            colorHistorySize: Defaults[.colorHistorySize],
            showColorPickerIcon: Defaults[.showColorPickerIcon],
            // Clipboard
            enableClipboardManager: Defaults[.enableClipboardManager],
            clipboardHistorySize: Defaults[.clipboardHistorySize],
            persistClipboardHistory: Defaults[.persistClipboardHistory],
            showClipboardIcon: Defaults[.showClipboardIcon],
            clipboardDisplayMode: Defaults[.clipboardDisplayMode],
            // Screen Assistant
            enableScreenAssistant: Defaults[.enableScreenAssistant],
            screenAssistantDisplayMode: Defaults[.screenAssistantDisplayMode],
            selectedAIProvider: Defaults[.selectedAIProvider],
            enableThinkingMode: Defaults[.enableThinkingMode],
            localModelEndpoint: Defaults[.localModelEndpoint],
            // Third-Party Extensions
            enableThirdPartyExtensions: Defaults[.enableThirdPartyExtensions],
            enableExtensionLiveActivities: Defaults[.enableExtensionLiveActivities],
            enableExtensionLockScreenWidgets: Defaults[.enableExtensionLockScreenWidgets],
            enableExtensionNotchExperiences: Defaults[.enableExtensionNotchExperiences],
            enableExtensionNotchTabs: Defaults[.enableExtensionNotchTabs],
            enableExtensionNotchMinimalisticOverrides: Defaults[.enableExtensionNotchMinimalisticOverrides],
            enableExtensionNotchInteractiveWebViews: Defaults[.enableExtensionNotchInteractiveWebViews],
            extensionDiagnosticsLoggingEnabled: Defaults[.extensionDiagnosticsLoggingEnabled],
            extensionLiveActivityCapacity: Defaults[.extensionLiveActivityCapacity],
            extensionLockScreenWidgetCapacity: Defaults[.extensionLockScreenWidgetCapacity],
            extensionNotchExperienceCapacity: Defaults[.extensionNotchExperienceCapacity],
            enableExtensionFileSharing: Defaults[.enableExtensionFileSharing],
            // Keyboard Shortcuts
            enableShortcuts: Defaults[.enableShortcuts],
            // Screen Recording
            enableScreenRecordingDetection: Defaults[.enableScreenRecordingDetection],
            showRecordingIndicator: Defaults[.showRecordingIndicator],
            recordingHoverStyle: Defaults[.recordingHoverStyle],
            recordingControlMode: Defaults[.recordingControlMode],
            // Focus / DND
            enableDoNotDisturbDetection: Defaults[.enableDoNotDisturbDetection],
            focusMonitoringMode: Defaults[.focusMonitoringMode],
            showDoNotDisturbIndicator: Defaults[.showDoNotDisturbIndicator],
            showDoNotDisturbLabel: Defaults[.showDoNotDisturbLabel],
            focusIndicatorNonPersistent: Defaults[.focusIndicatorNonPersistent],
            // Privacy Indicators
            enableCameraDetection: Defaults[.enableCameraDetection],
            enableMicrophoneDetection: Defaults[.enableMicrophoneDetection],
            // Caps Lock
            enableCapsLockIndicator: Defaults[.enableCapsLockIndicator],
            capsLockIndicatorTintMode: Defaults[.capsLockIndicatorTintMode],
            showCapsLockLabel: Defaults[.showCapsLockLabel],
            // Third-Party DDC
            enableThirdPartyDDCIntegration: Defaults[.enableThirdPartyDDCIntegration],
            thirdPartyDDCProvider: Defaults[.thirdPartyDDCProvider],
            enableExternalVolumeControlListener: Defaults[.enableExternalVolumeControlListener],
            // Lyrics
            enableLyrics: Defaults[.enableLyrics],
            lyricHighlightStyle: Defaults[.lyricHighlightStyle],
            pinnedLyricContext: Defaults[.pinnedLyricContext],
            pinLyricsWhenClosed: Defaults[.pinLyricsWhenClosed],
            lyricsPanelWidth: Defaults[.lyricsPanelWidth],
            lyricsPanelOffset: Defaults[.lyricsPanelOffset],
            showLiveCanvasInDynamicIsland: Defaults[.showLiveCanvasInDynamicIsland],
            // Notes
            enableNotes: Defaults[.enableNotes],
            enableNotePinning: Defaults[.enableNotePinning],
            enableNoteSearch: Defaults[.enableNoteSearch],
            enableNoteColorFiltering: Defaults[.enableNoteColorFiltering],
            enableCreateFromClipboard: Defaults[.enableCreateFromClipboard],
            enableNoteCharCount: Defaults[.enableNoteCharCount],
            enableAppleNotesSync: Defaults[.enableAppleNotesSync],
            // Metadata
            exportedByVersion: appVersion,
            exportedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    // MARK: - Apply snapshot

    // swiftlint:disable:next function_body_length
    private static func applySnapshot(_ s: AtollSettingsSnapshot) {
        // General / Behavior
        Defaults[.menubarIcon] = s.menubarIcon
        Defaults[.showOnAllDisplays] = s.showOnAllDisplays
        Defaults[.automaticallySwitchDisplay] = s.automaticallySwitchDisplay
        Defaults[.hideDynamicIslandFromScreenCapture] = s.hideDynamicIslandFromScreenCapture
        Defaults[.minimumHoverDuration] = s.minimumHoverDuration
        Defaults[.enableHaptics] = s.enableHaptics
        Defaults[.openNotchOnHover] = s.openNotchOnHover
        Defaults[.extendHoverArea] = s.extendHoverArea
        Defaults[.externalDisplayStyle] = s.externalDisplayStyle
        Defaults[.hideNonNotchUntilHover] = s.hideNonNotchUntilHover
        Defaults[.enableMinimalisticUI] = s.enableMinimalisticUI
        Defaults[.updateChannel] = s.updateChannel
        Defaults[.logLevel] = s.logLevel
        Defaults[.notchHeightMode] = s.notchHeightMode
        Defaults[.nonNotchHeightMode] = s.nonNotchHeightMode
        Defaults[.nonNotchHeight] = s.nonNotchHeight
        Defaults[.notchHeight] = s.notchHeight
        Defaults[.openNotchWidth] = s.openNotchWidth
        Defaults[.closedNotchWidth] = s.closedNotchWidth
        Defaults[.customizePhysicalNotchWidth] = s.customizePhysicalNotchWidth
        // Appearance
        Defaults[.showEmojis] = s.showEmojis
        Defaults[.showMirror] = s.showMirror
        Defaults[.mirrorShape] = s.mirrorShape
        Defaults[.settingsIconInNotch] = s.settingsIconInNotch
        Defaults[.lightingEffect] = s.lightingEffect
        Defaults[.accentColor] = s.accentColor
        Defaults[.enableShadow] = s.enableShadow
        Defaults[.cornerRadiusScaling] = s.cornerRadiusScaling
        Defaults[.useModernCloseAnimation] = s.useModernCloseAnimation
        Defaults[.showNotHumanFace] = s.showNotHumanFace
        Defaults[.tileShowLabels] = s.tileShowLabels
        Defaults[.showCalendar] = s.showCalendar
        Defaults[.hideCompletedReminders] = s.hideCompletedReminders
        Defaults[.hideAllDayEvents] = s.hideAllDayEvents
        Defaults[.sliderColor] = s.sliderColor
        Defaults[.playerColorTinting] = s.playerColorTinting
        Defaults[.useMusicVisualizer] = s.useMusicVisualizer
        Defaults[.visualizerBarCount] = s.visualizerBarCount
        Defaults[.enableWaveformScrubber] = s.enableWaveformScrubber
        Defaults[.colorExtractionMode] = s.colorExtractionMode
        Defaults[.enableWobbleAnimation] = s.enableWobbleAnimation
        // Gestures
        Defaults[.enableGestures] = s.enableGestures
        Defaults[.closeGestureEnabled] = s.closeGestureEnabled
        Defaults[.gestureSensitivity] = s.gestureSensitivity
        Defaults[.enableHorizontalMusicGestures] = s.enableHorizontalMusicGestures
        Defaults[.musicGestureBehavior] = s.musicGestureBehavior
        Defaults[.reverseSwipeGestures] = s.reverseSwipeGestures
        Defaults[.reverseScrollGestures] = s.reverseScrollGestures
        // Media Playback
        Defaults[.coloredSpectrogram] = s.coloredSpectrogram
        Defaults[.enableRealTimeWaveform] = s.enableRealTimeWaveform
        Defaults[.enableSneakPeek] = s.enableSneakPeek
        Defaults[.sneakPeekStyles] = s.sneakPeekStyles
        Defaults[.showSneakPeekOnTrackChange] = s.showSneakPeekOnTrackChange
        Defaults[.enableFullscreenMediaDetection] = s.enableFullscreenMediaDetection
        Defaults[.parallaxEffectIntensity] = s.parallaxEffectIntensity
        Defaults[.waitInterval] = s.waitInterval
        Defaults[.showShuffleAndRepeat] = s.showShuffleAndRepeat
        Defaults[.showMediaOutputControl] = s.showMediaOutputControl
        Defaults[.alwaysShowLockScreenVolume] = s.alwaysShowLockScreenVolume
        Defaults[.musicSkipBehavior] = s.musicSkipBehavior
        Defaults[.musicControlWindowEnabled] = s.musicControlWindowEnabled
        Defaults[.showStandardMediaControls] = s.showStandardMediaControls
        Defaults[.autoHideInactiveNotchMediaPlayer] = s.autoHideInactiveNotchMediaPlayer
        Defaults[.enableLockScreenMediaWidget] = s.enableLockScreenMediaWidget
        Defaults[.enableLockScreenWeatherWidget] = s.enableLockScreenWeatherWidget
        Defaults[.enableLockScreenFocusWidget] = s.enableLockScreenFocusWidget
        Defaults[.siriResponsivenessMode] = s.siriResponsivenessMode
        Defaults[.enableLockScreenReminderWidget] = s.enableLockScreenReminderWidget
        Defaults[.enableLockScreenTimerWidget] = s.enableLockScreenTimerWidget
        Defaults[.mediaController] = s.mediaController
        Defaults[.showSongMetadataInClosedNotch] = s.showSongMetadataInClosedNotch
        // Lock Screen
        Defaults[.lockScreenWeatherRefreshInterval] = s.lockScreenWeatherRefreshInterval
        Defaults[.lockScreenWeatherShowsLocation] = s.lockScreenWeatherShowsLocation
        Defaults[.lockScreenWeatherShowsSunrise] = s.lockScreenWeatherShowsSunrise
        Defaults[.lockScreenWeatherWidgetStyle] = s.lockScreenWeatherWidgetStyle
        Defaults[.lockScreenWeatherTemperatureUnit] = s.lockScreenWeatherTemperatureUnit
        Defaults[.lockScreenWeatherShowsAQI] = s.lockScreenWeatherShowsAQI
        Defaults[.lockScreenWeatherAQIScale] = s.lockScreenWeatherAQIScale
        Defaults[.lockScreenWeatherUsesGaugeTint] = s.lockScreenWeatherUsesGaugeTint
        Defaults[.lockScreenWeatherProviderSource] = s.lockScreenWeatherProviderSource
        Defaults[.lockScreenWeatherVerticalOffset] = s.lockScreenWeatherVerticalOffset
        Defaults[.lockScreenMusicVerticalOffset] = s.lockScreenMusicVerticalOffset
        Defaults[.lockScreenMusicPanelWidth] = s.lockScreenMusicPanelWidth
        Defaults[.lockScreenMusicAlbumParallaxEnabled] = s.lockScreenMusicAlbumParallaxEnabled
        Defaults[.lockScreenTimerVerticalOffset] = s.lockScreenTimerVerticalOffset
        Defaults[.lockScreenTimerWidgetWidth] = s.lockScreenTimerWidgetWidth
        Defaults[.lockScreenWidgetAppearance] = s.lockScreenWidgetAppearance
        Defaults[.lockScreenGlassStyle] = s.lockScreenGlassStyle
        Defaults[.lockScreenGlassCustomizationMode] = s.lockScreenGlassCustomizationMode
        Defaults[.lockScreenTimerGlassStyle] = s.lockScreenTimerGlassStyle
        Defaults[.lockScreenTimerGlassCustomizationMode] = s.lockScreenTimerGlassCustomizationMode
        Defaults[.lockScreenMusicLiquidGlassVariant] = s.lockScreenMusicLiquidGlassVariant
        Defaults[.lockScreenTimerLiquidGlassVariant] = s.lockScreenTimerLiquidGlassVariant
        Defaults[.lockScreenShowAppIcon] = s.lockScreenShowAppIcon
        Defaults[.lockScreenPanelShowsBorder] = s.lockScreenPanelShowsBorder
        Defaults[.lockScreenMusicUsesEnhancedLiquidBorder] = s.lockScreenMusicUsesEnhancedLiquidBorder
        Defaults[.lockScreenPanelUsesBlur] = s.lockScreenPanelUsesBlur
        Defaults[.lockScreenMusicMergedAirPlayOutput] = s.lockScreenMusicMergedAirPlayOutput
        Defaults[.lockScreenMusicFullscreenArtworkEnabled] = s.lockScreenMusicFullscreenArtworkEnabled
        Defaults[.lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork] = s.lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork
        Defaults[.lockScreenMusicFullscreenVideoArtwork] = s.lockScreenMusicFullscreenVideoArtwork
        Defaults[.lockScreenUseArtworkLayoutOverFullscreenCanvas] = s.lockScreenUseArtworkLayoutOverFullscreenCanvas
        Defaults[.lockScreenTimerWidgetUsesBlur] = s.lockScreenTimerWidgetUsesBlur
        Defaults[.lockScreenReminderChipStyle] = s.lockScreenReminderChipStyle
        Defaults[.lockScreenReminderWidgetHorizontalAlignment] = s.lockScreenReminderWidgetHorizontalAlignment
        Defaults[.lockScreenReminderWidgetVerticalOffset] = s.lockScreenReminderWidgetVerticalOffset
        Defaults[.lockScreenShowCalendarEvent] = s.lockScreenShowCalendarEvent
        Defaults[.lockScreenCalendarEventLookaheadWindow] = s.lockScreenCalendarEventLookaheadWindow
        Defaults[.lockScreenCalendarSelectionMode] = s.lockScreenCalendarSelectionMode
        Defaults[.lockScreenSelectedCalendarIDs] = s.lockScreenSelectedCalendarIDs
        Defaults[.lockScreenShowCalendarCountdown] = s.lockScreenShowCalendarCountdown
        Defaults[.lockScreenShowCalendarEventEntireDuration] = s.lockScreenShowCalendarEventEntireDuration
        Defaults[.lockScreenShowCalendarEventAfterStartEnabled] = s.lockScreenShowCalendarEventAfterStartEnabled
        Defaults[.lockScreenShowCalendarEventAfterStartWindow] = s.lockScreenShowCalendarEventAfterStartWindow
        Defaults[.lockScreenShowCalendarTimeRemaining] = s.lockScreenShowCalendarTimeRemaining
        Defaults[.lockScreenShowCalendarStartTimeAfterBegins] = s.lockScreenShowCalendarStartTimeAfterBegins
        Defaults[.lockScreenWeatherWidgetRowOrder] = s.lockScreenWeatherWidgetRowOrder
        Defaults[.lockScreenBatteryShowsBatteryGauge] = s.lockScreenBatteryShowsBatteryGauge
        Defaults[.lockScreenBatteryUsesLaptopSymbol] = s.lockScreenBatteryUsesLaptopSymbol
        Defaults[.lockScreenBatteryShowsCharging] = s.lockScreenBatteryShowsCharging
        Defaults[.lockScreenBatteryShowsChargingPercentage] = s.lockScreenBatteryShowsChargingPercentage
        Defaults[.lockScreenBatteryShowsBluetooth] = s.lockScreenBatteryShowsBluetooth
        Defaults[.lockScreenLiveActivityIconStyle] = s.lockScreenLiveActivityIconStyle
        Defaults[.enableLockScreenLiveActivity] = s.enableLockScreenLiveActivity
        Defaults[.enableLockSounds] = s.enableLockSounds
        // Third-party Calendar
        Defaults[.enableThirdPartyCalendarApp] = s.enableThirdPartyCalendarApp
        Defaults[.selectedCalendarApp] = s.selectedCalendarApp
        Defaults[.fantasticalDefaultView] = s.fantasticalDefaultView
        // Battery
        Defaults[.showPowerStatusNotifications] = s.showPowerStatusNotifications
        Defaults[.showBatteryIndicator] = s.showBatteryIndicator
        Defaults[.showBatteryPercentage] = s.showBatteryPercentage
        Defaults[.showBatteryPercentInside] = s.showBatteryPercentInside
        Defaults[.showMinimalisticBatteryIndicator] = s.showMinimalisticBatteryIndicator
        Defaults[.showPowerStatusIcons] = s.showPowerStatusIcons
        Defaults[.playLowBatteryAlertSound] = s.playLowBatteryAlertSound
        Defaults[.showChargingBatteryHUD] = s.showChargingBatteryHUD
        Defaults[.showLowBatteryHUD] = s.showLowBatteryHUD
        Defaults[.showFullBatteryHUD] = s.showFullBatteryHUD
        Defaults[.chargingBatteryHUDDuration] = s.chargingBatteryHUDDuration
        Defaults[.lowBatteryHUDDuration] = s.lowBatteryHUDDuration
        Defaults[.fullBatteryHUDDuration] = s.fullBatteryHUDDuration
        Defaults[.lowBatteryHUDThreshold] = s.lowBatteryHUDThreshold
        Defaults[.fullBatteryHUDThreshold] = s.fullBatteryHUDThreshold
        Defaults[.lowBatteryHUDStyle] = s.lowBatteryHUDStyle
        Defaults[.fullBatteryHUDStyle] = s.fullBatteryHUDStyle
        // Downloads
        Defaults[.enableDownloadListener] = s.enableDownloadListener
        Defaults[.enableSafariDownloads] = s.enableSafariDownloads
        Defaults[.selectedDownloadIndicatorStyle] = s.selectedDownloadIndicatorStyle
        Defaults[.showDownloadSpeed] = s.showDownloadSpeed
        Defaults[.selectedDownloadIconStyle] = s.selectedDownloadIconStyle
        // HUD / OSD
        Defaults[.inlineHUD] = s.inlineHUD
        Defaults[.progressBarStyle] = s.progressBarStyle
        Defaults[.systemEventIndicatorShadow] = s.systemEventIndicatorShadow
        Defaults[.systemEventIndicatorUseAccent] = s.systemEventIndicatorUseAccent
        Defaults[.showProgressPercentages] = s.showProgressPercentages
        Defaults[.enableSystemHUD] = s.enableSystemHUD
        Defaults[.enableVolumeHUD] = s.enableVolumeHUD
        Defaults[.enableBrightnessHUD] = s.enableBrightnessHUD
        Defaults[.enableKeyboardBacklightHUD] = s.enableKeyboardBacklightHUD
        Defaults[.systemHUDSensitivity] = s.systemHUDSensitivity
        Defaults[.playVolumeChangeFeedback] = s.playVolumeChangeFeedback
        Defaults[.volumeStepPercent] = s.volumeStepPercent
        Defaults[.volumeFineStepPercent] = s.volumeFineStepPercent
        Defaults[.brightnessStepPercent] = s.brightnessStepPercent
        Defaults[.brightnessFineStepPercent] = s.brightnessFineStepPercent
        Defaults[.enableCustomOSD] = s.enableCustomOSD
        Defaults[.enableVerticalHUD] = s.enableVerticalHUD
        Defaults[.enableCircularHUD] = s.enableCircularHUD
        Defaults[.verticalHUDPosition] = s.verticalHUDPosition
        Defaults[.verticalHUDShowValue] = s.verticalHUDShowValue
        Defaults[.verticalHUDInteractive] = s.verticalHUDInteractive
        Defaults[.verticalHUDHeight] = s.verticalHUDHeight
        Defaults[.verticalHUDWidth] = s.verticalHUDWidth
        Defaults[.verticalHUDPadding] = s.verticalHUDPadding
        Defaults[.verticalHUDUseAccentColor] = s.verticalHUDUseAccentColor
        Defaults[.verticalHUDMaterial] = s.verticalHUDMaterial
        Defaults[.verticalHUDLiquidGlassCustomizationMode] = s.verticalHUDLiquidGlassCustomizationMode
        Defaults[.verticalHUDLiquidGlassVariant] = s.verticalHUDLiquidGlassVariant
        Defaults[.circularHUDShowValue] = s.circularHUDShowValue
        Defaults[.circularHUDSize] = s.circularHUDSize
        Defaults[.circularHUDStrokeWidth] = s.circularHUDStrokeWidth
        Defaults[.circularHUDUseAccentColor] = s.circularHUDUseAccentColor
        Defaults[.osdMaterial] = s.osdMaterial
        Defaults[.osdLiquidGlassCustomizationMode] = s.osdLiquidGlassCustomizationMode
        Defaults[.osdLiquidGlassVariant] = s.osdLiquidGlassVariant
        Defaults[.osdIconColorStyle] = s.osdIconColorStyle
        Defaults[.useColorCodedVolumeDisplay] = s.useColorCodedVolumeDisplay
        Defaults[.useSmoothColorGradient] = s.useSmoothColorGradient
        Defaults[.enableOSDVolume] = s.enableOSDVolume
        Defaults[.enableOSDBrightness] = s.enableOSDBrightness
        Defaults[.enableOSDKeyboardBacklight] = s.enableOSDKeyboardBacklight
        // Shelf
        Defaults[.dynamicShelf] = s.dynamicShelf
        Defaults[.openShelfByDefault] = s.openShelfByDefault
        Defaults[.quickShareProvider] = s.quickShareProvider
        Defaults[.copyOnDrag] = s.copyOnDrag
        Defaults[.allowMoveOnDrag] = s.allowMoveOnDrag
        Defaults[.autoRemoveShelfItems] = s.autoRemoveShelfItems
        Defaults[.expandedDragDetection] = s.expandedDragDetection
        // Calendar
        Defaults[.calendarSelectionState] = s.calendarSelectionState
        Defaults[.showFullEventTitles] = s.showFullEventTitles
        Defaults[.autoScrollToNextEvent] = s.autoScrollToNextEvent
        Defaults[.alwaysHideInFullscreen] = s.alwaysHideInFullscreen
        Defaults[.hideNotchOption] = s.hideNotchOption
        // Bluetooth / Devices
        Defaults[.showBluetoothDeviceConnections] = s.showBluetoothDeviceConnections
        Defaults[.useColorCodedBatteryDisplay] = s.useColorCodedBatteryDisplay
        Defaults[.useCircularBluetoothBatteryIndicator] = s.useCircularBluetoothBatteryIndicator
        Defaults[.showBluetoothBatteryPercentageText] = s.showBluetoothBatteryPercentageText
        Defaults[.showBluetoothDeviceNameMarquee] = s.showBluetoothDeviceNameMarquee
        Defaults[.useBluetoothHUD3DIcon] = s.useBluetoothHUD3DIcon
        Defaults[.showAirPodsListeningModeChanges] = s.showAirPodsListeningModeChanges
        // Stats
        Defaults[.enableStatsFeature] = s.enableStatsFeature
        Defaults[.enableLLMUsageFeature] = s.enableLLMUsageFeature
        Defaults[.enableClaudeProvider] = s.enableClaudeProvider
        Defaults[.enableCodexProvider] = s.enableCodexProvider
        Defaults[.enableCursorProvider] = s.enableCursorProvider
        Defaults[.enableAntigravityProvider] = s.enableAntigravityProvider
        Defaults[.autoStartStatsMonitoring] = s.autoStartStatsMonitoring
        Defaults[.statsStopWhenNotchCloses] = s.statsStopWhenNotchCloses
        Defaults[.statsUpdateInterval] = s.statsUpdateInterval
        Defaults[.showCpuGraph] = s.showCpuGraph
        Defaults[.showMemoryGraph] = s.showMemoryGraph
        Defaults[.showGpuGraph] = s.showGpuGraph
        Defaults[.showNetworkGraph] = s.showNetworkGraph
        Defaults[.showDiskGraph] = s.showDiskGraph
        Defaults[.cpuTemperatureUnit] = s.cpuTemperatureUnit
        // Terminal
        Defaults[.enableTerminalFeature] = s.enableTerminalFeature
        Defaults[.terminalShellPath] = s.terminalShellPath
        Defaults[.terminalFontFamily] = s.terminalFontFamily
        Defaults[.terminalFontSize] = s.terminalFontSize
        Defaults[.terminalOpacity] = s.terminalOpacity
        Defaults[.terminalMaxHeightFraction] = s.terminalMaxHeightFraction
        Defaults[.terminalCursorStyle] = s.terminalCursorStyle
        Defaults[.terminalScrollbackLines] = s.terminalScrollbackLines
        Defaults[.terminalOptionAsMeta] = s.terminalOptionAsMeta
        Defaults[.terminalMouseReporting] = s.terminalMouseReporting
        Defaults[.terminalBoldAsBright] = s.terminalBoldAsBright
        Defaults[.terminalBackgroundColor] = s.terminalBackgroundColor
        Defaults[.terminalForegroundColor] = s.terminalForegroundColor
        Defaults[.terminalCursorColor] = s.terminalCursorColor
        Defaults[.terminalStickyMode] = s.terminalStickyMode
        // Timer
        Defaults[.enableTimerFeature] = s.enableTimerFeature
        Defaults[.timerDisplayMode] = s.timerDisplayMode
        Defaults[.showTimerPresetsInNotchTab] = s.showTimerPresetsInNotchTab
        Defaults[.timerIconColorMode] = s.timerIconColorMode
        Defaults[.timerSolidColor] = s.timerSolidColor
        Defaults[.timerShowsCountdown] = s.timerShowsCountdown
        Defaults[.timerShowsLabel] = s.timerShowsLabel
        Defaults[.timerShowsProgress] = s.timerShowsProgress
        Defaults[.timerProgressStyle] = s.timerProgressStyle
        Defaults[.mirrorSystemTimer] = s.mirrorSystemTimer
        Defaults[.timerInputStyle] = s.timerInputStyle
        Defaults[.timerControlWindowEnabled] = s.timerControlWindowEnabled
        // Reminder Live Activity
        Defaults[.enableReminderLiveActivity] = s.enableReminderLiveActivity
        Defaults[.reminderPresentationStyle] = s.reminderPresentationStyle
        Defaults[.reminderLeadTime] = s.reminderLeadTime
        Defaults[.reminderSneakPeekDuration] = s.reminderSneakPeekDuration
        // Per-App Volume
        Defaults[.enablePerAppVolume] = s.enablePerAppVolume
        Defaults[.showPerAppVolumeIcon] = s.showPerAppVolumeIcon
        // Caffeinate
        Defaults[.enableCaffeinate] = s.enableCaffeinate
        Defaults[.showCaffeinateIcon] = s.showCaffeinateIcon
        Defaults[.caffeinateDefaultDuration] = s.caffeinateDefaultDuration
        Defaults[.caffeinateKeepsDisplayAwake] = s.caffeinateKeepsDisplayAwake
        // Color Picker
        Defaults[.enableColorPickerFeature] = s.enableColorPickerFeature
        Defaults[.showColorFormats] = s.showColorFormats
        Defaults[.colorPickerDisplayMode] = s.colorPickerDisplayMode
        Defaults[.colorHistorySize] = s.colorHistorySize
        Defaults[.showColorPickerIcon] = s.showColorPickerIcon
        // Clipboard
        Defaults[.enableClipboardManager] = s.enableClipboardManager
        Defaults[.clipboardHistorySize] = s.clipboardHistorySize
        Defaults[.persistClipboardHistory] = s.persistClipboardHistory
        Defaults[.showClipboardIcon] = s.showClipboardIcon
        Defaults[.clipboardDisplayMode] = s.clipboardDisplayMode
        // Screen Assistant
        Defaults[.enableScreenAssistant] = s.enableScreenAssistant
        Defaults[.screenAssistantDisplayMode] = s.screenAssistantDisplayMode
        Defaults[.selectedAIProvider] = s.selectedAIProvider
        Defaults[.enableThinkingMode] = s.enableThinkingMode
        Defaults[.localModelEndpoint] = s.localModelEndpoint
        // Third-Party Extensions
        Defaults[.enableThirdPartyExtensions] = s.enableThirdPartyExtensions
        Defaults[.enableExtensionLiveActivities] = s.enableExtensionLiveActivities
        Defaults[.enableExtensionLockScreenWidgets] = s.enableExtensionLockScreenWidgets
        Defaults[.enableExtensionNotchExperiences] = s.enableExtensionNotchExperiences
        Defaults[.enableExtensionNotchTabs] = s.enableExtensionNotchTabs
        Defaults[.enableExtensionNotchMinimalisticOverrides] = s.enableExtensionNotchMinimalisticOverrides
        Defaults[.enableExtensionNotchInteractiveWebViews] = s.enableExtensionNotchInteractiveWebViews
        Defaults[.extensionDiagnosticsLoggingEnabled] = s.extensionDiagnosticsLoggingEnabled
        Defaults[.extensionLiveActivityCapacity] = s.extensionLiveActivityCapacity
        Defaults[.extensionLockScreenWidgetCapacity] = s.extensionLockScreenWidgetCapacity
        Defaults[.extensionNotchExperienceCapacity] = s.extensionNotchExperienceCapacity
        Defaults[.enableExtensionFileSharing] = s.enableExtensionFileSharing
        // Keyboard Shortcuts
        Defaults[.enableShortcuts] = s.enableShortcuts
        // Screen Recording
        Defaults[.enableScreenRecordingDetection] = s.enableScreenRecordingDetection
        Defaults[.showRecordingIndicator] = s.showRecordingIndicator
        Defaults[.recordingHoverStyle] = s.recordingHoverStyle
        Defaults[.recordingControlMode] = s.recordingControlMode
        // Focus / DND
        Defaults[.enableDoNotDisturbDetection] = s.enableDoNotDisturbDetection
        Defaults[.focusMonitoringMode] = s.focusMonitoringMode
        Defaults[.showDoNotDisturbIndicator] = s.showDoNotDisturbIndicator
        Defaults[.showDoNotDisturbLabel] = s.showDoNotDisturbLabel
        Defaults[.focusIndicatorNonPersistent] = s.focusIndicatorNonPersistent
        // Privacy Indicators
        Defaults[.enableCameraDetection] = s.enableCameraDetection
        Defaults[.enableMicrophoneDetection] = s.enableMicrophoneDetection
        // Caps Lock
        Defaults[.enableCapsLockIndicator] = s.enableCapsLockIndicator
        Defaults[.capsLockIndicatorTintMode] = s.capsLockIndicatorTintMode
        Defaults[.showCapsLockLabel] = s.showCapsLockLabel
        // Third-Party DDC
        Defaults[.enableThirdPartyDDCIntegration] = s.enableThirdPartyDDCIntegration
        Defaults[.thirdPartyDDCProvider] = s.thirdPartyDDCProvider
        Defaults[.enableExternalVolumeControlListener] = s.enableExternalVolumeControlListener
        // Lyrics
        Defaults[.enableLyrics] = s.enableLyrics
        Defaults[.lyricHighlightStyle] = s.lyricHighlightStyle
        Defaults[.pinnedLyricContext] = s.pinnedLyricContext
        Defaults[.pinLyricsWhenClosed] = s.pinLyricsWhenClosed
        Defaults[.lyricsPanelWidth] = s.lyricsPanelWidth
        Defaults[.lyricsPanelOffset] = s.lyricsPanelOffset
        Defaults[.showLiveCanvasInDynamicIsland] = s.showLiveCanvasInDynamicIsland
        // Notes
        Defaults[.enableNotes] = s.enableNotes
        Defaults[.enableNotePinning] = s.enableNotePinning
        Defaults[.enableNoteSearch] = s.enableNoteSearch
        Defaults[.enableNoteColorFiltering] = s.enableNoteColorFiltering
        Defaults[.enableCreateFromClipboard] = s.enableCreateFromClipboard
        Defaults[.enableNoteCharCount] = s.enableNoteCharCount
        Defaults[.enableAppleNotesSync] = s.enableAppleNotesSync
    }
}

// MARK: - AtollSettingsSnapshot

/// A `Codable` snapshot of all user-facing, non-sensitive Atoll settings.
///
/// Each property maps 1-to-1 to a `Defaults.Key`.  Internal migration
/// flags, cached values and secrets (API keys, auth tokens) are
/// deliberately omitted to keep the exported file safe to share.
struct AtollSettingsSnapshot: Codable {
    // MARK: General / Behavior
    var menubarIcon: Bool
    var showOnAllDisplays: Bool
    var automaticallySwitchDisplay: Bool
    var hideDynamicIslandFromScreenCapture: Bool
    var minimumHoverDuration: TimeInterval
    var enableHaptics: Bool
    var openNotchOnHover: Bool
    var extendHoverArea: Bool
    var externalDisplayStyle: ExternalDisplayStyle
    var hideNonNotchUntilHover: Bool
    var enableMinimalisticUI: Bool
    var updateChannel: UpdateChannel
    var logLevel: LogLevel
    var notchHeightMode: WindowHeightMode
    var nonNotchHeightMode: WindowHeightMode
    var nonNotchHeight: CGFloat
    var notchHeight: CGFloat
    var openNotchWidth: CGFloat
    var closedNotchWidth: CGFloat
    var customizePhysicalNotchWidth: Bool
    // MARK: Appearance
    var showEmojis: Bool
    var showMirror: Bool
    var mirrorShape: MirrorShapeEnum
    var settingsIconInNotch: Bool
    var lightingEffect: Bool
    var accentColor: Color
    var enableShadow: Bool
    var cornerRadiusScaling: Bool
    var useModernCloseAnimation: Bool
    var showNotHumanFace: Bool
    var tileShowLabels: Bool
    var showCalendar: Bool
    var hideCompletedReminders: Bool
    var hideAllDayEvents: Bool
    var sliderColor: SliderColorEnum
    var playerColorTinting: Bool
    var useMusicVisualizer: Bool
    var visualizerBarCount: Int
    var enableWaveformScrubber: Bool
    var colorExtractionMode: ColorExtractionMode
    var enableWobbleAnimation: Bool
    // MARK: Gestures
    var enableGestures: Bool
    var closeGestureEnabled: Bool
    var gestureSensitivity: CGFloat
    var enableHorizontalMusicGestures: Bool
    var musicGestureBehavior: MusicSkipBehavior
    var reverseSwipeGestures: Bool
    var reverseScrollGestures: Bool
    // MARK: Media Playback
    var coloredSpectrogram: Bool
    var enableRealTimeWaveform: Bool
    var enableSneakPeek: Bool
    var sneakPeekStyles: SneakPeekStyle
    var showSneakPeekOnTrackChange: Bool
    var enableFullscreenMediaDetection: Bool
    var parallaxEffectIntensity: Double
    var waitInterval: Double
    var showShuffleAndRepeat: Bool
    var showMediaOutputControl: Bool
    var alwaysShowLockScreenVolume: Bool
    var musicSkipBehavior: MusicSkipBehavior
    var musicControlWindowEnabled: Bool
    var showStandardMediaControls: Bool
    var autoHideInactiveNotchMediaPlayer: Bool
    var enableLockScreenMediaWidget: Bool
    var enableLockScreenWeatherWidget: Bool
    var enableLockScreenFocusWidget: Bool
    var siriResponsivenessMode: SiriResponsivenessMode
    var enableLockScreenReminderWidget: Bool
    var enableLockScreenTimerWidget: Bool
    var mediaController: MediaControllerType
    var showSongMetadataInClosedNotch: Bool
    // MARK: Lock Screen
    var lockScreenWeatherRefreshInterval: TimeInterval
    var lockScreenWeatherShowsLocation: Bool
    var lockScreenWeatherShowsSunrise: Bool
    var lockScreenWeatherWidgetStyle: LockScreenWeatherWidgetStyle
    var lockScreenWeatherTemperatureUnit: LockScreenWeatherTemperatureUnit
    var lockScreenWeatherShowsAQI: Bool
    var lockScreenWeatherAQIScale: LockScreenWeatherAirQualityScale
    var lockScreenWeatherUsesGaugeTint: Bool
    var lockScreenWeatherProviderSource: LockScreenWeatherProviderSource
    var lockScreenWeatherVerticalOffset: Double
    var lockScreenMusicVerticalOffset: Double
    var lockScreenMusicPanelWidth: Double
    var lockScreenMusicAlbumParallaxEnabled: Bool
    var lockScreenTimerVerticalOffset: Double
    var lockScreenTimerWidgetWidth: Double
    var lockScreenWidgetAppearance: LockScreenWidgetAppearance
    var lockScreenGlassStyle: LockScreenGlassStyle
    var lockScreenGlassCustomizationMode: LockScreenGlassCustomizationMode
    var lockScreenTimerGlassStyle: LockScreenGlassStyle
    var lockScreenTimerGlassCustomizationMode: LockScreenGlassCustomizationMode
    var lockScreenMusicLiquidGlassVariant: LiquidGlassVariant
    var lockScreenTimerLiquidGlassVariant: LiquidGlassVariant
    var lockScreenShowAppIcon: Bool
    var lockScreenPanelShowsBorder: Bool
    var lockScreenMusicUsesEnhancedLiquidBorder: Bool
    var lockScreenPanelUsesBlur: Bool
    var lockScreenMusicMergedAirPlayOutput: Bool
    var lockScreenMusicFullscreenArtworkEnabled: Bool
    var lockScreenKeepAlbumArtVisibleDuringFullscreenArtwork: Bool
    var lockScreenMusicFullscreenVideoArtwork: Bool
    var lockScreenUseArtworkLayoutOverFullscreenCanvas: Bool
    var lockScreenTimerWidgetUsesBlur: Bool
    var lockScreenReminderChipStyle: LockScreenReminderChipStyle
    var lockScreenReminderWidgetHorizontalAlignment: String
    var lockScreenReminderWidgetVerticalOffset: Double
    var lockScreenShowCalendarEvent: Bool
    var lockScreenCalendarEventLookaheadWindow: String
    var lockScreenCalendarSelectionMode: String
    var lockScreenSelectedCalendarIDs: Set<String>
    var lockScreenShowCalendarCountdown: Bool
    var lockScreenShowCalendarEventEntireDuration: Bool
    var lockScreenShowCalendarEventAfterStartEnabled: Bool
    var lockScreenShowCalendarEventAfterStartWindow: String
    var lockScreenShowCalendarTimeRemaining: Bool
    var lockScreenShowCalendarStartTimeAfterBegins: Bool
    var lockScreenWeatherWidgetRowOrder: String
    var lockScreenBatteryShowsBatteryGauge: Bool
    var lockScreenBatteryUsesLaptopSymbol: Bool
    var lockScreenBatteryShowsCharging: Bool
    var lockScreenBatteryShowsChargingPercentage: Bool
    var lockScreenBatteryShowsBluetooth: Bool
    var lockScreenLiveActivityIconStyle: LockScreenLiveActivityIconStyle
    var enableLockScreenLiveActivity: Bool
    var enableLockSounds: Bool
    // MARK: Third-party Calendar
    var enableThirdPartyCalendarApp: Bool
    var selectedCalendarApp: ThirdPartyCalendarApp
    var fantasticalDefaultView: FantasticalViewStyle
    // MARK: Battery
    var showPowerStatusNotifications: Bool
    var showBatteryIndicator: Bool
    var showBatteryPercentage: Bool
    var showBatteryPercentInside: Bool
    var showMinimalisticBatteryIndicator: Bool
    var showPowerStatusIcons: Bool
    var playLowBatteryAlertSound: Bool
    var showChargingBatteryHUD: Bool
    var showLowBatteryHUD: Bool
    var showFullBatteryHUD: Bool
    var chargingBatteryHUDDuration: Int
    var lowBatteryHUDDuration: Int
    var fullBatteryHUDDuration: Int
    var lowBatteryHUDThreshold: Int
    var fullBatteryHUDThreshold: Int
    var lowBatteryHUDStyle: BatteryNotificationStyle
    var fullBatteryHUDStyle: BatteryNotificationStyle
    // MARK: Downloads
    var enableDownloadListener: Bool
    var enableSafariDownloads: Bool
    var selectedDownloadIndicatorStyle: DownloadIndicatorStyle
    var showDownloadSpeed: Bool
    var selectedDownloadIconStyle: DownloadIconStyle
    // MARK: HUD / OSD
    var inlineHUD: Bool
    var progressBarStyle: ProgressBarStyle
    var systemEventIndicatorShadow: Bool
    var systemEventIndicatorUseAccent: Bool
    var showProgressPercentages: Bool
    var enableSystemHUD: Bool
    var enableVolumeHUD: Bool
    var enableBrightnessHUD: Bool
    var enableKeyboardBacklightHUD: Bool
    var systemHUDSensitivity: Int
    var playVolumeChangeFeedback: Bool
    var volumeStepPercent: Int
    var volumeFineStepPercent: Int
    var brightnessStepPercent: Int
    var brightnessFineStepPercent: Int
    var enableCustomOSD: Bool
    var enableVerticalHUD: Bool
    var enableCircularHUD: Bool
    var verticalHUDPosition: String
    var verticalHUDShowValue: Bool
    var verticalHUDInteractive: Bool
    var verticalHUDHeight: CGFloat
    var verticalHUDWidth: CGFloat
    var verticalHUDPadding: CGFloat
    var verticalHUDUseAccentColor: Bool
    var verticalHUDMaterial: OSDMaterial
    var verticalHUDLiquidGlassCustomizationMode: LockScreenGlassCustomizationMode
    var verticalHUDLiquidGlassVariant: LiquidGlassVariant
    var circularHUDShowValue: Bool
    var circularHUDSize: CGFloat
    var circularHUDStrokeWidth: CGFloat
    var circularHUDUseAccentColor: Bool
    var osdMaterial: OSDMaterial
    var osdLiquidGlassCustomizationMode: LockScreenGlassCustomizationMode
    var osdLiquidGlassVariant: LiquidGlassVariant
    var osdIconColorStyle: OSDIconColorStyle
    var useColorCodedVolumeDisplay: Bool
    var useSmoothColorGradient: Bool
    var enableOSDVolume: Bool
    var enableOSDBrightness: Bool
    var enableOSDKeyboardBacklight: Bool
    // MARK: Shelf
    var dynamicShelf: Bool
    var openShelfByDefault: Bool
    var quickShareProvider: String
    var copyOnDrag: Bool
    var allowMoveOnDrag: Bool
    var autoRemoveShelfItems: Bool
    var expandedDragDetection: Bool
    // MARK: Calendar
    var calendarSelectionState: CalendarSelectionState
    var showFullEventTitles: Bool
    var autoScrollToNextEvent: Bool
    var alwaysHideInFullscreen: Bool
    var hideNotchOption: HideNotchOption
    // MARK: Bluetooth / Devices
    var showBluetoothDeviceConnections: Bool
    var useColorCodedBatteryDisplay: Bool
    var useCircularBluetoothBatteryIndicator: Bool
    var showBluetoothBatteryPercentageText: Bool
    var showBluetoothDeviceNameMarquee: Bool
    var useBluetoothHUD3DIcon: Bool
    var showAirPodsListeningModeChanges: Bool
    // MARK: Stats
    var enableStatsFeature: Bool
    var enableLLMUsageFeature: Bool
    var enableClaudeProvider: Bool
    var enableCodexProvider: Bool
    var enableCursorProvider: Bool
    var enableAntigravityProvider: Bool
    var autoStartStatsMonitoring: Bool
    var statsStopWhenNotchCloses: Bool
    var statsUpdateInterval: Double
    var showCpuGraph: Bool
    var showMemoryGraph: Bool
    var showGpuGraph: Bool
    var showNetworkGraph: Bool
    var showDiskGraph: Bool
    var cpuTemperatureUnit: LockScreenWeatherTemperatureUnit
    // MARK: Terminal
    var enableTerminalFeature: Bool
    var terminalShellPath: String
    var terminalFontFamily: String
    var terminalFontSize: Double
    var terminalOpacity: Double
    var terminalMaxHeightFraction: Double
    var terminalCursorStyle: String
    var terminalScrollbackLines: Int
    var terminalOptionAsMeta: Bool
    var terminalMouseReporting: Bool
    var terminalBoldAsBright: Bool
    var terminalBackgroundColor: Color
    var terminalForegroundColor: Color
    var terminalCursorColor: Color
    var terminalStickyMode: Bool
    // MARK: Timer
    var enableTimerFeature: Bool
    var timerDisplayMode: TimerDisplayMode
    var showTimerPresetsInNotchTab: Bool
    var timerIconColorMode: TimerIconColorMode
    var timerSolidColor: Color
    var timerShowsCountdown: Bool
    var timerShowsLabel: Bool
    var timerShowsProgress: Bool
    var timerProgressStyle: TimerProgressStyle
    var mirrorSystemTimer: Bool
    var timerInputStyle: TimerInputStyle
    var timerControlWindowEnabled: Bool
    // MARK: Reminder Live Activity
    var enableReminderLiveActivity: Bool
    var reminderPresentationStyle: ReminderPresentationStyle
    var reminderLeadTime: Int
    var reminderSneakPeekDuration: Double
    // MARK: Per-App Volume
    var enablePerAppVolume: Bool
    var showPerAppVolumeIcon: Bool
    // MARK: Caffeinate
    var enableCaffeinate: Bool
    var showCaffeinateIcon: Bool
    var caffeinateDefaultDuration: CaffeinateDuration
    var caffeinateKeepsDisplayAwake: Bool
    // MARK: Color Picker
    var enableColorPickerFeature: Bool
    var showColorFormats: Bool
    var colorPickerDisplayMode: ColorPickerDisplayMode
    var colorHistorySize: Int
    var showColorPickerIcon: Bool
    // MARK: Clipboard
    var enableClipboardManager: Bool
    var clipboardHistorySize: Int
    var persistClipboardHistory: Bool
    var showClipboardIcon: Bool
    var clipboardDisplayMode: ClipboardDisplayMode
    // MARK: Screen Assistant
    var enableScreenAssistant: Bool
    var screenAssistantDisplayMode: ScreenAssistantDisplayMode
    var selectedAIProvider: AIModelProvider
    var enableThinkingMode: Bool
    var localModelEndpoint: String
    // MARK: Third-Party Extensions
    var enableThirdPartyExtensions: Bool
    var enableExtensionLiveActivities: Bool
    var enableExtensionLockScreenWidgets: Bool
    var enableExtensionNotchExperiences: Bool
    var enableExtensionNotchTabs: Bool
    var enableExtensionNotchMinimalisticOverrides: Bool
    var enableExtensionNotchInteractiveWebViews: Bool
    var extensionDiagnosticsLoggingEnabled: Bool
    var extensionLiveActivityCapacity: Int
    var extensionLockScreenWidgetCapacity: Int
    var extensionNotchExperienceCapacity: Int
    var enableExtensionFileSharing: Bool
    // MARK: Keyboard Shortcuts
    var enableShortcuts: Bool
    // MARK: Screen Recording
    var enableScreenRecordingDetection: Bool
    var showRecordingIndicator: Bool
    var recordingHoverStyle: RecordingHoverStyle
    var recordingControlMode: RecordingControlMode
    // MARK: Focus / DND
    var enableDoNotDisturbDetection: Bool
    var focusMonitoringMode: FocusMonitoringMode
    var showDoNotDisturbIndicator: Bool
    var showDoNotDisturbLabel: Bool
    var focusIndicatorNonPersistent: Bool
    // MARK: Privacy Indicators
    var enableCameraDetection: Bool
    var enableMicrophoneDetection: Bool
    // MARK: Caps Lock
    var enableCapsLockIndicator: Bool
    var capsLockIndicatorTintMode: CapsLockIndicatorTintMode
    var showCapsLockLabel: Bool
    // MARK: Third-Party DDC
    var enableThirdPartyDDCIntegration: Bool
    var thirdPartyDDCProvider: ThirdPartyDDCProvider
    var enableExternalVolumeControlListener: Bool
    // MARK: Lyrics
    var enableLyrics: Bool
    var lyricHighlightStyle: LyricHighlightStyle
    var pinnedLyricContext: PinnedLyricContext
    var pinLyricsWhenClosed: Bool
    var lyricsPanelWidth: CGFloat
    var lyricsPanelOffset: CGFloat
    var showLiveCanvasInDynamicIsland: Bool
    // MARK: Notes
    var enableNotes: Bool
    var enableNotePinning: Bool
    var enableNoteSearch: Bool
    var enableNoteColorFiltering: Bool
    var enableCreateFromClipboard: Bool
    var enableNoteCharCount: Bool
    var enableAppleNotesSync: Bool
    // MARK: Metadata
    /// App version string at export time, for forward-compatibility checks.
    var exportedByVersion: String
    /// ISO-8601 timestamp of when the snapshot was created.
    var exportedAt: String
}
