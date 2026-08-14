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
import Defaults
import SwiftUI

/// Owns the floating prompter window.
@MainActor
final class TeleprompterPanelManager: ObservableObject {
    static let shared = TeleprompterPanelManager()

    @Published private(set) var isVisible = false

    private var panel: TeleprompterPanel?

    private init() {}

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        if panel.frame.isEmpty || panel.frame.origin == .zero {
            positionBelowNotch(panel)
        }
        // `orderFrontRegardless` rather than `makeKeyAndOrderFront`: the prompter
        // appearing must not steal focus from whatever the user is presenting in.
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    /// Tears the window down for good, used when the feature is switched off.
    func teardown() {
        panel?.orderOut(nil)
        panel = nil
        isVisible = false
    }

    private func makePanel() -> TeleprompterPanel {
        let panel = TeleprompterPanel()
        panel.contentView = NSHostingView(rootView: TeleprompterPanelView())
        panel.onKeyCommand = { [weak self] command in
            self?.handle(command)
        }
        return panel
    }

    /// Places the prompter just under the notch, which is where the camera is.
    private func positionBelowNotch(_ panel: TeleprompterPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let width = min(760, visible.width * 0.6)
        let height: CGFloat = 240
        let origin = CGPoint(
            x: visible.midX - width / 2,
            y: visible.maxY - height - 12
        )
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: width, height: height)), display: false)
    }

    private func handle(_ command: TeleprompterKeyCommand) {
        let manager = TeleprompterManager.shared
        switch command {
        case .togglePlayback: manager.toggleTake()
        case .nextWord: manager.advance(by: 1)
        case .previousWord: manager.advance(by: -1)
        case .nextSection: manager.jumpToSection(manager.currentSectionIndex + 1)
        case .previousSection: manager.jumpToSection(max(0, manager.currentSectionIndex - 1))
        case .restart: manager.restart()
        case .close: hide()
        case .jumpToSection(let index): manager.jumpToSection(index)
        }
    }
}
