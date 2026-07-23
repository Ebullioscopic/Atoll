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
import Combine
import SwiftUI
import AVFoundation
import AppKit
import Defaults

class TimerManager: ObservableObject {
    // MARK: - Properties
    static let shared = TimerManager()
    
    @Published var isTimerActive: Bool = false
    @Published var timerName: String = "Timer"
    @Published var totalDuration: TimeInterval = 0
    @Published var remainingTime: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var isPaused: Bool = false
    @Published var isFinished: Bool = false
    @Published var isOvertime: Bool = false // Timer has gone past 0 and is counting negative
    @Published var lastUpdated: Date = .distantPast
    @Published var activePresetId: UUID?
    @Published private(set) var activeSource: TimerSource = .none
    
    // Timer progress (0.0 to 1.0, or >1.0 for overtime)
    var progress: Double {
        guard totalDuration > 0 else { return 0.0 }
        if isOvertime {
            // For overtime, progress goes beyond 1.0
            return 1.0 + min(1.0, abs(remainingTime) / totalDuration)
        } else {
            return min(1.0, max(0.0, elapsedTime / totalDuration))
        }
    }
    
    // Color based on progress: green -> yellow -> red -> flashing red for overtime
    var timerColor: Color {
        if isOvertime {
            // Flashing red for overtime
            return .red
        }
        
        let p = progress
        if p < 0.6 {
            // Green phase (0-60%)
            return .green
        } else if p < 0.9 {
            // Yellow phase (60-90%)
            let yellowProgress = (p - 0.6) / 0.3
            return Color(
                red: 1.0 - (1.0 - yellowProgress) * 0.5, // Gradually more red
                green: 1.0,
                blue: 0.0
            )
        } else {
            // Red phase (90-100%)
            return .red
        }
    }
    
    // Computed properties for UI
    var isRunning: Bool {
        return isTimerActive && !isPaused
    }
    
    var currentColor: Color {
        return timerColor
    }
    
    var formattedTimeRemaining: String {
        return formattedRemainingTime()
    }
    
    var statusText: String {
        if isOvertime {
            return "Overtime"
        } else if isPaused {
            return "Paused"
        } else if isTimerActive {
            return "Running"
        } else {
            return "Ready"
        }
    }
    
    // NSColor version for compatibility
    var timerNSColor: NSColor {
        if isOvertime {
            return NSColor.systemRed
        }
        
        let p = progress
        if p < 0.6 {
            return NSColor.systemGreen
        } else if p < 0.9 {
            let yellowProgress = (p - 0.6) / 0.3
            return NSColor(
                red: 1.0 - (1.0 - yellowProgress) * 0.5,
                green: 1.0,
                blue: 0.0,
                alpha: 1.0
            )
        } else {
            return NSColor.systemRed
        }
    }
    
    private var timerInstance: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var soundPlayer: AVAudioPlayer?
    private var smoothCloseWorkItem: DispatchWorkItem?
    private var lifecycle = TimerLifecycle()

    /// Identifies the current timer run. Delayed cleanup must match this value
    /// before changing presentation state.
    var activeSessionID: UUID? {
        lifecycle.sessionID
    }

    /// Session that most recently reached completion. Starting a replacement
    /// session clears this value before any delayed cleanup can capture it.
    var completedSessionID: UUID? {
        lifecycle.completedSessionID
    }
    // MARK: - Initialization
    private init() {
        // Simple initialization
    }
    
    deinit {
        timerInstance?.invalidate()
        smoothCloseWorkItem?.cancel()
        soundPlayer?.stop()
        cancellables.removeAll()
    }
    
