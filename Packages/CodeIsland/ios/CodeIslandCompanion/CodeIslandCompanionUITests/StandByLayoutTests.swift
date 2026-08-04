import XCTest
import CoreGraphics

final class StandByLayoutTests: XCTestCase {
    // 消息行数固定为 3。
    func testMessageLimitAlwaysThree() {
        XCTAssertEqual(standbySessionBoardLayout(boardHeight: 800, sessionCount: 2).messageLineLimit, 3)
        XCTAssertEqual(standbySessionBoardLayout(boardHeight: 200, sessionCount: 6).messageLineLimit, 3)
    }

    // 可见会话数按行高 stride 100 容纳（usable = 高度 - 44）。
    func testVisibleCountFitsByHeight() {
        // usable 756，Int(756/100)=7 行，6 个会话全显
        XCTAssertEqual(standbySessionBoardLayout(boardHeight: 800, sessionCount: 6).visibleCount, 6)
        // usable 356，Int(356/100)=3 行，10 个会话只显 3 个
        XCTAssertEqual(standbySessionBoardLayout(boardHeight: 400, sessionCount: 10).visibleCount, 3)
    }

    // 会话数超过可容纳行数时，按 stride 截断（覆盖 sessionCount > maxRows）。
    func testVisibleCountCapsAtMaxRows() {
        // usable 756，Int(756/100)=7 行，12 个会话只显 7 个
        XCTAssertEqual(standbySessionBoardLayout(boardHeight: 800, sessionCount: 12).visibleCount, 7)
    }

    // 极小高度也至少显示 1 条。
    func testAtLeastOneRow() {
        XCTAssertEqual(standbySessionBoardLayout(boardHeight: 30, sessionCount: 6).visibleCount, 1)
    }
}
