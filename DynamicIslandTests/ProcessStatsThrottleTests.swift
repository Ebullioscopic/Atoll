import XCTest
@testable import Atoll

/// The top-process list runs `/bin/ps` at most every 2 s from the 1 s stats tick.
final class ProcessStatsThrottleTests: XCTestCase {
    func testOneSecondTicksRefreshEveryOtherTick() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var lastStart = Date.distantPast
        var refreshTicks: [Int] = []
        for tick in 0..<7 {
            // Ticks arrive a little early or late, as a timer with tolerance does.
            let now = start.addingTimeInterval(Double(tick) + (tick.isMultiple(of: 2) ? -0.02 : 0.03))
            if StatsManager.isProcessRefreshDue(now: now, lastRefreshStart: lastStart, interval: 2) {
                refreshTicks.append(tick)
                lastStart = now
            }
        }
        XCTAssertEqual(refreshTicks, [0, 2, 4, 6])
    }

    func testNotDueWithinTheInterval() {
        let last = Date(timeIntervalSinceReferenceDate: 100)
        XCTAssertFalse(StatsManager.isProcessRefreshDue(now: last.addingTimeInterval(1.5), lastRefreshStart: last, interval: 2))
        XCTAssertTrue(StatsManager.isProcessRefreshDue(now: last.addingTimeInterval(2), lastRefreshStart: last, interval: 2))
    }
}
