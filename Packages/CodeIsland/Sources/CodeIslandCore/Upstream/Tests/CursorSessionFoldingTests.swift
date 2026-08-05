import XCTest
@testable import CodeIslandCore

final class CursorSessionFoldingTests: XCTestCase {

    func testParentIdFromParentTranscriptPath() {
        let path = "/Users/u/.cursor/projects/Users-u-Code-Reelay/agent-transcripts/e1247fd5-d9a0-48ef-8457-0304606b1833/e1247fd5-d9a0-48ef-8457-0304606b1833.jsonl"
        XCTAssertEqual(
            CursorSessionFolding.parentConversationId(fromTranscriptPath: path),
            "e1247fd5-d9a0-48ef-8457-0304606b1833"
        )
    }

    func testParentIdFromSubagentsTranscriptPath() {
        let path = "/Users/u/.cursor/projects/Users-u-Code-Reelay/agent-transcripts/e1247fd5-d9a0-48ef-8457-0304606b1833/subagents/2528cb91-6379-48f2-aff8-40f4b804dafa.jsonl"
        XCTAssertEqual(
            CursorSessionFolding.parentConversationId(fromTranscriptPath: path),
            "e1247fd5-d9a0-48ef-8457-0304606b1833"
        )
    }

    func testFoldTargetWhenChildSessionDiffersFromTranscriptParent() {
        let path = "/Users/u/.cursor/projects/x/agent-transcripts/e1247fd5-d9a0-48ef-8457-0304606b1833/e1247fd5-d9a0-48ef-8457-0304606b1833.jsonl"
        XCTAssertEqual(
            CursorSessionFolding.foldTarget(
                childSessionId: "2528cb91-6379-48f2-aff8-40f4b804dafa",
                transcriptPath: path
            ),
            "e1247fd5-d9a0-48ef-8457-0304606b1833"
        )
    }

    func testFoldTargetNilWhenSessionMatchesParent() {
        let path = "/Users/u/.cursor/projects/x/agent-transcripts/e1247fd5-d9a0-48ef-8457-0304606b1833/e1247fd5-d9a0-48ef-8457-0304606b1833.jsonl"
        XCTAssertNil(
            CursorSessionFolding.foldTarget(
                childSessionId: "e1247fd5-d9a0-48ef-8457-0304606b1833",
                transcriptPath: path
            )
        )
    }

    func testFoldTargetNilWithoutTranscriptPath() {
        XCTAssertNil(
            CursorSessionFolding.foldTarget(
                childSessionId: "2528cb91-6379-48f2-aff8-40f4b804dafa",
                transcriptPath: nil
            )
        )
    }

    func testRouterLeavesCursorChildWhenModeIsSeparate() {
        let raw: [String: Any] = [
            "_source": "cursor",
            "session_id": "2528cb91-6379-48f2-aff8-40f4b804dafa",
            "transcript_path": "/Users/u/.cursor/projects/x/agent-transcripts/e1247fd5-d9a0-48ef-8457-0304606b1833/e1247fd5-d9a0-48ef-8457-0304606b1833.jsonl",
            "hook_event_name": "beforeReadFile",
        ]
        XCTAssertEqual(CursorSubsessionRouter.decide(raw: raw, mode: "separate"), .leave)
    }

    func testRouterMergesCursorChildWhenModeIsMerge() {
        let raw: [String: Any] = [
            "_source": "cursor",
            "session_id": "2528cb91-6379-48f2-aff8-40f4b804dafa",
            "transcript_path": "/Users/u/.cursor/projects/x/agent-transcripts/e1247fd5-d9a0-48ef-8457-0304606b1833/e1247fd5-d9a0-48ef-8457-0304606b1833.jsonl",
            "hook_event_name": "beforeReadFile",
        ]
        XCTAssertEqual(
            CursorSubsessionRouter.decide(raw: raw, mode: "merge"),
            .merge(
                parentSessionId: "e1247fd5-d9a0-48ef-8457-0304606b1833",
                childSessionId: "2528cb91-6379-48f2-aff8-40f4b804dafa"
            )
        )
    }

