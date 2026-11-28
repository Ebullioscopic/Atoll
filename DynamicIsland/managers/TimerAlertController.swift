/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import Foundation

/// Alert timing only; TimerManager owns the existing timer and audio player.
struct TimerAlertController {
    private var phaseStarted: Date?
    private(set) var isRinging = false

    /// Begins a ring at `date`, replacing any previous alert phase.
    mutating func start(at date: Date = Date()) {
        phaseStarted = date
        isRinging = true
    }

    /// Cancels both the current ring and any pending repeat reminder.
    mutating func stop() {
        phaseStarted = nil
        isRinging = false
    }

    /// Converts an active ring to silence before playback is stopped for sleep.
    mutating func prepareForSleep(at date: Date = Date()) {
        if isRinging {
            phaseStarted = date
            isRinging = false
        }
    }

    /// Returns a playback change, or nil when no transition is due.
    /// Start each phase now so delayed ticks never replay missed reminders.
    mutating func update(at date: Date = Date(), duration: Int, interval: Int) -> Bool? {
        guard let phaseStarted else { return nil }
        let seconds = isRinging ? min(3600, max(1, duration)) : min(1440, max(1, interval)) * 60
        guard date.timeIntervalSince(phaseStarted) >= Double(seconds) else { return nil }
        isRinging.toggle()
        self.phaseStarted = date
        return isRinging
    }
}
