import XCTest
@testable import CodeIsland
@testable import CodeIslandCore

/// Cursor's AskQuestion tool has no hook channel (#265): the question is asked
/// and answered inside Cursor's own UI while hooks go silent, historically
/// leaving the card stuck on "thinking". These tests cover the display-only
/// wait derived from the transcript tail: flip to `.waitingQuestion` with the
/// question text while the trailing entry is an unanswered question, and resume
/// the normal status flow as soon as anything newer arrives.
@MainActor
final class AppStateCursorQuestionTests: XCTestCase {

    private let mainId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
    private let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"

    private func mainTranscriptPath(for id: String) -> String {
        "/Users/u/.cursor/projects/x/agent-transcripts/\(id)/\(id).jsonl"
    }

    private func cursorSession(
        status: AgentStatus = .processing,
        source: String = "cursor",
        transcriptPath: String?
    ) -> SessionSnapshot {
        var session = SessionSnapshot()
        session.source = source
        session.status = status
        session.transcriptPath = transcriptPath
        return session
    }

    // MARK: - applyCursorQuestionSignal (pure transition)

    func testPendingFlipsProcessingMainAgentSessionToWaitingQuestion() {
        let path = mainTranscriptPath(for: mainId)
        var session = cursorSession(status: .processing, transcriptPath: path)
        session.currentTool = "Shell"
        session.toolDescription = "npm test"

        let result = AppState.applyCursorQuestionSignal(
            .pending(prompt: "Which DB?"),
            to: &session,
            sessionId: mainId,
            transcriptPath: path
        )

        XCTAssertEqual(result, .markedWaiting(fresh: true))
        XCTAssertEqual(session.status, .waitingQuestion)
        XCTAssertEqual(session.cursorPendingQuestion, "Which DB?")
        XCTAssertNil(session.currentTool)
        XCTAssertNil(session.toolDescription)
    }

    func testPendingAlsoFlipsRunningAndIdleSessions() {
        let path = mainTranscriptPath(for: mainId)
        for status in [AgentStatus.running, .idle] {
            var session = cursorSession(status: status, transcriptPath: path)
            let result = AppState.applyCursorQuestionSignal(
                .pending(prompt: "Q"),
                to: &session,
                sessionId: mainId,
                transcriptPath: path
            )
            XCTAssertEqual(result, .markedWaiting(fresh: true), "status \(status)")
            XCTAssertEqual(session.status, .waitingQuestion, "status \(status)")
        }
    }

    func testPendingIsIgnoredForSubagentTranscript() {
        // Task/subagent card: session id differs from the transcript's parent
        // directory — the new logic must never touch folded/child sessions (#262).
        let parentPath = mainTranscriptPath(for: mainId)
        var session = cursorSession(status: .processing, transcriptPath: parentPath)

        let result = AppState.applyCursorQuestionSignal(
            .pending(prompt: "Q"),
            to: &session,
            sessionId: childId,
            transcriptPath: parentPath
        )

        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(session.status, .processing)
        XCTAssertNil(session.cursorPendingQuestion)
    }

    func testPendingIsIgnoredForNonCursorSources() {
        let path = mainTranscriptPath(for: mainId)
        var session = cursorSession(status: .processing, source: "claude", transcriptPath: path)

        let result = AppState.applyCursorQuestionSignal(
            .pending(prompt: "Q"),
            to: &session,
            sessionId: mainId,
            transcriptPath: path
        )

        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(session.status, .processing)
    }

    func testPendingDoesNotStompWaitingApproval() {
        let path = mainTranscriptPath(for: mainId)
        var session = cursorSession(status: .waitingApproval, transcriptPath: path)

        let result = AppState.applyCursorQuestionSignal(
            .pending(prompt: "Q"),
            to: &session,
            sessionId: mainId,
            transcriptPath: path
        )

        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(session.status, .waitingApproval)
    }

    func testRepeatedPendingRefreshesPromptWithoutFreshFlag() {
        let path = mainTranscriptPath(for: mainId)
        var session = cursorSession(status: .processing, transcriptPath: path)

        XCTAssertEqual(
            AppState.applyCursorQuestionSignal(
                .pending(prompt: "First?"), to: &session, sessionId: mainId, transcriptPath: path),
            .markedWaiting(fresh: true)
        )
        XCTAssertEqual(
            AppState.applyCursorQuestionSignal(
                .pending(prompt: "Second?"), to: &session, sessionId: mainId, transcriptPath: path),
            .markedWaiting(fresh: false)
        )
        XCTAssertEqual(session.cursorPendingQuestion, "Second?")
    }

    func testClearedResumesProcessingAndDropsQuestion() {
        let path = mainTranscriptPath(for: mainId)
        var session = cursorSession(status: .waitingQuestion, transcriptPath: path)
        session.cursorPendingQuestion = "Which DB?"

        let result = AppState.applyCursorQuestionSignal(
            .cleared,
            to: &session,
            sessionId: mainId,
            transcriptPath: path
        )

        XCTAssertEqual(result, .clearedWaiting)
        XCTAssertEqual(session.status, .processing)
        XCTAssertNil(session.cursorPendingQuestion)
    }

    func testClearedDoesNotDisturbSessionsWithoutPendingQuestion() {
        let path = mainTranscriptPath(for: mainId)
        var session = cursorSession(status: .idle, transcriptPath: path)

        let result = AppState.applyCursorQuestionSignal(
            .cleared,
            to: &session,
            sessionId: mainId,
            transcriptPath: path
        )

        XCTAssertEqual(result, .ignored)
        XCTAssertEqual(session.status, .idle)
    }

