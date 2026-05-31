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
import CoreGraphics
import Defaults
import AppKit
import AVFoundation

final class SystemChangesObserver: MediaKeyInterceptorDelegate {
    private weak var coordinator: DynamicIslandViewCoordinator?
    private let volumeController = SystemVolumeController.shared
    private let brightnessController = SystemBrightnessController.shared
    private let keyboardBacklightController = SystemKeyboardBacklightController.shared
    private let mediaKeyInterceptor = MediaKeyInterceptor.shared
    private let volumeFeedbackPlayer = VolumeFeedbackPlayer.shared
    private var volumeDebounceWorkItem: DispatchWorkItem?
    private var brightnessDebounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.016 // one frame

    private static let headsetIconSymbols: Set<String> = [
        "airpods",
        "airpodspro",
        "airpodsmax",
        "beats.headphones",
        "headphones"
    ]

    private var standardVolumeStep: Float {
        Float(Defaults[.volumeStepPercent]) / 100.0
    }
    private var fineVolumeStep: Float {
        Float(Defaults[.volumeFineStepPercent]) / 100.0
    }
    private var standardBrightnessStep: Float {
        Float(Defaults[.brightnessStepPercent]) / 100.0
    }
    private var fineBrightnessStep: Float {
        Float(Defaults[.brightnessFineStepPercent]) / 100.0
    }

    private var volumeEnabled = false
    private var brightnessEnabled = false
    private var keyboardBacklightEnabled = false

    init(coordinator: DynamicIslandViewCoordinator) {
        self.coordinator = coordinator
    }

