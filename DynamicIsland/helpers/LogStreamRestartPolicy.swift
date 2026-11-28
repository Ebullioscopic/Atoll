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

/// Decides whether a `/usr/bin/log stream` child that exited should be restarted.
///
/// Streaming the unified log can make macOS show the "Developer Tools Access"
/// authorization prompt. When the user cancels it, the child exits right away,
/// so restarting it on a fixed delay re-prompts every few seconds forever.
/// A stream that ran for a while (logd restart, memory pressure) is restarted
/// normally; repeated short-lived runs back off and then stop for the session.
struct LogStreamRestartPolicy {
    static let healthyRuntime: TimeInterval = 60
    static let maximumShortRuns = 1

    private(set) var shortRuns = 0
    private(set) var hasGivenUp = false

    /// Returns the delay before restarting, or `nil` when the stream should stay stopped.
    mutating func restartDelay(afterRuntime runtime: TimeInterval, baseDelay: TimeInterval) -> TimeInterval? {
        guard !hasGivenUp else { return nil }

        if runtime >= Self.healthyRuntime {
            shortRuns = 0
            return baseDelay
        }

        shortRuns += 1
        guard shortRuns <= Self.maximumShortRuns else {
            hasGivenUp = true
            return nil
        }
        return baseDelay * Double(1 << shortRuns)
    }

    mutating func reset() {
        shortRuns = 0
        hasGivenUp = false
    }
}
