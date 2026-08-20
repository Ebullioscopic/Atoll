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
import Combine

/// Clean screen: black out every display so smudges are easy to see and wipe.
///
/// A pure AppKit overlay window that needs no permissions.
/// Observes `didChangeScreenParametersNotification` to handle displays being plugged/unplugged,
/// resolution changes, or rearrangement during cleaning — otherwise a newly attached screen
/// would expose the desktop.
final class ScreenCleaningManager: ObservableObject {
    static let shared = ScreenCleaningManager()

    @Published private(set) var isActive = false

    private var overlayWindows: [CleaningOverlayWindow] = []
    private var screenChangeObserver: NSObjectProtocol?

    private init() {}

    func toggle() {
        isActive ? stop() : start()
    }

    func start() {
        guard !isActive else { return }

        // The two cleaning modes are mutually exclusive: both use a same-layer full-screen black
        // overlay, so enabling both stacks them — a single click only closes the topmost layer,
        // leaving the other as a black screen with no hint and no way out.
        KeyboardCleaningManager.shared.stop()

        isActive = true
        buildOverlays()

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isActive else { return }
            // The display topology changed; a full rebuild is both the simplest and the least
            // likely to miss a screen.
            self.tearDownOverlays()
            self.buildOverlays()
        }

        NSLog("✅ [ScreenCleaning] Clean screen enabled (\(overlayWindows.count) screen(s))")
    }

    func stop() {
        guard isActive else { return }

        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }

        tearDownOverlays()
        isActive = false
        NSLog("✅ [ScreenCleaning] Clean screen disabled")
    }

    // MARK: - Overlay windows

    private func buildOverlays() {
        let hint = String(
            localized: "Click anywhere or press Esc to finish cleaning",
            comment: "Exit hint shown on the clean-screen overlay"
        )

        overlayWindows = NSScreen.screens.map { screen in
            let window = CleaningOverlayWindow.make(
                for: screen,
                hint: hint,
                allowsKeyboardDismiss: true
            ) { [weak self] in
                self?.stop()
            }
            window.orderFrontRegardless()
            return window
        }

        // Only the first screen's window becomes key, responsible for receiving ESC.
        if let keyWindow = overlayWindows.first {
            keyWindow.makeKey()
            // Route key events to the overlay view so `keyDown` actually sees ESC.
            keyWindow.makeFirstResponder(keyWindow.contentView)
        }
        fadeOutHints()
    }

    private func tearDownOverlays() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }

    /// The hint text fades out after 3 seconds — leaving it up would block the very area being wiped.
    private func fadeOutHints() {
        let labels = overlayWindows.compactMap { window in
            window.contentView?.subviews.first as? NSTextField
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.isActive else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 1.0
                labels.forEach { $0.animator().alphaValue = 0 }
            }
        }
    }
}
