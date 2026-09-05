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

/// Covers the two pure pieces of the caffeinate feature: when a session ends,
/// and how the countdown reads. The assertion itself is IOKit state, so it is
/// not exercised here.
final class CaffeinateManagerTests: XCTestCase {

    // MARK: - expiry

    func testIndefiniteSessionNeverExpires() {
        XCTAssertNil(CaffeinateManager.expiry(from: Date(), duration: .indefinite))
    }

    func testTimedSessionExpiresAfterItsDuration() {
        let start = Date(timeIntervalSince1970: 1_000_000)

        for duration in CaffeinateDuration.allCases {
            guard let seconds = duration.seconds else { continue }
            let expiry = CaffeinateManager.expiry(from: start, duration: duration)
            XCTAssertEqual(
                expiry?.timeIntervalSince(start),
                seconds,
                "\(duration.rawValue) should expire exactly \(seconds)s after it starts"
            )
        }
    }

    func testDurationsAreOrderedAndDistinct() {
        // The popover renders `allCases` in declaration order, so a duration
        // list that is not ascending would read as a shuffled menu.
        let seconds = CaffeinateDuration.allCases.compactMap(\.seconds)
        XCTAssertEqual(seconds, seconds.sorted())
        XCTAssertEqual(Set(seconds).count, seconds.count)
    }

    // MARK: - remainingLabel

    func testLabelUnderAnHourOmitsTheHourField() {
        XCTAssertEqual(CaffeinateManager.remainingLabel(0), "0:00")
        XCTAssertEqual(CaffeinateManager.remainingLabel(59), "0:59")
        XCTAssertEqual(CaffeinateManager.remainingLabel(60), "1:00")
        XCTAssertEqual(CaffeinateManager.remainingLabel(15 * 60), "15:00")
        XCTAssertEqual(CaffeinateManager.remainingLabel(3599), "59:59")
    }

    func testLabelAtOrAboveAnHourIncludesIt() {
        XCTAssertEqual(CaffeinateManager.remainingLabel(3600), "1:00:00")
        XCTAssertEqual(CaffeinateManager.remainingLabel(3661), "1:01:01")
        XCTAssertEqual(CaffeinateManager.remainingLabel(4 * 60 * 60), "4:00:00")
    }

    func testLabelRoundsUpSoTheFinalSecondIsNotShownAsZero() {
        // Truncating instead would show "0:00" for the whole last second,
        // which reads as a session that has already ended.
        XCTAssertEqual(CaffeinateManager.remainingLabel(0.4), "0:01")
        XCTAssertEqual(CaffeinateManager.remainingLabel(59.5), "1:00")
    }

    func testNegativeRemainderClampsToZero() {
        // The ticker deactivates at <= 0, but a late tick can still arrive with
        // a negative interval; it must not render as "-1:-1".
        XCTAssertEqual(CaffeinateManager.remainingLabel(-5), "0:00")
    }
}
