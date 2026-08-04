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

import AppKit
import ApplicationServices
import Combine
import CoreGraphics

/// System-defined event (the function-key row's brightness/volume/playback controls use this
/// type). `CGEventType` has no matching Swift case, so it must be written by raw value, matching
/// MediaKeyInterceptor.
private let NX_SYSDEFINED_EVENT_TYPE: UInt32 = 14

/// Clean keyboard: temporarily swallow all keyboard events so wiping the keyboard doesn't
/// trigger anything by accident.
///
/// Uses `CGEvent.tapCreate` in `.defaultTap` mode to intercept `keyDown` / `keyUp` /
/// `flagsChanged` and returns `nil` to swallow them. Requires **Accessibility permission**.
///
/// Known limitations (things it can't do — not bugs):
/// - **Power key / Touch ID can't be swallowed** — they don't go through the CGEvent pipeline.
/// - **The tap is disabled entirely during secure input** — e.g. while a password field is focused.
/// - Exiting is only possible via **mouse click** (all keys are swallowed, so ESC can't reach
///   the overlay); a timeout failsafe backs this up.
final class KeyboardCleaningManager: ObservableObject {
    static let shared = KeyboardCleaningManager()

    /// Failsafe auto-exit time. In case the mouse also fails, this keeps the keyboard from being
    /// locked forever.
    private static let failsafeTimeout: TimeInterval = 120

    @Published private(set) var isActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlayWindows: [CleaningOverlayWindow] = []
    private var failsafeTimer: Timer?
    private var screenChangeObserver: NSObjectProtocol?

    private let tapLocations: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]

    private init() {}

    func toggle() {
        if isActive {
            stop()
        } else {
            start()
        }
    }

    @discardableResult
    func start() -> Bool {
        guard !isActive else { return true }

        guard requestAccessibilityPermissionIfNeeded() else {
            NSLog("⚠️ [KeyboardCleaning] Missing Accessibility permission, cannot intercept the keyboard")
            return false
        }

        guard installEventTap() else {
            NSLog("❌ [KeyboardCleaning] Failed to create the keyboard event tap")
            return false
        }

        // The two cleaning modes are mutually exclusive: both use a same-layer full-screen black
        // overlay, so enabling both stacks them — a single click only closes the topmost layer,
        // leaving the other as a black screen with no hint and no way out.
        ScreenCleaningManager.shared.stop()

        isActive = true
        buildOverlays()
        startFailsafeTimer()

        // The observer is registered exactly once in start(); putting it inside buildOverlays()
        // would re-register it from its own callback — doubling the observer count on every screen
        // change, a process-level leak (matches ScreenCleaningManager).
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            self.tearDownOverlays()
            self.buildOverlays()
        }

        NSLog("✅ [KeyboardCleaning] Clean keyboard enabled")
        return true
    }

    func stop() {
        guard isActive else { return }

        failsafeTimer?.invalidate()
        failsafeTimer = nil

        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }

        removeEventTap()
        tearDownOverlays()
        isActive = false

        NSLog("✅ [KeyboardCleaning] Clean keyboard disabled")
    }

    // MARK: - Event tap

    private func installEventTap() -> Bool {
        // Hooking only keyDown/keyUp/flagsChanged is not enough: the function-key row
        // (brightness, volume, playback controls) travels as NX_SYSDEFINED system-defined events,
        // which are not in those three categories — miss it and, while wiping the keyboard, F1/F2
        // still change brightness and F8 still pauses music. See MediaKeyInterceptor, which
        // handles exactly this kind of event.
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << NX_SYSDEFINED_EVENT_TYPE)

        let callback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
            let manager = Unmanaged<KeyboardCleaningManager>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return manager.handleEvent(cgEvent: cgEvent, type: type)
        }

        var createdTap: CFMachPort?
        for location in tapLocations {
            if let tap = CGEvent.tapCreate(
                tap: location,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            ) {
                createdTap = tap
                break
            }
        }

        guard let tap = createdTap else { return false }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(cgEvent: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        // The system disables the tap on processing timeout or user input, so it must be
        // re-enabled; otherwise cleaning mode still looks active while the keyboard has already
        // been let through.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if isActive, let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                NSLog(
                    "[KeyboardCleaning] event tap disabled by %@, re-enabled",
                    type == .tapDisabledByTimeout ? "timeout" : "user input"
                )
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        // Swallow it.
        return nil
    }

    // MARK: - Overlays

    private func buildOverlays() {
        let hint = String(
            localized: "Keyboard is locked for cleaning — click anywhere to finish",
            comment: "Exit hint shown on the clean-keyboard overlay"
        )

        overlayWindows = NSScreen.screens.map { screen in
            let window = CleaningOverlayWindow.make(
                for: screen,
                hint: hint,
                // All keys are swallowed, so ESC can't reach here; only the mouse works.
                allowsKeyboardDismiss: false
            ) { [weak self] in
                self?.stop()
            }
            window.orderFrontRegardless()
            return window
        }
    }

    private func tearDownOverlays() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }

    private func startFailsafeTimer() {
        failsafeTimer?.invalidate()
        failsafeTimer = Timer.scheduledTimer(
            withTimeInterval: Self.failsafeTimeout,
            repeats: false
        ) { [weak self] _ in
            NSLog("[KeyboardCleaning] Failsafe timeout reached, exiting cleaning mode automatically")
            self?.stop()
        }
    }

    // MARK: - Permission

    @discardableResult
    private func requestAccessibilityPermissionIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
