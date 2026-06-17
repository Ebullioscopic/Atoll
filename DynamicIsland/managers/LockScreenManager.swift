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
import AppKit
import Defaults
import SwiftUI
import AVFoundation

enum LockScreenAnimationTimings {
    static let lockExpand: TimeInterval = 0.45
    static let unlockCollapse: TimeInterval = 0.82
    static let postUnlockMusicHUDPause: TimeInterval = 1.0
    static let postUnlockMusicHUDReveal: TimeInterval = 0.34
}

@MainActor
class LockScreenManager: ObservableObject {
    static let shared = LockScreenManager()
    
    // MARK: - Coordinator
    private let coordinator = DynamicIslandViewCoordinator.shared
    private weak var viewModel: DynamicIslandViewModel?
    
    // MARK: - Published Properties
    @Published var isLocked: Bool = false
    @Published var isLockIdle: Bool = true
    @Published var shouldDelayPostUnlockMusicHUD: Bool = false
    @Published var lastUpdated: Date = .distantPast
    
    // MARK: - Private Properties
    private var debounceIdleTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var postUnlockMusicHUDTask: Task<Void, Never>?
    private var lockStatePollTask: Task<Void, Never>?
    
    // MARK: - Helpers
    
    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    // MARK: - Initialization
    private init() {
        setupObservers()
        print("LockScreenManager: 🔒 Initialized")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            print("DEBUG: ASYNC NSApplication.shared.delegate is \(String(describing: NSApplication.shared.delegate))")
        }
    }
    
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        debounceIdleTask?.cancel()
        collapseTask?.cancel()
        postUnlockMusicHUDTask?.cancel()
        lockStatePollTask?.cancel()
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Observe screen locked event
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenLocked),
            name: .init("com.apple.screenIsLocked"),
            object: nil
        )

        // Observe screen unlocked event
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: .init("com.apple.screenIsUnlocked"),
            object: nil
        )

        // Fallback: macOS sometimes delays `com.apple.screenIsUnlocked`, leaving
        // lock-screen widgets visible after the user-perceived unlock.
        // The workspace session-active notification typically fires earlier; the
        // guard at the top of `screenUnlocked` makes the call idempotent.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenUnlocked),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        print("LockScreenManager: ✅ Observers registered for lock/unlock events")
    }
    
    // MARK: - Event Handlers
    
    @objc private func screenLocked() {
        guard !isLocked else {
            print("[\(timestamp())] LockScreenManager: 🔁 Duplicate LOCK event ignored")
            return
        }
        print("[\(timestamp())] LockScreenManager: 🔒 Screen LOCKED event received")
        Logger.log("LockScreenManager: Screen locked", category: .lifecycle)
        LockSoundPlayer.shared.playLockChime()
        LockScreenDisplayContextProvider.shared.refresh(reason: "screen-locked")
        
        // Update state SYNCHRONOUSLY without Task/await to avoid any delay
        lastUpdated = Date()
        updateIdleState(locked: true)
        postUnlockMusicHUDTask?.cancel()
        shouldDelayPostUnlockMusicHUD = false
        
        // Set locked state immediately without animation wrapper
        isLocked = true
        collapseTask?.cancel()

        viewModel?.closeForLockScreen()

        if coordinator.expandingView.show {
            let currentType = coordinator.expandingView.type
            coordinator.toggleExpandingView(status: false, type: currentType)
        }

        if coordinator.sneakPeek.show {
            coordinator.toggleSneakPeek(status: false, type: coordinator.sneakPeek.type)
        }
        
        // Show panel FIRST (creates and shows window on lock screen)
        print("[\(timestamp())] LockScreenManager: 🎵 Showing lock screen panel")
        LockScreenPanelManager.shared.showPanel()
        LockScreenLiveActivityWindowManager.shared.showLocked()
        LockScreenWeatherManager.shared.showWeatherWidget()
        LockScreenTimerWidgetManager.shared.handleLockStateChange(isLocked: true)
        TimerControlWindowManager.shared.hide(animated: false)
        
        // THEN trigger lock icon in Atoll (only if enabled in settings)
        if Defaults[.enableLockScreenLiveActivity] {
            print("[\(timestamp())] LockScreenManager: 🔴 Starting lock icon live activity")
            coordinator.toggleExpandingView(status: true, type: .lockScreen)
        } else {
            print("[\(timestamp())] LockScreenManager: ⏭️ Lock icon disabled in settings")
        }
        
        startLockStatePolling()

        print("[\(timestamp())] LockScreenManager: ✅ Lock screen activated")
    }

    @objc private func screenUnlocked() {
        guard isLocked else {
            print("[\(timestamp())] LockScreenManager: 🔁 Unlock event ignored (already unlocked)")
            return
        }
        print("[\(timestamp())] LockScreenManager: 🔓 Screen UNLOCKED event received")
        Logger.log("LockScreenManager: Screen unlocked", category: .lifecycle)
        LockSoundPlayer.shared.playUnlockChime()
        LockScreenDisplayContextProvider.shared.refresh(reason: "screen-unlocked")
        lastUpdated = Date()
        updateIdleState(locked: false)
        isLocked = false
        stopLockStatePolling()
        postUnlockMusicHUDTask?.cancel()
        shouldDelayPostUnlockMusicHUD = Defaults[.enableLockScreenLiveActivity]

        if shouldDelayPostUnlockMusicHUD {
            postUnlockMusicHUDTask = Task { [weak self] in
                try? await Task.sleep(
                    for: .seconds(
                        LockScreenAnimationTimings.unlockCollapse
                            + LockScreenAnimationTimings.postUnlockMusicHUDPause
                    )
                )
                guard let self = self, !Task.isCancelled else { return }
                await MainActor.run {
                    if !self.isLocked {
                        withAnimation(
                            .spring(
                                response: LockScreenAnimationTimings.postUnlockMusicHUDReveal,
                                dampingFraction: 0.88,
                                blendDuration: 0.08
                            )
                        ) {
                            self.shouldDelayPostUnlockMusicHUD = false
                        }
                    }
                }
            }
        }
        
        // Hide panel window immediately and synchronously
        print("[\(timestamp())] LockScreenManager: 🚪 Hiding panel window")
        LockScreenPanelManager.shared.hidePanel()
        FullScreenArtworkWindowManager.shared.hide()
        LockScreenLiveActivityWindowManager.shared.showUnlockAndScheduleHide()
        LockScreenWeatherManager.shared.hideWeatherWidget()
        LockScreenTimerWidgetManager.shared.handleLockStateChange(isLocked: false)
        
        // Update state immediately
        if Defaults[.enableLockScreenLiveActivity] {
            collapseTask?.cancel()
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(LockScreenAnimationTimings.unlockCollapse))
                guard let self = self, !Task.isCancelled else { return }
                await MainActor.run {
                    self.coordinator.toggleExpandingView(status: false, type: .lockScreen)
                }
            }
        }
        
        print("[\(self.timestamp())] LockScreenManager: ✅ Lock screen deactivated")
    }
    
    // MARK: - Lock State Polling

    // Defensive fallback against late/missed `com.apple.screenIsUnlocked` and
    // `NSWorkspace.sessionDidBecomeActiveNotification` notifications, which
    // macOS sometimes delivers well after the user-perceived unlock — leaving
    // lock-screen widgets visible for an extra moment. While we believe we are
    // locked, poll the canonical session-lock state and fire `screenUnlocked()`
    // the moment the OS flips. The handler's duplicate-event guard makes this
    // safe to call alongside any later-arriving notification.
    private static func isSessionScreenLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func startLockStatePolling() {
        lockStatePollTask?.cancel()
        lockStatePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self, self.isLocked else { return }
                    if !Self.isSessionScreenLocked() {
                        print("[\(self.timestamp())] LockScreenManager: 🔓 Polling detected unlock ahead of notification")
                        self.screenUnlocked()
                    }
                }
            }
        }
    }

    private func stopLockStatePolling() {
        lockStatePollTask?.cancel()
        lockStatePollTask = nil
    }

    // MARK: - Idle State Management

    /// Copy EXACT logic from ScreenRecordingManager
    private func updateIdleState(locked: Bool) {
        if locked {
            isLockIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                // Keep the lock live activity mounted until the collapse animation finishes,
                // otherwise the content disappears before the island fully closes.
                let idleDelay = LockScreenAnimationTimings.unlockCollapse
                try? await Task.sleep(for: .seconds(idleDelay))
                guard let self = self, !Task.isCancelled else { return }
                await MainActor.run {
                    if self.lastUpdated.timeIntervalSinceNow < -idleDelay {
                        withAnimation(.smooth(duration: 0.3)) {
                            self.isLockIdle = !self.isLocked
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Extensions

extension LockScreenManager {
    func configure(viewModel: DynamicIslandViewModel) {
        self.viewModel = viewModel
    }
    
    /// Get current lock status without async
    var currentLockStatus: Bool {
        return isLocked
    }
    
    /// Check if monitoring is available (for settings UI)
    var isMonitoringAvailable: Bool {
        return true // Always available on macOS
    }
}

// MARK: - Lock Sound Playback

@MainActor
final class LockSoundPlayer {
    static let shared = LockSoundPlayer()
    private let throttleInterval: TimeInterval = 0.25
    private var players: [SoundType: AVAudioPlayer] = [:]
    private var lastPlaybackDates: [SoundType: Date] = [:]

    private init() {}

    func playLockChime() {
        play(.lock)
    }

    func playUnlockChime() {
        play(.unlock)
    }

    private func play(_ type: SoundType) {
        guard Defaults[.enableLockSounds] else { return }
        guard shouldPlay(type) else { return }
        guard let player = resolvePlayer(for: type) else { return }

        player.currentTime = 0
        player.play()
        lastPlaybackDates[type] = Date()
    }

    private func shouldPlay(_ type: SoundType) -> Bool {
        guard let last = lastPlaybackDates[type] else { return true }
        return Date().timeIntervalSince(last) >= throttleInterval
    }

    private func resolvePlayer(for type: SoundType) -> AVAudioPlayer? {
        if let cached = players[type] {
            return cached
        }

        guard let url = Bundle.main.url(forResource: type.resourceName, withExtension: "mp3") else {
            Logger.log("Missing \(type.resourceName).mp3 in bundle", category: .warning)
            return nil
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            players[type] = player
            return player
        } catch {
            Logger.log("Failed to initialize lock sound player for \(type.resourceName): \(error.localizedDescription)", category: .error)
            return nil
        }
    }

    private enum SoundType: String {
        case lock
        case unlock

        var resourceName: String { rawValue }
    }
}
