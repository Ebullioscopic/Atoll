import XCTest
@testable import CodeIslandCore

final class JSONLTailerTests: XCTestCase {

    // MARK: - scanLines (pure)

    func testScanLinesEmptyInputProducesEmptyDeltaAndFragment() {
        let result = JSONLTailer.scanLines(Data())
        XCTAssertTrue(result.delta.isEmpty)
        XCTAssertEqual(result.trailingFragment, Data())
    }

    func testScanLinesExtractsAssistantTextFromSingleLine() {
        let line = assistantLine(text: "hello world") + "\n"
        let result = JSONLTailer.scanLines(Data(line.utf8))
        XCTAssertEqual(result.delta.lastAssistantMessage, "hello world")
        XCTAssertNil(result.delta.lastUserPrompt)
        XCTAssertEqual(result.trailingFragment, Data())
    }

    func testScanLinesExtractsUserPromptFromSingleLine() {
        let line = userLine(text: "what's the weather?") + "\n"
        let result = JSONLTailer.scanLines(Data(line.utf8))
        XCTAssertEqual(result.delta.lastUserPrompt, "what's the weather?")
        XCTAssertNil(result.delta.lastAssistantMessage)
    }

    func testScanLinesLatestLineWinsForEachRole() {
        let bytes = Data(([
            assistantLine(text: "first reply"),
            userLine(text: "first question"),
            assistantLine(text: "second reply"),
            userLine(text: "second question"),
        ].joined(separator: "\n") + "\n").utf8)

        let result = JSONLTailer.scanLines(bytes)
        XCTAssertEqual(result.delta.lastAssistantMessage, "second reply")
        XCTAssertEqual(result.delta.lastUserPrompt, "second question")
    }

    func testScanLinesTrailingPartialLineReturnsAsFragment() {
        let completeLine = assistantLine(text: "done") + "\n"
        let partial = "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"half"
        let combined = Data((completeLine + partial).utf8)

        let result = JSONLTailer.scanLines(combined)
        XCTAssertEqual(result.delta.lastAssistantMessage, "done")
        XCTAssertEqual(result.trailingFragment, Data(partial.utf8))
    }

    func testScanLinesIgnoresIsMetaLines() {
        let meta = """
        {"type":"assistant","isMeta":true,"message":{"content":[{"type":"text","text":"boot"}]}}
        """
        let real = assistantLine(text: "real reply")
        let combined = Data((meta + "\n" + real + "\n").utf8)

        let result = JSONLTailer.scanLines(combined)
        XCTAssertEqual(result.delta.lastAssistantMessage, "real reply")
    }

    func testScanLinesIgnoresUnknownType() {
        let line = """
        {"type":"tool_use","message":{"content":[{"type":"text","text":"internal"}]}}
        """
        let result = JSONLTailer.scanLines(Data((line + "\n").utf8))
        XCTAssertTrue(result.delta.isEmpty)
    }

    func testScanLinesExtractsAntigravityUserInputWithTags() {
        let line = """
        {"type":"USER_INPUT","content":"<USER_REQUEST>\\nhello world\\n</USER_REQUEST>"}
        """
        let result = JSONLTailer.scanLines(Data((line + "\n").utf8))
        XCTAssertEqual(result.delta.lastUserPrompt, "hello world")
        XCTAssertNil(result.delta.lastAssistantMessage)
    }

    func testScanLinesExtractsAntigravityUserInputWithoutTags() {
        let line = """
        {"type":"USER_INPUT","content":"hello world"}
        """
        let result = JSONLTailer.scanLines(Data((line + "\n").utf8))
        XCTAssertEqual(result.delta.lastUserPrompt, "hello world")
        XCTAssertNil(result.delta.lastAssistantMessage)
    }

    func testScanLinesExtractsAntigravityPlannerResponseWithContent() {
        let line = """
        {"type":"PLANNER_RESPONSE","content":"answer content","thinking":"thought process"}
        """
        let result = JSONLTailer.scanLines(Data((line + "\n").utf8))
        XCTAssertEqual(result.delta.lastAssistantMessage, "answer content")
        XCTAssertNil(result.delta.lastUserPrompt)
    }

    func testScanLinesExtractsAntigravityPlannerResponseWithOnlyThinking() {
        let line = """
        {"type":"PLANNER_RESPONSE","thinking":"thought process"}
        """
        let result = JSONLTailer.scanLines(Data((line + "\n").utf8))
        XCTAssertEqual(result.delta.lastAssistantMessage, "thought process")
        XCTAssertNil(result.delta.lastUserPrompt)
    }

    func testScanLinesExtractsCodexTaskStartedAsProcessing() {
        let line = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1"}}"#
        let result = JSONLTailer.scanLines(Data((line + "\n").utf8))

        XCTAssertEqual(result.delta.turnStatus, .processing)
        XCTAssertFalse(result.delta.isEmpty)
    }

    func testScanLinesExtractsCodexTerminalTurnEventsAsIdle() {
        let lines = [
            #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}"#,
            #"{"type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#,
            #"{"type":"event_msg","payload":{"type":"turn_failed","reason":"tool_error"}}"#
        ].joined(separator: "\n")
        let result = JSONLTailer.scanLines(Data((lines + "\n").utf8))

        XCTAssertEqual(result.delta.turnStatus, .idle)
        XCTAssertFalse(result.delta.isEmpty)
    }

