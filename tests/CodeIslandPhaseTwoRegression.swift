import Foundation
import CodeIslandCore
import CodeIslandRuntime

private enum RegressionFailure: Error {
    case failed(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RegressionFailure.failed(message) }
}

@main
private struct CodeIslandPhaseTwoRegression {
    static func main() throws {
        let context = try makeContext()
        let metadata = try verifyProjectionAndArchive(context)
        try verifyCodexLifecycle(context)
        try verifyToolFailureExclusion(context)
        try verifyCompactionContinuity(context)
        try verifyActiveResponderExclusion(context)
        try verifyNonOwningCompletion()
        try verifyCapabilitiesAndInertRuntime()
        try verifyOrderingAndPersistence(context, metadata: metadata)
    }

    private static func makeContext() throws -> RegressionContext {
        let observedAt = Date(timeIntervalSince1970: 1_754_275_200)
        let sessionID = try require(OpaqueSessionID("thr_regression"), "opaque session id")
        let project = try require(ProjectIdentity(workingDirectory: "/workspace/atoll"), "project identity")
        let origin = OriginNavigation(
            applicationBundleIdentifier: "com.example.Terminal",
            terminalSessionIdentifier: "terminal-session",
            workspaceIdentifier: "workspace-1",
            paneIdentifier: "pane-1",
            tty: "/dev/ttys001"
        )
        return RegressionContext(
            observedAt: observedAt,
            sessionID: sessionID,
            project: project,
            origin: origin
        )
    }

    private static func verifyProjectionAndArchive(
        _ context: RegressionContext
    ) throws -> SessionMetadata {
        let metadata = SessionMetadataProjector().applying(
            SessionObservation(
                provider: .codex,
                sessionID: context.sessionID,
                project: context.project,
                origin: context.origin,
                transition: .waitingForOrigin(.approval),
                observedAt: context.observedAt
            ),
            to: nil
        )
        try expect(metadata.state == .waitingForApproval, "approval state was not projected")

        let archive = try SessionMetadataArchiveCodec().encode([metadata])
        let archiveText = try require(String(data: archive, encoding: .utf8), "archive text")
        for forbidden in [
            "private user prompt",
            "private assistant response",
            "private command",
            "private question",
            "private answer",
            "private tool input",
            "private raw payload",
        ] {
            try expect(!archiveText.contains(forbidden), "archive retained \(forbidden)")
        }
        let decodedArchive = try SessionMetadataArchiveCodec().decode(archive)
        try expect(decodedArchive == [metadata], "archive round trip")

        var unsupportedObject = try require(
            JSONSerialization.jsonObject(with: archive) as? [String: Any],
            "archive object"
        )
        unsupportedObject["schemaVersion"] = 99
        let unsupportedArchive = try JSONSerialization.data(withJSONObject: unsupportedObject)
        do {
            _ = try SessionMetadataArchiveCodec().decode(unsupportedArchive)
            throw RegressionFailure.failed("unsupported archive schema was accepted")
        } catch SessionMetadataArchiveError.unsupportedSchemaVersion(99) {
            // Expected.
        }
        return metadata
    }

