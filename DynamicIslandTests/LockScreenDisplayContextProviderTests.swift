import XCTest
@testable import Atoll

final class LockScreenDisplayContextProviderTests: XCTestCase {
    private let select = LockScreenDisplayContextProvider.preferredDisplayIndex

    func testExternalMainDisplayWinsOverBuiltin() {
        XCTAssertEqual(select([(1, true), (2, false)], 2), 1)
    }

    func testBuiltinMainDisplayIsUsed() {
        XCTAssertEqual(select([(1, true), (2, false)], 1), 0)
    }

    func testClamshellUsesMainExternalDisplay() {
        XCTAssertEqual(select([(2, false), (3, false)], 3), 1)
    }

    func testFallsBackToBuiltinThenFirstWhenMainIsMissing() {
        XCTAssertEqual(select([(2, false), (1, true)], 3), 1)
        XCTAssertEqual(select([(2, false)], 3), 0)
        XCTAssertNil(select([], 3))
    }
}
