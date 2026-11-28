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
import Combine
import CoreAudio

class SystemHUDManager {
    static let shared = SystemHUDManager()
    
    private var changesObserver: SystemChangesObserver?
    private weak var coordinator: DynamicIslandViewCoordinator?
    private var isSetupComplete = false
    private var isSystemOperationInProgress = false
    /// The lock state the native HUD has actually been handed over for, so a
    /// handover that restarts OSDUIHelper only happens when it changes.
    private var lastNativeHUDLockState: Bool?
    /// Whether the native HUD is currently suppressed for this app's HUDs, so
    /// a per-channel toggle only restarts OSDUIHelper when that changes.
    private var nativeHUDSuppressed: Bool?
    
    private init() {
        // Set up observer for settings changes
        setupSettingsObserver()
    }
    
    private func setupSettingsObserver() {
        // Observe Vertical HUD toggle
        Defaults.publisher(.enableVerticalHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue {
                    // Always restart to ensure correct flags are applied
                    await self.startSystemObserver()
                } else if Defaults[.enableSystemHUD] || Defaults[.enableCustomOSD] || Defaults[.enableCircularHUD] {
                    // Restart to apply flags for the remaining active HUD
                    await self.startSystemObserver()
                } else {
                    await self.stopSystemObserver()
                }
            }
        }.store(in: &cancellables)
        
