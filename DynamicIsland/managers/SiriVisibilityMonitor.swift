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
final class SiriVisibilityMonitor {
    static let shared = SiriVisibilityMonitor()
    
    @Published private(set) var isSiriVisible = false
    
    private var monitoringTimer: Timer?
    private var lastSiriState = false
    
    private init() {}
    
    func startMonitoring() {
        guard monitoringTimer == nil else { return }
        
        // Poll every 0.5 seconds to detect Siri presence
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkSiriVisibility()
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
        }
    }
    
    private func detectSiriWindow() -> Bool {
        // Look only at windows currently rendered on screen
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        
        return windowList.contains { window in
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            
            // Siri's lock screen window is massive (Height > 500 per the reported case)
            // We ensure we are detecting the actual Siri UI, not a tiny background daemon window
            let bounds = window[kCGWindowBounds as String] as? [String: Int] ?? [:]
            let height = bounds["Height"] ?? 0
            
            return owner == "Siri" && height > 500
        }
    }
}