    func startObserving(volumeEnabled: Bool, brightnessEnabled: Bool, keyboardBacklightEnabled: Bool) {
        self.volumeEnabled = volumeEnabled
        self.brightnessEnabled = brightnessEnabled
        self.keyboardBacklightEnabled = keyboardBacklightEnabled

        volumeController.onVolumeChange = { [weak self] volume, muted in
            guard let self, self.volumeEnabled else { return }
            let value = muted ? 0 : volume
            self.volumeDebounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.sendVolumeNotification(value: value, isMuted: muted)
                }
            }
            self.volumeDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + self.debounceInterval, execute: workItem)
        }
        volumeController.onRouteChange = { [weak self] in
            guard let self, self.volumeEnabled else { return }
            let muted = self.volumeController.isMuted
            Task { @MainActor in
                self.sendVolumeNotification(value: muted ? 0 : self.volumeController.currentVolume, isMuted: muted)
            }
        }
        volumeController.start()

        brightnessController.onBrightnessChange = { [weak self] brightness in
            guard let self, self.brightnessEnabled else { return }
            self.brightnessDebounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.sendBrightnessNotification(value: brightness)
            }
            self.brightnessDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + self.debounceInterval, execute: workItem)
        }
        brightnessController.start()

        configureKeyboardBacklightCallback()
        if keyboardBacklightEnabled {
            keyboardBacklightController.start()
        }

        mediaKeyInterceptor.delegate = self
        let tapStarted = mediaKeyInterceptor.start()
        if !tapStarted {
            NSLog("⚠️ Media key interception unavailable; system HUD will remain visible")
        }
        mediaKeyInterceptor.configuration = MediaKeyConfiguration(
            interceptVolume: volumeEnabled,
            interceptBrightness: brightnessEnabled,
            interceptCommandModifiedBrightness: keyboardBacklightEnabled
        )
    }

    func update(volumeEnabled: Bool, brightnessEnabled: Bool, keyboardBacklightEnabled: Bool) {
        self.volumeEnabled = volumeEnabled
        self.brightnessEnabled = brightnessEnabled
        let backlightStateChanged = self.keyboardBacklightEnabled != keyboardBacklightEnabled
        self.keyboardBacklightEnabled = keyboardBacklightEnabled

        if keyboardBacklightEnabled {
            configureKeyboardBacklightCallback()
        } else {
            keyboardBacklightController.onBacklightChange = nil
        }

        if backlightStateChanged {
            if keyboardBacklightEnabled {
                keyboardBacklightController.start()
            } else {
                keyboardBacklightController.stop()
            }
        }

        mediaKeyInterceptor.configuration = MediaKeyConfiguration(
            interceptVolume: volumeEnabled,
            interceptBrightness: brightnessEnabled,
            interceptCommandModifiedBrightness: keyboardBacklightEnabled
        )
    }

    func stopObserving() {
        mediaKeyInterceptor.stop()
        mediaKeyInterceptor.delegate = nil

        volumeController.stop()
        volumeController.onVolumeChange = nil
        volumeController.onRouteChange = nil

        brightnessController.stop()
        brightnessController.onBrightnessChange = nil

        keyboardBacklightController.stop()
        keyboardBacklightController.onBacklightChange = nil
    }

    // MARK: - MediaKeyInterceptorDelegate

    func mediaKeyInterceptor(
        _ interceptor: MediaKeyInterceptor,
        didReceiveVolumeCommand direction: MediaKeyDirection,
        step: MediaKeyStep,
        isRepeat: Bool,
        modifiers: NSEvent.ModifierFlags
    ) {
        guard volumeEnabled else { return }
        
        // Elastic Limit Detection (Vertical HUD)
        if Defaults[.enableVerticalHUD] {
            let volume = volumeController.currentVolume
            if direction == .up && volume >= 0.99 {
                Task { @MainActor in VerticalHUDWindowManager.shared.triggerBump(direction: 1) }
            } else if direction == .down && volume <= 0.01 {
                Task { @MainActor in VerticalHUDWindowManager.shared.triggerBump(direction: -1) }
            }
        }
        
        let baseStep = volumeStep(for: step)
        let delta = direction == .up ? baseStep : -baseStep
        volumeController.adjust(by: delta)
        volumeFeedbackPlayer.playIfNeeded()
    }

    func mediaKeyInterceptorDidToggleMute(_ interceptor: MediaKeyInterceptor) {
        guard volumeEnabled else { return }
        volumeController.toggleMute()
    }

    func mediaKeyInterceptor(
        _ interceptor: MediaKeyInterceptor,
        didReceiveBrightnessCommand direction: MediaKeyDirection,
        step: MediaKeyStep,
        isRepeat: Bool,
        modifiers: NSEvent.ModifierFlags
    ) {
        let isBacklight = modifiers.contains(.command) && keyboardBacklightEnabled
        guard isBacklight || brightnessEnabled else { return }

        // Elastic Limit Detection (Vertical HUD)
        if Defaults[.enableVerticalHUD] {
            let brightness = brightnessController.currentBrightness
            if direction == .up && brightness >= 0.99 {
                Task { @MainActor in VerticalHUDWindowManager.shared.triggerBump(direction: 1) }
            } else if direction == .down && brightness <= 0.01 {
                Task { @MainActor in VerticalHUDWindowManager.shared.triggerBump(direction: -1) }
            }
        }

        let baseStep = brightnessStep(for: step)
        let delta = direction == .up ? baseStep : -baseStep
        if isBacklight {
            keyboardBacklightController.adjust(by: delta)
        } else {
            brightnessController.adjust(by: delta)
        }
    }

    // MARK: - HUD Dispatch

    @MainActor
    private func sendVolumeNotification(value: Float, isMuted: Bool) {
        if HUDSuppressionCoordinator.shared.shouldSuppressVolumeHUD {
            return
        }
        
        // Send to Circular HUD if enabled
        if Defaults[.enableCircularHUD] && Defaults[.enableVolumeHUD] {
            Task { @MainActor in
                CircularHUDWindowManager.shared.show(type: .volume, value: CGFloat(value))
            }
            return
        }
        
        // Send to Vertical HUD if enabled
        if Defaults[.enableVerticalHUD] && Defaults[.enableVolumeHUD] {
            let icon = resolvedVolumeIcon(isMuted: isMuted)
            VerticalHUDWindowManager.shared.show(type: .volume, value: CGFloat(value), icon: icon)
            return
        }
        
        // Send to custom OSD if enabled
        if Defaults[.enableCustomOSD] && Defaults[.enableOSDVolume] {
            Task { @MainActor in
                CustomOSDWindowManager.shared.showVolume(value: CGFloat(value))
            }
        }
        
        // Send to notch HUD if enabled and OSD/Vertical/Circular is not enabled
        if Defaults[.enableSystemHUD] && !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] && Defaults[.enableVolumeHUD] {
            Task { @MainActor in
                guard let coordinator else { return }
                coordinator.toggleSneakPeek(
                    status: true,
                    type: .volume,
                    value: CGFloat(value),
                    icon: ""
                )
            }
        }
    }

    @MainActor
    private func resolvedVolumeIcon(isMuted: Bool) -> String {
        guard let icon = BluetoothAudioManager.shared.activeDeviceIconSymbol() else { return "" }
        if isMuted && Self.headsetIconSymbols.contains(icon) {
            return "headphones.slash"
        }
        return icon
    }

    private func sendBrightnessNotification(value: Float) {
        // Send to Circular HUD if enabled
        if Defaults[.enableCircularHUD] && Defaults[.enableBrightnessHUD] {
            Task { @MainActor in
                CircularHUDWindowManager.shared.show(type: .brightness, value: CGFloat(value))
            }
            return
        }
        
        // Send to Vertical HUD if enabled
        if Defaults[.enableVerticalHUD] && Defaults[.enableBrightnessHUD] {
            Task { @MainActor in
                VerticalHUDWindowManager.shared.show(type: .brightness, value: CGFloat(value))
            }
            return
        }

        // Send to custom OSD if enabled
        if Defaults[.enableCustomOSD] && Defaults[.enableOSDBrightness] {
            Task { @MainActor in
                CustomOSDWindowManager.shared.showBrightness(value: CGFloat(value))
            }
        }
        
        // Send to notch HUD if enabled and OSD/Vertical/Circular is not enabled
        if Defaults[.enableSystemHUD] && !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] && Defaults[.enableBrightnessHUD] {
            Task { @MainActor in
                guard let coordinator else { return }
                coordinator.toggleSneakPeek(
                    status: true,
                    type: .brightness,
                    value: CGFloat(value),
                    icon: ""
                )
            }
        }
    }

    private func sendKeyboardBacklightNotification(value: Float) {
        // Send to Circular HUD if enabled
        if Defaults[.enableCircularHUD] && Defaults[.enableKeyboardBacklightHUD] {
            Task { @MainActor in
                CircularHUDWindowManager.shared.show(type: .backlight, value: CGFloat(value))
            }
            return
        }
        
        // Send to Vertical HUD if enabled
        if Defaults[.enableVerticalHUD] && Defaults[.enableKeyboardBacklightHUD] {
            Task { @MainActor in
                VerticalHUDWindowManager.shared.show(type: .backlight, value: CGFloat(value))
            }
            return
        }

        // Send to custom OSD if enabled
        if Defaults[.enableCustomOSD] && Defaults[.enableOSDKeyboardBacklight] {
            Task { @MainActor in
                CustomOSDWindowManager.shared.showBacklight(value: CGFloat(value))
            }
        }
        
        // Send to notch HUD if enabled and OSD/Vertical/Circular is not enabled
        if Defaults[.enableSystemHUD] && !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] && Defaults[.enableKeyboardBacklightHUD] {
            Task { @MainActor in
                guard let coordinator else { return }
                coordinator.toggleSneakPeek(
                    status: true,
                    type: .backlight,
                    value: CGFloat(value),
                    icon: ""
                )
            }
        }
    }

    private func configureKeyboardBacklightCallback() {
        if keyboardBacklightEnabled {
            keyboardBacklightController.onBacklightChange = { [weak self] value in
                guard let self, self.keyboardBacklightEnabled else { return }
                self.sendKeyboardBacklightNotification(value: value)
            }
        } else {
            keyboardBacklightController.onBacklightChange = nil
        }
    }
}

