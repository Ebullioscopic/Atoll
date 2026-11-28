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

import XCTest

@testable import Atoll

/// A cancelled Developer Tools Access prompt makes `log stream` exit at once;
/// restarting it on a fixed delay re-prompted the user every few seconds (#280).
final class LogStreamRestartPolicyTests: XCTestCase {
    func testLongRunningStreamIsAlwaysRestarted() {
        var policy = LogStreamRestartPolicy()
        for _ in 0..<5 {
            XCTAssertEqual(policy.restartDelay(afterRuntime: 600, baseDelay: 2), 2)
        }
        XCTAssertFalse(policy.hasGivenUp)
    }

    func testRepeatedShortRunsBackOffThenGiveUp() {
        var policy = LogStreamRestartPolicy()
        XCTAssertEqual(policy.restartDelay(afterRuntime: 1, baseDelay: 2), 4)
        XCTAssertNil(policy.restartDelay(afterRuntime: 1, baseDelay: 2))
        XCTAssertTrue(policy.hasGivenUp)
        XCTAssertNil(policy.restartDelay(afterRuntime: 600, baseDelay: 2))
    }

    func testHealthyRunClearsShortRunCount() {
        var policy = LogStreamRestartPolicy()
        XCTAssertNotNil(policy.restartDelay(afterRuntime: 1, baseDelay: 2))
        XCTAssertEqual(policy.restartDelay(afterRuntime: 600, baseDelay: 2), 2)
        XCTAssertNotNil(policy.restartDelay(afterRuntime: 1, baseDelay: 2))
    }

    func testResetAllowsRestartingAfterGivingUp() {
        var policy = LogStreamRestartPolicy()
        _ = policy.restartDelay(afterRuntime: 1, baseDelay: 2)
        _ = policy.restartDelay(afterRuntime: 1, baseDelay: 2)
        policy.reset()
        XCTAssertEqual(policy.restartDelay(afterRuntime: 1, baseDelay: 2), 4)
    }
}
