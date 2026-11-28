import XCTest
@testable import Atoll

final class TimerCountdownTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testRemainingTimeFollowsTheWallClockAcrossSleep() {
        let end = start.addingTimeInterval(600)
        // A lid closed for four minutes produces no ticks, but the next one
        // must still land four minutes further on (#271).
        XCTAssertEqual(TimerCountdown.remainingSeconds(until: end, now: start.addingTimeInterval(240)), 360)
    }

    func testLateTicksRoundToTheNearestSecond() {
        let end = start.addingTimeInterval(60)
        XCTAssertEqual(TimerCountdown.remainingSeconds(until: end, now: start.addingTimeInterval(1.08)), 59)
        XCTAssertEqual(TimerCountdown.remainingSeconds(until: end, now: start.addingTimeInterval(0.97)), 59)
    }

    func testExpiryDuringSleepReportsOvertime() {
        let end = start.addingTimeInterval(60)
        XCTAssertEqual(TimerCountdown.remainingSeconds(until: end, now: start.addingTimeInterval(60)), 0)
        XCTAssertEqual(TimerCountdown.remainingSeconds(until: end, now: start.addingTimeInterval(3_660)), -3_600)
    }
}
