import XCTest
@testable import CodeIsland

final class QuietHoursTests: XCTestCase {

    func testSameDayWindowIsHalfOpen() {
        // 10:00–12:00
        XCTAssertFalse(SoundManager.isInQuietHours(minutesSinceMidnight: 599, start: 600, end: 720))
        XCTAssertTrue(SoundManager.isInQuietHours(minutesSinceMidnight: 600, start: 600, end: 720))
        XCTAssertTrue(SoundManager.isInQuietHours(minutesSinceMidnight: 719, start: 600, end: 720))
        XCTAssertFalse(SoundManager.isInQuietHours(minutesSinceMidnight: 720, start: 600, end: 720))
    }

    func testOvernightWindowSpansMidnight() {
        // 22:00–08:00
        XCTAssertFalse(SoundManager.isInQuietHours(minutesSinceMidnight: 1319, start: 1320, end: 480))
        XCTAssertTrue(SoundManager.isInQuietHours(minutesSinceMidnight: 1320, start: 1320, end: 480))
        XCTAssertTrue(SoundManager.isInQuietHours(minutesSinceMidnight: 0, start: 1320, end: 480))
        XCTAssertTrue(SoundManager.isInQuietHours(minutesSinceMidnight: 479, start: 1320, end: 480))
        XCTAssertFalse(SoundManager.isInQuietHours(minutesSinceMidnight: 480, start: 1320, end: 480))
        XCTAssertFalse(SoundManager.isInQuietHours(minutesSinceMidnight: 720, start: 1320, end: 480))
    }

    func testEmptyWindowNeverMutes() {
        for m in [0, 600, 1439] {
            XCTAssertFalse(SoundManager.isInQuietHours(minutesSinceMidnight: m, start: 600, end: 600))
        }
    }

    func testQuietHoursL10nKeysExistInAllLanguages() {
        for (lang, table) in L10n.strings {
            for key in ["quiet_hours", "quiet_hours_desc", "quiet_hours_start", "quiet_hours_end"] {
                XCTAssertNotNil(table[key], "\(lang) missing \(key)")
            }
        }
    }
}