    // MARK: - Timer Methods
    func startTimer(duration: TimeInterval, name: String = "Timer", preset: TimerPreset? = nil) {
        if activeSource == .external {
            endExternalTimer(triggerSmoothClose: false)
        }

        // Stop any existing timer
        timerInstance?.invalidate()
        soundPlayer?.stop()
        beginTimerSession()
        
        // Start new timer
        withAnimation(.smooth) {
            isTimerActive = true
        }
        activeSource = .manual
        isFinished = false
        isOvertime = false
        timerName = name
        totalDuration = duration
        remainingTime = duration
        elapsedTime = 0
        isPaused = false
        lastUpdated = Date()

        activePresetId = preset?.id
        
        // Start countdown timer
        timerInstance = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                if !self.isPaused {
                    if self.remainingTime > 0 {
                        // Normal countdown
                        self.remainingTime -= 1
                        self.elapsedTime = self.totalDuration - self.remainingTime
                        self.lastUpdated = Date()
                    } else if self.remainingTime == 0 {
                        // Timer just finished - play sound and start overtime
                        self.isFinished = true
                        self.isOvertime = true
                        self.playTimerSound()
                        self.remainingTime = -1
                        self.lastUpdated = Date()
                    } else {
                        // Overtime - count negative
                        self.remainingTime -= 1
                        self.lastUpdated = Date()
                    }
                }
            }
        }
    }
    
    func startDemoTimer(duration: TimeInterval) {
        startTimer(duration: duration, name: "Demo Timer")
    }
    
    func stopTimer() {
        if activeSource == .external {
            endExternalTimer(triggerSmoothClose: true)
            return
        }

        timerInstance?.invalidate()
        timerInstance = nil
        soundPlayer?.stop()
        
        // Smooth close animation for live activity
        if isTimerActive {
            scheduleSmoothClose()
        }
        
        resetTimer()
    }
    
    func forceStopTimer() {
        if activeSource == .external {
            endExternalTimer(triggerSmoothClose: false)
            return
        }

        // Immediate stop for user action (stop button)
        timerInstance?.invalidate()
        timerInstance = nil
        soundPlayer?.stop()
        withAnimation(.smooth) {
            isTimerActive = false
        }
        resetTimer()
    }
    
    func pauseTimer() {
        guard activeSource == .manual else { return }
        guard isTimerActive && !isPaused else { return }
        isPaused = true
        timerInstance?.invalidate()
        timerInstance = nil
    }
    
    func resumeTimer() {
        guard activeSource == .manual else { return }
        guard isTimerActive && isPaused else { return }
        isPaused = false
        lastUpdated = Date()
        
        // Resume countdown timer with same logic as start timer
        timerInstance = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                if !self.isPaused {
                    if self.remainingTime > 0 {
                        // Normal countdown
                        self.remainingTime -= 1
                        self.elapsedTime = self.totalDuration - self.remainingTime
                        self.lastUpdated = Date()
                    } else if self.remainingTime == 0 {
                        // Timer just finished - play sound and start overtime
                        self.isFinished = true
                        self.isOvertime = true
                        self.playTimerSound()
                        self.remainingTime = -1
                        self.lastUpdated = Date()
                    } else {
                        // Overtime - count negative
                        self.remainingTime -= 1
                        self.lastUpdated = Date()
                    }
                }
            }
        }
    }

    func adoptExternalTimer(name: String, totalDuration: TimeInterval, remaining: TimeInterval, isPaused: Bool) {
        guard activeSource != .manual else { return }

        timerInstance?.invalidate()
        timerInstance = nil
        soundPlayer?.stop()
        beginTimerSession()

        activeSource = .external

        let clampedTotal = totalDuration > 0 ? totalDuration : max(totalDuration, remaining)

        withAnimation(.smooth) {
            isTimerActive = true
        }

        timerName = name.isEmpty ? "Clock Timer" : name
        self.totalDuration = clampedTotal
        remainingTime = remaining
        elapsedTime = max(0, clampedTotal - remaining)
        self.isPaused = isPaused
        isFinished = false
        isOvertime = remaining < 0
        activePresetId = nil
        lastUpdated = Date()
    }

    func updateExternalTimer(remaining: TimeInterval, totalDuration: TimeInterval?, isPaused paused: Bool, name: String? = nil) {
        guard activeSource == .external else { return }

        // Clock may reuse both the timer ID and duration. A positive update
        // after completion is nevertheless a new run and must invalidate the
        // previous run's delayed close.
        if remaining > 0 && (isFinished || isOvertime || remainingTime <= 0) {
            beginTimerSession()
            withAnimation(.smooth) {
                isTimerActive = true
            }
        }

        if let name, !name.isEmpty, name != timerName {
            timerName = name
        }

        if let totalDuration, totalDuration > 0 {
            self.totalDuration = max(totalDuration, self.totalDuration)
        } else if self.totalDuration <= 0 {
            self.totalDuration = max(self.totalDuration, remaining)
        }

        remainingTime = remaining
        elapsedTime = max(0, self.totalDuration - remaining)
        isOvertime = remaining < 0
        isPaused = paused
        isFinished = remaining <= 0 && !isOvertime
        lastUpdated = Date()
    }

    func completeExternalTimer() {
        guard activeSource == .external else { return }

        lifecycle.completeSession()
        remainingTime = 0
        elapsedTime = totalDuration
        isOvertime = false
        isFinished = true
        lastUpdated = Date()
        scheduleSmoothClose()
    }

    func endExternalTimer(triggerSmoothClose: Bool) {
        guard activeSource == .external else { return }

        if triggerSmoothClose && isTimerActive {
            scheduleSmoothClose()
        } else {
            withAnimation(.smooth) {
                isTimerActive = false
            }
        }

        resetTimer()
    }
    
    private func resetTimer() {
        endTimerSession()
        withAnimation(.smooth) {
            isTimerActive = false
        }
        timerName = "Timer"
        totalDuration = 0
        remainingTime = 0
        elapsedTime = 0
        isPaused = false
        isFinished = false
        isOvertime = false
        activePresetId = nil
        activeSource = .none
    }

    // MARK: - Derived State
    var activePreset: TimerPreset? {
        guard let presetId = activePresetId else { return nil }
        return Defaults[.timerPresets].first { $0.id == presetId }
    }

    var isExternalTimerActive: Bool {
        activeSource == .external && isTimerActive
    }

    var hasManualTimerRunning: Bool {
        activeSource == .manual && isTimerActive
    }

    var allowsManualInteraction: Bool {
        activeSource != .external
    }

    enum TimerSource: String {
        case none
        case manual
        case external
    }

    private func scheduleSmoothClose() {
        guard let sessionID = activeSessionID else { return }

        smoothCloseWorkItem?.cancel()

        // Wait 3 seconds then smoothly close the live activity
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.lifecycle.isCurrent(sessionID) else { return }
            self.smoothCloseWorkItem = nil
            withAnimation(.easeInOut(duration: 1.0)) {
                self.isTimerActive = false
            }
        }

        smoothCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    private func beginTimerSession() {
        smoothCloseWorkItem?.cancel()
        smoothCloseWorkItem = nil
        lifecycle.beginSession()
    }

    private func endTimerSession() {
        smoothCloseWorkItem?.cancel()
        smoothCloseWorkItem = nil
        lifecycle.endSession()
    }
    
    private func playTimerSound() {
        var soundURL: URL?
        
        // Check for custom timer sound first
        let customTimerSoundPath = UserDefaults.standard.string(forKey: "customTimerSoundPath")
        if let customPath = customTimerSoundPath, !customPath.isEmpty {
            // Use custom sound file
            soundURL = URL(fileURLWithPath: customPath)
            
            // Verify the file exists
            if !FileManager.default.fileExists(atPath: customPath) {
                soundURL = nil
            }
        }
        
        // Fall back to default sound if no custom sound or custom sound doesn't exist
        if soundURL == nil {
            soundURL = Bundle.main.url(forResource: "timer", withExtension: "mp3")
                ?? Bundle.main.url(forResource: "dynamic", withExtension: "m4a")
        }
        
        guard let finalSoundURL = soundURL else {
            // Final fallback to system sound
            NSSound.beep()
            return
        }
        
        do {
            soundPlayer = try AVAudioPlayer(contentsOf: finalSoundURL)
            soundPlayer?.numberOfLoops = -1 // Loop indefinitely
            soundPlayer?.play()
        } catch {
            // Fallback to system sound if there's an error playing the custom sound
            NSSound.beep()
        }
    }
    
    // MARK: - Formatted Time Strings
    func formattedRemainingTime() -> String {
        if isOvertime && remainingTime < 0 {
            return "-" + timeString(from: abs(remainingTime))
        } else {
            return timeString(from: remainingTime)
        }
    }
    
    func formattedElapsedTime() -> String {
        return timeString(from: elapsedTime)
    }
    
    func formattedTotalDuration() -> String {
        return timeString(from: totalDuration)
    }
    
    private func timeString(from seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}
