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

import Cocoa
import Combine
import Defaults

@MainActor
final class SiriVisibilityMonitor: ObservableObject {
    static let shared = SiriVisibilityMonitor()
    
    @Published private(set) var isSiriVisible = false
    
    private var monitoringTimer: Timer?
    private var lastSiriState = false
    private var isScreenLocked = false
    private var isDisplayOn = true
    private var isPluggedIn = false
    private var isInLowPowerMode = false
    private var cancellables = Set<AnyCancellable>()
    
    // Hysteresis: Require multiple consecutive "not found" checks before declaring Siri gone
    private var disappearanceConfirmationCount = 0
    private let disappearanceThreshold = 3 // ~100ms at high performance
    
    // Polling intervals calculated dynamically
    private var currentIdleInterval: TimeInterval {
        calculateIntervals().idle
    }
    
    private var currentActiveInterval: TimeInterval {
        calculateIntervals().active
    }
    
    private init() {
        setupStateObservers()
    }
    
    private func setupStateObservers() {
        // Observe lock state via LockScreenManager
        LockScreenManager.shared.$isLocked
            .receive(on: RunLoop.main)
            .sink { [weak self] locked in
                self?.isScreenLocked = locked
                self?.updateMonitoringState()
            }
            .store(in: &cancellables)
            
        // Observe display sleep/wake
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isDisplayOn = false
            self?.updateMonitoringState()
        }
        workspaceCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isDisplayOn = true
            self?.updateMonitoringState()
        }

        // Observe power state
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.isInLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            self?.updateMonitoringState()
        }
        self.isInLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // Observe plugged in state via BatteryActivityManager
        BatteryActivityManager.shared.onPowerSourceChange = { [weak self] pluggedIn in
            Task { @MainActor in
                self?.isPluggedIn = pluggedIn
                self?.updateMonitoringState()
            }
        }
        
        // Observe responsiveness mode preference
        Defaults.publisher(.siriResponsivenessMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMonitoringState()
            }
            .store(in: &cancellables)
    }

    private func calculateIntervals() -> (idle: TimeInterval, active: TimeInterval) {
        let mode = Defaults[.siriResponsivenessMode]
        
        let effectiveMode: SiriResponsivenessMode
        if mode == .automatic {
            if isInLowPowerMode {
                effectiveMode = .powerSaver
            } else if isPluggedIn {
                effectiveMode = .highPerformance
            } else {
                effectiveMode = .balanced
            }
        } else {
            effectiveMode = mode
        }

        let intervals: (idle: TimeInterval, active: TimeInterval)
        switch effectiveMode {
        case .highPerformance:
            intervals = (idle: 0.2, active: 0.03) // ~33Hz active
        case .balanced, .automatic:
            intervals = (idle: 0.5, active: 0.06) // ~16Hz active (Fluid motion)
        case .powerSaver:
            intervals = (idle: 2.0, active: 0.25) // 4Hz active, 0.5Hz idle
        }
        
        print("⏱️ [SiriVisibilityMonitor] Mode: \(effectiveMode) (User Pref: \(mode)) -> Intervals: Idle \(intervals.idle)s, Active \(intervals.active)s")
        return intervals
    }
    
    private func updateMonitoringState() {
        let shouldMonitor = isScreenLocked && isDisplayOn
        
        print("🔌 [SiriVisibilityMonitor] State Update - Locked: \(isScreenLocked), Display: \(isDisplayOn), Plugged: \(isPluggedIn), LPM: \(isInLowPowerMode)")
        
        if shouldMonitor {
            startMonitoring()
        } else {
            stopMonitoring()
            // Reset state when monitoring stops
            if isSiriVisible {
                isSiriVisible = false
                lastSiriState = false
            }
        }
    }
    
    private func startMonitoring() {
        // If already monitoring with correct interval, do nothing
        let currentInterval = isSiriVisible ? currentActiveInterval : currentIdleInterval
        
        // Restart timer if interval changed or if it was nil
        if monitoringTimer?.timeInterval != currentInterval {
            monitoringTimer?.invalidate()
            monitoringTimer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: true) { [weak self] _ in
                self?.checkSiriVisibility()
            }
            monitoringTimer?.tolerance = currentInterval * 0.1
        }
    }
    
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
    }
    
    private func checkSiriVisibility() {
        let isSiriActive = detectSiriWindow()
        
        if isSiriActive {
            // Siri is found: Update state immediately
            disappearanceConfirmationCount = 0
            if !lastSiriState {
                updateSiriVisibility(true)
            }
        } else {
            // Siri not found: Debounce disappearance
            if lastSiriState {
                disappearanceConfirmationCount += 1
                if disappearanceConfirmationCount >= disappearanceThreshold {
                    updateSiriVisibility(false)
                    disappearanceConfirmationCount = 0
                }
            }
        }
    }

    private func updateSiriVisibility(_ visible: Bool) {
        lastSiriState = visible
        isSiriVisible = visible
        
        // Adjust polling rate immediately based on visibility
        startMonitoring()
    }
    
    private func detectSiriWindow() -> Bool {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        return windowList.contains { window in
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            let bounds = window[kCGWindowBounds as String] as? [String: Int] ?? [:]
            let height = bounds["Height"] ?? 0
            
            // Siri lock screen window is large (usually covers bottom half or more)
            return owner == "Siri" && height > 400
        }
    }
    
    /// Centralized helper to automatically fade a window based on Siri visibility.
    func autohide(_ window: NSWindow?, cancellables: inout Set<AnyCancellable>) {
        guard let window else { return }
        
        Publishers.CombineLatest($isSiriVisible, LockScreenManager.shared.$isLocked)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .receive(on: RunLoop.main)
            .sink { isVisible, isLocked in
                // Safety: Only manage visibility if the screen is actually locked.
                // This prevents 'autohide' from fighting with the manager's hide animation
                // during unlock, and prevents clearing unlock animations via removeAllAnimations().
                guard isLocked else { return }
                
                let targetAlpha: CGFloat = isVisible ? 0.0 : 1.0
                
                // Stop any current animation to prevent flickering if state changes mid-fade
                window.contentView?.layer?.removeAllAnimations()
                
                if window.alphaValue != targetAlpha {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.25 // Smooth fade
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        window.animator().alphaValue = targetAlpha
                    }
                }
            }
            .store(in: &cancellables)
    }
}