    func testClearedAfterHookAlreadyWentIdleOnlyDropsQuestionText() {
        // Race: afterAgentResponse (idle) can land before the transcript's final
        // line produces the cleared delta — the delta must not revive the session.
        let path = mainTranscriptPath(for: mainId)
        var session = cursorSession(status: .idle, transcriptPath: path)
        session.cursorPendingQuestion = "Which DB?"

        let result = AppState.applyCursorQuestionSignal(
            .cleared,
            to: &session,
            sessionId: mainId,
            transcriptPath: path
        )

        XCTAssertEqual(result, .clearedWaiting)
        XCTAssertEqual(session.status, .idle)
        XCTAssertNil(session.cursorPendingQuestion)
    }

    // MARK: - applyTranscriptDelta wiring

    func testTranscriptDeltaPendingMarksSessionWaiting() {
        let path = mainTranscriptPath(for: mainId)
        let appState = AppState()
        appState.sessions[mainId] = cursorSession(status: .processing, transcriptPath: path)
        appState.attachedTranscriptPaths[mainId] = path

        appState.applyTranscriptDelta(ConversationTailDelta(
            sessionId: mainId,
            lastUserPrompt: nil,
            lastAssistantMessage: "Need one detail before continuing.",
            cursorQuestion: .pending(prompt: "Which DB?")
        ))

        XCTAssertEqual(appState.sessions[mainId]?.status, .waitingQuestion)
        XCTAssertEqual(appState.sessions[mainId]?.cursorPendingQuestion, "Which DB?")
        XCTAssertEqual(appState.sessions[mainId]?.lastAssistantMessage, "Need one detail before continuing.")
    }

    func testTranscriptDeltaClearedResumesSession() {
        let path = mainTranscriptPath(for: mainId)
        let appState = AppState()
        var session = cursorSession(status: .waitingQuestion, transcriptPath: path)
        session.cursorPendingQuestion = "Which DB?"
        appState.sessions[mainId] = session
        appState.attachedTranscriptPaths[mainId] = path

        appState.applyTranscriptDelta(ConversationTailDelta(
            sessionId: mainId,
            lastUserPrompt: "PostgreSQL",
            lastAssistantMessage: nil,
            cursorQuestion: .cleared
        ))

        XCTAssertEqual(appState.sessions[mainId]?.status, .processing)
        XCTAssertNil(appState.sessions[mainId]?.cursorPendingQuestion)
        XCTAssertEqual(appState.sessions[mainId]?.lastUserPrompt, "PostgreSQL")
    }

    // MARK: - Hook activity resumes the display wait

    func testHookActivityAfterDisplayWaitResumesProcessing() throws {
        // The user answered in Cursor and the agent moved on to a tool call: the
        // wasWaiting blanket drain must lift the display-only wait (no queue
        // items exist for it) instead of leaving the card stuck.
        let path = mainTranscriptPath(for: mainId)
        let appState = AppState()
        var session = cursorSession(status: .waitingQuestion, transcriptPath: path)
        session.cursorPendingQuestion = "Which DB?"
        session.cwd = "/tmp/cursor-question-test"
        appState.sessions[mainId] = session

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "beforeShellExecution",
            "session_id": mainId,
            "_source": "cursor",
            "command": "npm test",
        ])
        appState.handleEvent(try XCTUnwrap(HookEvent(from: data)))

        XCTAssertNotEqual(appState.sessions[mainId]?.status, .waitingQuestion)
    }

    // MARK: - Attach-time backfill

    func testAttachBackfillDetectsTrailingQuestionInFreshTranscript() throws {
        let root = NSTemporaryDirectory() + "cursor-question-backfill-" + UUID().uuidString
        let dir = root + "/agent-transcripts/\(mainId)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let path = dir + "/\(mainId).jsonl"
        let lines = [
            #"{"role":"user","message":{"content":[{"type":"text","text":"set up the db"}]}}"#,
            #"{"role":"assistant","message":{"content":[{"type":"text","text":"One question."},{"type":"tool_use","name":"AskQuestion","input":{"title":"Clarifying Questions","questions":[{"id":"db","prompt":"Which database should we target?"}]}}]}}"#,
        ]
        try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)

        let appState = AppState()
        appState.sessions[mainId] = cursorSession(status: .processing, transcriptPath: path)
        appState.attachTranscriptTailerIfNeeded(sessionId: mainId)

        XCTAssertEqual(appState.sessions[mainId]?.status, .waitingQuestion)
        XCTAssertEqual(
            appState.sessions[mainId]?.cursorPendingQuestion,
            "Which database should we target?"
        )

        appState.detachTranscriptTailer(sessionId: mainId)
    }

    func testAttachBackfillLeavesAnsweredTranscriptAlone() throws {
        let root = NSTemporaryDirectory() + "cursor-question-backfill-" + UUID().uuidString
        let dir = root + "/agent-transcripts/\(mainId)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let path = dir + "/\(mainId).jsonl"
        let lines = [
            #"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"AskQuestion","input":{"questions":[{"id":"db","prompt":"Which DB?"}]}}]}}"#,
            #"{"role":"user","message":{"content":[{"type":"text","text":"PostgreSQL"}]}}"#,
            #"{"role":"assistant","message":{"content":[{"type":"text","text":"Using PostgreSQL."}]}}"#,
        ]
        try (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)

        let appState = AppState()
        appState.sessions[mainId] = cursorSession(status: .processing, transcriptPath: path)
        appState.attachTranscriptTailerIfNeeded(sessionId: mainId)

        XCTAssertEqual(appState.sessions[mainId]?.status, .processing)
        XCTAssertNil(appState.sessions[mainId]?.cursorPendingQuestion)

        appState.detachTranscriptTailer(sessionId: mainId)
    }
}
