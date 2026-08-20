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

/// The media key tap cannot be created until Accessibility is granted, and
/// granting it does not relaunch the app — so the retry schedule is the only
/// thing standing between a denied prompt and volume keys that behave natively
/// for the rest of the session.
final class MediaKeyTapRetryPolicyTests: XCTestCase {
    /// The common case: permission arrives seconds after the prompt.
    func testKeepsRetryingEarlyOn() {
        XCTAssertEqual(MediaKeyTapRetryPolicy.step(attempt: 1, elapsed: 2), .retry)
        XCTAssertEqual(MediaKeyTapRetryPolicy.step(attempt: 5, elapsed: 10), .retry)
    }

    /// After the first minute, polling every two seconds is just burning
    /// wakeups for a user who has not opened System Settings.
    func testBacksOffOnceAfterTheFastAttemptLimit() {
        let limit = MediaKeyTapRetryPolicy.fastAttemptLimit
        XCTAssertEqual(MediaKeyTapRetryPolicy.step(attempt: limit - 1, elapsed: 58), .retry)
        XCTAssertEqual(MediaKeyTapRetryPolicy.step(attempt: limit, elapsed: 60), .backOff)
        // Only once — a repeated .backOff would reinstall the timer every tick.
        XCTAssertEqual(MediaKeyTapRetryPolicy.step(attempt: limit + 1, elapsed: 75), .retry)
    }

    /// Stop eventually rather than polling for the life of the process.
    func testGivesUpAfterAnHour() {
        let deadline = MediaKeyTapRetryPolicy.giveUpAfter
        XCTAssertEqual(MediaKeyTapRetryPolicy.step(attempt: 200, elapsed: deadline - 1), .retry)
        XCTAssertEqual(MediaKeyTapRetryPolicy.step(attempt: 200, elapsed: deadline), .giveUp)
    }

    /// The deadline outranks the back-off, so a tap that is still missing at
    /// the hour mark stops instead of rescheduling itself.
    func testGivingUpWinsOverBackingOff() {
        XCTAssertEqual(
            MediaKeyTapRetryPolicy.step(
                attempt: MediaKeyTapRetryPolicy.fastAttemptLimit,
                elapsed: MediaKeyTapRetryPolicy.giveUpAfter
            ),
            .giveUp
        )
    }

    /// A slower poll than the fast one, or the back-off would be pointless.
    func testSlowIntervalIsSlowerThanFast() {
        XCTAssertGreaterThan(MediaKeyTapRetryPolicy.slowInterval, MediaKeyTapRetryPolicy.fastInterval)
    }
}
