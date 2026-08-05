import XCTest
@testable import CodeIslandCore

/// Cursor transcripts key entries on a top-level `role` (`{"role":"assistant",
/// "message":{"content":[…]}}`) and record the AskQuestion tool as a `tool_use`
/// content block. Because Cursor has no hook for its question tool (#265), the
/// tailer derives a `CursorQuestionSignal` from the trailing transcript entry.
final class JSONLTailerCursorQuestionTests: XCTestCase {

    // MARK: - Line builders (role is always the first key, matching Cursor's writer)

    private func cursorUserLine(text: String) -> String {
        #"{"role":"user","message":{"content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    private func cursorAssistantTextLine(text: String) -> String {
        #"{"role":"assistant","message":{"content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    /// Assistant entry whose content ends in a question tool_use. `inputJSON` is
    /// raw JSON for the tool input object.
    private func cursorQuestionLine(
        toolName: String = "AskQuestion",
        inputJSON: String,
        leadingText: String? = nil
    ) -> String {
        var blocks: [String] = []
        if let leadingText {
            blocks.append(#"{"type":"text","text":"\#(leadingText)"}"#)
        }
        blocks.append(#"{"type":"tool_use","name":"\#(toolName)","input":\#(inputJSON)}"#)
        return #"{"role":"assistant","message":{"content":[\#(blocks.joined(separator: ","))]}}"#
    }

    private func scan(_ lines: [String]) -> JSONLTailer.ScanResult {
        JSONLTailer.scanLines(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    // MARK: - Role-keyed lines produce only question signals

    func testCursorUserLineClearsQuestionWithoutDuplicatingChatText() {
        // Chat text stays hook-sourced (beforeSubmitPrompt) — the transcript copy
        // is wrapped in <user_query> tags and would dedup-miss into a second row.
        let result = scan([cursorUserLine(text: "fix the bug")])
        XCTAssertNil(result.delta.lastUserPrompt)
        XCTAssertNil(result.delta.lastAssistantMessage)
        XCTAssertEqual(result.delta.cursorQuestion, .cleared)
    }

    func testCursorAssistantTextLineClearsQuestionWithoutDuplicatingChatText() {
        let result = scan([cursorAssistantTextLine(text: "done, deployed")])
        XCTAssertNil(result.delta.lastAssistantMessage)
        XCTAssertEqual(result.delta.cursorQuestion, .cleared)
    }

    // MARK: - Pending question detection

    func testAskQuestionToolUseMarksPending() {
        let input = #"{"title":"Clarifying Questions","questions":[{"id":"db","prompt":"Which database should we target?","options":[{"id":"pg","label":"PostgreSQL"}],"allow_multiple":false}]}"#
        let result = scan([cursorQuestionLine(inputJSON: input, leadingText: "I need one detail.")])

        XCTAssertEqual(result.delta.cursorQuestion, .pending(prompt: "Which database should we target?"))
        XCTAssertNil(result.delta.lastAssistantMessage)
    }

    func testAskQuestionMultiplePromptsGetNumericSuffix() {
        let input = #"{"title":"Clarifying Questions","questions":[{"id":"a","prompt":"Which DB?"},{"id":"b","prompt":"Which tests?"},{"id":"c","prompt":"Which CI?"}]}"#
        let result = scan([cursorQuestionLine(inputJSON: input)])

        XCTAssertEqual(result.delta.cursorQuestion, .pending(prompt: "Which DB? (+2)"))
    }

    func testAskQuestionFallsBackToTitleWhenPromptsMissing() {
        let input = #"{"title":"Pick a rollout strategy","questions":[]}"#
        let result = scan([cursorQuestionLine(inputJSON: input)])

        XCTAssertEqual(result.delta.cursorQuestion, .pending(prompt: "Pick a rollout strategy"))
    }

    func testAskQuestionWithUnparseableArgsStillSignalsPendingWithEmptyPrompt() {
        let result = scan([cursorQuestionLine(inputJSON: #"{"unexpected":"shape"}"#)])
        XCTAssertEqual(result.delta.cursorQuestion, .pending(prompt: ""))
    }

    func testAskQuestionAcceptsFlatQuestionField() {
        // Forward-compatible flat shape some harnesses use.
        let result = scan([cursorQuestionLine(inputJSON: #"{"question":"Deploy to staging first?"}"#)])
        XCTAssertEqual(result.delta.cursorQuestion, .pending(prompt: "Deploy to staging first?"))
    }

    func testQuestionToolNameMatchingIsSeparatorAndCaseInsensitive() {
        XCTAssertTrue(JSONLTailer.isCursorQuestionToolName("AskQuestion"))
        XCTAssertTrue(JSONLTailer.isCursorQuestionToolName("ask_question"))
        XCTAssertTrue(JSONLTailer.isCursorQuestionToolName("askQuestion"))
        XCTAssertTrue(JSONLTailer.isCursorQuestionToolName("AskUserQuestion"))
        XCTAssertTrue(JSONLTailer.isCursorQuestionToolName("ask-followup-question"))
        XCTAssertFalse(JSONLTailer.isCursorQuestionToolName("Shell"))
        XCTAssertFalse(JSONLTailer.isCursorQuestionToolName("QuestionnaireImport"))
        XCTAssertFalse(JSONLTailer.isCursorQuestionToolName(""))
    }

    // MARK: - run_async questions do not block

    func testRunAsyncSnakeCaseQuestionIsNotPending() {
        let input = #"{"title":"Optional","questions":[{"id":"a","prompt":"Any preference?"}],"run_async":true}"#
        let result = scan([cursorQuestionLine(inputJSON: input)])
        XCTAssertEqual(result.delta.cursorQuestion, .cleared)
    }

    func testRunAsyncCamelCaseQuestionIsNotPending() {
        let input = #"{"title":"Optional","questions":[{"id":"a","prompt":"Any preference?"}],"runAsync":true}"#
        let result = scan([cursorQuestionLine(inputJSON: input)])
        XCTAssertEqual(result.delta.cursorQuestion, .cleared)
    }

    // MARK: - Last entry wins (answered questions never linger)

    func testQuestionFollowedByUserEntryClears() {
        let question = cursorQuestionLine(inputJSON: #"{"questions":[{"id":"a","prompt":"Which DB?"}]}"#)
        let result = scan([question, cursorUserLine(text: "PostgreSQL please")])
        XCTAssertEqual(result.delta.cursorQuestion, .cleared)
    }

    func testQuestionFollowedByAssistantEntryClears() {
        let question = cursorQuestionLine(inputJSON: #"{"questions":[{"id":"a","prompt":"Which DB?"}]}"#)
        let result = scan([question, cursorAssistantTextLine(text: "Great, using PostgreSQL.")])
        XCTAssertEqual(result.delta.cursorQuestion, .cleared)
    }

    func testAnsweredQuestionMidTranscriptDoesNotResurface() {
        let lines = [
            cursorUserLine(text: "set up the db layer"),
            cursorQuestionLine(inputJSON: #"{"questions":[{"id":"a","prompt":"Which DB?"}]}"#),
            cursorUserLine(text: "PostgreSQL"),
            cursorAssistantTextLine(text: "Done."),
        ]
        XCTAssertEqual(scan(lines).delta.cursorQuestion, .cleared)
        XCTAssertEqual(JSONLTailer.latestCursorQuestion(in: Data((lines.joined(separator: "\n") + "\n").utf8)), .cleared)
    }

    func testLatestCursorQuestionPendingWhenQuestionIsTrailingEntry() {
        let lines = [
            cursorUserLine(text: "set up the db layer"),
            cursorAssistantTextLine(text: "Looking at the schema."),
            cursorQuestionLine(inputJSON: #"{"questions":[{"id":"a","prompt":"Which DB?"}]}"#),
        ]
        XCTAssertEqual(
            JSONLTailer.latestCursorQuestion(in: Data((lines.joined(separator: "\n") + "\n").utf8)),
            .pending(prompt: "Which DB?")
        )
    }

    func testLatestCursorQuestionNilForNonCursorTranscript() {
        let claude = #"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}"#
        XCTAssertNil(JSONLTailer.latestCursorQuestion(in: Data((claude + "\n").utf8)))
    }

    // MARK: - Scoping: type-keyed formats never produce cursor signals

    func testClaudeStyleAskUserQuestionToolUseProducesNoCursorSignal() {
        // Claude's own question tool is handled by the hook flow — the transcript
        // tail must not double-report it.
        let line = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Pick one"}]}}]}}"#
        let result = scan([line])
        XCTAssertNil(result.delta.cursorQuestion)
    }

    func testCodeBuddyStyleRoleWithTypeKeyProducesNoCursorSignal() {
        let line = #"{"type":"message","role":"assistant","content":[{"type":"text","text":"hello"}]}"#
        let result = scan([line])
        XCTAssertNil(result.delta.cursorQuestion)
    }

    // MARK: - Probe routing

    func testQuickTypeProbeClassifiesCursorRoleLines() {
        XCTAssertEqual(
            JSONLTailer.quickTypeProbe(lineBytes: Data(cursorUserLine(text: "hi").utf8)),
            .cursorRole
        )
        XCTAssertEqual(
            JSONLTailer.quickTypeProbe(lineBytes: Data(cursorAssistantTextLine(text: "hi").utf8)),
            .cursorRole
        )
    }

    func testQuickTypeProbeStillClassifiesClaudeLines() {
        let claude = #"{"type":"assistant","message":{"role":"assistant","content":[]}}"#
        XCTAssertEqual(JSONLTailer.quickTypeProbe(lineBytes: Data(claude.utf8)), .assistant)
    }

    func testQuickTypeProbeIgnoresNestedRoleInNonLeadingPosition() {
        // Codex rollout `response_item` lines carry a nested role — they must stay
        // on the fast irrelevant path (the cursor writer always emits `role` as
        // the first key, so a strict prefix check is safe and cheap).
        let codex = #"{"type":"response_item","payload":{"type":"message","role":"assistant","content":[]}}"#
        XCTAssertEqual(JSONLTailer.quickTypeProbe(lineBytes: Data(codex.utf8)), .irrelevant)
    }

    // MARK: - Fragments

    func testTrailingPartialCursorQuestionLineStaysBuffered() {
        let complete = cursorAssistantTextLine(text: "checking") + "\n"
        let partial = #"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"AskQuestion","#
        let result = JSONLTailer.scanLines(Data((complete + partial).utf8))

        XCTAssertEqual(result.delta.cursorQuestion, .cleared)
        XCTAssertEqual(result.trailingFragment, Data(partial.utf8))
    }

    func testDeltaIsEmptyAccountsForCursorQuestion() {
        var delta = JSONLTailer.ScanResult.Delta()
        XCTAssertTrue(delta.isEmpty)
        delta.cursorQuestion = .cleared
        XCTAssertFalse(delta.isEmpty)
    }
}
