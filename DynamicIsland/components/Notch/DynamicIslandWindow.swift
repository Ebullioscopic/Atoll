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

import Cocoa
import Defaults

class DynamicIslandWindow: NSPanel {
    static let pinnedCollectionBehavior: NSWindow.CollectionBehavior = [
        .fullScreenAuxiliary,
        .canJoinAllSpaces,
        .ignoresCycle,
        .stationary,
    ]

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        
        collectionBehavior = Self.pinnedCollectionBehavior
        
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        hasShadow = false

        ScreenCaptureVisibilityManager.shared.register(self, scope: .entireInterface)
    }
    
    /// The notch's view model, so closing it can tell whether this window holds the keyboard.
    weak var notchViewModel: DynamicIslandViewModel?

    /// Only tabs that take keyboard input make the notch key (#386). Becoming key takes
    /// the keyboard from the frontmost app, and in a full-screen Space that left the
    /// app's title bar and the menu bar showing after the notch closed.
    override var canBecomeKey: Bool {
        notchTabTakesKeyboardInput(
            DynamicIslandViewCoordinator.shared.currentView,
            arrowKeySeekEnabled: Defaults[.arrowKeySeekEnabled],
            isMinimalistic: Defaults[.enableMinimalisticUI]
        )
    }
    
    override var canBecomeMain: Bool {
        true
    }

}

/// Whether a notch tab needs the keyboard: text fields, the terminal, the shelf's
/// Delete and ⌘A, the timer's rename field, extension content, and the music
/// player's arrow-key seeking when that option is on.
func notchTabTakesKeyboardInput(_ view: NotchViews, arrowKeySeekEnabled: Bool, isMinimalistic: Bool) -> Bool {
    switch view {
    case .terminal, .notes, .clipboard, .shelf, .timer, .extensionExperience:
        return true
    case .home, .nowPlaying:
        return arrowKeySeekEnabled && view.showsMusicPlayer(isMinimalistic: isMinimalistic)
    case .stats, .llmUsage, .colorPicker:
        return false
    }
}
