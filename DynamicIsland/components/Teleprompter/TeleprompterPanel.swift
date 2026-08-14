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
import SwiftUI

/// The detachable prompter window.
///
/// A `nonactivatingPanel` so putting the prompter on screen does not pull the
/// user out of Zoom, Keynote or whatever they are presenting from. It still
/// accepts key events, because the reader needs space, arrows and the number
/// keys — a panel that cannot be driven from the keyboard is useless to someone
/// looking at a camera.
final class TeleprompterPanel: NSPanel {
    /// Called for keys the prompter handles itself.
    var onKeyCommand: ((TeleprompterKeyCommand) -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 260),
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        configure()
    }

    override var canBecomeKey: Bool { true }
    /// Never main: becoming the main window would make Atoll the active app and
    /// take the presenter out of their own slides.
    override var canBecomeMain: Bool { false }

    private func configure() {
        isFloatingPanel = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        // Follows the presenter across desktops and sits above a full-screen app,
        // which is exactly where a prompter has to be.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        minSize = NSSize(width: 320, height: 120)

        // Invisible to screen sharing and recording. The `.teleprompter` scope has
        // its own switch rather than inheriting the notch's.
        ScreenCaptureVisibilityManager.shared.register(self, scope: .teleprompter)
    }

    deinit {
        ScreenCaptureVisibilityManager.shared.unregister(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let command = TeleprompterKeyCommand(event: event) else {
            super.keyDown(with: event)
            return
        }
        onKeyCommand?(command)
    }
}

/// Keys the prompter acts on while it has focus.
enum TeleprompterKeyCommand: Equatable {
    case togglePlayback
    case nextWord
    case previousWord
    case nextSection
    case previousSection
    case restart
    case close
    /// Number keys 1-9 jump to that section.
    case jumpToSection(Int)

    init?(event: NSEvent) {
        switch event.keyCode {
        case 49: self = .togglePlayback          // space
        case 124: self = .nextWord               // →
        case 123: self = .previousWord           // ←
        case 125: self = .nextSection            // ↓
        case 126: self = .previousSection        // ↑
        case 53: self = .close                   // esc
        default:
            guard let characters = event.charactersIgnoringModifiers else { return nil }
            if characters == "r" || characters == "R" {
                self = .restart
                return
            }
            // `1` selects the first section, so the index is one less.
            guard let digit = Int(characters), (1...9).contains(digit) else { return nil }
            self = .jumpToSection(digit - 1)
        }
    }
}
