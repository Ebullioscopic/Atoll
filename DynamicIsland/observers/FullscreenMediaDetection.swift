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
import Darwin

/// Metadata-only detection. The parent owns window ordering and lock/Space gates.
@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    @Published private(set) var fullscreenStatus: [String: Bool] = [:]
    private var subscriptions = Set<AnyCancellable>()
    private var settleTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var isRefreshing = false

    private init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            observe(workspace, name: name)
        }
        // AppKit posts this on the default center, not NSWorkspace's center.
        observe(.default, name: NSApplication.didChangeScreenParametersNotification)
        Publishers.Merge(
            Defaults.publisher(.enableFullscreenMediaDetection, options: []).map { _ in () },
            Defaults.publisher(.hideNotchOption, options: []).map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in MainActor.assumeIsolated { self?.handleChange() } }
        .store(in: &subscriptions)
        MusicManager.shared.$bundleIdentifier
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.handleChange() } }
            .store(in: &subscriptions)
        refresh()
    }

    private func observe(_ center: NotificationCenter, name: Notification.Name) {
        center.publisher(for: name)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.handleChange() } }
            .store(in: &subscriptions)
    }

    private func handleChange() {
        refresh()
        settleTask?.cancel()
        // Space notifications may precede the WindowServer/AX transition. A
        // replaceable task avoids queued stale snapshots or a task per event.
        settleTask = Task { [weak self] in
            for delay in [150, 500] {
                do { try await Task.sleep(for: .milliseconds(delay)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    /// Synchronous main-actor refresh for the parent's activeSpaceDidChange
    /// handler, before it reasserts window presence. Never changes app settings,
    /// requests AX permission, or orders any window front.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let enabled = Defaults[.enableFullscreenMediaDetection]
        let mode: FullscreenVisibilityPolicy.HideMode
        switch Defaults[.hideNotchOption] {
        case .always: mode = .always
        case .nowPlayingOnly: mode = .nowPlayingOnly
        case .never: mode = .never
        }
        configurePolling(enabled: enabled && mode != .never)
        let screens = NSScreen.screens.compactMap { screen -> FullscreenVisibilityPolicy.Screen? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let frame = CGDisplayBounds(number.uint32Value)
            let insets = screen.safeAreaInsets
            let safeFrame = CGRect(x: frame.minX + insets.left, y: frame.minY + insets.top,
                                   width: frame.width - insets.left - insets.right,
                                   height: frame.height - insets.top - insets.bottom)
            return .init(name: screen.localizedName, frame: frame, safeFrame: safeFrame)
        }
        let active = enabled && mode != .never
        let windows = active ? visibleWindows() : []
        let trusted = active && AXIsProcessTrusted()
        let candidates = screens.compactMap { FullscreenVisibilityPolicy.candidate(on: $0, windows: windows) }
        let nativeWindows = trusted ? nativeFullscreenWindows(for: candidates) : []
        let status = FullscreenVisibilityPolicy.statuses(
            screens: screens, windows: windows, nativeWindows: nativeWindows,
            accessibilityTrusted: trusted, enabled: enabled, mode: mode,
            mediaBundleIdentifier: MusicManager.shared.bundleIdentifier)
        if status != fullscreenStatus { fullscreenStatus = status }
    }

    private func configurePolling(enabled: Bool) {
        guard enabled else {
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }
        guard pollTimer == nil else { return }
        // Covers AX fullscreen changes, window close/resize and permission
        // changes that produce no Space notification. No polling while disabled.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func visibleWindows() -> [FullscreenVisibilityPolicy.Window] {
        // MacroVisionKit's local API discards CGWindowID and matches only a
        // safe-area frame. Keep one on-screen snapshot with exact IDs so an AX
        // fullscreen window in another Space cannot confirm the visible one.
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        var bundles: [Int32: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            bundles[app.processIdentifier] = app.bundleIdentifier
        }
        return info.compactMap { value in
            guard let pid = value[kCGWindowOwnerPID as String] as? NSNumber,
                  pid.int32Value != ProcessInfo.processInfo.processIdentifier,
                  let id = value[kCGWindowNumber as String] as? NSNumber,
                  let bounds = value[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let layer = value[kCGWindowLayer as String] as? NSNumber,
                  let alpha = value[kCGWindowAlpha as String] as? NSNumber,
                  let onscreen = value[kCGWindowIsOnscreen as String] as? NSNumber else { return nil }
            return .init(id: id.uint32Value, pid: pid.int32Value, bundleIdentifier: bundles[pid.int32Value],
                         frame: frame, layer: layer.intValue, alpha: alpha.doubleValue, isOnscreen: onscreen.boolValue)
        }
    }

    // AX exposes no public CGWindowID accessor. Resolve the system bridge
    // optionally instead of hard-linking a private symbol. If unavailable we
    // cannot confirm native fullscreen; never substitute another window's flag.
    private typealias WindowIDFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let windowIDFunction: WindowIDFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: WindowIDFunction.self)
    }()

    private func nativeFullscreenWindows(for candidates: [FullscreenVisibilityPolicy.Window]) -> [FullscreenVisibilityPolicy.NativeWindow] {
        guard let windowIDFunction = Self.windowIDFunction else { return [] }
        var result: [FullscreenVisibilityPolicy.NativeWindow] = []
        // Synchronous refresh is bounded even if an application stops responding.
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        for (pid, targets) in Dictionary(grouping: candidates, by: \.pid).sorted(by: { $0.key < $1.key }) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.02)
            var remaining = Set(targets.map(\.id))
            func inspect(_ element: AXUIElement) {
                guard !remaining.isEmpty, ProcessInfo.processInfo.systemUptime < deadline else { return }
                AXUIElementSetMessagingTimeout(element, 0.02)
                var id: CGWindowID = 0
                guard windowIDFunction(element, &id) == .success, remaining.contains(id) else { return }
                let fullscreen: Bool? = copyAttribute("AXFullScreen" as CFString, from: element)
                result.append(.init(id: id, pid: pid, isFullscreen: fullscreen == true))
                remaining.remove(id)
            }
            if let focused: AXUIElement = copyAttribute(kAXFocusedWindowAttribute as CFString, from: app) {
                inspect(focused)
            }
            guard !remaining.isEmpty, ProcessInfo.processInfo.systemUptime < deadline else { continue }
            if let windows: [AXUIElement] = copyAttribute(kAXWindowsAttribute as CFString, from: app) {
                for window in windows.prefix(64) {
                    guard !remaining.isEmpty, ProcessInfo.processInfo.systemUptime < deadline else { break }
                    inspect(window)
                }
            }
        }
        return result
    }

    private func copyAttribute<T>(_ attribute: CFString, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? T
    }

    deinit {
        settleTask?.cancel()
        pollTimer?.invalidate()
    }
}