    func testRouterHidesCursorChildWhenModeIsHide() {
        let raw: [String: Any] = [
            "_source": "cursor",
            "session_id": "2528cb91-6379-48f2-aff8-40f4b804dafa",
            "transcript_path": "/Users/u/.cursor/projects/x/agent-transcripts/e1247fd5-d9a0-48ef-8457-0304606b1833/e1247fd5-d9a0-48ef-8457-0304606b1833.jsonl",
        ]
        XCTAssertEqual(CursorSubsessionRouter.decide(raw: raw, mode: "hide"), .hide)
    }

    func testRouterLeavesUnrelatedCursorSession() {
        let raw: [String: Any] = [
            "_source": "cursor",
            "session_id": "e1247fd5-d9a0-48ef-8457-0304606b1833",
            "transcript_path": "/Users/u/.cursor/projects/x/agent-transcripts/e1247fd5-d9a0-48ef-8457-0304606b1833/e1247fd5-d9a0-48ef-8457-0304606b1833.jsonl",
        ]
        XCTAssertEqual(CursorSubsessionRouter.decide(raw: raw, mode: "merge"), .leave)
    }

    func testRouterLeavesNonCursorSources() {
        let raw: [String: Any] = [
            "_source": "claude",
            "session_id": "2528cb91-6379-48f2-aff8-40f4b804dafa",
            "transcript_path": "/Users/u/.cursor/projects/x/agent-transcripts/e1247fd5-d9a0-48ef-8457-0304606b1833/e1247fd5-d9a0-48ef-8457-0304606b1833.jsonl",
        ]
        XCTAssertEqual(CursorSubsessionRouter.decide(raw: raw, mode: "merge"), .leave)
    }

    func testApplyMergeRewritesSessionAndSetsAgentId() {
        var raw: [String: Any] = [
            "session_id": "2528cb91-6379-48f2-aff8-40f4b804dafa",
            "hook_event_name": "beforeShellExecution",
        ]
        CursorSubsessionRouter.applyMerge(
            to: &raw,
            parentSessionId: "e1247fd5-d9a0-48ef-8457-0304606b1833",
            childSessionId: "2528cb91-6379-48f2-aff8-40f4b804dafa"
        )
        XCTAssertEqual(raw["session_id"] as? String, "e1247fd5-d9a0-48ef-8457-0304606b1833")
        XCTAssertEqual(raw["agent_id"] as? String, "2528cb91-6379-48f2-aff8-40f4b804dafa")
        XCTAssertEqual(raw["agent_type"] as? String, "cursor-subagent")
        XCTAssertEqual(raw["_cursor_subagent"] as? Bool, true)
        XCTAssertEqual(raw["_cursor_subagent_event"] as? String, "PreToolUse")
    }

    func testMergedCursorSubagentAfterAgentResponseDoesNotCompleteParent() throws {
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.lastUserPrompt = "main prompt"
        parent.lastAssistantMessage = "parent reply"

        var sessions = ["e1247fd5-d9a0-48ef-8457-0304606b1833": parent]
        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "afterAgentResponse",
            "session_id": "e1247fd5-d9a0-48ef-8457-0304606b1833",
            "_source": "cursor",
            "agent_id": "2528cb91-6379-48f2-aff8-40f4b804dafa",
            "agent_type": "cursor-subagent",
            "text": "child-only reply",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)

