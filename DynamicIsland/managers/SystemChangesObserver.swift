//
//  SystemChangesObserver.swift
//  DynamicIsland
//
//  Adapted from TheBoringWorker-HUD ChangesObserver.swift
//  Created by GitHub Copilot on 06/09/25.
//

import Cocoa
import Foundation
import Defaults

class SystemChangesObserver {
    private var oldVolume: Float = 0
    private var oldMuted: Bool = false
    private var oldBrightness: Float = 0
    
    private weak var coordinator: DynamicIslandViewCoordinator?
    
    // Backup timer for edge cases only
    private var backupTimer: Timer?

    init(coordinator: DynamicIslandViewCoordinator) {
        self.coordinator = coordinator
        
        // Initialize baseline values only once
        oldVolume = SystemVolumeManager.getOutputVolume()
        oldMuted = SystemVolumeManager.isMuted()
        
        do {
            oldBrightness = try SystemDisplayManager.getDisplayBrightness()
        } catch {
            NSLog("Failed to retrieve initial display brightness: \(error)")
        }
    }

    func startObserving() {
        guard Defaults[.enableSystemHUD] else { return }
        
        startMinimalBackupTimer()
    }
    
    private func startMinimalBackupTimer() {
        // More frequent backup check (every 300ms) for better responsiveness
        // This is a reasonable compromise between the original 200ms and the previous 5s
        backupTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard Defaults[.enableSystemHUD] else { return }
            self?.performBackupCheck()
        }
    }
    
    private func performBackupCheck() {
        // Only check if we haven't had recent activity
        checkVolumeChanges()
        checkBrightnessChanges()
    }
    
    // MARK: - Public Media Key Event Handlers (called from MediaKeyApplication)
    
    func handleVolumeKeyEvent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.handleVolumeKeyPress()
        }
    }
    
    func handleBrightnessKeyEvent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.handleBrightnessKeyPress()
        }
    }
    
    // MARK: - Key Press Event Handlers
    
    private func handleVolumeKeyPress() {
        guard Defaults[.enableVolumeHUD] else { return }
        
        let newVolume = SystemVolumeManager.getOutputVolume()
        let newMuted = SystemVolumeManager.isMuted()
        
        // Always show HUD for key press feedback, even if value doesn't change
        print("🔊 Volume key pressed - showing HUD: volume=\(newVolume), muted=\(newMuted)")
        
        if newMuted {
            sendVolumeNotification(value: 0.0)
        } else {
            sendVolumeNotification(value: newVolume)
        }
        
        // Update stored values
        oldVolume = newVolume
        oldMuted = newMuted
    }
    
    private func handleBrightnessKeyPress() {
        guard Defaults[.enableBrightnessHUD] else { return }
        guard NSScreen.screens.count > 0 else { return }
        
        do {
            let newBrightness = try SystemDisplayManager.getDisplayBrightness()
            
            // Always show HUD for key press feedback, even if value doesn't change
            print("☀️ Brightness key pressed - showing HUD: brightness=\(newBrightness)")
            sendBrightnessNotification(value: newBrightness)
            
            // Update stored value
            oldBrightness = newBrightness
        } catch {
            // Silently ignore brightness errors to reduce log spam
        }
    }

    private func checkVolumeChanges() {
        guard Defaults[.enableVolumeHUD] else { return }
        
        let newVolume = SystemVolumeManager.getOutputVolume()
        let newMuted = SystemVolumeManager.isMuted()
        
        let volumeChanged = !isAlmost(firstNumber: oldVolume, secondNumber: newVolume)
        let muteChanged = newMuted != oldMuted
        
        if volumeChanged || muteChanged {
            print("🔊 Volume change detected: \(oldVolume) → \(newVolume), muted: \(oldMuted) → \(newMuted)")
            
            if newMuted {
                sendVolumeNotification(value: 0.0)
            } else {
                sendVolumeNotification(value: newVolume)
            }
            oldVolume = newVolume
            oldMuted = newMuted
        }
    }

    private func checkBrightnessChanges() {
        guard Defaults[.enableBrightnessHUD] else { return }
        guard NSScreen.screens.count > 0 else { return }
        
        do {
            let newBrightness = try SystemDisplayManager.getDisplayBrightness()
            let brightnessChanged = !isAlmost(firstNumber: oldBrightness, secondNumber: newBrightness)
            
            if brightnessChanged {
                print("☀️ Brightness change detected: \(oldBrightness) → \(newBrightness)")
                sendBrightnessNotification(value: newBrightness)
                oldBrightness = newBrightness
            }
        } catch {
            // Silently ignore brightness errors to reduce log spam
        }
    }
    
    private func isAlmost(firstNumber: Float, secondNumber: Float) -> Bool {
        // Convert sensitivity setting to a more responsive threshold
        // Sensitivity 1-10 scale maps to 0.01-0.10 threshold range
        let marginValue = Float(Defaults[.systemHUDSensitivity]) / 100.0
        let threshold = max(0.01, marginValue) // Minimum threshold for responsiveness
        return abs(firstNumber - secondNumber) <= threshold
    }
    
    // MARK: - Internal Notification Methods
    
    private func sendVolumeNotification(value: Float) {
        coordinator?.toggleSneakPeek(
            status: true,
            type: .volume,
            value: CGFloat(value),
            icon: ""
        )
    }
    
    private func sendBrightnessNotification(value: Float) {
        coordinator?.toggleSneakPeek(
            status: true,
            type: .brightness,
            value: CGFloat(value),
            icon: ""
        )
    }
    
    deinit {
        stopObserving()
    }
    
    func stopObserving() {
        // Clean up backup timer
        backupTimer?.invalidate()
        backupTimer = nil
        
        print("🎹 Media key detection stopped")
    }
}


