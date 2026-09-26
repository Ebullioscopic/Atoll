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

/// Left and right arrow keys seek the playing track, but only for as long as
/// the notch is open.
///
/// Scoped that tightly on purpose. Arrow keys belong to whatever the user is
/// typing in; claiming them permanently would break text editors, browsers and
/// games. Having the notch open is the signal that the keys are meant here.
@MainActor
final class NotchSeekKeyMonitor {
    static let shared = NotchSeekKeyMonitor()

    private var localMonitor: Any?
    private var globalMonitor: Any?

    /// The open notches currently asking for the arrow keys.
    ///
    /// One pair of process-wide event taps is shared by every screen, so they
    /// cannot come down until nothing wants them: with notches open on two
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
        guard localMonitor == nil, globalMonitor == nil else { return }

        // Fires when Atoll itself is frontmost, and can swallow the event so the
        // key does not also act on the notch's own SwiftUI focus.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }

        // The notch opens on hover without activating Atoll, so the keystroke
        // usually belongs to the frontmost app and the local monitor never sees
        // it. A global monitor does -- passively. It cannot swallow the event,
        // so the app underneath still receives its arrow key; seeking is in
        // addition to whatever that app does, not instead of it.
        //
        // Global key monitoring needs Accessibility. Without it this simply
        // never fires, which degrades to "works while Atoll is frontmost"
        // rather than failing loudly.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handle(event)
        }
    }

    /// Gives the arrow keys back on behalf of one notch.
    ///
    /// The taps come down only once the last notch has let go. Releasing a
    /// notch that never asked, or has already let go, does nothing -- which is
    /// what makes it safe to call from every teardown path without first
    /// working out whether this notch was the one that started it.
    func stop(owner: UUID) {
        owners.remove(owner)
        guard owners.isEmpty else { return }

        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
    }

    /// Returns whether the event was consumed.
    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        guard Defaults[.arrowKeySeekEnabled] else { return false }
        guard let arrow = ArrowKey(rawValue: event.keyCode) else { return false }

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