        XCTAssertEqual(
            sessions["e1247fd5-d9a0-48ef-8457-0304606b1833"]?.lastAssistantMessage,
            "parent reply"
        )
        XCTAssertEqual(sessions["e1247fd5-d9a0-48ef-8457-0304606b1833"]?.status, .running)
        XCTAssertFalse(effects.contains(where: {
            if case .enqueueCompletion = $0 { return true }
            return false
        }))
        XCTAssertEqual(
            sessions["e1247fd5-d9a0-48ef-8457-0304606b1833"]?
                .subagents["2528cb91-6379-48f2-aff8-40f4b804dafa"]?.status,
            .processing
        )
    }

    func testSubagentStopRecordsClosedTombstoneAndClearsOnRestart() throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.subagents[childId] = SubagentState(agentId: childId, agentType: "cursor-subagent")
        var sessions = [parentId: parent]

        let stopData = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "stop",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "agent_type": "cursor-subagent",
        ] as [String: Any])
        let stopEvent = try XCTUnwrap(HookEvent(from: stopData))
        _ = reduceEvent(sessions: &sessions, event: stopEvent, maxHistory: 10)

        XCTAssertNil(sessions[parentId]?.subagents[childId])
        XCTAssertEqual(sessions[parentId]?.closedSubagentIds, [childId])

        let startData = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "SubagentStart",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "agent_type": "cursor-subagent",
        ] as [String: Any])
        let startEvent = try XCTUnwrap(HookEvent(from: startData))
        _ = reduceEvent(sessions: &sessions, event: startEvent, maxHistory: 10)

        XCTAssertNotNil(sessions[parentId]?.subagents[childId])
        XCTAssertTrue(sessions[parentId]?.closedSubagentIds.isEmpty == true)
    }

    func testLateAfterAgentResponseDoesNotClearStopTombstone() throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .processing
        parent.closedSubagentIds = [childId]
        var sessions = [parentId: parent]

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "afterAgentResponse",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "agent_type": "cursor-subagent",
            "text": "late child reply",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)

        XCTAssertNil(sessions[parentId]?.subagents[childId])
        XCTAssertEqual(sessions[parentId]?.closedSubagentIds, [childId])
        XCTAssertEqual(sessions[parentId]?.status, .processing)
    }

    func testSeparateCursorStopSelfTombstonesSessionId() throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"
        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .running
        child.transcriptPath = transcriptPath
        child.cliPid = 12_345
        child.cliStartTime = Date(timeIntervalSince1970: 1_700_000_000)
        var sessions = [childId: child]

        let stopData = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "stop",
            "session_id": childId,
            "_source": "cursor",
        ] as [String: Any])
        let stopEvent = try XCTUnwrap(HookEvent(from: stopData))
        _ = reduceEvent(sessions: &sessions, event: stopEvent, maxHistory: 10)

        XCTAssertEqual(sessions[childId]?.status, .idle)
        XCTAssertEqual(sessions[childId]?.closedSubagentIds, [childId])
        XCTAssertNil(sessions[childId]?.cliPid)
        XCTAssertNil(sessions[childId]?.cliStartTime)
    }

    func testParentCursorStopDoesNotSelfTombstoneOrClearCliPid() throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.transcriptPath = transcriptPath
        parent.cliPid = 98_765
        parent.cliStartTime = Date(timeIntervalSince1970: 1_700_000_000)
        var sessions = [parentId: parent]

        let stopData = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "stop",
            "session_id": parentId,
            "_source": "cursor",
        ] as [String: Any])
        let stopEvent = try XCTUnwrap(HookEvent(from: stopData))
        _ = reduceEvent(sessions: &sessions, event: stopEvent, maxHistory: 10)

        XCTAssertEqual(sessions[parentId]?.status, .idle)
        XCTAssertTrue(sessions[parentId]?.closedSubagentIds.isEmpty == true)
        XCTAssertEqual(sessions[parentId]?.cliPid, 98_765)
        XCTAssertEqual(sessions[parentId]?.cliStartTime, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testParentAfterAgentResponseKeepsActiveWhileFoldedTaskRunning() throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.currentTool = "Agent"
        parent.toolDescription = "cursor-subagent"
        var sub = SubagentState(agentId: childId, agentType: "cursor-subagent")
        sub.status = .running
        parent.subagents[childId] = sub
        var sessions = [parentId: parent]

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "afterAgentResponse",
            "session_id": parentId,
            "_source": "cursor",
            "text": "parent turn done; task still working",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)

        XCTAssertEqual(
            sessions[parentId]?.lastAssistantMessage,
            "parent turn done; task still working"
        )
        XCTAssertEqual(sessions[parentId]?.status, .running)
        XCTAssertEqual(sessions[parentId]?.currentTool, "Agent")
        XCTAssertEqual(sessions[parentId]?.subagents[childId]?.status, .running)
        XCTAssertFalse(effects.contains(where: {
            if case .enqueueCompletion = $0 { return true }
            return false
        }))
    }

    func testUserPromptSubmitClearsCursorSelfTombstone() throws {
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .idle
        child.closedSubagentIds = [childId]
        var sessions = [childId: child]

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "beforeSubmitPrompt",
            "session_id": childId,
            "_source": "cursor",
            "prompt": "retry",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)

        XCTAssertTrue(sessions[childId]?.closedSubagentIds.isEmpty == true)
        XCTAssertEqual(sessions[childId]?.status, .processing)
    }

    func testMergedCursorNotificationWithQuestionSetsWaitingQuestion() throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.subagents[childId] = SubagentState(agentId: childId, agentType: "cursor-subagent")
        var sessions = [parentId: parent]

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Notification",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "agent_type": "cursor-subagent",
            "question": "Which approach should we take?",
            "options": ["A", "B"],
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)

        XCTAssertEqual(sessions[parentId]?.status, .waitingQuestion)
        XCTAssertEqual(sessions[parentId]?.subagents[childId]?.status, .waitingQuestion)
        XCTAssertTrue(effects.contains(where: {
            if case .setActiveSession(let id) = $0 { return id == parentId }
            return false
        }))
    }

    func testParentStopKeepsActiveWhileFoldedTaskRunning() throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.currentTool = "Agent"
        var sub = SubagentState(agentId: childId, agentType: "cursor-subagent")
        sub.status = .running
        parent.subagents[childId] = sub
        var sessions = [parentId: parent]

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "stop",
            "session_id": parentId,
            "_source": "cursor",
            "stop_reason": "user",
            "last_assistant_message": "main turn ended",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))
        let effects = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)

        XCTAssertEqual(sessions[parentId]?.status, .running)
        XCTAssertEqual(sessions[parentId]?.currentTool, "Agent")
        XCTAssertEqual(sessions[parentId]?.subagents[childId]?.status, .running)
        XCTAssertFalse(sessions[parentId]?.interrupted == true)
        XCTAssertFalse(sessions[parentId]?.closedSubagentIds.contains(parentId) == true)
        XCTAssertFalse(effects.contains(where: {
            if case .enqueueCompletion = $0 { return true }
            return false
        }))
    }

    func testMergeFirstTaskHookFillsParentSourceAndTranscript() throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"
        var sessions: [String: SessionSnapshot] = [:]

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "beforeReadFile",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "agent_type": "cursor-subagent",
            "_cursor_subagent": true,
            "transcript_path": transcriptPath,
            "_ppid": 42_424,
            "tool_name": "Read",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)

        XCTAssertEqual(sessions[parentId]?.source, "cursor")
        XCTAssertEqual(sessions[parentId]?.transcriptPath, transcriptPath)
        XCTAssertEqual(sessions[parentId]?.cliPid, 42_424)
        XCTAssertEqual(sessions[parentId]?.subagents[childId]?.currentTool, "Read")
    }

    func testMergeFirstTaskHookDoesNotOverwriteKnownParentSource() throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.cwd = "/tmp/known"
        parent.transcriptPath = "/known.jsonl"
        parent.cliPid = 7
        var sessions = [parentId: parent]

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "beforeReadFile",
            "session_id": parentId,
            "_source": "cursor-cli",
            "agent_id": childId,
            "cwd": "/tmp/child-only",
            "transcript_path": "/child.jsonl",
            "_ppid": 99,
            "tool_name": "Read",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)

        XCTAssertEqual(sessions[parentId]?.source, "cursor")
        XCTAssertEqual(sessions[parentId]?.cwd, "/tmp/known")
        XCTAssertEqual(sessions[parentId]?.transcriptPath, "/known.jsonl")
        XCTAssertEqual(sessions[parentId]?.cliPid, 7)
    }

    func testCursorUserPromptSubmitClearsMergedTombstoneAndReopens() throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .processing
        parent.closedSubagentIds = [childId]
        var sessions = [parentId: parent]

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "beforeSubmitPrompt",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "agent_type": "cursor-subagent",
            "_cursor_subagent": true,
            "prompt": "retry the task",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)

        XCTAssertTrue(sessions[parentId]?.closedSubagentIds.isEmpty == true)
        XCTAssertNotNil(sessions[parentId]?.subagents[childId])
        XCTAssertEqual(sessions[parentId]?.subagents[childId]?.status, .processing)
        XCTAssertEqual(sessions[parentId]?.status, .running)
    }

    func testLatePreToolUseStillBlockedByClosedTombstone() throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .processing
        parent.closedSubagentIds = [childId]
        var sessions = [parentId: parent]

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "beforeReadFile",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "tool_name": "Read",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))
        _ = reduceEvent(sessions: &sessions, event: event, maxHistory: 10)

        XCTAssertNil(sessions[parentId]?.subagents[childId])
        XCTAssertEqual(sessions[parentId]?.closedSubagentIds, [childId])
    }
}
