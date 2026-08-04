import XCTest
@testable import CodeIslandRuntime

final class CodeIslandRuntimeTests: XCTestCase {
    func testRuntimeIsInertByDefault() {
        XCTAssertFalse(CodeIslandRuntime.isEnabledByDefault)
        XCTAssertFalse(CodeIslandRuntime().isRunning)
    }
}