    func testLatestTurnStatusUsesMostRecentCodexTurnEvent() {
        let lines = [
            #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"turn-2"}}"#
        ].joined(separator: "\n")

        XCTAssertEqual(JSONLTailer.latestTurnStatus(in: Data((lines + "\n").utf8)), .processing)
    }

    func testScanLinesTreatsCodexEventMessagesAsActivity() {
        let line = #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{}}}}"#
        let result = JSONLTailer.scanLines(Data((line + "\n").utf8))

        XCTAssertTrue(result.delta.hasActivity)
        XCTAssertFalse(result.delta.isEmpty)
    }

    // MARK: - extractText

    func testExtractTextFromPlainString() {
        XCTAssertEqual(JSONLTailer.extractText(from: "hi"), "hi")
        XCTAssertEqual(JSONLTailer.extractText(from: "  hi  "), "hi")
        XCTAssertNil(JSONLTailer.extractText(from: ""))
        XCTAssertNil(JSONLTailer.extractText(from: "   "))
    }

    func testExtractTextFromMixedBlocks() {
        let blocks: [[String: Any]] = [
            ["type": "text", "text": "part one"],
            ["type": "tool_use", "name": "Bash", "input": ["command": "ls"]],
            ["type": "text", "text": "part two"]
        ]
        XCTAssertEqual(JSONLTailer.extractText(from: blocks), "part one\npart two")
    }

    func testExtractTextFromEmptyArrayReturnsNil() {
        XCTAssertNil(JSONLTailer.extractText(from: [[String: Any]]()))
    }

    func testExtractTextFromUnknownShapeReturnsNil() {
        XCTAssertNil(JSONLTailer.extractText(from: 42))
        XCTAssertNil(JSONLTailer.extractText(from: nil))
    }

    // MARK: - Integration: tail a real file

    func testAttachAndDetectAppendedLine() throws {
        let url = temporaryFileURL()
        try Data("".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let expectation = self.expectation(description: "delta delivered")
        let captured = LockedValue<ConversationTailDelta?>(nil)

        let tailer = JSONLTailer(
            queue: DispatchQueue(label: "tailer-test"),
            onDelta: { delta in
                captured.set(delta)
                expectation.fulfill()
            }
        )
        tailer.attach(sessionId: "s1", filePath: url.path)

        // Let the DispatchSource attach before appending.
        Thread.sleep(forTimeInterval: 0.15)

        let line = assistantLine(text: "ping") + "\n"
        try appendToFile(url: url, content: line)

        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(captured.value?.sessionId, "s1")
        XCTAssertEqual(captured.value?.lastAssistantMessage, "ping")

        tailer.detach(sessionId: "s1")
    }

    func testAttachIgnoresPreexistingContentByDefault() throws {
        let url = temporaryFileURL()
        let pre = assistantLine(text: "already written") + "\n"
        try Data(pre.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let receivedDelta = self.expectation(description: "delta fires for new append only")

        let tailer = JSONLTailer(
            queue: DispatchQueue(label: "tailer-test"),
            onDelta: { delta in
                XCTAssertEqual(delta.lastAssistantMessage, "fresh")
                receivedDelta.fulfill()
            }
        )
        tailer.attach(sessionId: "s1", filePath: url.path)
        Thread.sleep(forTimeInterval: 0.15)
        try appendToFile(url: url, content: assistantLine(text: "fresh") + "\n")

        wait(for: [receivedDelta], timeout: 2)
        tailer.detach(sessionId: "s1")
    }

    func testDetachStopsFurtherCallbacks() throws {
        let url = temporaryFileURL()
        try Data("".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let callCount = LockedValue(0)
        let tailer = JSONLTailer(
            queue: DispatchQueue(label: "tailer-test"),
            onDelta: { _ in callCount.update { $0 += 1 } }
        )
        tailer.attach(sessionId: "s1", filePath: url.path)
        Thread.sleep(forTimeInterval: 0.15)

        try appendToFile(url: url, content: assistantLine(text: "first") + "\n")
        // Give the dispatch source a moment to deliver.
        Thread.sleep(forTimeInterval: 0.2)

        tailer.detach(sessionId: "s1")
        // Allow detach to flush.
        Thread.sleep(forTimeInterval: 0.15)

        try appendToFile(url: url, content: assistantLine(text: "ignored") + "\n")
        Thread.sleep(forTimeInterval: 0.2)

        XCTAssertEqual(callCount.value, 1)
    }

    // MARK: - Fixtures

    private func assistantLine(text: String) -> String {
        let payload: [String: Any] = [
            "type": "assistant",
            "message": [
                "content": [
                    ["type": "text", "text": text]
                ]
            ]
        ]
        return jsonString(payload)
    }

    private func userLine(text: String) -> String {
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "content": text
            ]
        ]
        return jsonString(payload)
    }

    private func jsonString(_ obj: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8)!
    }

    private func temporaryFileURL() -> URL {
        let name = "jsonl-tailer-\(UUID().uuidString).jsonl"
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    }

    private func appendToFile(url: URL, content: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(content.utf8))
        try handle.close()
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        self.storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func update(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}
