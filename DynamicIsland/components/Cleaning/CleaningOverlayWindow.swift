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

/// Full-screen overlay window used by cleaning mode (shared by clean-screen / clean-keyboard).
///
/// Must be able to become the key window, otherwise it won't receive ESC.
final class CleaningOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Overlay content view: receives the dismiss gesture and draws the hint text.
final class CleaningOverlayView: NSView {
    /// Called back when the user asks to exit cleaning mode.
    var onDismiss: (() -> Void)?

    /// Whether keyboard (ESC) dismissal is allowed.
    ///
    /// In clean-keyboard mode key events are swallowed by the event tap and never reach here, so
    /// that scenario can only be exited by mouse click — and the hint text is worded accordingly.
    var allowsKeyboardDismiss = true

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onDismiss?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        guard allowsKeyboardDismiss else { return }
        if event.keyCode == 53 { // ESC
            onDismiss?()
        }
    }
}

extension CleaningOverlayWindow {
    /// Build a full-bleed black overlay window on the given screen.
    static func make(for screen: NSScreen, hint: String, allowsKeyboardDismiss: Bool, onDismiss: @escaping () -> Void) -> CleaningOverlayWindow {
        let window = CleaningOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.isReleasedWhenClosed = false
        // Cover the menu bar, Dock, and full-screen apps.
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let contentView = CleaningOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        contentView.allowsKeyboardDismiss = allowsKeyboardDismiss
        contentView.onDismiss = onDismiss
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor

        let label = NSTextField(labelWithString: hint)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = NSColor.white.withAlphaComponent(0.55)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        window.contentView = contentView
        return window
    }
}