private extension SystemChangesObserver {
    func volumeStep(for step: MediaKeyStep) -> Float {
        switch step {
        case .standard:
            return standardVolumeStep
        case .fine:
            return fineVolumeStep
        }
    }

    func brightnessStep(for step: MediaKeyStep) -> Float {
        switch step {
        case .standard:
            return standardBrightnessStep
        case .fine:
            return fineBrightnessStep
        }
    }
}

private final class VolumeFeedbackPlayer {
    static let shared = VolumeFeedbackPlayer()

    private let queue = DispatchQueue(label: "com.dynamicisland.volume-feedback-player")
    private var player: AVAudioPlayer?
    private var lastPlayDate: Date = .distantPast
    private let minimumInterval: TimeInterval = 0.08
    private var didLogMissingAsset = false

    private init() {}

    func playIfNeeded() {
        guard Defaults[.playVolumeChangeFeedback] else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let now = Date()
            guard now.timeIntervalSince(self.lastPlayDate) >= self.minimumInterval else { return }
            self.lastPlayDate = now
            self.preparePlayerIfNeeded()
            guard let player = self.player else { return }
            player.currentTime = 0
            player.play()
        }
    }

    private func preparePlayerIfNeeded() {
        if player != nil { return }
        guard let url = Bundle.main.url(forResource: "audio-feedback", withExtension: "m4a") else {
            if !didLogMissingAsset {
                NSLog("⚠️ audio-feedback.m4a is missing from the app bundle; volume feedback disabled.")
                didLogMissingAsset = true
            }
            return
        }

        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.volume = 1
            audioPlayer.prepareToPlay()
            player = audioPlayer
        } catch {
            if !didLogMissingAsset {
                NSLog("⚠️ Failed to initialize volume feedback player: \(error.localizedDescription)")
                didLogMissingAsset = true
            }
        }
    }
}


