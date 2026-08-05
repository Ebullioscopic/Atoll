import Foundation
import XCTest
import CodeIslandCore
@testable import CodeIslandRuntime

final class CodeIslandRuntimeTests: XCTestCase {
    func testRuntimeRemainsInertByDefault() {
        XCTAssertFalse(CodeIslandRuntime.isEnabledByDefault)
        XCTAssertFalse(CodeIslandRuntime().isRunning)
    }

    func testCodexIsMonitoringOnlyAndCannotBeActivatedDuringPhaseTwo() throws {
        let profile = try XCTUnwrap(ProviderCapabilityRegistry.phaseTwo.profile(for: .codex))

        XCTAssertEqual(profile.verifiedCapability, .monitoring)
        XCTAssertFalse(profile.isActivationAvailable)
        XCTAssertEqual(
            profile.limitations,
            [
                .activationDeferred,
                .interactiveQuestionObservationUnavailable,
                .toolFailureObservationUnavailable,
            ]
        )
    }

    func testEveryCodexFixtureCompletesWithoutProviderOutput() throws {
        let adapter = CodexHookAdapter()
        let policy = NonOwningHookCompletionPolicy()
        let fixtures = try codexFixtureURLs().map(loadFixture(at:))
        var simulatedOriginOutcomes: [String: String] = [:]

        XCTAssertEqual(Set(fixtures.map(\.scenario)), [
            "atoll-missing",
            "atoll-shutdown",
            "observer-timeout",
            "origin-allows",
            "origin-cancels",
            "origin-denies",
            "origin-question",
        ])

        for fixture in fixtures {
            let evaluation = adapter.evaluate(
                payload: fixture.payload,
                context: CodexHookContext(
                    currentDirectory: "/fallback/project",
                    origin: OriginNavigation(
                        applicationBundleIdentifier: "com.example.Terminal",
                        terminalSessionIdentifier: "terminal-session",
                        workspaceIdentifier: "workspace-1",
                        paneIdentifier: "pane-1",
                        tty: "/dev/ttys001"
                    )
                ),
                observedAt: Date(timeIntervalSince1970: 1_754_275_200)
            )
            let completion = policy.completion(after: fixture.deliveryOutcome)

            XCTAssertEqual(completion.exitStatus, 0, fixture.scenario)
            XCTAssertTrue(completion.standardOutput.isEmpty, fixture.scenario)

            if let originOutcome = fixture.originOutcome {
                simulatedOriginOutcomes[fixture.scenario] = simulateNativeOrigin(
                    intendedOutcome: originOutcome,
                    after: completion
                )
            }

            if let expectedState = fixture.expectedState {
                XCTAssertEqual(evaluation.observation?.transition.resultingState, expectedState, fixture.scenario)
            } else {
                XCTAssertNil(evaluation.observation, fixture.scenario)
            }
        }

        XCTAssertEqual(simulatedOriginOutcomes["origin-allows"], "allow")
        XCTAssertEqual(simulatedOriginOutcomes["origin-denies"], "deny")
        XCTAssertEqual(simulatedOriginOutcomes["origin-cancels"], "cancelled")
        XCTAssertEqual(simulatedOriginOutcomes["origin-question"], "answered")
    }

    func testAppServerQuestionRequestIsNotConsumedAsAHookObservation() throws {
        let fixture = try loadFixture(named: "origin-question")
        let evaluation = CodexHookAdapter().evaluate(
            payload: fixture.payload,
            context: CodexHookContext(currentDirectory: nil, origin: nil),
            observedAt: Date(timeIntervalSince1970: 1_754_275_200)
        )

        XCTAssertNil(evaluation.observation)
        XCTAssertEqual(evaluation.completion.exitStatus, 0)
        XCTAssertTrue(evaluation.completion.standardOutput.isEmpty)
    }

    func testCodexLifecycleEventsMapToContentFreeTransitions() throws {
        let expectedStates: [(event: String, state: SessionState)] = [
            ("SessionStart", .working),
            ("UserPromptSubmit", .working),
            ("PreToolUse", .working),
            ("PostToolUse", .working),
            ("PreCompact", .working),
            ("PostCompact", .working),
            ("SubagentStart", .working),
            ("SubagentStop", .working),
            ("PermissionRequest", .waitingForApproval),
            ("Stop", .recentlyCompleted),
            ("SessionEnd", .ended),
        ]

        for expected in expectedStates {
            let payload = try JSONSerialization.data(withJSONObject: [
                "session_id": "thr_transition",
                "hook_event_name": expected.event,
                "prompt": "private content that must be ignored",
            ])
            let evaluation = CodexHookAdapter().evaluate(
                payload: payload,
                context: CodexHookContext(currentDirectory: nil, origin: nil),
                observedAt: Date(timeIntervalSince1970: 1_754_275_200)
            )

            XCTAssertEqual(
                evaluation.observation?.transition.resultingState,
                expected.state,
                expected.event
            )
            XCTAssertTrue(evaluation.completion.standardOutput.isEmpty, expected.event)
        }
    }

