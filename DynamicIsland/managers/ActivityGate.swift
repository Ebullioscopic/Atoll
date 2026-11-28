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

/// Tells optional background pollers when the displays or the system are
/// asleep, so they can stop waking the app while nothing can be shown.
@MainActor
final class ActivityGate: ObservableObject {
    static let shared = ActivityGate()

    @Published private(set) var shouldSuspendBackgroundWork: Bool = false

    // Tracked separately: a dark wake ends system sleep while the screens stay off.
    private var screensAsleep = false {
        didSet { updateSuspension() }
    }
    private var systemAsleep = false {
        didSet { updateSuspension() }
    }

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        let transitions: [(Notification.Name, ReferenceWritableKeyPath<ActivityGate, Bool>, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, \.screensAsleep, true),
            (NSWorkspace.screensDidWakeNotification, \.screensAsleep, false),
            (NSWorkspace.willSleepNotification, \.systemAsleep, true),
            (NSWorkspace.didWakeNotification, \.systemAsleep, false)
        ]
        for (name, keyPath, value) in transitions {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?[keyPath: keyPath] = value
                }
            }
        }
        // Don't rely solely on screensDidWake after a full sleep: re-read the
        // display state so a missed notification cannot leave work suspended.
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0
            }
        }
    }

    private func updateSuspension() {
        let suspended = screensAsleep || systemAsleep
        if suspended != shouldSuspendBackgroundWork {
            shouldSuspendBackgroundWork = suspended
        }
    }
}
