import XCTest
@testable import Atoll

final class LockScreenDisplayContextProviderTests: XCTestCase {
    func testPreferredDisplayOrder() {
        let select = LockScreenDisplayContextProvider.preferredDisplayIndex
        let displays: [(displayID: UInt32?, isBuiltin: Bool)] = [(1, true), (2, false)]
        XCTAssertEqual(select(displays, 2, 0), 1)
        XCTAssertEqual(select(displays, 1, 1), 0)
        XCTAssertEqual(select([(2, false), (3, false)], 3, 0), 1)
        XCTAssertEqual(select(displays, 3, 1), 1)
        XCTAssertEqual(select(displays.reversed(), 3, nil), 1)
        XCTAssertEqual(select([(2, false)], 3, nil), 0)
        XCTAssertNil(select([], 3, nil))
    }
}
