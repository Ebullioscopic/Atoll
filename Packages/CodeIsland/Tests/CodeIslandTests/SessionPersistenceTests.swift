import XCTest
@testable import CodeIsland

final class SessionPersistenceTests: XCTestCase {
    func testPersistedSessionDecodesWithoutCliStartTimeForBackwardCompatibility() throws {
        let json = """
        {
          "sessionId": "session-1",
          "cwd": "/tmp/demo",
          "source": "claude",
          "model": "claude-sonnet-4",
          "sessionTitle": null,
          "sessionTitleSource": null,
          "providerSessionId": null,
          "lastUserPrompt": "hi",
          "lastAssistantMessage": "hello",
          "termApp": null,
          "itermSessionId": null,
          "ttyPath": null,
          "kittyWindowId": null,
          "tmuxPane": null,
          "tmuxClientTty": null,
          "tmuxEnv": null,
          "termBundleId": null,
          "cliPid": 123,
          "startTime": "2026-04-09T10:00:00Z",
          "lastActivity": "2026-04-09T10:01:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(PersistedSession.self, from: Data(json.utf8))

        XCTAssertEqual(session.sessionId, "session-1")
        XCTAssertEqual(session.cliPid, 123)
        XCTAssertNil(session.cliStartTime)
    }

    func testPersistedSessionRoundTripPreservesCliStartTime() throws {
        let startTime = ISO8601DateFormatter().date(from: "2026-04-09T10:00:00Z")!
        let cliStartTime = ISO8601DateFormatter().date(from: "2026-04-09T10:00:05Z")!
        let session = PersistedSession(
            sessionId: "session-2",
            cwd: "/tmp/demo",
            source: "codex",
            model: "gpt-5",
            sessionTitle: "Demo",
            sessionTitleSource: nil,
            providerSessionId: "provider-2",
            lastUserPrompt: "ping",
            lastAssistantMessage: "pong",
            termApp: "iTerm.app",
            itermSessionId: "abc",
            ttyPath: "/dev/ttys001",
            kittyWindowId: nil,
            tmuxPane: nil,
            tmuxClientTty: nil,
            tmuxEnv: nil,
            termBundleId: nil,
            cmuxSurfaceId: nil,
            cmuxWorkspaceId: nil,
            zellijPaneId: nil,
            zellijSessionName: nil,
            weztermPaneId: nil,
            cliPid: 456,
            cliStartTime: cliStartTime,
            startTime: startTime,
            lastActivity: startTime.addingTimeInterval(30),
            transcriptPath: nil,
            closedSubagentIds: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(session)
        let decoded = try decoder.decode(PersistedSession.self, from: data)

        XCTAssertEqual(decoded.cliPid, 456)
        XCTAssertEqual(decoded.cliStartTime, cliStartTime)
    }

    func testPersistedSessionRoundTripPreservesClosedSubagentIds() throws {
        let startTime = ISO8601DateFormatter().date(from: "2026-04-09T10:00:00Z")!
        let session = PersistedSession(
            sessionId: "session-3",
            cwd: "/tmp/demo",
            source: "cursor",
            model: nil,
            sessionTitle: nil,
            sessionTitleSource: nil,
            providerSessionId: "parent-1",
            lastUserPrompt: nil,
            lastAssistantMessage: nil,
            termApp: nil,
            itermSessionId: nil,
            ttyPath: nil,
            kittyWindowId: nil,
            tmuxPane: nil,
            tmuxClientTty: nil,
            tmuxEnv: nil,
            termBundleId: nil,
            cmuxSurfaceId: nil,
            cmuxWorkspaceId: nil,
            zellijPaneId: nil,
            zellijSessionName: nil,
            weztermPaneId: nil,
            cliPid: nil,
            cliStartTime: nil,
            startTime: startTime,
            lastActivity: startTime,
            transcriptPath: nil,
            closedSubagentIds: ["2528cb91-6379-48f2-aff8-40f4b804dafa"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PersistedSession.self, from: try encoder.encode(session))

        XCTAssertEqual(decoded.closedSubagentIds, ["2528cb91-6379-48f2-aff8-40f4b804dafa"])
    }

    func testPersistedSessionDecodesWithoutClosedSubagentIdsForBackwardCompatibility() throws {
        let json = """
        {
          "sessionId": "session-4",
          "cwd": "/tmp/demo",
          "source": "cursor",
          "model": null,
          "sessionTitle": null,
          "sessionTitleSource": null,
          "providerSessionId": null,
          "lastUserPrompt": "hi",
          "lastAssistantMessage": null,
          "termApp": null,
          "itermSessionId": null,
          "ttyPath": null,
          "kittyWindowId": null,
          "tmuxPane": null,
          "tmuxClientTty": null,
          "tmuxEnv": null,
          "termBundleId": null,
          "cliPid": null,
          "startTime": "2026-04-09T10:00:00Z",
          "lastActivity": "2026-04-09T10:01:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(PersistedSession.self, from: Data(json.utf8))
        XCTAssertNil(session.closedSubagentIds)
    }

    func testPersistedSessionRoundTripPreservesTranscriptPath() throws {
        let startTime = ISO8601DateFormatter().date(from: "2026-04-09T10:00:00Z")!
        let path = "/Users/u/.cursor/projects/x/agent-transcripts/e1247fd5-d9a0-48ef-8457-0304606b1833/e1247fd5-d9a0-48ef-8457-0304606b1833.jsonl"
        let session = PersistedSession(
            sessionId: "session-5",
            cwd: "/tmp/demo",
            source: "cursor",
            model: nil,
            sessionTitle: nil,
            sessionTitleSource: nil,
            providerSessionId: "e1247fd5-d9a0-48ef-8457-0304606b1833",
            lastUserPrompt: nil,
            lastAssistantMessage: nil,
            termApp: nil,
            itermSessionId: nil,
            ttyPath: nil,
            kittyWindowId: nil,
            tmuxPane: nil,
            tmuxClientTty: nil,
            tmuxEnv: nil,
            termBundleId: nil,
            cmuxSurfaceId: nil,
            cmuxWorkspaceId: nil,
            zellijPaneId: nil,
            zellijSessionName: nil,
            weztermPaneId: nil,
            cliPid: nil,
            cliStartTime: nil,
            startTime: startTime,
            lastActivity: startTime,
            transcriptPath: path,
            closedSubagentIds: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PersistedSession.self, from: try encoder.encode(session))
        XCTAssertEqual(decoded.transcriptPath, path)
    }

    func testPersistedSessionDecodesWithoutTranscriptPathForBackwardCompatibility() throws {
        let json = """
        {
          "sessionId": "session-6",
          "cwd": "/tmp/demo",
          "source": "cursor",
          "model": null,
          "sessionTitle": null,
          "sessionTitleSource": null,
          "providerSessionId": null,
          "lastUserPrompt": "hi",
          "lastAssistantMessage": null,
          "termApp": null,
          "itermSessionId": null,
          "ttyPath": null,
          "kittyWindowId": null,
          "tmuxPane": null,
          "tmuxClientTty": null,
          "tmuxEnv": null,
          "termBundleId": null,
          "cliPid": null,
          "startTime": "2026-04-09T10:00:00Z",
          "lastActivity": "2026-04-09T10:01:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let session = try decoder.decode(PersistedSession.self, from: Data(json.utf8))
        XCTAssertNil(session.transcriptPath)
    }
}
