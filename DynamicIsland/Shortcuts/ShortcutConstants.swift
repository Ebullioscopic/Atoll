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

import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let clipboardHistoryPanel = Self("clipboardHistoryPanel", default: .init(.v, modifiers: [.shift, .command]))
    static let colorPickerPanel = Self("colorPickerPanel", default: .init(.p, modifiers: [.shift, .command]))
    static let screenAssistantPanel = Self("screenAssistantPanel", default: .init(.a, modifiers: [.shift, .command]))
    static let decreaseBacklight = Self("decreaseBacklight", default: .init(.f1, modifiers: [.command]))
    static let increaseBacklight = Self("increaseBacklight", default: .init(.f2, modifiers: [.command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.command, .shift]))
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.command, .shift]))
    static let toggleTerminalTab = Self("toggleTerminalTab", default: .init(.backtick, modifiers: [.control]))
    static let startDemoTimer = Self("startDemoTimer", default: .init(.t, modifiers: [.command, .shift]))
    static let teleprompterToggle = Self("teleprompterToggle", default: .init(.r, modifiers: [.command, .shift]))
    static let teleprompterPlayPause = Self("teleprompterPlayPause", default: .init(.k, modifiers: [.command, .shift]))
    /// Deliberately unassigned. Anything comfortable to press mid-sentence is
    /// already doing something in the app the speaker is presenting from, and a
    /// global shortcut takes it away everywhere.
    static let teleprompterNextSection = Self("teleprompterNextSection")
    static let teleprompterPreviousSection = Self("teleprompterPreviousSection")
}
