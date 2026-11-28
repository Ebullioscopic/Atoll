import XCTest
@testable import Atoll

/// Geometry measured on a 13" MacBook Air: 1470pt wide, notch 645.5...824.5.
/// Menu spans are the accessibility frames of real apps on that screen.
final class MenuBarClearanceTests: XCTestCase {
    private let notch: ClosedRange<CGFloat> = 645.5...824.5
    private let gap: CGFloat = 8

    /// Chrome in French: its last left menu ends 9.5pt before the notch, and
    /// "Fenêtre" and "Aide" are carried over to start 9.5pt after it.
    private let chromeMenus: [ClosedRange<CGFloat>] = [
        10...44, 43...115, 119...181, 185...248, 253...350,
        355...438, 442...506, 511...570, 574...636,
        834...901, 906...954,
    ]

    /// An app with a handful of short menus, all well left of the notch.
    private let shortMenus: [ClosedRange<CGFloat>] = [10...44, 50...120, 125...190, 195...260]

    private func placement(
        core: CGFloat = 190,
        wings: CGFloat = 40,
        menus: [ClosedRange<CGFloat>],
        gatherable: Bool = true
    ) -> ClosedActivityPlacement {
        MenuBarLayout.placement(
            notch: notch,
            coreWidth: core,
            wingsWidth: wings,
            menuSpans: menus,
            canGatherWings: gatherable,
            gap: gap
        )
    }

    func testShortMenusLeaveTheActivityCentred() {
        XCTAssertEqual(placement(menus: shortMenus), .centered)
    }

    func testNoMenusLeaveTheActivityCentred() {
        XCTAssertEqual(placement(menus: []), .centered)
    }

    func testMenusOnBothSidesOfTheNotchFoldTheWings() {
        // Chrome leaves 1.5pt of room each side once the gap is counted: no
        // arrangement of 40pt of wings fits.
        XCTAssertEqual(placement(menus: chromeMenus), .retracted)
    }

    func testCarriedOverMenusAreNotTreatedAsLeftMenus() {
        // The old rule took the rightmost menu edge (954) as the end of the
        // left menus and pushed the activity off towards the screen edge.
        // Right-hand menus only ever limit the right-hand side.
        let rightOnly: [ClosedRange<CGFloat>] = [10...44, 900...960]
        XCTAssertEqual(placement(menus: rightOnly), .centered)
    }

    func testMenusReachingTheLeftWingGatherBothWingsOnTheRight() {
        // Left menus end at 630: 7.5pt of room, not the 20 a centred wing
        // needs, while the right side is open.
        let menus: [ClosedRange<CGFloat>] = [10...44, 560...630]
        XCTAssertEqual(placement(menus: menus), .trailing)
    }

    func testMenusReachingTheRightWingGatherBothWingsOnTheLeft() {
        let menus: [ClosedRange<CGFloat>] = [10...44, 840...900]
        XCTAssertEqual(placement(menus: menus), .leading)
    }

    func testAnActivityThatCannotGatherItsWingsFolds() {
        let menus: [ClosedRange<CGFloat>] = [10...44, 560...630]
        XCTAssertEqual(placement(menus: menus, gatherable: false), .retracted)
    }

    func testTheGapAloneIsEnoughToMakeWay() {
        // Centred wings reach 5.5 + 20 = 25.5pt past the notch, to 620. Menus
        // ending at 615 clear that, but not by the 8pt gap.
        let menus: [ClosedRange<CGFloat>] = [10...44, 560...615]
        XCTAssertEqual(placement(menus: menus), .trailing)
        let roomier: [ClosedRange<CGFloat>] = [10...44, 560...611]
        XCTAssertEqual(placement(menus: roomier), .centered)
    }

    func testACoreWiderThanTheRoomFoldsEvenWhenGatherable() {
        // A 240pt core reaches 30.5pt past each edge on its own; gathering the
        // wings does not help when the core alone covers a menu.
        let menus: [ClosedRange<CGFloat>] = [10...44, 560...630]
        XCTAssertEqual(placement(core: 240, wings: 40, menus: menus), .retracted)
    }

    func testAnExternalDisplayIsMeasuredInGlobalCoordinates() {
        // The same notch and menus on a display that starts at x=1710: only
        // global positions are compared, so the outcomes must not change.
        let shift: CGFloat = 1710
        let moved: (ClosedRange<CGFloat>) -> ClosedRange<CGFloat> = {
            ($0.lowerBound + shift)...($0.upperBound + shift)
        }
        func placementShifted(_ menus: [ClosedRange<CGFloat>]) -> ClosedActivityPlacement {
            MenuBarLayout.placement(
                notch: moved(notch),
                coreWidth: 190,
                wingsWidth: 40,
                menuSpans: menus.map(moved),
                canGatherWings: true,
                gap: gap
            )
        }
        XCTAssertEqual(placementShifted(chromeMenus), .retracted)
        XCTAssertEqual(placementShifted(shortMenus), .centered)
        XCTAssertEqual(placementShifted([10...44, 560...630]), .trailing)
    }