    private static func verifyCodexLifecycle(_ context: RegressionContext) throws {
        let permissionPayload = Data(#"""
        {
          "session_id":"thr_regression",
          "cwd":"/workspace/atoll",
          "hook_event_name":"PermissionRequest",
          "tool_name":"Bash",
          "tool_input":{"command":"private command"}
        }
        """#.utf8)
        let evaluation = CodexHookAdapter().evaluate(
            payload: permissionPayload,
            context: CodexHookContext(currentDirectory: nil, origin: context.origin),
            observedAt: context.observedAt
        )
        try expect(
            evaluation.observation?.transition.resultingState == .waitingForApproval,
            "Codex permission observation"
        )
        try expect(evaluation.completion.exitStatus == 0, "Codex completion status")
        try expect(evaluation.completion.standardOutput.isEmpty, "Codex completion output")

        let expectedTransitions: [(String, SessionState)] = [
            ("UserPromptSubmit", .working),
            ("PostToolUse", .working),
            ("Stop", .recentlyCompleted),
        ]
        for (eventName, expectedState) in expectedTransitions {
            let payload = try JSONSerialization.data(withJSONObject: [
                "session_id": "thr_regression",
                "hook_event_name": eventName,
                "last_assistant_message": "private assistant response",
            ])
            let observed = CodexHookAdapter().evaluate(
                payload: payload,
                context: CodexHookContext(currentDirectory: nil, origin: nil),
                observedAt: context.observedAt
            )
            try expect(
                observed.observation?.transition.resultingState == expectedState,
                "Codex transition \(eventName)"
            )
        }
    }

    private static func verifyToolFailureExclusion(_ context: RegressionContext) throws {
        let unsupportedFailurePayload = try JSONSerialization.data(withJSONObject: [
            "session_id": "thr_regression",
            "hook_event_name": "PostToolUseFailure",
        ])
        let unsupportedFailure = CodexHookAdapter().evaluate(
            payload: unsupportedFailurePayload,
            context: CodexHookContext(currentDirectory: nil, origin: nil),
            observedAt: context.observedAt
        )
        try expect(
            unsupportedFailure.observation == nil,
            "undocumented Codex failure event was accepted"
        )

        let richPostToolPayload = try JSONSerialization.data(withJSONObject: [
            "session_id": "thr_regression",
            "hook_event_name": "PostToolUse",
            "tool_response": [
                "exit_code": 1,
                "content": "private provider output",
            ],
        ])
        let richPostTool = CodexHookAdapter().evaluate(
            payload: richPostToolPayload,
            context: CodexHookContext(currentDirectory: nil, origin: nil),
            observedAt: context.observedAt
        )
        try expect(
            richPostTool.observation?.transition == .active,
            "arbitrary tool response was interpreted as a stable failure signal"
        )
    }

    private static func verifyCompactionContinuity(_ context: RegressionContext) throws {
        let originalStart = SessionMetadataProjector().applying(
            SessionObservation(
                provider: .codex,
                sessionID: context.sessionID,
                project: context.project,
                origin: context.origin,
                transition: .started,
                observedAt: context.observedAt
            ),
            to: nil
        )
        let compactPayload = try JSONSerialization.data(withJSONObject: [
            "session_id": context.sessionID.rawValue,
            "hook_event_name": "SessionStart",
            "source": "compact",
        ])
        let compactObservation = try require(
            CodexHookAdapter().evaluate(
                payload: compactPayload,
                context: CodexHookContext(currentDirectory: nil, origin: nil),
                observedAt: context.observedAt.addingTimeInterval(60)
            ).observation,
            "compact observation"
        )
        let compacted = SessionMetadataProjector().applying(
            compactObservation,
            to: originalStart
        )
        try expect(compactObservation.transition == .active, "compact was treated as a new start")
        try expect(
            compacted.startedAt == context.observedAt,
            "compact reset the original start time"
        )
    }

    private static func verifyActiveResponderExclusion(_ context: RegressionContext) throws {
        let activeResponderPayload = Data(#"""
        {
          "jsonrpc":"2.0",
          "id":"request-1",
          "method":"item/tool/requestUserInput",
          "params":{"threadId":"thr_question","questions":[{"question":"private question"}]}
        }
        """#.utf8)
        let excluded = CodexHookAdapter().evaluate(
            payload: activeResponderPayload,
            context: CodexHookContext(currentDirectory: nil, origin: nil),
            observedAt: context.observedAt
        )
        try expect(excluded.observation == nil, "active responder request crossed the hook seam")
    }

    private static func verifyNonOwningCompletion() throws {
        let policy = NonOwningHookCompletionPolicy()
        for outcome in ObservationDeliveryOutcome.allCases {
            let completion = policy.completion(after: outcome)
            try expect(completion.exitStatus == 0, "delivery outcome changed status: \(outcome)")
            try expect(completion.standardOutput.isEmpty, "delivery outcome produced output: \(outcome)")
        }
    }

    private static func verifyCapabilitiesAndInertRuntime() throws {
        let profile = try require(
            ProviderCapabilityRegistry.phaseTwo.profile(for: .codex),
            "Codex capability profile"
        )
        try expect(profile.verifiedCapability == .monitoring, "Codex capability was over-promoted")
        try expect(!profile.isActivationAvailable, "Codex activation became available in Phase 2")
        try expect(
            profile.limitations.contains(.toolFailureObservationUnavailable),
            "Codex tool-failure observation was over-claimed"
        )
        try expect(CodeIslandCoreBoundary.isReadyForHostIntegration, "Core boundary is not ready")
        try expect(!CodeIslandRuntime.isEnabledByDefault, "runtime enabled itself")
        try expect(!CodeIslandRuntime().isRunning, "runtime started itself")
    }

    private static func verifyOrderingAndPersistence(
        _ context: RegressionContext,
        metadata: SessionMetadata
    ) throws {
        let staleObservation = SessionObservation(
            provider: .codex,
            sessionID: context.sessionID,
            project: nil,
            origin: nil,
            transition: .failed,
            observedAt: context.observedAt.addingTimeInterval(-1)
        )
        try expect(
            SessionMetadataProjector().applying(staleObservation, to: metadata) == metadata,
            "stale observation replaced newer metadata"
        )

        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeDirectory) }
        let storeURL = storeDirectory.appendingPathComponent("sessions.json")
        let store = FileSessionMetadataStore(fileURL: storeURL)
        try store.save([metadata])
        let loadedMetadata = try store.load()
        try expect(loadedMetadata == [metadata], "metadata file round trip")
        let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        let permissions = try require(attributes[.posixPermissions] as? NSNumber, "file permissions")
        try expect(permissions.intValue & 0o777 == 0o600, "metadata file permissions")
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw RegressionFailure.failed(message) }
        return value
    }
}

private struct RegressionContext {
    let observedAt: Date
    let sessionID: OpaqueSessionID
    let project: ProjectIdentity
    let origin: OriginNavigation
}
