import AppKit
import XCTest
@testable import CodeIsland

final class ScreenDetectorTests: XCTestCase {
    func testAutoPreferredIndexUsesActiveWorkScreenBeforeBuiltInScreen() {
        let candidates = [
            ScreenDetector.Candidate(
                frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
                hasNotch: true,
                isMain: true
            ),
            ScreenDetector.Candidate(
                frame: NSRect(x: 1512, y: 0, width: 1920, height: 1080),
                hasNotch: false,
                isMain: false
            )
        ]

        let index = ScreenDetector.autoPreferredIndex(
            candidates: candidates,
            activeWindowBounds: NSRect(x: 1800, y: 100, width: 1000, height: 800)
        )

        XCTAssertEqual(index, 1)
    }

    func testAutoPreferredIndexFallsBackToBuiltInScreenWhenNoActiveWorkScreenExists() {
        let candidates = [
            ScreenDetector.Candidate(
                frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
                hasNotch: true,
                isMain: false
            ),
            ScreenDetector.Candidate(
                frame: NSRect(x: 1512, y: 0, width: 1920, height: 1080),
                hasNotch: false,
                isMain: true
            )
        ]

        let index = ScreenDetector.autoPreferredIndex(
            candidates: candidates,
            activeWindowBounds: nil
        )

        XCTAssertEqual(index, 0)
    }

    func testAutoPreferredIndexFallsBackToMainScreenWhenNoBuiltInScreenExists() {
        let candidates = [
            ScreenDetector.Candidate(
                frame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
                hasNotch: false,
                isMain: false
            ),
            ScreenDetector.Candidate(
                frame: NSRect(x: 1920, y: 0, width: 1920, height: 1080),
                hasNotch: false,
                isMain: true
            )
        ]

        let index = ScreenDetector.autoPreferredIndex(
            candidates: candidates,
            activeWindowBounds: nil
        )

        XCTAssertEqual(index, 1)
    }
}
