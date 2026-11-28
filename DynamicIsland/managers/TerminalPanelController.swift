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

/// Floating window that hosts the notch terminal while it is popped out.
///
/// It takes `TerminalManager.containerView` — the same view, so the running
/// shell, its scrollback and the cursor carry over untouched — and hands it
/// back when the window closes, which returns the terminal to its notch tab.
@MainActor
final class TerminalPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.title = String(localized: "Terminal")
        panel.isFloatingPanel = true
        panel.level = .floating
        // Panels hide when their app deactivates by default; this one is meant
        // to stay in view beside whatever the user is doing.
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = .black
        panel.minSize = NSSize(width: 320, height: 160)
        panel.contentView = NSView()
        panel.delegate = self
        if !panel.setFrameUsingName("AtollTerminalPanel") {
            panel.center()
        }
        panel.setFrameAutosaveName("AtollTerminalPanel")
    }

    var isVisible: Bool { panel.isVisible }

    func setTitle(_ title: String) {
        panel.title = title
    }

    /// Moves `containerView` into the window and brings it to the front.
    func show(containerView: NSView) {
        guard let content = panel.contentView else { return }
        if containerView.superview !== content {
            containerView.removeFromSuperview()
            containerView.frame = content.bounds
            containerView.autoresizingMask = [.width, .height]
            content.addSubview(containerView)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        panel.contentView?.subviews.forEach { $0.removeFromSuperview() }
        onClose()
    }
}