    func testCodexDoesNotInventAToolFailureSignalFromRichOutput() throws {
        let adapter = CodexHookAdapter()
        let observedAt = Date(timeIntervalSince1970: 1_754_275_200)
        let unsupportedFailure = try JSONSerialization.data(withJSONObject: [
            "session_id": "thr_transition",
            "hook_event_name": "PostToolUseFailure",
        ])
        let arbitraryPostToolResponse = try JSONSerialization.data(withJSONObject: [
            "session_id": "thr_transition",
            "hook_event_name": "PostToolUse",
            "tool_response": [
                "exit_code": 1,
                "content": "private provider output",
            ],
        ])

        XCTAssertNil(adapter.evaluate(
            payload: unsupportedFailure,
            context: CodexHookContext(currentDirectory: nil, origin: nil),
            observedAt: observedAt
        ).observation)
        XCTAssertEqual(adapter.evaluate(
            payload: arbitraryPostToolResponse,
            context: CodexHookContext(currentDirectory: nil, origin: nil),
            observedAt: observedAt
        ).observation?.transition, .active)
    }

    func testCodexCompactSessionStartPreservesTheOriginalStartTime() throws {
        let adapter = CodexHookAdapter()
        let projector = SessionMetadataProjector()
        let startedAt = Date(timeIntervalSince1970: 1_754_275_200)
        let compactedAt = startedAt.addingTimeInterval(60)
        let sessionID = try XCTUnwrap(OpaqueSessionID("thr_compact"))
        let original = projector.applying(
            SessionObservation(
                provider: .codex,
                sessionID: sessionID,
                project: nil,
                origin: nil,
                transition: .started,
                observedAt: startedAt
            ),
            to: nil
        )
        let compactPayload = try JSONSerialization.data(withJSONObject: [
            "session_id": sessionID.rawValue,
            "hook_event_name": "SessionStart",
            "source": "compact",
        ])
        let compactObservation = try XCTUnwrap(adapter.evaluate(
            payload: compactPayload,
            context: CodexHookContext(currentDirectory: nil, origin: nil),
            observedAt: compactedAt
        ).observation)
        let compacted = projector.applying(compactObservation, to: original)

        XCTAssertEqual(compactObservation.transition, .active)
        XCTAssertEqual(compacted.startedAt, startedAt)
        XCTAssertEqual(compacted.updatedAt, compactedAt)
        XCTAssertEqual(compacted.state, .working)
    }

    private func codexFixtureURLs() throws -> [URL] {
        let directory = try XCTUnwrap(
            Bundle.module.resourceURL?
                .appendingPathComponent("Fixtures", isDirectory: true)
                .appendingPathComponent("Codex", isDirectory: true)
        )
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func loadFixture(named name: String) throws -> CodexFixture {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Fixtures/Codex"
            )
        )
        return try loadFixture(at: url)
    }

    private func loadFixture(at url: URL) throws -> CodexFixture {
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let scenario = try XCTUnwrap(root["scenario"] as? String)
        let deliveryValue = try XCTUnwrap(root["deliveryOutcome"] as? String)
        let deliveryOutcome = try XCTUnwrap(ObservationDeliveryOutcome(rawValue: deliveryValue))
        let inputModeValue = try XCTUnwrap(root["inputMode"] as? String)
        let inputMode = try XCTUnwrap(CodexFixtureInputMode(rawValue: inputModeValue))
        let payloadObject = try XCTUnwrap(root["payload"] as? [String: Any])
        let payload = try JSONSerialization.data(withJSONObject: payloadObject, options: [.sortedKeys])
        let expectedState = (root["expectedState"] as? String).flatMap(SessionState.init(rawValue:))

        return CodexFixture(
            scenario: scenario,
            inputMode: inputMode,
            originOutcome: root["originOutcome"] as? String,
            deliveryOutcome: deliveryOutcome,
            payload: payload,
            expectedState: expectedState
        )
    }

    private func simulateNativeOrigin(
        intendedOutcome: String,
        after completion: ProviderHookCompletion
    ) -> String? {
        guard completion.exitStatus == 0, completion.standardOutput.isEmpty else {
            return nil
        }
        return intendedOutcome
    }
}

private enum CodexFixtureInputMode: String {
    case complete
    case stalled
}

private struct CodexFixture {
    let scenario: String
    let inputMode: CodexFixtureInputMode
    let originOutcome: String?
    let deliveryOutcome: ObservationDeliveryOutcome
    let payload: Data
    let expectedState: SessionState?
}
