import XCTest
@testable import CodeIsland

final class ESP32BridgeManagerQueueTests: XCTestCase {
    func testWriteQueueDropsOldAuxiliaryFramesBeforePrimaryFrames() {
        var queue = BuddyWriteQueue(capacity: 3)

        XCTAssertEqual(queue.append(Data([0xFB, 0]), priority: .auxiliary), 0)
        XCTAssertEqual(queue.append(Data([0xFB, 1]), priority: .auxiliary), 0)
        XCTAssertEqual(queue.append(Data([0x01]), priority: .primary), 0)
        XCTAssertEqual(queue.append(Data([0x02]), priority: .primary), 1)

        XCTAssertEqual(queue.contents.map(\.data), [
            Data([0xFB, 1]),
            Data([0x01]),
            Data([0x02]),
        ])
    }

    func testWriteQueueDropsNewAuxiliaryFrameWhenExistingFramesAreMoreImportant() {
        var queue = BuddyWriteQueue(capacity: 3)

        XCTAssertEqual(queue.append(Data([0x01]), priority: .primary), 0)
        XCTAssertEqual(queue.append(Data([0x02]), priority: .primary), 0)
        XCTAssertEqual(queue.append(Data([0xF7, 1]), priority: .control), 0)
        XCTAssertEqual(queue.append(Data([0xFB, 0]), priority: .auxiliary), 1)

        XCTAssertEqual(queue.contents.map(\.data), [
            Data([0x01]),
            Data([0x02]),
            Data([0xF7, 1]),
        ])
    }

    func testWriteQueuePreservesSendOrderForRetainedFrames() {
        var queue = BuddyWriteQueue(capacity: 3)

        _ = queue.append(Data([0xFB, 0]), priority: .auxiliary)
        _ = queue.append(Data([0x01]), priority: .primary)
        _ = queue.append(Data([0xFD, 1]), priority: .control)

        XCTAssertEqual(queue.popFirst()?.data, Data([0xFB, 0]))
        XCTAssertEqual(queue.popFirst()?.data, Data([0x01]))
        XCTAssertEqual(queue.popFirst()?.data, Data([0xFD, 1]))
        XCTAssertNil(queue.popFirst())
    }
}