        // Observe master HUD toggle
        Defaults.publisher(.enableSystemHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue && !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] {
                     // Always restart to ensure correct flags are applied
                    await self.startSystemObserver()
                } else if !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] {
                    // Only stop if others are also disabled
                    await self.stopSystemObserver()
                } else if change.newValue == false && (Defaults[.enableCustomOSD] || Defaults[.enableVerticalHUD] || Defaults[.enableCircularHUD]) {
                     // If disabling system HUD but others are active, restart to update flags
                     await self.startSystemObserver()
                }
            }
        }.store(in: &cancellables)
        
        // Observe OSD toggle
        Defaults.publisher(.enableCustomOSD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue {
                     // Always restart to ensure correct flags are applied
                    await self.startSystemObserver()
                } else if Defaults[.enableSystemHUD] || Defaults[.enableVerticalHUD] || Defaults[.enableCircularHUD] {
                    // Restart to apply flags for the remaining active HUD
                    await self.startSystemObserver()
                } else {
                    await self.stopSystemObserver()
                }
            }
        }.store(in: &cancellables)
        
        // Observe Circular HUD toggle
        Defaults.publisher(.enableCircularHUD, options: []).sink { [weak self] change in
            guard let self = self, self.isSetupComplete else {
                return
            }
            Task { @MainActor in
                if change.newValue {
                     // Always restart to ensure correct flags are applied
                    await self.startSystemObserver()
                } else if Defaults[.enableSystemHUD] || Defaults[.enableCustomOSD] || Defaults[.enableVerticalHUD] {
                    // Restart to apply flags for the remaining active HUD
                    await self.startSystemObserver()
                } else {
                    await self.stopSystemObserver()
                }
            }
        }.store(in: &cancellables)
        
        // Observe individual HUD toggles
        Defaults.publisher(.enableVolumeHUD, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, self.requiresSystemToggleHandling else {
                return
            }
            self.applyResolvedFlags()
        }.store(in: &cancellables)
        
        Defaults.publisher(.enableBrightnessHUD, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, self.requiresSystemToggleHandling else {
                return
            }
            self.applyResolvedFlags()
        }.store(in: &cancellables)

        Defaults.publisher(.enableKeyboardBacklightHUD, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, self.requiresSystemToggleHandling else {
                return
            }
            self.applyResolvedFlags()
        }.store(in: &cancellables)
        
        // Observe individual OSD toggles
        Defaults.publisher(.enableOSDVolume, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, Defaults[.enableCustomOSD] else {
                return
            }
            self.applyResolvedFlags()
        }.store(in: &cancellables)
        
        Defaults.publisher(.enableOSDBrightness, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, Defaults[.enableCustomOSD] else {
                return
            }
            self.applyResolvedFlags()
        }.store(in: &cancellables)
        
        Defaults.publisher(.enableOSDKeyboardBacklight, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete, Defaults[.enableCustomOSD] else {
                return
            }
            self.applyResolvedFlags()
        }.store(in: &cancellables)

        // Restart observer when third-party DDC integration state changes.
        Defaults.publisher(.enableThirdPartyDDCIntegration, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete else { return }
            Task { @MainActor in
                await self.startSystemObserver()
            }
        }.store(in: &cancellables)

        Defaults.publisher(.thirdPartyDDCProvider, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete else { return }
            Task { @MainActor in
                await self.startSystemObserver()
            }
        }.store(in: &cancellables)

        Defaults.publisher(.enableExternalVolumeControlListener, options: []).sink { [weak self] _ in
            guard let self = self, self.isSetupComplete else { return }
            Task { @MainActor in
                await self.startSystemObserver()
            }
        }.store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()

    private func applyResolvedFlags() {
        let flags = resolvedControlFlags()
        changesObserver?.update(
            volumeEnabled: flags.volume,
            brightnessEnabled: flags.brightness,
            keyboardBacklightEnabled: flags.backlight
        )
        Task { @MainActor in
            self.applyNativeHUDSuppression(for: flags)
        }
    }

    /// Whether macOS's own HUD has to be suppressed for the given channels.
    ///
    /// OSDUIHelper is one process for every channel, so it is suppressed when
    /// this app draws any of them. When it draws none -- every per-channel HUD
    /// switched off -- freezing the helper only takes the HUD away entirely and
    /// risks leaving it stuck on screen (#908). The exception is a running DDC
    /// helper app, whose own notifications drive this app's HUD.
    static func shouldSuppressNativeHUD(
        volume: Bool,
        brightness: Bool,
        backlight: Bool,
        thirdPartyDDCActive: Bool
    ) -> Bool {
        volume || brightness || backlight || thirdPartyDDCActive
    }

    /// Whether a DDC app can be handling the volume keys for this output.
    ///
    /// Lunar and BetterDisplay set the volume of displays. Built-in speakers
    /// and Bluetooth headphones are never theirs: the keys fall through to
    /// macOS, which draws its own HUD and sends the app no volume event, so
    /// handing volume to the provider there left no HUD in Atoll at all --
    /// after unplugging from a monitor hub, say (#465). Unknown transports
    /// keep the provider in charge, as before.
    static func externalProviderControlsVolume(outputTransport: UInt32) -> Bool {
        switch outputTransport {
        case kAudioDeviceTransportTypeBuiltIn,
             kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:
            return false
        default:
            return true
        }
    }

    @MainActor
    private func applyNativeHUDSuppression(
        for flags: (volume: Bool, brightness: Bool, backlight: Bool, thirdPartyDDC: Bool)
    ) {
        guard changesObserver != nil else { return }
        let suppress = Self.shouldSuppressNativeHUD(
            volume: flags.volume,
            brightness: flags.brightness,
            backlight: flags.backlight,
            thirdPartyDDCActive: flags.thirdPartyDDC
        )
        guard suppress != nativeHUDSuppressed else { return }
        nativeHUDSuppressed = suppress
        // What was handed over for the lock state says nothing about a
        // suppression decided afresh here.
        lastNativeHUDLockState = nil

        if suppress {
            SystemOSDManager.disableSystemHUD()
        } else {
            SystemOSDManager.enableSystemHUD()
        }
    }

    private var requiresSystemToggleHandling: Bool {
        Defaults[.enableSystemHUD] || Defaults[.enableVerticalHUD] || Defaults[.enableCircularHUD]
    }
    
    /// Public property to check if system operations are in progress
    var isOperationInProgress: Bool {
        return isSystemOperationInProgress
    }
    
    func setup(coordinator: DynamicIslandViewCoordinator) {
        self.coordinator = coordinator

        // Initialize OSD manager
        Task { @MainActor in
            CustomOSDWindowManager.shared.initialize()
        }

        // Re-resolve flags when a DDC helper starts/stops so brightness handling
        // recovers if the helper is quit while integration stays enabled.
        Task { @MainActor in
            Publishers.Merge(
                BetterDisplayManager.shared.$isRunning.removeDuplicates().map { _ in () },
                LunarManager.shared.$isRunning.removeDuplicates().map { _ in () }
            )
            .sink { [weak self] in
                guard let self, self.isSetupComplete,
                      Defaults[.enableThirdPartyDDCIntegration] else { return }
                Task { @MainActor in
                    await self.startSystemObserver()
                }
            }
            .store(in: &self.cancellables)
        }
        
        // With the external volume listener on, whether the provider or this
        // app owns the volume keys depends on where the sound is going.
        NotificationCenter.default.publisher(for: .systemAudioRouteDidChange)
            .sink { [weak self] _ in
                guard let self, self.isSetupComplete,
                      Defaults[.enableThirdPartyDDCIntegration],
                      Defaults[.enableExternalVolumeControlListener] else { return }
                self.applyResolvedFlags()
            }
            .store(in: &cancellables)

        // Start observer if any HUD/OSD is enabled
        if Defaults[.enableSystemHUD] || Defaults[.enableCustomOSD] || Defaults[.enableVerticalHUD] || Defaults[.enableCircularHUD] {
            Task { @MainActor in
                await startSystemObserver()
                self.isSetupComplete = true
            }
        } else {
            isSetupComplete = true
        }
    }
    
    /// Resolves the effective control flags, applying third-party DDC overrides.
    private func resolvedControlFlags() -> (volume: Bool, brightness: Bool, backlight: Bool, thirdPartyDDC: Bool) {
        var volumeEnabled: Bool
        var brightnessEnabled: Bool
        var keyboardBacklightEnabled: Bool

        if Defaults[.enableCircularHUD] || Defaults[.enableVerticalHUD] {
            volumeEnabled = Defaults[.enableVolumeHUD]
            brightnessEnabled = Defaults[.enableBrightnessHUD]
            keyboardBacklightEnabled = Defaults[.enableKeyboardBacklightHUD]
        } else if Defaults[.enableCustomOSD] {
            volumeEnabled = Defaults[.enableOSDVolume]
            brightnessEnabled = Defaults[.enableOSDBrightness]
            keyboardBacklightEnabled = Defaults[.enableOSDKeyboardBacklight]
        } else {
            volumeEnabled = Defaults[.enableVolumeHUD]
            brightnessEnabled = Defaults[.enableBrightnessHUD]
            keyboardBacklightEnabled = Defaults[.enableKeyboardBacklightHUD]
        }

        // Surrender brightness to the DDC helper only when it is actually running;
        // otherwise keep handling it ourselves so HUDs still show (and the native
        // OSD isn't left permanently suppressed) when the helper has been quit.
        let ddcProviderRunning: Bool = {
            switch Defaults[.thirdPartyDDCProvider] {
            case .betterDisplay: return BetterDisplayManager.checkRunning()
            case .lunar: return LunarManager.checkRunning()
            }
        }()

        let thirdPartyDDCActive = Defaults[.enableThirdPartyDDCIntegration] && ddcProviderRunning
        if thirdPartyDDCActive {
            brightnessEnabled = false
            keyboardBacklightEnabled = false

            // Optional: route volume exclusively from the selected external
            // provider -- but only for outputs it can control.
            if Defaults[.enableExternalVolumeControlListener],
               Self.externalProviderControlsVolume(
                   outputTransport: SystemVolumeController.shared.defaultOutputTransportType
               ) {
                volumeEnabled = false
            }
        }

        return (volumeEnabled, brightnessEnabled, keyboardBacklightEnabled, thirdPartyDDCActive)
    }

    @MainActor
    private func startSystemObserver() async {
        guard let coordinator = coordinator, !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true

        // Stop any existing observer directly (cannot call stopSystemObserver()
        // because isSystemOperationInProgress is already true).
        changesObserver?.stopObserving()
        changesObserver = nil
        
        changesObserver = SystemChangesObserver(coordinator: coordinator)

        let flags = resolvedControlFlags()
        changesObserver?.startObserving(
            volumeEnabled: flags.volume,
            brightnessEnabled: flags.brightness,
            keyboardBacklightEnabled: flags.backlight
        )
        
        // A fresh observer has none of the old one's suppression applied to it,
        // so re-apply the decision rather than trusting the previous one.
        nativeHUDSuppressed = nil
        applyNativeHUDSuppression(for: flags)
        
        print("System observer started (HUD: \(Defaults[.enableSystemHUD]), OSD: \(Defaults[.enableCustomOSD]), Vertical: \(Defaults[.enableVerticalHUD]), ThirdPartyDDC: \(Defaults[.enableThirdPartyDDCIntegration]), Provider: \(Defaults[.thirdPartyDDCProvider].displayName), ExternalVolumeListener: \(Defaults[.enableExternalVolumeControlListener]))")
        isSystemOperationInProgress = false
    }
    
    /// Hands the HUD to macOS while the Mac is locked, and takes it back on
    /// unlock.
    ///
    /// None of this app's HUD styles can be seen over the lock screen — the
    /// inline one lives in the notch, the others sit below the lock screen
    /// shield — so suppressing the system HUD there left the volume keys with
    /// no feedback at all. The exception is the lock screen music panel, which
    /// carries its own slider; unsuppressing then would put two indicators on
    /// screen at once.
    @MainActor
    func updateNativeHUDSuppressionForLockState(isLocked: Bool) {
        // Readiness first, then the record of what has been applied. The other
        // order marked a request applied that this guard had in fact dropped,
        // and every later request for the same state returned early on the
        // strength of it -- so a lock that arrived before setup finished left
        // the HUD in the wrong hands for the rest of the session.
        guard isSetupComplete, changesObserver != nil else { return }
        // Nothing is suppressed, so macOS already draws its HUD everywhere.
        guard nativeHUDSuppressed == true else { return }

        // Handing the HUD over restarts OSDUIHelper, so only act on a change.
        guard isLocked != lastNativeHUDLockState else { return }
        lastNativeHUDLockState = isLocked

        if SystemHUDPlacement.yieldsToNativeHUD(isLocked: isLocked) {
            SystemOSDManager.enableSystemHUD()
        } else {
            SystemOSDManager.disableSystemHUD()
            // disableSystemHUD arms the watcher, which polls; on unlock the
            // helper is already awake and can draw one more HUD before the
            // first poll lands. Freeze it now as well.
            SystemOSDManager.suppressNativeOSDNow()
        }
    }

    @MainActor
    private func stopSystemObserver() async {
        guard !isSystemOperationInProgress else { return }
        
        isSystemOperationInProgress = true
        changesObserver?.stopObserving()
        changesObserver = nil
        nativeHUDSuppressed = nil
        
        // Re-enable system HUD when we stop observing
        SystemOSDManager.enableSystemHUD()
        
        print("System observer stopped")
        isSystemOperationInProgress = false
    }
    
    deinit {
        cancellables.removeAll()
        Task { @MainActor in
            await stopSystemObserver()
        }
    }
}