    func testNothingBeyondTheNotchNeverMoves() {
        XCTAssertEqual(placement(core: 170, wings: 0, menus: chromeMenus), .centered)
    }

    // MARK: - Full screen

    func testAFullScreenWindowImposesNoConstraint() {
        // The menu bar is hidden in full screen, but accessibility still reports
        // the menus where they were.
        let menus = AppMenuBar(spans: chromeMenus, origin: CGPoint(x: 10, y: 0))
        XCTAssertNil(MenuBarLayout.constraint(menus: menus, isFullScreen: true))
        XCTAssertEqual(MenuBarLayout.constraint(menus: menus, isFullScreen: false), menus)
    }

    func testMenusWithoutWidthImposeNoConstraint() {
        let menus = AppMenuBar(spans: [10...10, 50...50], origin: CGPoint(x: 10, y: 0))
        XCTAssertNil(MenuBarLayout.constraint(menus: menus, isFullScreen: false))
        XCTAssertNil(MenuBarLayout.constraint(menus: nil, isFullScreen: false))
    }

    // MARK: - Several displays
    //
    // MacBook 1470x956 at the origin. In Cocoa coordinates a 27" display
    // (2560x1440) to its right with top edges aligned starts at y = 956 - 1440;
    // one above it starts at y = 956.
    private let macBook = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let externalRight = CGRect(x: 1470, y: -484, width: 2560, height: 1440)
    private let externalAbove = CGRect(x: -545, y: 956, width: 2560, height: 1440)

    private func spans(_ menus: AppMenuBar, on screen: CGRect) -> [ClosedRange<CGFloat>] {
        menus.spans(onScreen: screen, primaryScreenMaxY: macBook.maxY)
    }

    func testMenusOnADisplayToTheRightDoNotMoveTheMacBookActivity() {
        // Menus read on the external display's menu bar, at global x 1478...2070.
        let menus = AppMenuBar(spans: [1478...1512, 1516...2070], origin: CGPoint(x: 1478, y: 0))
        XCTAssertTrue(spans(menus, on: macBook).isEmpty)
        XCTAssertEqual(spans(menus, on: externalRight), menus.spans)
        XCTAssertEqual(placement(menus: spans(menus, on: macBook)), .centered)
    }

    func testMenusOnADisplayAboveDoNotMoveTheMacBookActivity() {
        // Stacked displays share x positions, so the menus' x alone would put
        // them over the MacBook's notch; their y places them on the other bar.
        let menus = AppMenuBar(spans: [-537...(-503), -499...630], origin: CGPoint(x: -537, y: -1440))
        XCTAssertTrue(spans(menus, on: macBook).isEmpty)
        XCTAssertEqual(spans(menus, on: externalAbove), menus.spans)
        XCTAssertEqual(placement(menus: spans(menus, on: macBook)), .centered)
    }

    func testMenusOnTheMacBookStillApplyThere() {
        let menus = AppMenuBar(spans: chromeMenus, origin: CGPoint(x: 10, y: 0))
        XCTAssertEqual(spans(menus, on: macBook), chromeMenus)
        XCTAssertTrue(spans(menus, on: externalRight).isEmpty)
        XCTAssertEqual(placement(menus: spans(menus, on: macBook)), .retracted)
    }

    // MARK: - Sneak peeks and HUDs

    private func yields(
        closed: Bool = true,
        hidden: Bool = false,
        island: Bool = false,
        connectivityHUD: Bool = false,
        sneakPeek: Bool = false,
        expansion: Bool = false
    ) -> Bool {
        MenuBarLayout.yieldsToMenus(
            isNotchClosed: closed,
            isHiddenOnClosed: hidden,
            isIslandMode: island,
            isConnectivityHUDVisible: connectivityHUD,
            isSneakPeekVisible: sneakPeek,
            isExpansionVisible: expansion
        )
    }

    func testAClosedLiveActivityMakesWayForMenus() {
        XCTAssertTrue(yields())
    }

    func testSneakPeeksAndHUDsStayCentred() {
        // Volume, brightness and the other sneak peeks, inline expansions and
        // the connectivity HUD keep their full width over a menu.
        XCTAssertFalse(yields(sneakPeek: true))
        XCTAssertFalse(yields(expansion: true))
        XCTAssertFalse(yields(connectivityHUD: true))
    }

    func testAnOpenHiddenOrFloatingNotchStaysCentred() {
        XCTAssertFalse(yields(closed: false))
        XCTAssertFalse(yields(hidden: true))
        XCTAssertFalse(yields(island: true))
    }
}
