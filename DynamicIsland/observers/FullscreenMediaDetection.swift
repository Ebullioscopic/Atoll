/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import ApplicationServices
import Combine
import Defaults
import MacroVisionKit
import SwiftUI

class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    private let detector: MacroVisionKit
    @ObservedObject private var musicManager = MusicManager.shared
    @MainActor @Published private(set) var fullscreenStatus: [String: Bool] = [:]
    private var notificationTask: Task<Void, Never>?
    private var nowPlayingAppCancellable: AnyCancellable?
    /// Pending follow-up check while a fullscreen app waits to become Now Playing.
    @MainActor private var recheckTask: Task<Void, Never>?
    /// Follow-up checks made since the last Space, screen or Now Playing change;
    /// sets the back-off delay of the next one.
    @MainActor private var rechecksDone = 0
    /// Bumped on every refresh so a slower, older refresh cannot overwrite a newer one.
    @MainActor private var refreshGeneration = 0
    /// The 500 ms settle wait after a change; replaced by each newer change.
    @MainActor private var settleTask: Task<Void, Never>?

    private init() {
        self.detector = MacroVisionKit.shared
        detector.configuration.includeSystemApps = true
        setupNotificationObservers()
        observeNowPlayingApp()
        Task { @MainActor [weak self] in
            await self?.refresh(resetRechecks: true)
        }
    }

    private func setupNotificationObservers() {
        notificationTask = Task { @Sendable [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let activeSpaceNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.activeSpaceDidChangeNotification
                    )
                    
                    for await _ in activeSpaceNotifications {
                        await self?.scheduleRefresh()
                    }
                }
                
                group.addTask {
                    let screenParameterNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named:  NSApplication.didChangeScreenParametersNotification
                    )
                    
                    for await _ in screenParameterNotifications {
                        await self?.scheduleRefresh()
                    }
                }
            }
        }
    }

    /// Playback that starts (or moves to another app) after the window went
    /// fullscreen produces no Space change, so the Now Playing app is a trigger
    /// of its own — and so is the active controller starting or stopping to
    /// follow system Now Playing, which can happen without the id changing.
    /// Under a controller that follows system Now Playing this fires on every
    /// switch between players; otherwise the follow-up checks in `refresh`
    /// cover the gap.
    private func observeNowPlayingApp() {
        let bundleChanges = musicManager.$bundleIdentifier
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
        let trackingChanges = musicManager.$activeControllerFollowsSystemNowPlaying
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
        nowPlayingAppCancellable = bundleChanges.merge(with: trackingChanges)
            .sink { [weak self] _ in
                self?.scheduleRefresh()
            }
    }

    /// Starts a refresh 500 ms after a change, without waiting for it. Any
    /// refresh still in flight (for example, waiting on the probe) is dropped at
    /// once, and a newer change replaces a pending settle wait, so a result for
    /// the Space being left is never published.
    @MainActor
    private func scheduleRefresh() {
        refreshGeneration += 1
        recheckTask?.cancel()
        recheckTask = nil
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.refresh(resetRechecks: true)
        }
    }

    @MainActor
    private func refresh(resetRechecks: Bool) async {
        if resetRechecks { rechecksDone = 0 }
        recheckTask?.cancel()
        recheckTask = nil
        refreshGeneration += 1
        let generation = refreshGeneration

        let (newStatus, keepRechecking) = await computeFullScreenStatus()
        guard generation == refreshGeneration else { return }

        if newStatus != fullscreenStatus {
            fullscreenStatus = newStatus
            NSLog("✅ Fullscreen status: \(newStatus)")
        }

        guard keepRechecking else { return }
        let delay = FullscreenHidePolicy.recheckDelay(afterRechecks: rechecksDone)
        rechecksDone += 1
        recheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.refresh(resetRechecks: false)
        }
    }

    /// Per-screen hide state, and whether a follow-up check is worth scheduling.
    @MainActor
    private func computeFullScreenStatus() async -> (status: [String: Bool], keepRechecking: Bool) {
        guard Defaults[.enableFullscreenMediaDetection] else {
            let reset = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { ($0.localizedName, false) })
            return (reset, false)
        }

        let apps = detector.detectFullscreenApps(debug: false)
            .filter { $0.bundleIdentifier != "com.apple.finder" }
        let names = NSScreen.screens.map { $0.localizedName }
        let hideOption = Defaults[.hideNotchOption]

        // Only worth asking when something could hide because of it.
        let nowPlayingIsObserved = musicManager.activeControllerFollowsSystemNowPlaying
        let nowPlayingBundleID: String? = (hideOption == .nowPlayingOnly && !apps.isEmpty)
            ? await resolveNowPlayingBundleID()
            : nil

        var newStatus: [String: Bool] = [:]
        var keepRechecking = false
        for name in names {
            let candidates = apps.filter { $0.screen.localizedName == name }

            // The notch stays on display by default (the window's collectionBehavior
            // rides along with fullscreen spaces). It only hides when the user's
            // "Hide DynamicIsland" option asks for it. The policy is asked first as if
            // the window were native fullscreen, so the Accessibility check only runs
            // for apps that would otherwise hide.
            let hidden = candidates.contains { app in
                FullscreenHidePolicy.shouldHide(
                    option: hideOption,
                    fullscreenBundleID: app.bundleIdentifier,
                    nowPlayingBundleID: nowPlayingBundleID,
                    isNativeFullscreen: true
                ) && isInNativeFullscreen(app)
            }
            newStatus[name] = hidden

            // Frame-based candidates only: no Accessibility call here, so an app that
            // is fullscreen but not Now Playing is never queried over AX.
            keepRechecking = keepRechecking || FullscreenHidePolicy.shouldKeepRechecking(
                option: hideOption,
                detectionEnabled: true,
                hasFullscreenCandidate: !candidates.isEmpty,
                isHidden: hidden,
                nowPlayingIsObserved: nowPlayingIsObserved
            )
        }

        return (newStatus, keepRechecking)
    }

    /// The app macOS reports as Now Playing. When `MusicManager`'s active
    /// controller follows system Now Playing it already knows; any other
    /// controller pins `MusicManager` to its player (also when Pear Desktop or a
    /// deprecated Now Playing API swapped the controller under a "Now Playing"
    /// preference), so the system is asked directly, falling back to the
    /// controller's app if the query fails.
    @MainActor
    private func resolveNowPlayingBundleID() async -> String? {
        if musicManager.activeControllerFollowsSystemNowPlaying {
            return musicManager.bundleIdentifier
        }
        return await SystemNowPlayingProbe.currentBundleIdentifier() ?? musicManager.bundleIdentifier
    }

    /// Confirms an app the detector flagged as screen-filling is in *genuine* native
    /// fullscreen, not merely maximized/zoomed. On a notched Mac a maximized window and a
    /// fullscreen window report nearly identical frames, so frame size alone can't tell them
    /// apart — the Accessibility `AXFullScreen` attribute can. Falls back to the detector's
    /// frame-based result when Accessibility isn't trusted (so behavior doesn't silently break).
    private func isInNativeFullscreen(_ app: MacroVisionKit.FullscreenWindowInfo) -> Bool {
        guard AXIsProcessTrusted() else { return true }

        let reader = BoundedAXReader(timeout: Self.accessibilityTimeout, budget: Self.accessibilityBudget)
        let appElement = AXUIElementCreateApplication(app.processId)

        // Prefer the focused window, then fall back to scanning all windows.
        if let focused: AXUIElement = reader.copyAttribute(kAXFocusedWindowAttribute as CFString, from: appElement),
           reader.isWindowFullscreen(focused) {
            return true
        }

        if let windows: [AXUIElement] = reader.copyAttribute(kAXWindowsAttribute as CFString, from: appElement) {
            return windows.contains { reader.isWindowFullscreen($0) }
        }

        return false
    }

    /// Upper bound, in seconds, for one Accessibility read of a fullscreen app.
    private static let accessibilityTimeout: Float = 0.25
    /// Upper bound, in seconds, for all Accessibility reads of one app in one check.
    private static let accessibilityBudget: TimeInterval = 0.5

    private func cleanupNotificationObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

