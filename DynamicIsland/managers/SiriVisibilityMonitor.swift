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

@MainActor
final class SiriVisibilityMonitor: ObservableObject {
    static let shared = SiriVisibilityMonitor()
    
    @Published private(set) var isSiriVisible = false
    
    private var monitoringTimer: Timer?
    private var lastSiriState = false
    private var isScreenLocked = false
    private var isDisplayOn = true
    private var cancellables = Set<AnyCancellable>()
    
    private let idleInterval: TimeInterval = 0.5    // Slow heartbeat when locked
    private let activeInterval: TimeInterval = 0.1  // Fast polling when Siri is visible
    
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
    }
    
    private func updateMonitoringState() {
        let shouldMonitor = isScreenLocked && isDisplayOn
        
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
        let currentInterval = isSiriVisible ? activeInterval : idleInterval
        
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
        
        if isSiriActive != lastSiriState {
            lastSiriState = isSiriActive
            isSiriVisible = isSiriActive
            
            // Adjust polling rate immediately based on visibility
            startMonitoring()
        }
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
        
        $isSiriVisible
            .receive(on: RunLoop.main)
            .sink { isVisible in
                let targetAlpha: CGFloat = isVisible ? 0.0 : 1.0
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
