import XCTest
@testable import Atoll

/// The screen these use is a 14" MacBook Pro: 1710pt wide, notch 185pt wide and
/// centred, so the menu bar's left strip runs 0...762.5.
final class MenuBarClearanceTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    private let gap: CGFloat = 8

    private func offset(contentWidth: CGFloat, menusEnd: CGFloat, screen: CGRect? = nil) -> CGFloat {
        MenuBarLayout.clearanceOffset(
            contentWidth: contentWidth,
            screenFrame: screen ?? self.screen,
            menusRightEdge: menusEnd,
            gap: gap
        )
    }

    func testShortMenusLeaveTheNotchCentred() {
        // 300pt of content is centred at 855, so it begins at 705. Menus that
        // end at 606 -- Zen's, measured -- are nowhere near it.
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 606), 0)
    }

    func testMenusReachingTheContentPushItRight() {
        // Content begins at 705; menus ending at 720 overlap it by 15, plus the
        // 8pt gap.
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 720), 23)
    }

    func testTheGapAloneIsEnoughToMove() {
        // Menus end exactly where the content begins: no overlap, but they would
        // be flush, so the content still steps aside by the gap.
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 705), 8)
    }

    func testMenusEndingJustShortOfTheGapDoNotMove() {
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 697), 0)
    }

    func testAWiderActivityIsCoveredSooner() {
        // 500pt of content begins at 605, so the same menus that cleared a
        // 300pt activity now overlap it.
        XCTAssertEqual(offset(contentWidth: 500, menusEnd: 606), 9)
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 606), 0)
    }

    func testTheShiftStopsAtTheScreenEdge() {
        // Content this wide has only 105pt of room on the right, so a demand for
        // more than that is capped rather than pushing it off screen.
        let wide: CGFloat = 1500
        let headroom = screen.maxX - (screen.midX - wide / 2 + wide)
        XCTAssertEqual(offset(contentWidth: wide, menusEnd: 1000), headroom)
        XCTAssertEqual(headroom, 105)
    }

    func testContentFillingTheScreenNeverMoves() {
        XCTAssertEqual(offset(contentWidth: 1710, menusEnd: 900), 0)
    }

    func testNoContentMeansNoShift() {
        XCTAssertEqual(offset(contentWidth: 0, menusEnd: 900), 0)
    }

    func testAnExternalDisplayIsMeasuredOnItsOwnGeometry() {
        // A screen that does not start at x=0 -- the arithmetic is in global
        // coordinates, so a second display must not be treated as if it did.
        let external = CGRect(x: 1710, y: 0, width: 2560, height: 1440)
        // Centre is 2990, so 300pt of content begins at 2840.
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 2850, screen: external), 18)
        XCTAssertEqual(offset(contentWidth: 300, menusEnd: 2000, screen: external), 0)
    }
}
