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

/// When to remind the user that an agent is still waiting.
///
/// The ladder widens deliberately: an immediate nudge for someone who is looking,
/// then progressively rarer ones so an unattended request does not turn into a
/// stream of notifications. Pure and injectable-time, so the cadence is tested
/// without waiting fifteen minutes.
enum AgentEscalationSchedule {
    /// Seconds after the request arrives at which to remind. Matches the cadence
    /// Crew Tower uses: right away, a beat later, then 1, 5 and 15 minutes.
    static let defaultSteps: [TimeInterval] = [0, 8, 60, 300, 900]

    /// Cleans a step list into something safe to iterate: non-negative, sorted,
    /// duplicate-free.
    ///
    /// Necessary because the steps are user-configurable, and a negative or
    /// out-of-order value would otherwise produce a negative sleep or fire
    /// reminders in the wrong order.
    static func normalized(_ steps: [TimeInterval]) -> [TimeInterval] {
        var seen = Set<TimeInterval>()
        return steps
            .filter { $0 >= 0 }
            .sorted()
            .filter { seen.insert($0).inserted }
    }

    /// Gaps to sleep between consecutive reminders.
    ///
    /// `[0, 8, 60]` becomes `[0, 8, 52]`: fire, wait 8s, fire, wait 52s, fire.
    static func deltas(for steps: [TimeInterval]) -> [TimeInterval] {
        let clean = normalized(steps)
        var result: [TimeInterval] = []
        var previous: TimeInterval = 0
        for step in clean {
            result.append(max(0, step - previous))
            previous = step
        }
        return result
    }

    /// How many reminders should already have fired by `elapsed`.
    static func dueCount(elapsed: TimeInterval, steps: [TimeInterval] = defaultSteps) -> Int {
        normalized(steps).filter { $0 <= elapsed }.count
    }

    /// Seconds until the next reminder, or `nil` once the ladder is exhausted.
    ///
    /// Never returns a negative value: a reminder whose moment has already passed
    /// is due now.
    static func delayUntilNext(
        elapsed: TimeInterval,
        firedCount: Int,
        steps: [TimeInterval] = defaultSteps
    ) -> TimeInterval? {
        let clean = normalized(steps)
        guard firedCount >= 0, firedCount < clean.count else { return nil }
        return max(0, clean[firedCount] - elapsed)
    }

    /// Whether a reminder should be suppressed.
    ///
    /// Privacy mode silences reminders but never hides the card itself — the user
    /// asked not to be interrupted, not to be kept in the dark.
    static func shouldSuppressReminder(privacyMode: Bool, doNotDisturbActive: Bool) -> Bool {
        privacyMode || doNotDisturbActive
    }
}
