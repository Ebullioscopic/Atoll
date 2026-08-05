import CodeIslandCore
import CodeIslandRuntime
import Foundation

private enum RegressionFailure: Error {
    case failed(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RegressionFailure.failed(message) }
}

@main
private struct CodeIslandPhaseFiveBridgeRegression {
    static func main() throws {
        try verifyMetadataOnlyWireContract()
        try verifyEventSpecificNativePassThrough()
    }

    private static func verifyMetadataOnlyWireContract() throws {
        let observation = SessionObservation(
            provider: .codex,
            sessionID: OpaqueSessionID("thr_phase_five")!,
            project: ProjectIdentity(
                displayName: "Atoll",
                workingDirectory: "/Users/example/Atoll"
            ),
            origin: OriginNavigation(
                applicationBundleIdentifier: "com.apple.Terminal",
                terminalSessionIdentifier: "terminal-1",
                workspaceIdentifier: nil,
                paneIdentifier: "pane-2",
                tty: "/dev/ttys001"
            ),
            transition: .waitingForOrigin(.approval),
            observedAt: Date(timeIntervalSince1970: 1_754_275_200)
        )
        let codec = CodeIslandObservationWireCodec()
        let encoded = try codec.encode(observation)
        let encodedText = String(decoding: encoded, as: UTF8.self)

        try expect(encoded.count <= CodeIslandObservationWireCodec.maximumEnvelopeSize, "wire envelope must be bounded")
        try expect(!encodedText.contains("prompt"), "wire envelope must not contain prompt content")
        try expect(!encodedText.contains("command"), "wire envelope must not contain command content")
        let decoded = try codec.decode(encoded)
        try expect(decoded == observation, "metadata-only envelope must round-trip")

        var root = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        root["prompt"] = "private provider content"
        let smuggled = try JSONSerialization.data(withJSONObject: root)
        do {
            _ = try codec.decode(smuggled)
            throw RegressionFailure.failed("unknown content-bearing keys must be rejected")
        } catch is CodeIslandObservationWireError {
            // Expected: the listener accepts only the fixed metadata schema.
        }
    }

    private static func verifyEventSpecificNativePassThrough() throws {
        let adapter = CodexHookAdapter()
        let context = CodexHookContext(currentDirectory: nil, origin: nil)
        let observedAt = Date(timeIntervalSince1970: 1_754_275_200)

        let stop = try JSONSerialization.data(withJSONObject: [
            "session_id": "thr_stop",
            "hook_event_name": "Stop",
            "last_assistant_message": "private content",
        ])
        let stopEvaluation = adapter.evaluate(
            payload: stop,
            context: context,
            observedAt: observedAt
        )
        try expect(stopEvaluation.completion.exitStatus == 0, "Stop must continue in Codex")
        try expect(stopEvaluation.completion.standardOutput == Data("{}".utf8), "Stop must receive valid no-op JSON")

        let permission = try JSONSerialization.data(withJSONObject: [
            "session_id": "thr_permission",
            "hook_event_name": "PermissionRequest",
            "tool_input": ["command": "private command"],
        ])
        let permissionEvaluation = adapter.evaluate(
            payload: permission,
            context: context,
            observedAt: observedAt
        )
        try expect(permissionEvaluation.completion.exitStatus == 0, "PermissionRequest must continue in Codex")
        try expect(permissionEvaluation.completion.standardOutput.isEmpty, "PermissionRequest must return no decision")

        let policy = NonOwningHookCompletionPolicy()
        for outcome in ObservationDeliveryOutcome.allCases {
            try expect(
                policy.completion(for: .permissionRequest, after: outcome).standardOutput.isEmpty,
                "delivery must never change PermissionRequest ownership"
            )
            try expect(
                policy.completion(for: .stop, after: outcome).standardOutput == Data("{}".utf8),
                "delivery must never change Stop's no-op JSON"
            )
        }
    }
}
