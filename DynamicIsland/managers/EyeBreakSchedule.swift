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

import Foundation

/// The 20-20-20 cycle, as pure state.
///
/// Every transition is driven by a caller-supplied `now`, and each phase carries
/// an absolute deadline rather than a tick count. That is what makes the schedule
/// survive display and system sleep: waking up hours later collapses into a
/// single transition instead of replaying every missed second, so a long sleep
/// can never stack up several breaks.
struct EyeBreakSchedule: Equatable {
    enum Phase: Equatable {
        /// The feature is off, or nothing is scheduled yet.
        case idle
        /// Counting down to the next break.
        case working(deadline: Date)
        /// The break has fallen due but has not been shown yet — the screen is
        /// locked, or the display is asleep. The rest countdown deliberately does
        /// not start here, so a break cannot burn its twenty seconds unseen.
        case breakDue
        /// Resting; the notch is showing the countdown.
        case resting(deadline: Date)
        /// Work countdown held while the user is away from the Mac.
        case pausedWorking(remaining: TimeInterval)
    }

    /// Seconds of work between breaks.
    var workInterval: TimeInterval
    /// Seconds each break lasts.
    var restDuration: TimeInterval

    private(set) var phase: Phase = .idle

    init(workInterval: TimeInterval, restDuration: TimeInterval) {
        self.workInterval = workInterval
        self.restDuration = restDuration
    }

    // MARK: - Derived state

    var isResting: Bool {
        if case .resting = phase { return true }
        return false
    }

    /// True while the break should be visible in the notch.
    var isBreakVisible: Bool { isResting }

    var isRunning: Bool { phase != .idle }

    /// Whole seconds left in the current countdown, or nil when nothing is
    /// counting down. Rounded up so a countdown reads "1" until it is really over.
    func remainingSeconds(at now: Date) -> Int? {
        switch phase {
        case .idle, .breakDue:
            return nil
        case .working(let deadline), .resting(let deadline):
            return max(0, Int(ceil(deadline.timeIntervalSince(now))))
        case .pausedWorking(let remaining):
            return max(0, Int(ceil(remaining)))
        }
    }

    // MARK: - Transitions

    mutating func start(at now: Date) {
        phase = .working(deadline: now.addingTimeInterval(workInterval))
    }

    mutating func stop() {
        phase = .idle
    }

    /// Moves the schedule forward to `now`.
    ///
    /// `canPresent` is false while the break cannot be shown (locked screen,
    /// sleeping display); a break that falls due then waits in `breakDue` until
    /// the user is back.
    mutating func advance(to now: Date, canPresent: Bool = true) {
        switch phase {
        case .idle, .pausedWorking:
            break

        case .working(let deadline):
            guard now >= deadline else { break }
            phase = canPresent ? .resting(deadline: now.addingTimeInterval(restDuration)) : .breakDue

        case .breakDue:
            guard canPresent else { break }
            phase = .resting(deadline: now.addingTimeInterval(restDuration))

        case .resting(let deadline):
            guard now >= deadline else { break }
            phase = .working(deadline: now.addingTimeInterval(workInterval))
        }
    }

    /// Ends the current break early and starts the next work interval. A no-op
    /// while working, so a stray Skip cannot shorten the work period.
    mutating func skipBreak(at now: Date) {
        switch phase {
        case .breakDue, .resting:
            phase = .working(deadline: now.addingTimeInterval(workInterval))
        case .idle, .working, .pausedWorking:
            break
        }
    }

    /// Holds the work countdown while the user is away. Only the work phase
    /// pauses: a rest that is already running just finishes, and a break already
    /// due stays due.
    mutating func pause(at now: Date) {
        guard case .working(let deadline) = phase else { return }
        phase = .pausedWorking(remaining: max(0, deadline.timeIntervalSince(now)))
    }

    mutating func resume(at now: Date) {
        guard case .pausedWorking(let remaining) = phase else { return }
        phase = .working(deadline: now.addingTimeInterval(remaining))
    }

    /// Applies edited durations. The work countdown is rebased onto the new
    /// interval so a change in settings takes effect immediately instead of after
    /// one more full cycle.
    mutating func updateDurations(workInterval: TimeInterval, restDuration: TimeInterval, at now: Date) {
        let workChanged = workInterval != self.workInterval
        self.workInterval = workInterval
        self.restDuration = restDuration

        guard workChanged else { return }
        switch phase {
        case .working:
            phase = .working(deadline: now.addingTimeInterval(workInterval))
        case .pausedWorking:
            phase = .pausedWorking(remaining: workInterval)
        case .idle, .breakDue, .resting:
            break
        }
    }
}
