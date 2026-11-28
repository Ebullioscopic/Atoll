/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation

/// Gives each timer run its own identity so delayed work from an earlier run
/// cannot mutate a timer that was started in the meantime.
struct TimerLifecycle {
    private(set) var sessionID: UUID?
    private(set) var completedSessionID: UUID?

    @discardableResult
    mutating func beginSession() -> UUID {
        let sessionID = UUID()
        self.sessionID = sessionID
        completedSessionID = nil
        return sessionID
    }

    @discardableResult
    mutating func completeSession() -> UUID? {
        completedSessionID = sessionID
        return completedSessionID
    }

    mutating func endSession() {
        sessionID = nil
        completedSessionID = nil
    }

    func isCurrent(_ candidate: UUID) -> Bool {
        sessionID == candidate
    }
}

/// Countdown arithmetic for a timer that runs against the wall clock, so time
/// the Mac spends asleep (for example with the lid closed) still counts down.
enum TimerCountdown {
    /// Whole seconds left until `endDate`; negative once the timer is in overtime.
    static func remainingSeconds(until endDate: Date, now: Date) -> TimeInterval {
        endDate.timeIntervalSince(now).rounded()
    }
}
