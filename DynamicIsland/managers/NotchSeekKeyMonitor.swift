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
import SwiftTerm

/// Left and right arrow keys seek the playing track, but only while the notch
/// is open on the home view and Atoll itself has the keyboard.
///
/// Scoped that tightly on purpose. Arrow keys belong to whatever the user is
/// typing in, so there is no global monitor (it would seek while the keys also
/// reach another app's text field), and text views inside the notch keep them.
@MainActor
final class NotchSeekKeyMonitor {
    static let shared = NotchSeekKeyMonitor()

    private var localMonitor: Any?

    /// The open notches currently asking for the arrow keys.
    ///
    /// One process-wide monitor is shared by every screen, so it cannot come
    /// down until nothing wants it: with notches open on two
    /// displays, closing one used to take seeking away from the other.
    private var owners: Set<UUID> = []

    private enum ArrowKey: UInt16 {
        case left = 123
        case right = 124
    }

    private init() {}

    /// Asks for the arrow keys on behalf of one notch.
    ///
    /// - Parameter owner: identifies the notch, so it can give them back
    ///   without speaking for any other notch that is still open.
    func start(owner: UUID) {
        owners.insert(owner)
        guard localMonitor == nil else { return }

        // Fires only when Atoll itself is frontmost, and can swallow the event so
        // the key does not also act on the notch's own SwiftUI focus.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// Gives the arrow keys back on behalf of one notch.
    ///
    /// The monitor comes down only once the last notch has let go. Releasing a
    /// notch that never asked, or has already let go, does nothing -- which is
    /// what makes it safe to call from every teardown path without first
    /// working out whether this notch was the one that started it.
    func stop(owner: UUID) {
        owners.remove(owner)
        guard owners.isEmpty else { return }

        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
    }

    /// Returns whether the event was consumed.
    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard Defaults[.arrowKeySeekEnabled] else { return false }
        guard let arrow = ArrowKey(rawValue: event.keyCode) else { return false }
        guard DynamicIslandViewCoordinator.shared.currentView == .home else { return false }

        // Text fields (clipboard search, notes) and the terminal use the arrows
        // to move the caret, so leave the key to them.
        let responder = event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder
        if responder is NSTextView || responder is TerminalView { return false }

        // Only a bare arrow seeks. The modified ones already mean something:
        // command-left is "back", option-left is "one word left", and shift
        // extends a selection. Note that .function and .numericPad are set on
        // every arrow key by AppKit, so they are not disqualifying.
        let claimed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .isDisjoint(with: claimed)
        else { return false }

        let interval = MusicManager.skipGestureSeekInterval
        switch arrow {
        case .left: MusicManager.shared.seek(by: -interval)
        case .right: MusicManager.shared.seek(by: interval)
        }

        return true
    }
}
