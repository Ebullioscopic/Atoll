import XCTest
@testable import CodeIsland
import CodeIslandCore

/// Locks in the wire-level pieces of ZCode support (#245). ZCode (Z.ai) is an
/// Electron desktop app — NOT a CLI matching any existing format. Its native
/// hook config (~/.zcode/cli/config.json) wraps hooks in `{enabled, events}`
/// with a STRICT 7-name event schema: writing any other event key silently
/// drops the whole `hooks` config on load. These assertions guard the parts
/// that don't need a live ZCode install: source recognition, the new
/// `.zcode` HookFormat, the default event list, the event-name whitelist,
/// and the JSON merge/remove logic for the `{enabled, events}` wrapper.
final class ZCodeSupportTests: XCTestCase {

    // MARK: - Source recognition / display name

    func testZcodeIsRecognizedAsSupportedSource() {
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("zcode"), "zcode")
    }

    func testZcodeAliasesNormalizeToZcode() {
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("z-code"), "zcode")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("z code"), "zcode")
    }

    func testZcodeDisplayLabel() {
        var snapshot = SessionSnapshot()
        snapshot.source = "zcode"
        XCTAssertEqual(snapshot.sourceLabel, "ZCode")
    }

    // MARK: - HookFormat round-trip

    func testHookFormatZcodeRoundTripsThroughStorageValue() {
        XCTAssertEqual(HookFormat.zcode.storageValue, "zcode")
        XCTAssertEqual(HookFormat(storageValue: "zcode"), .zcode)
        XCTAssertEqual(HookFormat(storageValue: "ZCode"), .zcode) // case-insensitive
    }

    // MARK: - CLIConfig wiring

    func testZcodeCLIConfigIsRegistered() {
        let cli = ConfigInstaller.allCLIs.first { $0.source == "zcode" }
        XCTAssertEqual(cli?.name, "ZCode")
        XCTAssertEqual(cli?.configPath, ".zcode/cli/config.json")
        XCTAssertEqual(cli?.configKey, "hooks")
    }

    // MARK: - Default events

    func testZcodeDefaultEventsCoverAllSevenIncludingPermissionRequest() {
        // #258: PermissionRequest's decision contract was confirmed against
        // the shipped ZCode kernel, so the full 7-event schema is registered.
        let events = ConfigInstaller.defaultEvents(for: .zcode)
        XCTAssertEqual(events.map { $0.0 }, [
            "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
            "PostToolUse", "PostToolUseFailure", "Stop",
        ])
        // The blocking approval hook must outlive ZCode's 60s default timeout.
        let permission = events.first { $0.0 == "PermissionRequest" }
        XCTAssertEqual(permission?.1, 86400)
    }

    // MARK: - Strict event-name whitelist (#245)

    func testZcodeAllowedEventsMatchesUpstreamStrictSchema() {
        XCTAssertEqual(ConfigInstaller.zcodeAllowedEvents, [
            "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
            "PostToolUse", "PostToolUseFailure", "Stop",
        ])
    }

    func testAllZcodeDefaultEventsAreWithinTheWhitelist() {
        // Writing any event name outside the whitelist silently drops the
        // WHOLE hooks config upstream — every event we ever emit must be a
        // subset of the 7 legal names.
        let names = Set(ConfigInstaller.defaultEvents(for: .zcode).map { $0.0 })
        XCTAssertTrue(names.isSubset(of: ConfigInstaller.zcodeAllowedEvents))
    }

    // MARK: - mergeZcodeHooks

    func testMergeZcodeHooksCreatesEnabledAndEventsWhenMissing() throws {
        let merged = ConfigInstaller.mergeZcodeHooks(into: "")

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(merged.utf8)) as? [String: Any])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(hooks["enabled"] as? Bool, true)

        let events = try XCTUnwrap(hooks["events"] as? [String: Any])
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "PostToolUse", "PostToolUseFailure", "Stop"] {
            let entries = try XCTUnwrap(events[event] as? [[String: Any]], "missing event \(event)")
            let entry = try XCTUnwrap(entries.first)
            let hookList = try XCTUnwrap(entry["hooks"] as? [[String: Any]])
            let hook = try XCTUnwrap(hookList.first)
            XCTAssertEqual(hook["type"] as? String, "command")
            let command = try XCTUnwrap(hook["command"] as? String)
            XCTAssertTrue(command.contains("codeisland-bridge --source zcode"))
            if event == "PermissionRequest" {
                // Blocking approval hook must override ZCode's 60s default.
                XCTAssertEqual(hook["timeout"] as? Int, 86400)
            } else {
                // Status hooks keep the upstream default — writing a tighter
                // one would regress the entries shipped in v1.0.30 (#245).
                XCTAssertNil(hook["timeout"])
            }
        }
    }

    func testMergeZcodeHooksUpgradesStatusOnlyInstallToIncludePermissionRequest() throws {
        // A config written by the #245 status-only MVP (6 events, no timeout
        // keys) must gain exactly one PermissionRequest entry on re-merge —
        // this is the silent upgrade path existing users hit at app launch.
        let bridge = "\(NSHomeDirectory())/.codeisland/codeisland-bridge"
        let legacyEvents = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Stop"]
        let legacyEventsJSON = legacyEvents.map {
            #""\#($0)": [ { "hooks": [ { "type": "command", "command": "\#(bridge) --source zcode" } ] } ]"#
        }.joined(separator: ",\n")
        let original = """
        {
          "hooks": {
            "enabled": true,
            "events": {
              \(legacyEventsJSON)
            }
          }
        }
        """

        let merged = ConfigInstaller.mergeZcodeHooks(into: original)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(merged.utf8)) as? [String: Any])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let events = try XCTUnwrap(hooks["events"] as? [String: Any])

        let permissionEntries = try XCTUnwrap(events["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(permissionEntries.count, 1)

        // No event may end up with a duplicated managed entry.
        for event in legacyEvents {
            let entries = try XCTUnwrap(events[event] as? [[String: Any]])
            XCTAssertEqual(entries.count, 1, "duplicated managed entry for \(event)")
        }
    }

    func testMergeZcodeHooksNeverFlipsUserDisabledMasterSwitch() throws {
        // `enabled` is the user's master switch over ALL their hooks — install
        // must not silently re-arm hook commands the user turned off.
        let original = """
        {
          "hooks": {
            "enabled": false,
            "events": {
              "Stop": [ { "hooks": [ { "type": "command", "command": "echo user-hook" } ] } ]
            }
          }
        }
        """

        let merged = ConfigInstaller.mergeZcodeHooks(into: original)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(merged.utf8)) as? [String: Any])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertEqual(hooks["enabled"] as? Bool, false)
    }

    func testMergeZcodeHooksIsIdempotent() throws {
        let once = ConfigInstaller.mergeZcodeHooks(into: "")
        let twice = ConfigInstaller.mergeZcodeHooks(into: once)

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(twice.utf8)) as? [String: Any])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let events = try XCTUnwrap(hooks["events"] as? [String: Any])
        let entries = try XCTUnwrap(events["Stop"] as? [[String: Any]])
        // Re-running must not duplicate our managed entry.
        XCTAssertEqual(entries.count, 1)
    }

    func testMergeZcodeHooksPreservesUserHooksAndOtherTopLevelKeys() throws {
        let bridge = "\(NSHomeDirectory())/.codeisland/codeisland-bridge"
        let original = """
        {
          "theme": "dark",
          "hooks": {
            "enabled": true,
            "events": {
              "Stop": [
                { "hooks": [ { "type": "command", "command": "echo user-hook" } ] },
                { "hooks": [ { "type": "command", "command": "\(bridge) --source zcode" } ] }
              ]
            }
          }
        }
        """

        let merged = ConfigInstaller.mergeZcodeHooks(into: original)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(merged.utf8)) as? [String: Any])

        // Sibling top-level key preserved.
        XCTAssertEqual(root["theme"] as? String, "dark")

        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let events = try XCTUnwrap(hooks["events"] as? [String: Any])
        let stopEntries = try XCTUnwrap(events["Stop"] as? [[String: Any]])
        let stopCommands = stopEntries.compactMap { ($0["hooks"] as? [[String: Any]])?.first?["command"] as? String }

        // User's own Stop hook preserved.
        XCTAssertTrue(stopCommands.contains("echo user-hook"))
        // Exactly one of our managed entries (the stale one was replaced, not duplicated).
        XCTAssertEqual(stopCommands.filter { $0.contains("codeisland-bridge") && $0.contains("--source zcode") }.count, 1)
    }

    // MARK: - removeManagedZcodeHooks

    func testRemoveManagedZcodeHooksDropsOnlyOurEntries() throws {
        let bridge = "\(NSHomeDirectory())/.codeisland/codeisland-bridge"
        let original = """
        {
          "hooks": {
            "enabled": true,
            "events": {
              "Stop": [
                { "hooks": [ { "type": "command", "command": "echo user-hook" } ] },
                { "hooks": [ { "type": "command", "command": "\(bridge) --source zcode" } ] }
              ],
              "SessionStart": [
                { "hooks": [ { "type": "command", "command": "\(bridge) --source zcode" } ] }
              ]
            }
          }
        }
        """

        let cleaned = ConfigInstaller.removeManagedZcodeHooks(from: original)
        XCTAssertFalse(cleaned.contains("codeisland-bridge --source zcode"))
        XCTAssertTrue(cleaned.contains("echo user-hook"))

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as? [String: Any])
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let events = try XCTUnwrap(hooks["events"] as? [String: Any])
        // SessionStart had only our entry — that event key is dropped entirely.
        XCTAssertNil(events["SessionStart"])
        // Stop still exists (user's hook survives).
        XCTAssertNotNil(events["Stop"])
    }

    func testRemoveManagedZcodeHooksDropsWholeHooksKeyWhenNothingElseRemains() throws {
        let bridge = "\(NSHomeDirectory())/.codeisland/codeisland-bridge"
        let original = """
        {
          "theme": "dark",
          "hooks": {
            "enabled": true,
            "events": {
              "Stop": [
                { "hooks": [ { "type": "command", "command": "\(bridge) --source zcode" } ] }
              ]
            }
          }
        }
        """

        let cleaned = ConfigInstaller.removeManagedZcodeHooks(from: original)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as? [String: Any])

        // Sibling top-level key untouched.
        XCTAssertEqual(root["theme"] as? String, "dark")
        // No leftover `{"enabled": true, "events": {}}` scaffolding.
        XCTAssertNil(root["hooks"])
    }

    func testRemoveManagedZcodeHooksLeavesUnrelatedConfigUntouched() {
        let original = """
        {
          "hooks": {
            "enabled": true,
            "events": {
              "Stop": [
                { "hooks": [ { "type": "command", "command": "echo user-hook" } ] }
              ]
            }
          }
        }
        """
        let cleaned = ConfigInstaller.removeManagedZcodeHooks(from: original)
        // Nothing of ours present -> unchanged.
        XCTAssertEqual(cleaned, original)
    }

    func testRemoveManagedZcodeHooksDropsPermissionRequestEntryWithTimeout() throws {
        // The #258 entry carries an extra `timeout` key — uninstall must still
        // recognize it as ours and remove it.
        let bridge = "\(NSHomeDirectory())/.codeisland/codeisland-bridge"
        let original = """
        {
          "hooks": {
            "enabled": true,
            "events": {
              "PermissionRequest": [
                { "hooks": [ { "type": "command", "command": "\(bridge) --source zcode", "timeout": 86400 } ] }
              ]
            }
          }
        }
        """

        let cleaned = ConfigInstaller.removeManagedZcodeHooks(from: original)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(cleaned.utf8)) as? [String: Any])
        // Only our scaffolding remained — the whole hooks key is dropped.
        XCTAssertNil(root["hooks"])
    }

    // MARK: - PermissionRequest payload parsing (#258)

    func testZcodePermissionRequestPayloadParsesCamelCaseFields() throws {
        // Field names taken verbatim from the ZCode kernel's hook input
        // (runPermissionRequestHooks in glm/zcode.cjs): everything is
        // camelCase and the invocation id is spelled `toolCallId`.
        let payload: [String: Any] = [
            "hookEventName": "PermissionRequest",
            "sessionId": "zc-session-1",
            "toolName": "Bash",
            "toolInput": ["command": "rm -rf build"],
            "toolCallId": "call-42",
            "requestId": "req-7",
            "riskLevel": "high",
            "reason": "Tool Bash requires approval",
            "mode": "build",
            "cwd": "/tmp/project",
            "timestamp": "2026-07-23T00:00:00Z",
            "_source": "zcode",
        ]
        let event = try XCTUnwrap(HookEvent(from: JSONSerialization.data(withJSONObject: payload)))

        XCTAssertEqual(EventNormalizer.normalize(event.eventName), "PermissionRequest")
        XCTAssertEqual(event.sessionId, "zc-session-1")
        XCTAssertEqual(event.toolName, "Bash")
        XCTAssertEqual(event.toolInput?["command"] as? String, "rm -rf build")
        // `toolCallId` must surface as toolUseId: a nil id would let
        // resolveOrphanPermissionsOnActivity auto-allow the queued card on the
        // next same-session activity event — unacceptable when the island is
        // the only approval surface ZCode shows.
        XCTAssertEqual(event.toolUseId, "call-42")
    }

    // MARK: - Always-allow decision shape (#258)

    func testZcodeAlwaysAllowResponseUsesStrictSchemaShape() throws {
        let data = AppState.zcodeAlwaysAllowResponse(toolName: "Bash")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")

        let decision = try XCTUnwrap(output["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        // Claude's key would fail ZCode's strict schema and void the decision.
        XCTAssertNil(decision["updatedPermissions"])

        let updates = try XCTUnwrap(decision["permissionUpdates"] as? [[String: Any]])
        let update = try XCTUnwrap(updates.first)
        XCTAssertEqual(update["type"] as? String, "addRules")
        XCTAssertEqual(update["behavior"] as? String, "allow")
        // `destination` does not exist in ZCode's schema.
        XCTAssertNil(update["destination"])

        let rules = try XCTUnwrap(update["rules"] as? [[String: Any]])
        let rule = try XCTUnwrap(rules.first)
        XCTAssertEqual(rule["toolName"] as? String, "Bash")
        // A bare toolName rule matches every call of the tool; a "*"
        // ruleContent would be compared against the command text and never match.
        XCTAssertNil(rule["ruleContent"])
    }

    func testZcodeAlwaysAllowResponseWithoutToolNameFallsBackToPlainAllow() throws {
        for toolName in [nil, ""] as [String?] {
            let data = AppState.zcodeAlwaysAllowResponse(toolName: toolName)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let output = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
            let decision = try XCTUnwrap(output["decision"] as? [String: Any])
            XCTAssertEqual(decision["behavior"] as? String, "allow")
            // An empty toolName can't form a schema-valid rule (min length 1) —
            // emitting one would void the WHOLE decision upstream.
            XCTAssertNil(decision["permissionUpdates"])
        }
    }

    func testIsZcodeEventDetectsNormalizedSource() throws {
        let zcodePayload: [String: Any] = [
            "hookEventName": "PermissionRequest", "sessionId": "s1", "_source": "zcode",
        ]
        let claudePayload: [String: Any] = [
            "hook_event_name": "PermissionRequest", "session_id": "s2", "_source": "claude",
        ]
        let zcodeEvent = try XCTUnwrap(HookEvent(from: JSONSerialization.data(withJSONObject: zcodePayload)))
        let claudeEvent = try XCTUnwrap(HookEvent(from: JSONSerialization.data(withJSONObject: claudePayload)))
        XCTAssertTrue(AppState.isZcodeEvent(zcodeEvent))
        XCTAssertFalse(AppState.isZcodeEvent(claudeEvent))
    }
}
