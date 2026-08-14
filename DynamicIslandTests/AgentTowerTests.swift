/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import XCTest
@testable import Atoll

/// Covers the pure seams of Agent Tower: hook payload interpretation, the
/// spool envelope, and the transform that edits another tool's config file.
final class AgentTowerTests: XCTestCase {

    /// The spool is redirected for the whole suite so nothing here ever writes
    /// into the real `~/.atoll`.
    private var spoolRoot: URL!

    override func setUpWithError() throws {
        spoolRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-spool-\(UUID().uuidString)", isDirectory: true)
        AgentTowerStorage.spoolRootOverride = spoolRoot
    }

    override func tearDownWithError() throws {
        AgentTowerStorage.spoolRootOverride = nil
        if let spoolRoot {
            try? FileManager.default.removeItem(at: spoolRoot)
        }
        spoolRoot = nil
    }

    // MARK: - Event name normalisation

    func testNormalizesClaudeCodeEventNames() {
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "SessionStart"), .sessionStart)
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "SessionEnd"), .sessionEnd)
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "Stop"), .stop)
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "Notification"), .notification)
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "UserPromptSubmit"), .userPromptSubmit)
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "PreToolUse"), .preToolUse)
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "PermissionRequest"), .permissionRequest)
    }

    /// Gemini CLI spells the tool events differently; the adapter folds them in
    /// rather than each call site having to know.
    func testNormalizesAlternateSpellings() {
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "BeforeTool"), .preToolUse)
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "AfterTool"), .postToolUse)
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "pre_tool_use"), .preToolUse)
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "beforeShellExecution"), .unknown)
    }

    func testUnknownEventNameIsUnknownAndExpectsNoDecision() {
        let name = AgentEventAdapter.normalizedName(for: "SomethingNewInV9")
        XCTAssertEqual(name, .unknown)
        XCTAssertFalse(name.expectsDecision, "An unrecognised event must never be answered with a decision.")
    }

    func testOnlyPermissionEventsExpectADecision() {
        XCTAssertTrue(AgentHookEvent.Name.preToolUse.expectsDecision)
        XCTAssertTrue(AgentHookEvent.Name.permissionRequest.expectsDecision)
        for name: AgentHookEvent.Name in [.sessionStart, .sessionEnd, .stop, .notification,
                                          .userPromptSubmit, .postToolUse, .subagentStart,
                                          .subagentStop, .unknown] {
            XCTAssertFalse(name.expectsDecision, "\(name) must not block an agent.")
        }
    }

    // MARK: - Payload interpretation

    private func makeEvent(_ json: String, agent: String? = "claudeCode", event: String? = nil) -> AgentHookEvent? {
        AgentEventAdapter.makeEvent(
            body: Data(json.utf8),
            agentHint: agent,
            eventHint: event,
            terminalProgram: "Apple_Terminal",
            terminalBundleID: "com.apple.Terminal",
            now: Date(timeIntervalSince1970: 1_000)
        )
    }

    /// Shaped after a real Claude Code `PreToolUse` payload.
    func testReadsRealClaudeCodeToolPayload() throws {
        let event = try XCTUnwrap(makeEvent("""
        {
          "session_id": "e15df9fc-aaa0-445e-865c-f07844b17570",
          "transcript_path": "/Users/x/.claude/projects/-Users-x-Atoll/e15df9fc.jsonl",
          "cwd": "/Users/x/Atoll",
          "permission_mode": "default",
          "hook_event_name": "PreToolUse",
          "tool_name": "Bash",
          "tool_input": { "command": "rm -rf /tmp/build", "description": "Clean build" },
          "tool_use_id": "toolu_01ABC"
        }
        """))

        XCTAssertEqual(event.kind, .claudeCode)
        XCTAssertEqual(event.name, .preToolUse)
        XCTAssertEqual(event.sessionID, "e15df9fc-aaa0-445e-865c-f07844b17570")
        XCTAssertEqual(event.cwd, "/Users/x/Atoll")
        XCTAssertEqual(event.projectName, "Atoll")
        XCTAssertEqual(event.transcriptPath, "/Users/x/.claude/projects/-Users-x-Atoll/e15df9fc.jsonl")
        XCTAssertEqual(event.permissionMode, "default")
        XCTAssertEqual(event.toolName, "Bash")
        XCTAssertEqual(event.command, "rm -rf /tmp/build")
        XCTAssertEqual(event.toolDescription, "Clean build")
        XCTAssertEqual(event.toolUseID, "toolu_01ABC")
        XCTAssertEqual(event.terminalProgram, "Apple_Terminal")
        XCTAssertEqual(event.sessionKey, "claudeCode:e15df9fc-aaa0-445e-865c-f07844b17570")
    }

    /// Without a session there is nothing to attribute the event to, so the
    /// payload is dropped rather than half-interpreted.
    func testRejectsPayloadWithoutSessionIdentifier() {
        XCTAssertNil(makeEvent(#"{"hook_event_name":"Stop","cwd":"/tmp"}"#))
    }

    func testRejectsNonObjectPayload() {
        XCTAssertNil(makeEvent("[1,2,3]"))
        XCTAssertNil(makeEvent("not json at all"))
    }

    /// The shim's `event=` argument is the fallback when the body omits the name.
    func testFallsBackToEventHintWhenBodyOmitsName() throws {
        let event = try XCTUnwrap(makeEvent(#"{"session_id":"s1"}"#, event: "SessionEnd"))
        XCTAssertEqual(event.name, .sessionEnd)
        XCTAssertEqual(event.rawEventName, "SessionEnd")
    }

    /// An unset shell variable expands to an empty string, so the shim can
    /// legitimately send `term=`.
    func testTreatsEmptyTerminalHintsAsAbsent() throws {
        let event = try XCTUnwrap(AgentEventAdapter.makeEvent(
            body: Data(#"{"session_id":"s1","hook_event_name":"Stop"}"#.utf8),
            agentHint: "claudeCode",
            eventHint: nil,
            terminalProgram: "",
            terminalBundleID: "   ",
            now: Date()
        ))
        XCTAssertNil(event.terminalProgram)
        XCTAssertNil(event.terminalBundleID)
    }

    func testCamelCaseAndAlternateFieldNamesAreAccepted() throws {
        let event = try XCTUnwrap(makeEvent("""
        {
          "sessionId": "s2",
          "hookEventName": "PreToolUse",
          "workingDirectory": "/tmp/project",
          "toolName": "shell",
          "toolInput": { "cmd": "ls -la" }
        }
        """))
        XCTAssertEqual(event.sessionID, "s2")
        XCTAssertEqual(event.cwd, "/tmp/project")
        XCTAssertEqual(event.toolName, "shell")
        XCTAssertEqual(event.command, "ls -la")
    }

    // MARK: - Session state machine

    func testSessionLifecycleTransitions() throws {
        let start = try XCTUnwrap(makeEvent(#"{"session_id":"s3","cwd":"/tmp/p","hook_event_name":"SessionStart"}"#))
        var session = AgentSession(event: start)
        session.apply(start)
        XCTAssertEqual(session.status, .working)
        XCTAssertNil(session.endedAt)

        let notification = try XCTUnwrap(makeEvent(#"{"session_id":"s3","hook_event_name":"Notification"}"#))
        session.apply(notification)
        XCTAssertEqual(session.status, .waitingOnUser)

        let prompt = try XCTUnwrap(makeEvent(#"{"session_id":"s3","hook_event_name":"UserPromptSubmit"}"#))
        session.apply(prompt)
        XCTAssertEqual(session.status, .working)

        let stop = try XCTUnwrap(makeEvent(#"{"session_id":"s3","hook_event_name":"Stop"}"#))
        session.apply(stop)
        XCTAssertEqual(session.status, .finished)
        XCTAssertNotNil(session.endedAt)
    }

    /// Elapsed time must freeze once a session ends, or a finished card keeps
    /// counting up forever.
    func testElapsedFreezesAfterTheSessionEnds() throws {
        let start = try XCTUnwrap(makeEvent(#"{"session_id":"s4","hook_event_name":"SessionStart"}"#))
        var session = AgentSession(event: start)
        session.startedAt = Date(timeIntervalSince1970: 0)
        session.endedAt = Date(timeIntervalSince1970: 42)
        XCTAssertEqual(session.elapsed(now: Date(timeIntervalSince1970: 10_000)), 42)
    }

    /// A resumed session re-fires SessionStart; the clock restarts rather than
    /// reporting an elapsed time that spans the gap.
    func testResumingAFinishedSessionRestartsTheClock() throws {
        let start = try XCTUnwrap(makeEvent(#"{"session_id":"s5","hook_event_name":"SessionStart"}"#))
        var session = AgentSession(event: start)
        session.status = .finished
        session.endedAt = Date(timeIntervalSince1970: 5)
        session.subagentsStarted = 3

        var resumed = start
        resumed = AgentHookEvent(
            kind: start.kind, name: .sessionStart, rawEventName: "SessionStart",
            sessionID: start.sessionID, cwd: start.cwd, transcriptPath: nil,
            permissionMode: nil, toolName: nil, toolUseID: nil, command: nil,
            toolDescription: nil, filePath: nil, plan: nil, message: nil,
            agentID: nil, agentType: nil, terminalProgram: nil, terminalBundleID: nil,
            receivedAt: Date(timeIntervalSince1970: 900)
        )
        session.apply(resumed)

        XCTAssertEqual(session.status, .working)
        XCTAssertNil(session.endedAt)
        XCTAssertEqual(session.startedAt, Date(timeIntervalSince1970: 900))
        XCTAssertEqual(session.subagentsStarted, 0, "Subagent counters belong to one run.")
    }

    func testContextFractionIsClampedAndNilWithoutData() throws {
        let start = try XCTUnwrap(makeEvent(#"{"session_id":"s6","hook_event_name":"SessionStart"}"#))
        var session = AgentSession(event: start)
        XCTAssertNil(session.contextFraction)

        session.contextTokens = 210_353
        session.contextWindow = 1_000_000
        XCTAssertEqual(try XCTUnwrap(session.contextFraction), 0.210353, accuracy: 0.000001)

        session.contextTokens = 300_000
        session.contextWindow = 200_000
        XCTAssertEqual(session.contextFraction, 1.0, "An over-full window must not exceed 1.")
    }

    // MARK: - Spool envelope

    private func envelopeJSON(version: Int = AgentHookSpool.protocolVersion, wait: Bool = false) -> String {
        """
        {"v":\(version),"id":"1700000000-123-abcd","event":"PreToolUse","agent":"claudeCode",
         "wait":\(wait),"pid":4242,"term":"Apple_Terminal","termbid":"com.apple.Terminal",
         "payload":{"session_id":"s7","hook_event_name":"PreToolUse"}}
        """
    }

    func testDecodesAWellFormedEnvelope() throws {
        let envelope = try XCTUnwrap(AgentHookSpool.decode(Data(envelopeJSON(wait: true).utf8)))
        XCTAssertEqual(envelope.id, "1700000000-123-abcd")
        XCTAssertEqual(envelope.event, "PreToolUse")
        XCTAssertEqual(envelope.agent, "claudeCode")
        XCTAssertTrue(envelope.expectsDecision)
        XCTAssertEqual(envelope.agentPID, 4242)
        XCTAssertEqual(envelope.terminalProgram, "Apple_Terminal")

        // The payload must survive as usable JSON for the adapter.
        let event = AgentEventAdapter.makeEvent(
            body: envelope.payload, agentHint: envelope.agent, eventHint: envelope.event,
            terminalProgram: nil, terminalBundleID: nil, now: Date()
        )
        XCTAssertEqual(event?.sessionID, "s7")
    }

    /// A shim left behind by a different Atoll version must be ignored, not
    /// reinterpreted against the current envelope shape.
    func testRejectsEnvelopeFromAnotherProtocolVersion() {
        XCTAssertNil(AgentHookSpool.decode(Data(envelopeJSON(version: 99).utf8)))
    }

    func testRejectsEnvelopeMissingRequiredFields() {
        XCTAssertNil(AgentHookSpool.decode(Data(#"{"v":1,"event":"Stop","agent":"claudeCode","payload":{}}"#.utf8)))
        XCTAssertNil(AgentHookSpool.decode(Data(#"{"v":1,"id":"x","event":"Stop","agent":"claudeCode"}"#.utf8)))
        XCTAssertNil(AgentHookSpool.decode(Data("truncated {".utf8)))
    }

    /// Request ids are used to build a path, so anything that could escape the
    /// outbox has to be refused.
    func testRequestIdentifierValidationRejectsPathTricks() {
        XCTAssertTrue(AgentHookSpool.isSafeRequestID("1700000000-123-a1b2c3"))
        XCTAssertTrue(AgentHookSpool.isSafeRequestID("abc_DEF-123"))
        XCTAssertFalse(AgentHookSpool.isSafeRequestID(""))
        XCTAssertFalse(AgentHookSpool.isSafeRequestID("../../etc/passwd"))
        XCTAssertFalse(AgentHookSpool.isSafeRequestID("a/b"))
        XCTAssertFalse(AgentHookSpool.isSafeRequestID("a.b"))
        XCTAssertFalse(AgentHookSpool.isSafeRequestID(String(repeating: "a", count: 200)))
    }

    // MARK: - Config merging

    private let shimPath = "/Users/x/.atoll/agent-hooks/atoll-hook.sh"

    /// A real `~/.claude/settings.json`: unrelated top-level keys, plus two
    /// `PreToolUse` groups the user owns.
    private var realWorldConfig: [String: Any] {
        [
            "theme": "dark",
            "language": "tr",
            "model": "opusplan",
            "enabledPlugins": ["superpowers@obra": true, "claude-mem@thedotmack": true],
            "hooks": [
                "PreToolUse": [
                    ["matcher": "*", "hooks": [["type": "command", "command": "/usr/bin/node /Users/x/.claude/statusbar/update.js pre"]]],
                    ["matcher": "Bash", "hooks": [["type": "command", "command": "rtk hook claude"]]]
                ],
                "SessionStart": [
                    ["hooks": [["type": "command", "command": "/usr/bin/node /Users/x/.claude/statusbar/lifecycle.js start"]]]
                ]
            ]
        ]
    }

    private func descriptor(includeApprovals: Bool = false) throws -> AgentHookConfigDescriptor {
        try XCTUnwrap(AgentHookInstaller.descriptor(for: .claudeCode, includeApprovals: includeApprovals))
    }

    func testInstallPreservesEveryUnrelatedSetting() throws {
        let merged = AgentHookInstaller.merging(
            descriptor: try descriptor(), into: realWorldConfig, shimPath: shimPath
        )

        XCTAssertEqual(merged["theme"] as? String, "dark")
        XCTAssertEqual(merged["language"] as? String, "tr")
        XCTAssertEqual(merged["model"] as? String, "opusplan")
        XCTAssertNotNil(merged["enabledPlugins"], "Plugin registry must survive a hook edit.")
    }

    func testInstallKeepsTheUsersOwnHookEntries() throws {
        let merged = AgentHookInstaller.merging(
            descriptor: try descriptor(), into: realWorldConfig, shimPath: shimPath
        )
        let preToolUse = try XCTUnwrap(
            (merged["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        )
        let commands = preToolUse
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String }

        XCTAssertTrue(commands.contains("rtk hook claude"), "A sibling matcher group must not be disturbed.")
        XCTAssertTrue(commands.contains { $0.hasSuffix("update.js pre") })
    }

    /// Uninstall has to return the `hooks` subtree to exactly what it was, or
    /// repeated toggling would erode the user's configuration.
    func testUninstallRestoresTheHooksSubtreeExactly() throws {
        let original = realWorldConfig
        let before = AgentHookInstaller.foreignHooksFingerprint(of: original, shimPath: shimPath)

        let merged = AgentHookInstaller.merging(descriptor: try descriptor(), into: original, shimPath: shimPath)
        XCTAssertTrue(AgentHookInstaller.containsAtollEntry(merged, shimPath: shimPath))

        let cleaned = AgentHookInstaller.removingAtollEntries(from: merged, shimPath: shimPath)
        XCTAssertFalse(AgentHookInstaller.containsAtollEntry(cleaned, shimPath: shimPath))
        XCTAssertEqual(
            AgentHookInstaller.foreignHooksFingerprint(of: cleaned, shimPath: shimPath),
            before
        )
        XCTAssertTrue(NSDictionary(dictionary: cleaned).isEqual(to: original))
    }

    /// Install is remove-then-add, so running it twice must not accumulate.
    func testInstallIsIdempotent() throws {
        let spec = try descriptor()
        var config = AgentHookInstaller.merging(descriptor: spec, into: realWorldConfig, shimPath: shimPath)
        config = AgentHookInstaller.removingAtollEntries(from: config, shimPath: shimPath)
        config = AgentHookInstaller.merging(descriptor: spec, into: config, shimPath: shimPath)

        let hooks = try XCTUnwrap(config["hooks"] as? [String: Any])
        for event in spec.events {
            let groups = try XCTUnwrap(hooks[event.wireName] as? [[String: Any]])
            let atollEntries = groups
                .compactMap { $0["hooks"] as? [[String: Any]] }
                .flatMap { $0 }
                .filter { AgentHookInstaller.isAtollEntry($0, shimPath: shimPath) }
            XCTAssertEqual(atollEntries.count, 1, "\(event.wireName) accumulated \(atollEntries.count) Atoll entries.")
        }
    }

    /// A group or event key emptied by uninstall is pruned rather than left as
    /// dead weight that grows on every toggle.
    func testUninstallPrunesEmptyContainers() {
        let onlyAtoll: [String: Any] = [
            "hooks": [
                "Stop": [["hooks": [["type": "command", "command": "\(shimPath) Stop claudeCode nowait"]]]]
            ]
        ]
        let cleaned = AgentHookInstaller.removingAtollEntries(from: onlyAtoll, shimPath: shimPath)
        XCTAssertNil(cleaned["hooks"], "An entirely Atoll-owned hooks tree should be removed, not left empty.")
    }

    func testEntryOwnershipMatchesOnTheShimPathOnly() {
        XCTAssertTrue(AgentHookInstaller.isAtollEntry(
            ["command": "\(shimPath) PreToolUse claudeCode wait"], shimPath: shimPath))
        XCTAssertTrue(AgentHookInstaller.isAtollEntry(["command": shimPath], shimPath: shimPath))
        XCTAssertFalse(AgentHookInstaller.isAtollEntry(["command": "rtk hook claude"], shimPath: shimPath))
        // A different tool whose path merely starts with the same characters.
        XCTAssertFalse(AgentHookInstaller.isAtollEntry(
            ["command": "\(shimPath)-other Stop"], shimPath: shimPath))
        XCTAssertFalse(AgentHookInstaller.isAtollEntry(["type": "command"], shimPath: shimPath))
    }

    /// Shapes Atoll does not understand are carried through untouched instead of
    /// being dropped on the floor.
    func testUnknownHookShapesArePreserved() {
        let exotic: [String: Any] = [
            "hooks": [
                "SomeFutureEvent": ["not": "an array of groups"],
                "Stop": [["hooks": [["type": "command", "command": "\(shimPath) Stop claudeCode nowait"]]]]
            ]
        ]
        let cleaned = AgentHookInstaller.removingAtollEntries(from: exotic, shimPath: shimPath)
        let hooks = cleaned["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks?["SomeFutureEvent"])
        XCTAssertNil(hooks?["Stop"])
    }

    // MARK: - Descriptors

    /// Every event installed in this phase is observe-only: nothing Atoll writes
    /// can block an agent until the approval flow ships.
    func testMonitoringDescriptorsNeverBlockAnAgent() {
        for kind in AgentKind.allCases {
            guard let spec = AgentHookInstaller.descriptor(for: kind, includeApprovals: false) else { continue }
            for event in spec.events {
                XCTAssertFalse(
                    event.expectsDecision,
                    "\(kind.displayName)/\(event.wireName) would block without the approval flow."
                )
            }
        }
    }

    func testOpencodeHasNoHookDescriptor() {
        XCTAssertFalse(AgentKind.opencode.supportsHookInstallation)
        XCTAssertNil(AgentHookInstaller.descriptor(for: .opencode, includeApprovals: false))
    }

    func testCommandLineCarriesEventAgentAndWaitMode() {
        let observe = AgentHookEventSpec(wireName: "Stop", usesMatcher: false, expectsDecision: false)
        let decide = AgentHookEventSpec(wireName: "PreToolUse", usesMatcher: true, expectsDecision: true)
        XCTAssertTrue(AgentHookInstaller.commandLine(for: observe, kind: .claudeCode).hasSuffix(" Stop claudeCode nowait"))
        XCTAssertTrue(AgentHookInstaller.commandLine(for: decide, kind: .codex).hasSuffix(" PreToolUse codex wait"))
    }

    /// Tool events need a matcher; lifecycle events must not carry one.
    func testMergedGroupsCarryAMatcherOnlyForToolEvents() throws {
        let spec = try descriptor(includeApprovals: true)
        let merged = AgentHookInstaller.merging(descriptor: spec, into: [:], shimPath: shimPath)
        let hooks = try XCTUnwrap(merged["hooks"] as? [String: Any])

        let stopGroup = try XCTUnwrap((hooks["Stop"] as? [[String: Any]])?.first)
        XCTAssertNil(stopGroup["matcher"])

        let toolGroup = try XCTUnwrap((hooks["PreToolUse"] as? [[String: Any]])?.first)
        XCTAssertEqual(toolGroup["matcher"] as? String, "*")
    }

    /// Blocking events get the long timeout; observe-only ones must stay short so
    /// a stalled filesystem can never hold an agent up.
    func testTimeoutsMatchTheEventKind() throws {
        let spec = try descriptor(includeApprovals: true)
        let merged = AgentHookInstaller.merging(descriptor: spec, into: [:], shimPath: shimPath)
        let hooks = try XCTUnwrap(merged["hooks"] as? [String: Any])

        func timeout(_ event: String) throws -> Int {
            let group = try XCTUnwrap((hooks[event] as? [[String: Any]])?.first)
            let entry = try XCTUnwrap((group["hooks"] as? [[String: Any]])?.first)
            return try XCTUnwrap(entry["timeout"] as? Int)
        }

        XCTAssertEqual(try timeout("Stop"), AgentHookInstaller.observeTimeout)
        XCTAssertEqual(try timeout("PreToolUse"), AgentHookInstaller.configuredTimeout)
        XCTAssertGreaterThan(
            AgentHookInstaller.configuredTimeout,
            AgentHookInstaller.decisionTimeout,
            "The agent must wait longer than the shim does, so the shim always exits cleanly first."
        )
    }

    // MARK: - Reading configs

    func testReadingAMissingConfigYieldsAnEmptyDictionary() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-absent-\(UUID().uuidString).json")
        XCTAssertTrue(try AgentHookInstaller.readConfig(at: missing).isEmpty)
    }

    /// An unparseable config must throw so the caller leaves the file alone; a
    /// silent empty dictionary would let a write wipe the user's settings.
    func testReadingAnUnparseableConfigThrows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-bad-\(UUID().uuidString).json")
        try Data("{ this is not json, // with a comment".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try AgentHookInstaller.readConfig(at: url))
    }

    // MARK: - Real file install / uninstall

    /// Builds a descriptor pointing at a throwaway config so the whole file I/O
    /// path — backup, write, verify, restore — runs for real without touching
    /// anything the user owns.
    private func makeTemporaryConfig(contents: [String: Any]?) throws -> (AgentHookConfigDescriptor, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-agenttower-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("settings.json")

        if let contents {
            let data = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted])
            try data.write(to: configURL)
        }

        let real = try XCTUnwrap(AgentHookInstaller.descriptor(for: .claudeCode, includeApprovals: false))
        let descriptor = AgentHookConfigDescriptor(
            kind: real.kind,
            configURL: configURL,
            events: real.events,
            isSchemaVerified: real.isSchemaVerified
        )
        return (descriptor, directory)
    }

    func testInstallThenUninstallLeavesTheConfigByteIdentical() throws {
        let (descriptor, directory) = try makeTemporaryConfig(contents: realWorldConfig)
        defer { try? FileManager.default.removeItem(at: directory) }

        let before = try Data(contentsOf: descriptor.configURL)

        try AgentHookInstaller.writeShim()
        try AgentHookInstaller.install(descriptor: descriptor)
        XCTAssertTrue(AgentHookInstaller.isInstalled(descriptor: descriptor))

        // The user's own hooks and settings must have survived the write.
        let installed = try AgentHookInstaller.readConfig(at: descriptor.configURL)
        XCTAssertEqual(installed["theme"] as? String, "dark")
        let commands = ((installed["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]] ?? [])
            .compactMap { $0["hooks"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["command"] as? String }
        XCTAssertTrue(commands.contains("rtk hook claude"))

        try AgentHookInstaller.uninstall(descriptor: descriptor)
        XCTAssertFalse(AgentHookInstaller.isInstalled(descriptor: descriptor))

        // Compare parsed contents: the writer reformats, so bytes will differ
        // while the meaning must not.
        let restored = try AgentHookInstaller.readConfig(at: descriptor.configURL)
        let original = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: before) as? [String: Any]
        )
        XCTAssertTrue(
            NSDictionary(dictionary: restored).isEqual(to: original),
            "Uninstall must restore the config exactly."
        )
    }

    func testInstallIsIdempotentOnDisk() throws {
        let (descriptor, directory) = try makeTemporaryConfig(contents: realWorldConfig)
        defer { try? FileManager.default.removeItem(at: directory) }

        try AgentHookInstaller.writeShim()
        try AgentHookInstaller.install(descriptor: descriptor)
        let first = try AgentHookInstaller.readConfig(at: descriptor.configURL)
        try AgentHookInstaller.install(descriptor: descriptor)
        let second = try AgentHookInstaller.readConfig(at: descriptor.configURL)

        XCTAssertTrue(
            NSDictionary(dictionary: first).isEqual(to: second),
            "A second install must not accumulate entries."
        )
    }

    /// A config that does not exist yet is created; Atoll must not need the file
    /// to be there already, only the agent's directory.
    func testInstallCreatesAMissingConfigFile() throws {
        let (descriptor, directory) = try makeTemporaryConfig(contents: nil)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: descriptor.configURL.path))
        try AgentHookInstaller.writeShim()
        try AgentHookInstaller.install(descriptor: descriptor)
        XCTAssertTrue(AgentHookInstaller.isInstalled(descriptor: descriptor))
    }

    /// The most important safety property of the installer: a config it cannot
    /// parse is left exactly as it was.
    func testInstallLeavesAnUnparseableConfigUntouched() throws {
        let (descriptor, directory) = try makeTemporaryConfig(contents: nil)
        defer { try? FileManager.default.removeItem(at: directory) }

        let broken = "{ \"hooks\": { /* a comment makes this JSONC */ } }"
        try Data(broken.utf8).write(to: descriptor.configURL)

        XCTAssertThrowsError(try AgentHookInstaller.install(descriptor: descriptor))
        let after = try String(contentsOf: descriptor.configURL, encoding: .utf8)
        XCTAssertEqual(after, broken, "A config Atoll cannot parse must not be rewritten.")
    }

    /// Uninstalling when nothing is installed must not rewrite the file at all —
    /// that would bump its mtime and reformat it for no reason.
    func testUninstallDoesNotTouchAConfigWithoutAtollEntries() throws {
        let (descriptor, directory) = try makeTemporaryConfig(contents: realWorldConfig)
        defer { try? FileManager.default.removeItem(at: directory) }

        let attributes = try FileManager.default.attributesOfItem(atPath: descriptor.configURL.path)
        let before = try XCTUnwrap(attributes[.modificationDate] as? Date)
        let bytesBefore = try Data(contentsOf: descriptor.configURL)

        try AgentHookInstaller.uninstall(descriptor: descriptor)

        let after = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: descriptor.configURL.path)[.modificationDate] as? Date
        )
        XCTAssertEqual(before, after)
        XCTAssertEqual(bytesBefore, try Data(contentsOf: descriptor.configURL))
    }

    /// The shim is the safety-critical artefact: it must be executable, owned
    /// privately, and never able to block a tool call.
    func testShimIsWrittenExecutableAndFailsOpen() throws {
        try AgentHookInstaller.writeShim()
        let url = AgentTowerStorage.shimURL

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let mode = try XCTUnwrap((attributes[.posixPermissions] as? NSNumber)?.uint16Value)
        XCTAssertEqual(mode & 0o777, 0o700, "The shim must not be readable by other users.")

        let script = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(script.hasPrefix("#!/bin/sh"))
        XCTAssertFalse(script.contains("exit 2"), "Exit 2 would block the tool call.")
        XCTAssertTrue(script.contains("ATOLL_HOOKS_DISABLED"), "The env kill switch must be present.")
        XCTAssertTrue(script.contains("alive"), "The heartbeat gate must be present.")
        // Every explicit exit is a clean one.
        for line in script.split(separator: "\n") where line.contains("exit ") {
            XCTAssertTrue(line.contains("exit 0"), "Unexpected non-zero exit: \(line)")
        }
    }

    func testInstallRefusesWhenTheAgentIsNotPresent() throws {
        let fake = AgentHookConfigDescriptor(
            kind: .cursor,
            configURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("atoll-nonexistent-\(UUID().uuidString)/hooks.json"),
            events: [],
            isSchemaVerified: false
        )
        XCTAssertFalse(AgentHookInstaller.isAgentPresent(fake))
        XCTAssertThrowsError(try AgentHookInstaller.install(descriptor: fake))
    }
}
