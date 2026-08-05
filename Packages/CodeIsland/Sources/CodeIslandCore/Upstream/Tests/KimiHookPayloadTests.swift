import XCTest
@testable import CodeIslandCore

/// Kimi Code CLI sends UserPromptSubmit.prompt as a content-part array, not a string.
final class KimiHookPayloadTests: XCTestCase {
    private func apply(_ payload: [String: Any], to sessions: inout [String: SessionSnapshot]) throws -> [SideEffect] {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let event = try XCTUnwrap(HookEvent(from: data))
        return reduceEvent(sessions: &sessions, event: event, maxHistory: 20)
    }

    func testKimiUserPromptSubmitContentPartArrayBecomesChatText() throws {
        let sessionId = "session_kimi_prompt_array"
        var sessions: [String: SessionSnapshot] = [:]

        _ = try apply([
            "hook_event_name": "UserPromptSubmit",
            "session_id": sessionId,
            "_source": "kimi",
            "cwd": "/Users/dev/Code",
            "prompt": [
                ["type": "text", "text": "Optimize the node parameter menu"],
            ],
        ], to: &sessions)

        let session = try XCTUnwrap(sessions[sessionId])
        XCTAssertEqual(session.status, .processing)
        XCTAssertEqual(session.lastUserPrompt, "Optimize the node parameter menu")
        XCTAssertEqual(session.recentMessages.last?.isUser, true)
        XCTAssertEqual(session.recentMessages.last?.text, "Optimize the node parameter menu")
    }

    func testKimiUserPromptSubmitJoinsMultipleTextParts() throws {
        let sessionId = "session_kimi_prompt_multi"
        var sessions: [String: SessionSnapshot] = [:]

        _ = try apply([
            "hook_event_name": "UserPromptSubmit",
            "session_id": sessionId,
            "_source": "kimi",
            "prompt": [
                ["type": "text", "text": "Hello "],
                ["type": "text", "text": "world"],
                ["type": "image", "url": "https://example.com/a.png"],
            ],
        ], to: &sessions)

        let session = try XCTUnwrap(sessions[sessionId])
        XCTAssertEqual(session.lastUserPrompt, "Hello world")
    }

    func testPlainStringPromptStillWorks() throws {
        let sessionId = "session_plain_prompt"
        var sessions: [String: SessionSnapshot] = [:]

        _ = try apply([
            "hook_event_name": "UserPromptSubmit",
            "session_id": sessionId,
            "_source": "claude",
            "prompt": "Keep string prompts working",
        ], to: &sessions)

        XCTAssertEqual(sessions[sessionId]?.lastUserPrompt, "Keep string prompts working")
    }
}
