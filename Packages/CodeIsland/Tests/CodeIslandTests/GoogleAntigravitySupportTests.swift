import XCTest
@testable import CodeIsland
import CodeIslandCore

/// Locks in the wire-level pieces of Google Antigravity support (#215). Google
/// Antigravity is a Gemini-based IDE/CLI and a SEPARATE product from the existing
/// "antigravity" source (a Claude-Code fork reading .antigravity/settings.json).
/// These assertions guard the parts that don't need a live Antigravity install:
/// source recognition + aliasing (must NOT collide with the fork), the new
/// `.antigravityNamed` HookFormat, the Claude-style PascalCase event list, and the
/// named-config wrapper the installer writes to ~/.gemini/config/hooks.json.
final class GoogleAntigravitySupportTests: XCTestCase {

    // MARK: - Source recognition / aliasing (no collision with the Claude fork)

    func testGoogleAntigravityIsRecognizedAsSupportedSource() {
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("google-antigravity"), "google-antigravity")
    }

    func testGoogleAntigravityAliasesNormalizeToGoogleAntigravity() {
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("googleantigravity"), "google-antigravity")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("google antigravity"), "google-antigravity")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("antigravity-ide"), "google-antigravity")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("antigravity-cli"), "google-antigravity")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("agy"), "google-antigravity")
        // Prefix-match path: any future "google-antigravity-*" sub-brand folds in.
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("google-antigravity-pro"), "google-antigravity")
    }

    func testExistingAntigravityForkAliasesStayPointedAtTheFork() {
        // CRITICAL: retargeting these would break existing AntiGravity-fork users.
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("antigravity"), "antigravity")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("ag"), "antigravity")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("anti-gravity"), "antigravity")
        // A bare "antigravity-something" still resolves to the fork, NOT Google's.
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("antigravity-pro"), "antigravity")
    }

    func testGoogleAntigravityDisplayLabel() {
        var snapshot = SessionSnapshot()
        snapshot.source = "google-antigravity"
        XCTAssertEqual(snapshot.sourceLabel, "Google Antigravity")
    }

    // MARK: - EventNormalizer (Antigravity uses Claude-style PascalCase)

    func testAntigravityEventNamesPassThroughNormalizerUnchanged() {
        // Antigravity hooks.json uses PreToolUse/PostToolUse/Stop — already internal
        // names — so they must survive normalize() verbatim (NOT the Gemini
        // Before/After mapping, which targets settings.json, not hooks.json).
        XCTAssertEqual(EventNormalizer.normalize("PreToolUse"), "PreToolUse")
        XCTAssertEqual(EventNormalizer.normalize("PostToolUse"), "PostToolUse")
        XCTAssertEqual(EventNormalizer.normalize("Stop"), "Stop")
    }

    func testBeforeToolNormalizesToPermissionRequest() {
        XCTAssertEqual(EventNormalizer.normalize("BeforeTool"), "PermissionRequest")
    }

    // MARK: - HookFormat round-trip

    func testHookFormatAntigravityNamedRoundTripsThroughStorageValue() {
        XCTAssertEqual(HookFormat.antigravityNamed.storageValue, "antigravityNamed")
        XCTAssertEqual(HookFormat(storageValue: "antigravityNamed"), .antigravityNamed)
        XCTAssertEqual(HookFormat(storageValue: "antigravitynamed"), .antigravityNamed) // case-insensitive
    }

    // MARK: - Default events

    func testAntigravityDefaultEventsAreClaudeStylePascalCase() {
        let names = ConfigInstaller.defaultEvents(for: .antigravityNamed).map { $0.0 }
        XCTAssertEqual(names, ["PreToolUse", "PostToolUse", "Stop"])
    }

    // MARK: - Named-config writer (~/.gemini/config/hooks.json shape)

    func testAntigravityNamedWriterEmitsNamedConfigWrapperWithEventFlag() throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let configPath = tempDir.appendingPathComponent("hooks.json").path
        let cli = CLIConfig(
            name: "Google Antigravity",
            source: "google-antigravity",
            configPath: configPath,
            configKey: "codeisland",
            format: .antigravityNamed,
            events: ConfigInstaller.defaultEvents(for: .antigravityNamed)
        )

        XCTAssertTrue(ConfigInstaller.installExternalHooks(cli: cli, fm: fm))

        let data = try XCTUnwrap(fm.contents(atPath: configPath))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // Outer object MUST be keyed by the named-config wrapper "codeisland"
        // (NOT a bare "hooks" key — Antigravity would not recognize that).
        let wrapper = try XCTUnwrap(root["codeisland"] as? [String: Any])
        XCTAssertNil(root["hooks"], "Antigravity must NOT use the bare hooks root key")

        // Each event nests {matcher?, hooks:[{type,command,timeout}]}.
        for event in ["PreToolUse", "PostToolUse", "Stop"] {
            let entries = try XCTUnwrap(wrapper[event] as? [[String: Any]], "missing event \(event)")
            let entry = try XCTUnwrap(entries.first)
            let hookList = try XCTUnwrap(entry["hooks"] as? [[String: Any]])
            let hook = try XCTUnwrap(hookList.first)
            XCTAssertEqual(hook["type"] as? String, "command")
            XCTAssertNotNil(hook["timeout"])
            let command = try XCTUnwrap(hook["command"] as? String)
            // stdin lacks hook_event_name, so the command MUST carry --event.
            XCTAssertTrue(command.contains("codeisland-bridge --source google-antigravity"))
            XCTAssertTrue(command.contains("--event \(event)"))
        }

        // matcher "*" only on the two tool events; omitted for Stop.
        let preEntry = try XCTUnwrap((wrapper["PreToolUse"] as? [[String: Any]])?.first)
        XCTAssertEqual(preEntry["matcher"] as? String, "*")
        let postEntry = try XCTUnwrap((wrapper["PostToolUse"] as? [[String: Any]])?.first)
        XCTAssertEqual(postEntry["matcher"] as? String, "*")
        let stopEntry = try XCTUnwrap((wrapper["Stop"] as? [[String: Any]])?.first)
        XCTAssertNil(stopEntry["matcher"], "Stop ignores matcher; we must not emit one")
    }

    func testGoogleAntigravityPreToolUseRoutesToPermission() async throws {
        let payload: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "test-sess",
            "_source": "google-antigravity",
            "tool_name": "Bash",
            "tool_input": ["command": "rm -rf foo"]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let event = try XCTUnwrap(HookEvent(from: data))
        
        let kind = await MainActor.run { HookServer.routeKind(for: event) }
        XCTAssertEqual(kind, .permission)
    }

    func testGeminiSourcePreToolUseRoutesToPermission() async throws {
        // agy CLI uses --source gemini and sends hook_event_name: "PreToolUse" in
        // its JSON payload, overriding the --event BeforeTool fallback.
        let payload: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "session_id": "test-gemini-sess",
            "_source": "gemini",
            "tool_name": "run_command",
            "tool_input": ["CommandLine": "rm -rf bar"]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let event = try XCTUnwrap(HookEvent(from: data))

        let kind = await MainActor.run { HookServer.routeKind(for: event) }
        XCTAssertEqual(kind, .permission,
            "agy CLI (--source gemini) PreToolUse must be treated as a blocking permission event")
    }

    func testAgyToolCallParsing() throws {
        let payload: [String: Any] = [
            "hook_event_name": "PreToolUse",
            "conversationId": "3ff64dc8-11bd-4f7e-9a97-495badd58069",
            "_source": "gemini",
            "toolCall": [
                "name": "run_command",
                "args": [
                    "CommandLine": "ls -la"
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let event = try XCTUnwrap(HookEvent(from: data))

        XCTAssertEqual(event.toolName, "run_command")
        XCTAssertEqual(event.toolInput?["CommandLine"] as? String, "ls -la")
        XCTAssertEqual(event.toolDescription, "ls -la")
    }
}

