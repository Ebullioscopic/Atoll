import XCTest
@testable import CodeIsland

final class KimiTranscriptTests: XCTestCase {
    func testReadsKimiCodeWireProtocol() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let path = dir.appendingPathComponent("wire.jsonl").path
        let lines = [
            #"{"type":"turn.prompt","input":[{"type":"text","text":"First question"}],"origin":{"kind":"user"}}"#,
            #"{"type":"context.append_loop_event","event":{"type":"content.part","part":{"type":"think","think":"ignore"}}}"#,
            #"{"type":"context.append_loop_event","event":{"type":"content.part","part":{"type":"text","text":"First answer"}}}"#,
            #"{"type":"turn.prompt","input":[{"type":"text","text":"Second question"}],"origin":{"kind":"user"}}"#,
            #"{"type":"context.append_loop_event","event":{"type":"content.part","part":{"type":"text","text":"Second "}}}"#,
            #"{"type":"context.append_loop_event","event":{"type":"content.part","part":{"type":"text","text":"answer"}}}"#,
        ]
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)

        let messages = AppState.readRecentFromKimiTranscript(path: path).1
        // Reader keeps only the last 3 chat rows.
        XCTAssertEqual(messages.map(\.isUser), [false, true, false])
        XCTAssertEqual(messages.map(\.text), [
            "First answer",
            "Second question",
            "Second answer",
        ])
    }

    func testReadsLegacyKimiCliWireProtocol() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let path = dir.appendingPathComponent("wire.jsonl").path
        let lines = [
            #"{"message":{"type":"TurnBegin","payload":{"user_input":[{"type":"text","text":"Legacy hi"}]}}}"#,
            #"{"message":{"type":"ContentPart","payload":{"type":"text","text":"Legacy bye"}}}"#,
            #"{"message":{"type":"TurnEnd"}}"#,
        ]
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)

        let messages = AppState.readRecentFromKimiTranscript(path: path).1
        XCTAssertEqual(messages.map(\.text), ["Legacy hi", "Legacy bye"])
        XCTAssertEqual(messages.map(\.isUser), [true, false])
    }
}