/// Accessibility reads for one fullscreen check of one app. Each read is bounded
/// by `timeout` and by what is left of `budget`, so the whole check — however many
/// windows the app has, and however close to the timeout each read comes — never
/// holds the main actor longer than `budget`. The first read that times out, or
/// one attempted after the budget is spent, marks the app as unresponsive and
/// every later read returns nil at once.
private final class BoundedAXReader {
    private let timeout: Float
    private let deadline: Date
    private var unresponsive = false

    init(timeout: Float, budget: TimeInterval) {
        self.timeout = timeout
        self.deadline = Date().addingTimeInterval(budget)
    }

    func isWindowFullscreen(_ window: AXUIElement) -> Bool {
        // "AXFullScreen" is the (undocumented but stable) attribute set true only in native
        // fullscreen; maximized/zoomed windows report false or omit it.
        let value: Bool? = copyAttribute("AXFullScreen" as CFString, from: window)
        return value ?? false
    }

    func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        guard !unresponsive else { return nil }
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            unresponsive = true
            return nil
        }
        // A timeout set on one element does not carry over to the elements it returns.
        AXUIElementSetMessagingTimeout(element, min(timeout, Float(remaining)))
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        if error == .cannotComplete {
            unresponsive = true
            return nil
        }
        guard error == .success, let typed = value as? T else { return nil }
        return typed
    }
}
