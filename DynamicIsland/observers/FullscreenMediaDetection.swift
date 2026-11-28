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
import SwiftUI

class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    @ObservedObject private var musicManager = MusicManager.shared
    @MainActor @Published private(set) var fullscreenStatus: [String: Bool] = [:]
    private var notificationTask: Task<Void, Never>?
    private var nowPlayingAppCancellable: AnyCancellable?
    /// Pending follow-up check while a fullscreen app waits to become Now Playing.
    @MainActor private var recheckTask: Task<Void, Never>?
    /// Follow-up checks made since the last Space, screen, frontmost-app or
    /// playback change; sets the back-off delay of the next one.
    @MainActor private var rechecksDone = 0
    /// Bumped on every refresh so a slower, older refresh cannot overwrite a newer one.
    @MainActor private var refreshGeneration = 0
    /// The 500 ms settle wait after a change; replaced by each newer change.
    @MainActor private var settleTask: Task<Void, Never>?

    private init() {
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
                
                // Bringing a player forward (or leaving it) is when playback
                // usually starts or moves, and causes no Space change.
                group.addTask {
                    let activationNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didActivateApplicationNotification
                    )

                    for await _ in activationNotifications {
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
    /// fullscreen produces no Space change, so the Now Playing app and the
    /// play state are triggers of their own — and so is the active controller
    /// starting or stopping to follow system Now Playing, which can happen
    /// without the id changing. Under a controller pinned to one player, the
    /// capped follow-up checks in `refresh` and the frontmost-app trigger cover
    /// playback in other apps.
    private func observeNowPlayingApp() {
        let bundleChanges = musicManager.$bundleIdentifier
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
        let trackingChanges = musicManager.$activeControllerFollowsSystemNowPlaying
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
        let playbackChanges = musicManager.$isPlaying
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
        nowPlayingAppCancellable = Publishers.Merge3(bundleChanges, trackingChanges, playbackChanges)
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

        guard keepRechecking,
              let delay = FullscreenHidePolicy.recheckDelay(afterRechecks: rechecksDone)
        else { return }
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

        let apps = detectFullscreenCandidates()
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
            let candidates = apps.filter { $0.screenName == name }

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

    /// A window on screen shaped like a fullscreen window: the whole safe area of
    /// its display, or its full height as one side of a Split View.
    struct FullscreenWindowCandidate {
        let processID: pid_t
        let bundleIdentifier: String?
        let screenName: String
        /// Global display coordinates with a top-left origin, as Accessibility reports frames.
        let bounds: CGRect
        let fit: FullscreenHidePolicy.WindowFit
    }

    /// On-screen windows (current Space of each display only) that could be
    /// fullscreen. Finder, the Dock and Atoll's own windows are skipped.
    @MainActor
    private func detectFullscreenCandidates() -> [FullscreenWindowCandidate] {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.height else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier

        var candidates: [FullscreenWindowCandidate] = []
        for info in windowInfo {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let alpha = info[kCGWindowAlpha as String] as? CGFloat, alpha > 0,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else { continue }

            let appKitFrame = CGRect(
                x: bounds.minX,
                y: primaryHeight - bounds.maxY,
                width: bounds.width,
                height: bounds.height
            )
            guard let screen = screens.first(where: { $0.frame.contains(appKitFrame) }) else { continue }

            let fit = FullscreenHidePolicy.windowFit(window: appKitFrame, safeArea: Self.safeArea(of: screen))
            guard fit != .none,
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != "com.apple.dock",
                  app.bundleIdentifier != "com.apple.finder"
            else { continue }

            candidates.append(FullscreenWindowCandidate(
                processID: pid,
                bundleIdentifier: app.bundleIdentifier,
                screenName: screen.localizedName,
                bounds: bounds,
                fit: fit
            ))
        }
        return candidates
    }

    /// The display area below the camera housing on notched displays.
    private static func safeArea(of screen: NSScreen) -> CGRect {
        let insets = screen.safeAreaInsets
        return CGRect(
            x: screen.frame.minX + insets.left,
            y: screen.frame.minY + insets.bottom,
            width: screen.frame.width - insets.left - insets.right,
            height: screen.frame.height - insets.top - insets.bottom
        )
    }

    /// Confirms a window flagged as screen-filling is in *genuine* native
    /// fullscreen, not merely maximized/zoomed or tiled. On a notched Mac a maximized
    /// window and a fullscreen window report nearly identical frames, so frame size
    /// alone can't tell them apart — the Accessibility `AXFullScreen` attribute can.
    ///
    /// The attribute is read from the app window whose frame matches the detected
    /// on-screen window, so another window of the same app (for example one in
    /// fullscreen on another Space) cannot hide the notch on this one. Without
    /// Accessibility, whole-screen windows keep the frame-based result (so behavior
    /// doesn't silently break) and Split View panes are not treated as fullscreen.
    private func isInNativeFullscreen(_ candidate: FullscreenWindowCandidate) -> Bool {
        guard AXIsProcessTrusted() else { return candidate.fit == .whole }

        let reader = BoundedAXReader(timeout: Self.accessibilityTimeout)
        let appElement = AXUIElementCreateApplication(candidate.processID)

        if let windows: [AXUIElement] = reader.copyAttribute(kAXWindowsAttribute as CFString, from: appElement) {
            for window in windows {
                guard let frame = reader.frame(of: window),
                      FullscreenHidePolicy.isSameWindow(frame, as: candidate.bounds)
                else { continue }
                return reader.isWindowFullscreen(window)
            }
        }

        // Not every app lists its windows over Accessibility; ask about the focused one.
        if let focused: AXUIElement = reader.copyAttribute(kAXFocusedWindowAttribute as CFString, from: appElement) {
            return reader.isWindowFullscreen(focused)
        }

        return false
    }

    /// Upper bound, in seconds, for one Accessibility read of a fullscreen app.
    private static let accessibilityTimeout: Float = 0.25

    private func cleanupNotificationObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

/// Accessibility reads for one fullscreen check, each bounded by `timeout`. The
/// first read that times out marks the app as unresponsive and every later read
/// returns nil at once, so a hung app costs at most one timeout per check rather
/// than one per window.
private final class BoundedAXReader {
    private let timeout: Float
    private var unresponsive = false

    init(timeout: Float) {
        self.timeout = timeout
    }

    func isWindowFullscreen(_ window: AXUIElement) -> Bool {
        // "AXFullScreen" is the (undocumented but stable) attribute set true only in native
        // fullscreen; maximized/zoomed windows report false or omit it.
        let value: Bool? = copyAttribute("AXFullScreen" as CFString, from: window)
        return value ?? false
    }

    /// The window's frame in global display coordinates (top-left origin).
    func frame(of window: AXUIElement) -> CGRect? {
        guard let position = copyValue(kAXPositionAttribute as CFString, from: window, type: .cgPoint, initial: CGPoint.zero),
              let size = copyValue(kAXSizeAttribute as CFString, from: window, type: .cgSize, initial: CGSize.zero)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func copyValue<T>(_ attribute: CFString, from element: AXUIElement, type: AXValueType, initial: T) -> T? {
        guard let raw: CFTypeRef = copyAttribute(attribute, from: element),
              CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        var value = initial
        guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), type, &value) else { return nil }
        return value
    }

    func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        guard !unresponsive else { return nil }
        // A timeout set on one element does not carry over to the elements it returns.
        AXUIElementSetMessagingTimeout(element, timeout)
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
