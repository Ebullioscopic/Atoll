import XCTest
@testable import CodeIslandCore

final class HookEventToolUseIdTests: XCTestCase {

    func testParsesFlatToolUseIdSnakeCase() throws {
        let event = try decode([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "tool_name": "Bash",
            "tool_use_id": "toolu_abc123"
        ])
        XCTAssertEqual(event.toolUseId, "toolu_abc123")
    }

    func testParsesFlatToolUseIdCamelCase() throws {
        let event = try decode([
            "hookEventName": "PreToolUse",
            "sessionId": "s1",
            "toolName": "Bash",
            "toolUseId": "toolu_xyz789"
        ])
        XCTAssertEqual(event.toolUseId, "toolu_xyz789")
    }

    func testParsesNestedToolUseIdInToolContainer() throws {
        let event = try decode([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "tool": [
                "name": "Bash",
                "id": "nested_id_42"
            ]
        ])
        XCTAssertEqual(event.toolUseId, "nested_id_42")
    }

    func testParsesNestedToolUseIdInToolUseContainer() throws {
        let event = try decode([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "tool_use": [
                "id": "anthropic_tool_use_id"
            ],
            "tool_name": "Read"
        ])
        XCTAssertEqual(event.toolUseId, "anthropic_tool_use_id")
    }

    func testAbsentToolUseIdIsNil() throws {
        let event = try decode([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "tool_name": "Bash"
        ])
        XCTAssertNil(event.toolUseId)
    }

    func testEmptyToolUseIdIsNil() throws {
        let event = try decode([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "tool_name": "Bash",
            "tool_use_id": "   "
        ])
        XCTAssertNil(event.toolUseId)
    }

    func testFlatFieldTakesPrecedenceOverNested() throws {
        let event = try decode([
            "hook_event_name": "PreToolUse",
            "session_id": "s1",
            "tool_use_id": "flat_wins",
            "tool": [
                "id": "nested_loses"
            ]
        ])
        XCTAssertEqual(event.toolUseId, "flat_wins")
    }

    func testBashToolDescriptionIncludesHumanSummaryAndFullCommand() throws {
        let event = try decode([
            "hook_event_name": "PermissionRequest",
            "session_id": "s1",
            "tool_name": "Bash",
            "tool_input": [
                "description": "Allow watch build before merge",
                "command": "npm run build --filter watch -- --mode production"
            ]
        ])

        XCTAssertEqual(
            event.toolDescription,
            "Allow watch build before merge\nCommand:\nnpm run build --filter watch -- --mode production"
        )
    }

    // MARK: - Helpers

    private func decode(_ payload: [String: Any]) throws -> HookEvent {
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let event = HookEvent(from: data) else {
            XCTFail("HookEvent should decode payload: \(payload)")
            throw NSError(domain: "HookEventToolUseIdTests", code: 1)
        }
        return event
    }
}
