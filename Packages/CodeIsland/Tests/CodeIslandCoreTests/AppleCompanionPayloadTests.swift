import XCTest
@testable import CodeIslandCore

final class AppleCompanionPayloadTests: XCTestCase {

    func testStatePayloadRoundTripsQuestionDetails() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_777_171_200)
        let payload = AppleCompanionStatePayload(
            sequence: 7,
            sessionId: "session-1",
            source: "codex",
            status: .waitingQuestion,
            toolName: "AskUserQuestion",
            workspaceName: "CodeIsland",
            messages: [
                AppleCompanionMessagePreview(role: .user, text: "帮我生成一篇长篇小说")
            ],
            pendingAction: .question,
            question: AppleCompanionQuestionPayload(
                header: "小说类型",
                question: "你想看什么类型的小说？",
                options: ["都市/现实", "科幻/未来"],
                descriptions: ["现代都市背景、职场、情感、生活故事", "未来世界、人工智能、太空探索、时间旅行"],
                index: 1,
                total: 4,
                allowsMultipleSelection: false
            ),
            updatedAt: updatedAt
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AppleCompanionStatePayload.self, from: data)

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.question?.header, "小说类型")
        XCTAssertEqual(decoded.pendingAction, .question)
    }

    func testOlderStatePayloadWithoutQuestionStillDecodes() throws {
        let json = """
        {
          "version": 1,
          "sequence": 8,
          "sessionId": "session-2",
          "source": "claude",
          "status": "idle",
          "toolName": null,
          "workspaceName": "workspace",
          "messages": [],
          "pendingAction": null,
          "updatedAt": 1777171200
        }
        """

        let decoded = try JSONDecoder().decode(AppleCompanionStatePayload.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.sequence, 8)
        XCTAssertEqual(decoded.source, "claude")
        XCTAssertNil(decoded.question)
        XCTAssertTrue(decoded.sessions.isEmpty)
    }

    func testStatePayloadRoundTripsSessionPreviews() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_777_171_230)
        let payload = AppleCompanionStatePayload(
            sequence: 9,
            sessionId: "codex-1",
            source: "codex",
            status: .processing,
            toolName: "Read",
            workspaceName: "CodeIsland",
            messages: [],
            pendingAction: nil,
            sessions: [
                AppleCompanionSessionPreview(
                    sessionId: "codex-1",
                    source: "codex",
                    status: .processing,
                    toolName: "Read",
                    workspaceName: "CodeIsland",
                    message: "检查 StandBy 多会话展示",
                    updatedAt: updatedAt
                ),
                AppleCompanionSessionPreview(
                    sessionId: "claude-1",
                    source: "claude",
                    status: .waitingQuestion,
                    toolName: "AskUserQuestion",
                    workspaceName: "workspace",
                    message: "你想写什么类型的小说？",
                    updatedAt: updatedAt
                )
            ],
            updatedAt: updatedAt
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(AppleCompanionStatePayload.self, from: data)

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.sessions.count, 2)
        XCTAssertEqual(decoded.sessions[1].status, .waitingQuestion)
    }

    func testAnswerQuestionCommandCarriesSelectedAnswer() throws {
        let command = AppleCompanionCommandPayload(
            type: .answerQuestion,
            sessionId: "session-3",
            source: "codex",
            answer: "科幻/未来"
        )

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(AppleCompanionCommandPayload.self, from: data)

        XCTAssertEqual(decoded.type, .answerQuestion)
        XCTAssertEqual(decoded.sessionId, "session-3")
        XCTAssertEqual(decoded.source, "codex")
        XCTAssertEqual(decoded.answer, "科幻/未来")
    }

    func testRequestCurrentStateCommandRoundTrips() throws {
        let command = AppleCompanionCommandPayload(type: .requestCurrentState)

        let data = try JSONEncoder().encode(command)
        let decoded = try JSONDecoder().decode(AppleCompanionCommandPayload.self, from: data)

        XCTAssertEqual(decoded.type, .requestCurrentState)
        XCTAssertNil(decoded.sessionId)
        XCTAssertNil(decoded.source)
        XCTAssertNil(decoded.answer)
    }
}
