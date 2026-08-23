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
        XCTAssertEqual(AgentEventAdapter.normalizedName(for: "beforeShellExecution"), .preToolUse)
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

    // MARK: - Context window resolution

    /// The case that forced the whole design: a live transcript recorded model
    /// `claude-opus-5` — no `[1m]` marker anywhere — while carrying 512,031
    /// tokens. A model-string rule reports 256% full; observation must win.
    func testObservationPromotesTheWindowPastTheModelTable() {
        let window = ContextWindowResolver.resolve(
            model: "claude-opus-5", observedTokens: 512_031, kind: .claudeCode
        )
        XCTAssertEqual(window.tokens, 1_000_000)
        XCTAssertEqual(window.confidence, .observed)
    }

    func testExplicitLongContextMarkerIsTrusted() {
        for model in ["claude-opus-5[1m]", "claude-sonnet-4-5-1m", "some-model:1m"] {
            let window = ContextWindowResolver.resolve(model: model, observedTokens: 10, kind: .claudeCode)
            XCTAssertEqual(window.tokens, 1_000_000, "\(model) should resolve to a 1M window")
            XCTAssertEqual(window.confidence, .table)
        }
    }

    func testKnownModelWithoutObservationUsesTheTable() {
        let window = ContextWindowResolver.resolve(
            model: "claude-opus-5", observedTokens: 50_000, kind: .claudeCode
        )
        XCTAssertEqual(window.tokens, 200_000)
        XCTAssertEqual(window.confidence, .table)
    }

    func testUnknownModelFallsBackToTheAgentDefaultAsAssumed() {
        let window = ContextWindowResolver.resolve(
            model: "something-brand-new", observedTokens: 1_000, kind: .codex
        )
        XCTAssertEqual(window.tokens, AgentKind.codex.defaultContextWindow)
        XCTAssertEqual(window.confidence, .assumed)
    }

    func testWindowIsPromotedToTheSmallestContainingTier() {
        XCTAssertEqual(
            ContextWindowResolver.resolve(model: "claude-x", observedTokens: 210_353, kind: .claudeCode).tokens,
            400_000
        )
        XCTAssertEqual(
            ContextWindowResolver.resolve(model: "claude-x", observedTokens: 400_001, kind: .claudeCode).tokens,
            1_000_000
        )
    }

    /// Past the largest known tier the observation is rounded up, so the ring
    /// stays informative instead of pinning at 100% forever.
    func testObservationBeyondEveryTierRoundsUpToWholeMillions() {
        let window = ContextWindowResolver.resolve(
            model: nil, observedTokens: 1_400_000, kind: .claudeCode
        )
        XCTAssertEqual(window.tokens, 2_000_000)
        XCTAssertEqual(window.confidence, .observed)
    }

    /// A guessed window with a small reading must not be drawn as a percentage.
    func testFractionIsHiddenWhileTheWindowIsOnlyAssumed() {
        XCTAssertFalse(ContextWindowResolver.shouldShowFraction(
            ContextWindow(tokens: 200_000, confidence: .assumed), usedTokens: 10_000
        ))
        XCTAssertTrue(ContextWindowResolver.shouldShowFraction(
            ContextWindow(tokens: 200_000, confidence: .assumed), usedTokens: 180_000
        ))
        XCTAssertTrue(ContextWindowResolver.shouldShowFraction(
            ContextWindow(tokens: 200_000, confidence: .table), usedTokens: 10
        ))
    }

    // MARK: - Transcript tail reading

    /// Mirrors the real record shape, including the `cache_creation` dictionary
    /// that sits next to the `cache_creation_input_tokens` scalar.
    private func assistantLine(
        input: Int, cacheCreation: Int, cacheRead: Int, output: Int = 1_849,
        model: String = "claude-opus-5", sidechain: Bool = false
    ) -> String {
        """
        {"type":"assistant","isSidechain":\(sidechain),"message":{"role":"assistant","model":"\(model)",\
        "usage":{"input_tokens":\(input),"cache_creation":{"ephemeral_5m_input_tokens":\(cacheCreation)},\
        "cache_creation_input_tokens":\(cacheCreation),"cache_read_input_tokens":\(cacheRead),\
        "output_tokens":\(output)}}}
        """
    }

    func testContextTokensSumMatchesTheRealTranscript() {
        let usage: [String: Any] = [
            "input_tokens": 2,
            "cache_creation_input_tokens": 558,
            "cache_read_input_tokens": 511_471,
            "output_tokens": 1_849,
            "cache_creation": ["ephemeral_5m_input_tokens": 558]
        ]
        XCTAssertEqual(AgentTranscriptReader.contextTokens(from: usage), 512_031)
    }

    func testTailReadTakesTheNewestAssistantTurnAndMetadata() throws {
        let lines = [
            assistantLine(input: 1, cacheCreation: 10, cacheRead: 1_000),
            #"{"type":"ai-title","aiTitle":"atoll-agent-tower","sessionId":"s"}"#,
            assistantLine(input: 2, cacheCreation: 558, cacheRead: 511_471),
            #"{"type":"permission-mode","permissionMode":"auto","sessionId":"s"}"#
        ]
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        let snapshot = try XCTUnwrap(AgentTranscriptReader.parseTail(data, startedMidFile: false))

        XCTAssertEqual(snapshot.contextTokens, 512_031)
        XCTAssertEqual(snapshot.model, "claude-opus-5")
        XCTAssertEqual(snapshot.title, "atoll-agent-tower")
        XCTAssertEqual(snapshot.permissionMode, "auto")
    }

    /// Subagent turns have their own context; counting one would corrupt the
    /// parent session's ring.
    func testTailReadIgnoresSidechainTurns() throws {
        let lines = [
            assistantLine(input: 2, cacheCreation: 0, cacheRead: 100_000),
            assistantLine(input: 5, cacheCreation: 0, cacheRead: 9, sidechain: true)
        ]
        let data = Data(lines.joined(separator: "\n").utf8)
        let snapshot = try XCTUnwrap(AgentTranscriptReader.parseTail(data, startedMidFile: false))
        XCTAssertEqual(snapshot.contextTokens, 100_002)
    }

    /// Reading from an arbitrary offset lands mid-line; that fragment must be
    /// discarded rather than fed to the JSON parser.
    func testTailReadDropsThePartialFirstLine() throws {
        let partial = #"{"type":"assistant","message":{"role":"assis"#
        let complete = assistantLine(input: 3, cacheCreation: 0, cacheRead: 7)
        let data = Data((partial + "\n" + complete).utf8)

        let snapshot = try XCTUnwrap(AgentTranscriptReader.parseTail(data, startedMidFile: true))
        XCTAssertEqual(snapshot.contextTokens, 10)
    }

    func testTailReadReturnsNilWithoutAnAssistantTurn() {
        let data = Data(#"{"type":"user","message":{"role":"user"}}"#.utf8)
        XCTAssertNil(AgentTranscriptReader.parseTail(data, startedMidFile: false))
    }

    func testTailReadSurvivesGarbageLines() throws {
        let lines = [
            "not json at all",
            "{ truncated",
            assistantLine(input: 1, cacheCreation: 1, cacheRead: 1)
        ]
        let data = Data(lines.joined(separator: "\n").utf8)
        let snapshot = try XCTUnwrap(AgentTranscriptReader.parseTail(data, startedMidFile: false))
        XCTAssertEqual(snapshot.contextTokens, 3)
    }

    func testReadingAMissingTranscriptReturnsNil() {
        XCTAssertNil(AgentTranscriptReader.read(path: "/nonexistent/\(UUID().uuidString).jsonl"))
        XCTAssertNil(AgentTranscriptReader.read(path: ""))
    }

    /// The tail read must agree with reading the whole file, and must actually
    /// read only the end of it.
    func testTailReadOfALargeFileMatchesTheFinalRecord() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-transcript-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }

        var text = ""
        for index in 0..<2_000 {
            text += assistantLine(input: index, cacheCreation: 0, cacheRead: 1_000) + "\n"
            text += #"{"type":"user","message":{"role":"user","content":"padding padding padding padding"}}"# + "\n"
        }
        text += assistantLine(input: 2, cacheCreation: 558, cacheRead: 511_471) + "\n"
        try Data(text.utf8).write(to: url)

        let size = try XCTUnwrap(
            (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
        )
        XCTAssertGreaterThan(size, AgentTranscriptReader.defaultTailBytes,
                             "Fixture must exceed the tail window for this test to mean anything.")

        let snapshot = try XCTUnwrap(AgentTranscriptReader.read(path: url.path))
        XCTAssertEqual(snapshot.contextTokens, 512_031)
    }

    // MARK: - Session context folding

    func testApplyingATranscriptCalibratesTheWindowAndKeepsThePeak() throws {
        let start = try XCTUnwrap(makeEvent(#"{"session_id":"s8","cwd":"/tmp/proj","hook_event_name":"SessionStart"}"#))
        var session = AgentSession(event: start)

        session.apply(AgentTranscriptSnapshot(
            contextTokens: 512_031, model: "claude-opus-5", title: "my-session", permissionMode: "auto"
        ))
        XCTAssertEqual(session.contextTokens, 512_031)
        XCTAssertEqual(session.contextWindow, 1_000_000)
        XCTAssertEqual(session.contextWindowConfidence, .observed)
        XCTAssertEqual(session.title, "my-session", "The agent's own title should beat the directory name.")
        XCTAssertEqual(session.permissionMode, "auto")

        // A compaction collapses the live count; the window must not shrink with it.
        session.apply(AgentTranscriptSnapshot(
            contextTokens: 40_000, model: "claude-opus-5", title: nil, permissionMode: nil
        ))
        XCTAssertEqual(session.contextTokens, 40_000)
        XCTAssertEqual(session.observedMaxContextTokens, 512_031)
        XCTAssertEqual(session.contextWindow, 1_000_000, "Window calibration must survive a compaction.")
        XCTAssertEqual(session.title, "my-session", "A snapshot without a title must not clear one.")
    }

    func testCompactTokenFormatting() {
        XCTAssertEqual(AgentContextRing.compactTokens(512_031), "512k")
        XCTAssertEqual(AgentContextRing.compactTokens(1_000_000), "1M")
        XCTAssertEqual(AgentContextRing.compactTokens(1_500_000), "1.5M")
        XCTAssertEqual(AgentContextRing.compactTokens(940), "940")
    }

    // MARK: - Shell lexing

    func testLexerSplitsOnEverySeparator() {
        let result = ShellCommandLexer.lex("cd /tmp && ls -la; echo done || true")
        XCTAssertEqual(result.commands.map(\.program), ["cd", "ls", "echo", "true"])
        XCTAssertFalse(result.commands.contains { $0.isPipeTarget })
    }

    func testLexerMarksPipeTargetsButNotOrOperands() {
        let piped = ShellCommandLexer.lex("cat f | grep x | wc -l")
        XCTAssertEqual(piped.commands.map(\.isPipeTarget), [false, true, true])

        let ored = ShellCommandLexer.lex("false || echo fallback")
        XCTAssertEqual(ored.commands.map(\.isPipeTarget), [false, false])
    }

    func testLexerStripsQuotesAndRemembersThemBeingThere() {
        let result = ShellCommandLexer.lex(#"echo "rm -rf /" 'literal $HOME'"#)
        XCTAssertEqual(result.commands.count, 1)
        XCTAssertEqual(result.commands[0].program, "echo")
        XCTAssertEqual(result.commands[0].arguments, ["rm -rf /", "literal $HOME"])
        XCTAssertTrue(result.commands[0].hadQuotedWord)
    }

    func testLexerIgnoresComments() {
        let result = ShellCommandLexer.lex("ls -la # rm -rf /\necho ok")
        XCTAssertEqual(result.commands.map(\.program), ["ls", "echo"])
    }

    func testLexerSkipsLeadingEnvironmentAssignments() {
        let result = ShellCommandLexer.lex("FOO=1 BAR=2 /bin/rm -rf build")
        XCTAssertEqual(result.commands[0].program, "rm", "The path should be stripped and assignments skipped.")
        XCTAssertEqual(result.commands[0].arguments, ["-rf", "build"])
    }

    func testLexerNotesEvalAndEncodedPayloadsButNotPlainSubstitution() {
        XCTAssertTrue(ShellCommandLexer.lex(#"eval "$CMD""#).obfuscation.hasEval)
        XCTAssertTrue(ShellCommandLexer.lex("base64 -d payload | sh").obfuscation.hasEncodedPayload)
        // Command substitution is recorded but, being ubiquitous, is not a flag.
        XCTAssertTrue(ShellCommandLexer.lex("echo $(git rev-parse HEAD)").obfuscation.hasCommandSubstitution)
    }

    // MARK: - Destructive command classification

    private func risk(_ command: String, cwd: String? = "/Users/x/Project") -> DestructiveRisk {
        DestructiveCommandClassifier.highestRisk(
            in: DestructiveCommandClassifier.evaluate(command: command, cwd: cwd)
        )
    }

    /// The tests that matter most: a classifier that cries wolf gets ignored, and
    /// then the real warnings are worthless too.
    func testOrdinaryCommandsAreNotFlagged() {
        let harmless = [
            "ls -la",
            "git status",
            "git commit -m 'wip'",
            "git push origin feature/x",
            #"echo "rm -rf /""#,
            "# rm -rf /",
            "ls -la # rm -rf /",
            "echo hello | grep h",
            "cat notes.txt | wc -l",
            "chmod 644 file.txt",
            "chmod +x script.sh",
            "npm install",
            "npm run build",
            "swift build",
            "xcodebuild test -scheme App",
            "echo $(git rev-parse HEAD)",
            "grep -r 'sudo' .",
            "find . -name '*.swift'",
            "mv old.txt new.txt",
            "kubectl get pods",
            "terraform plan"
        ]
        for command in harmless {
            XCTAssertEqual(risk(command), .none, "Should not be flagged: \(command)")
        }
    }

    func testRootDeletionIsHighRisk() {
        for command in ["rm -rf /", "rm -fr /", "rm -r -f /", "rm --recursive --force /",
                        "rm -rf ~", "rm -rf $HOME", "rm -rf /Users/x", "rm -rf /*",
                        "rm -rf /System", "rm -rf '/'"] {
            XCTAssertEqual(risk(command), .high, "Should be high risk: \(command)")
        }
    }

    /// Deleting inside the project is routine build cleanup, not an emergency.
    func testProjectLocalRecursiveDeleteIsOnlyMediumRisk() {
        XCTAssertEqual(risk("rm -rf ./build"), .medium)
        XCTAssertEqual(risk("rm -rf build/Debug"), .medium)
        XCTAssertEqual(risk("rm -rf /tmp/scratch"), .medium, "Temp space is not the user's work.")
    }

    func testDeletingOutsideTheProjectEscalates() {
        XCTAssertEqual(risk("rm -rf ../other-project", cwd: "/Users/x/Project"), .high)
        XCTAssertEqual(risk("rm -rf /Users/x/Documents/notes", cwd: "/Users/x/Project"), .high)
    }

    func testPrivilegeEscalationIsHighRisk() {
        XCTAssertEqual(risk("sudo make install"), .high)
        XCTAssertEqual(risk("cd /tmp && sudo rm -rf cache"), .high)
    }

    func testPipeToShellIsHighRiskButAPlainPipeIsNot() {
        XCTAssertEqual(risk("curl -sL https://example.com/i.sh | sh"), .high)
        XCTAssertEqual(risk("wget -qO- https://example.com/i.sh | bash"), .high)
        XCTAssertEqual(risk("curl -s https://example.com/x.py | python3"), .high)
        XCTAssertEqual(risk("curl -s https://example.com/data.json | jq ."), .none,
                       "Downloading and formatting is not executing.")
    }

    func testForkBombIsDetectedDespiteItsSyntax() {
        XCTAssertEqual(risk(":(){ :|:& };:"), .high)
        XCTAssertEqual(risk(":(){:|:&};:"), .high)
    }

    func testWorldWritablePermissionsAreHighRisk() {
        XCTAssertEqual(risk("chmod 777 ."), .high)
        XCTAssertEqual(risk("chmod -R 0777 /"), .high)
        XCTAssertEqual(risk("chmod a+w secrets"), .high)
        XCTAssertEqual(risk("chmod -R 755 scripts"), .medium, "Recursive but not world-writable.")
    }

    func testGitForcePushGradations() {
        XCTAssertEqual(risk("git push --force origin main"), .high)
        XCTAssertEqual(risk("git push -f"), .high)
        XCTAssertEqual(risk("git push origin +main:main"), .high)
        XCTAssertEqual(risk("git push --force-with-lease origin main"), .medium,
                       "A lease refuses when someone else has pushed, so it is materially safer.")
        XCTAssertEqual(risk("git reset --hard HEAD~1"), .medium)
        XCTAssertEqual(risk("git clean -fdx"), .medium)
        XCTAssertEqual(risk("git filter-branch --all"), .high)
    }

    func testDiskAndFilesystemOperations() {
        XCTAssertEqual(risk("dd if=/dev/zero of=/dev/disk2"), .high)
        XCTAssertEqual(risk("mkfs.ext4 /dev/sdb1"), .high)
        XCTAssertEqual(risk("diskutil eraseDisk JHFS+ Blank /dev/disk3"), .high)
        XCTAssertEqual(risk("shred -u secret.key"), .high)
    }

    func testKeychainAndPrivacyResetsAreHighRisk() {
        XCTAssertEqual(risk("security delete-keychain login.keychain"), .high)
        XCTAssertEqual(risk("tccutil reset ScreenCapture"), .high)
    }

    func testOutwardFacingOperationsAreHighRisk() {
        XCTAssertEqual(risk("npm publish"), .high)
        XCTAssertEqual(risk("gh release delete v1.0.0"), .high)
        XCTAssertEqual(risk("aws s3 rm s3://bucket --recursive"), .high)
        XCTAssertEqual(risk("terraform destroy -auto-approve"), .high)
        XCTAssertEqual(risk("terraform destroy"), .medium)
        XCTAssertEqual(risk("kubectl delete namespace prod"), .high)
    }

    func testFindDeleteScope() {
        XCTAssertEqual(risk("find . -name '*.tmp' -delete"), .medium)
        XCTAssertEqual(risk("find / -name '*.log' -delete"), .high)
        XCTAssertEqual(risk("find . -name '*.o' -exec rm {} ;"), .medium)
    }

    func testObfuscationIsFlaggedWithoutFlaggingEverySubstitution() {
        XCTAssertEqual(risk(#"eval "$(printf '\x72\x6d')""#), .medium)
        XCTAssertEqual(risk("echo dm0= | base64 -d | sh"), .high, "Decoded and piped into a shell.")
        XCTAssertEqual(risk("VERSION=$(git describe --tags) && echo $VERSION"), .none)
    }

    /// Chained commands must be judged individually, not as one blob of text.
    func testChainedCommandsAreEachClassified() {
        XCTAssertEqual(risk("cd /tmp && rm -rf *"), .high)
        XCTAssertEqual(risk("npm test; git push --force"), .high)
        XCTAssertEqual(risk("swift build && echo ok"), .none)
    }

    func testFlagsCarryHumanReadableReasonsAndAreSortedWorstFirst() {
        let flags = DestructiveCommandClassifier.evaluate(command: "sudo rm -rf /", cwd: nil)
        XCTAssertFalse(flags.isEmpty)
        XCTAssertEqual(flags.first?.risk, .high)
        for flag in flags {
            XCTAssertFalse(flag.summary.isEmpty, "Every flag needs a reason the user can read.")
            XCTAssertFalse(flag.id.isEmpty)
        }
        // Sorted worst-first so the card can show the headline reason.
        XCTAssertEqual(flags.map(\.risk), flags.map(\.risk).sorted(by: >))
    }

    func testDuplicateReasonsAreCollapsed() {
        let flags = DestructiveCommandClassifier.evaluate(command: "sudo ls && sudo cat /etc/hosts", cwd: nil)
        XCTAssertEqual(flags.filter { $0.id == "sudo" }.count, 1)
    }

    // MARK: - Decision encoding

    private func makeRequest(
        id: String = "req-1",
        kind: AgentKind = .claudeCode,
        event: String = "PreToolUse",
        tool: String? = "Bash",
        detail: AgentRequestDetail = .shellCommand("ls -la"),
        cwd: String? = "/Users/x/Project",
        session: String = "claudeCode:s1"
    ) -> AgentPendingRequest {
        let flags = DestructiveCommandClassifier.evaluate(command: detail.subject, cwd: cwd)
        return AgentPendingRequest(
            id: id, sessionID: session, kind: kind, rawEventName: event, toolName: tool,
            detail: detail, riskFlags: flags,
            receivedAt: Date(timeIntervalSince1970: 0),
            expiresAt: Date(timeIntervalSince1970: 295)
        )
    }

    private func decode(_ data: Data) -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func testAllowEncodesClaudeHookSpecificOutput() throws {
        let request = makeRequest()
        let root = try XCTUnwrap(decode(AgentDecisionEncoder.encode(.allowOnce, for: request)))
        let output = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["hookEventName"] as? String, "PreToolUse")
        XCTAssertEqual(output["permissionDecision"] as? String, "allow")
        XCTAssertFalse((output["permissionDecisionReason"] as? String ?? "").isEmpty)
    }

    func testDenyCarriesTheUsersNoteAsTheReason() throws {
        let request = makeRequest()
        let root = try XCTUnwrap(decode(AgentDecisionEncoder.encode(.deny(reason: "use --dry-run first"), for: request)))
        let output = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["permissionDecision"] as? String, "deny")
        XCTAssertEqual(output["permissionDecisionReason"] as? String, "use --dry-run first")
    }

    /// The invariant the whole fail-open story rests on: Atoll's silence is
    /// byte-identical to Atoll being absent.
    func testNoDecisionEncodesToZeroBytes() {
        let request = makeRequest()
        XCTAssertTrue(AgentDecisionEncoder.encode(.noDecision, for: request).isEmpty)
        XCTAssertNil(AgentDecisionEncoder.payload(for: .noDecision, request: request))
    }

    /// An "ask" reply would make Atoll's silence depend on the agent honouring a
    /// field; empty output does not.
    func testNoDecisionNeverEmitsAnAskField() {
        let data = AgentDecisionEncoder.encode(.noDecision, for: makeRequest())
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("ask"))
    }

    func testEventNameIsEchoedBackVerbatim() throws {
        let request = makeRequest(event: "PermissionRequest")
        let root = try XCTUnwrap(decode(AgentDecisionEncoder.encode(.allowOnce, for: request)))
        let output = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(output["hookEventName"] as? String, "PermissionRequest")
    }

    func testCursorUsesItsOwnReplyShape() throws {
        let request = makeRequest(kind: .cursor, event: "beforeShellExecution")
        let allow = try XCTUnwrap(decode(AgentDecisionEncoder.encode(.allowOnce, for: request)))
        XCTAssertEqual(allow["permission"] as? String, "allow")
        XCTAssertNil(allow["hookSpecificOutput"])

        let deny = try XCTUnwrap(decode(AgentDecisionEncoder.encode(.deny(reason: "no"), for: request)))
        XCTAssertEqual(deny["permission"] as? String, "deny")
    }

    /// An agent Atoll cannot configure must never receive a decision.
    func testUnsupportedAgentGetsNoDecision() {
        let request = makeRequest(kind: .opencode)
        XCTAssertTrue(AgentDecisionEncoder.encode(.allowOnce, for: request).isEmpty)
    }

    func testAllowVariantsAllEncodeAsAllow() throws {
        for decision in [AgentDecision.allowOnce, .allowForSession, .alwaysAllow] {
            let root = try XCTUnwrap(decode(AgentDecisionEncoder.encode(decision, for: makeRequest())))
            let output = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
            XCTAssertEqual(output["permissionDecision"] as? String, "allow", "\(decision)")
        }
    }

    // MARK: - Approval rules

    private func makeRuleStore() -> (AgentApprovalRuleStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-rules-\(UUID().uuidString).json")
        return (AgentApprovalRuleStore(fileURL: url), url)
    }

    func testSessionRuleMatchesOnlyItsOwnSession() {
        let (store, url) = makeRuleStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let request = makeRequest(detail: .shellCommand("npm test"))
        XCTAssertNil(store.match(request, cwd: "/Users/x/Project"))

        store.record(.allowForSession, for: request, cwd: "/Users/x/Project")
        XCTAssertNotNil(store.match(request, cwd: "/Users/x/Project"))

        let otherSession = makeRequest(detail: .shellCommand("npm test"), session: "claudeCode:s2")
        XCTAssertNil(store.match(otherSession, cwd: "/Users/x/Project"),
                     "A session rule must not leak into another session.")
    }

    /// Exact matching is the point: a near-miss must ask again.
    func testRuleMatchingIsExactNotPrefixed() {
        let (store, url) = makeRuleStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let approved = makeRequest(detail: .shellCommand("git push origin main"))
        store.record(.allowForSession, for: approved, cwd: "/Users/x/Project")

        let escalated = makeRequest(detail: .shellCommand("git push origin main --force"))
        XCTAssertNil(store.match(escalated, cwd: "/Users/x/Project"),
                     "A rule for `git push` must not cover `git push --force`.")

        let chained = makeRequest(detail: .shellCommand("git push origin main && rm -rf ~"))
        XCTAssertNil(store.match(chained, cwd: "/Users/x/Project"))
    }

    /// Re-indentation should not defeat a rule, but nothing else is normalised.
    func testFingerprintCollapsesWhitespaceOnly() {
        let spaced = makeRequest(detail: .shellCommand("npm   run    build"))
        let tight = makeRequest(detail: .shellCommand("npm run build"))
        XCTAssertEqual(AgentApprovalRule.fingerprint(for: spaced), AgentApprovalRule.fingerprint(for: tight))

        let differentCase = makeRequest(detail: .shellCommand("NPM run build"))
        XCTAssertNotEqual(
            AgentApprovalRule.fingerprint(for: tight),
            AgentApprovalRule.fingerprint(for: differentCase),
            "Case matters in a shell; folding it would be wrong."
        )
    }

    /// The single most important rule-store property.
    func testNoRuleCanEverAutoApproveAHighRiskCommand() {
        let (store, url) = makeRuleStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let dangerous = makeRequest(detail: .shellCommand("rm -rf /"))
        XCTAssertEqual(dangerous.risk, .high)
        XCTAssertFalse(dangerous.allowsPersistentRule)

        // Even if a rule is somehow requested, it is refused …
        XCTAssertNil(store.record(.alwaysAllow, for: dangerous, cwd: "/Users/x/Project"))
        XCTAssertNil(store.record(.allowForSession, for: dangerous, cwd: "/Users/x/Project"))
        // … and matching refuses independently of what is stored.
        XCTAssertNil(store.match(dangerous, cwd: "/Users/x/Project"))
    }

    func testProjectRuleIsScopedToItsDirectoryAndExpires() {
        let (store, url) = makeRuleStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let request = makeRequest(detail: .shellCommand("swift build"))
        let now = Date(timeIntervalSince1970: 1_000)
        let rule = store.record(.alwaysAllow, for: request, cwd: "/Users/x/Project", now: now)
        XCTAssertNotNil(rule)

        XCTAssertNotNil(store.match(request, cwd: "/Users/x/Project", now: now))
        XCTAssertNil(store.match(request, cwd: "/Users/x/Other"),
                     "A project rule must not apply to a different directory.")

        let afterExpiry = now.addingTimeInterval(AgentApprovalRuleStore.projectRuleLifetime + 1)
        XCTAssertNil(store.match(request, cwd: "/Users/x/Project", now: afterExpiry))
    }

    func testOnlyProjectRulesSurviveAReload() {
        let (store, url) = makeRuleStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let request = makeRequest(detail: .shellCommand("swift test"))
        store.record(.allowForSession, for: request, cwd: "/Users/x/Project")
        store.record(.alwaysAllow, for: makeRequest(detail: .shellCommand("swift build")), cwd: "/Users/x/Project")
        XCTAssertEqual(store.allRules.count, 2)

        let reloaded = AgentApprovalRuleStore(fileURL: url)
        XCTAssertEqual(reloaded.allRules.count, 1, "A session rule must not outlive the process.")
        if case .project = reloaded.allRules[0].scope {} else {
            XCTFail("The surviving rule should be project-scoped.")
        }
    }

    func testRecordingIgnoresDecisionsThatAreNotRules() {
        let (store, url) = makeRuleStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let request = makeRequest(detail: .shellCommand("ls"))
        XCTAssertNil(store.record(.allowOnce, for: request, cwd: "/Users/x/Project"))
        XCTAssertNil(store.record(.deny(reason: nil), for: request, cwd: "/Users/x/Project"))
        XCTAssertNil(store.record(.noDecision, for: request, cwd: "/Users/x/Project"))
        XCTAssertTrue(store.allRules.isEmpty)
    }

    func testRecordingTheSameApprovalTwiceDoesNotDuplicate() {
        let (store, url) = makeRuleStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let request = makeRequest(detail: .shellCommand("make"))
        store.record(.allowForSession, for: request, cwd: "/Users/x/Project")
        store.record(.allowForSession, for: request, cwd: "/Users/x/Project")
        XCTAssertEqual(store.allRules.count, 1)
    }

    func testPruningDropsRulesForSessionsThatHaveGone() {
        let (store, url) = makeRuleStore()
        defer { try? FileManager.default.removeItem(at: url) }

        let request = makeRequest(detail: .shellCommand("ls -la"))
        store.record(.allowForSession, for: request, cwd: "/Users/x/Project")
        XCTAssertEqual(store.allRules.count, 1)

        store.prune(liveSessionIDs: ["claudeCode:s1"])
        XCTAssertEqual(store.allRules.count, 1, "Its session is still live.")

        store.prune(liveSessionIDs: [])
        XCTAssertTrue(store.allRules.isEmpty)
    }

    // MARK: - Pending request presentation

    func testPersistentRulesAreOfferedOnlyBelowHighRisk() {
        XCTAssertTrue(makeRequest(detail: .shellCommand("npm run build")).allowsPersistentRule)
        XCTAssertTrue(makeRequest(detail: .shellCommand("rm -rf ./build")).allowsPersistentRule)
        XCTAssertFalse(makeRequest(detail: .shellCommand("sudo rm -rf /")).allowsPersistentRule)
    }

    func testRequestDetailSubjectsAndLabels() {
        XCTAssertEqual(makeRequest(detail: .shellCommand("ls")).detail.subject, "ls")
        XCTAssertEqual(makeRequest(detail: .fileEdit(path: "/a/b.swift", preview: nil)).detail.subject, "/a/b.swift")
        XCTAssertEqual(makeRequest(event: "PreToolUse", tool: nil).toolLabel, "PreToolUse")
        XCTAssertEqual(makeRequest(tool: "Edit").toolLabel, "Edit")
    }

    // MARK: - Escalation ladder

    func testDefaultLadderMatchesTheIntendedCadence() {
        XCTAssertEqual(AgentEscalationSchedule.defaultSteps, [0, 8, 60, 300, 900])
    }

    /// The deltas are what the reminder task actually sleeps, so an off-by-one
    /// here would either double-fire or skip a rung.
    func testDeltasAreTheGapsBetweenSteps() {
        XCTAssertEqual(AgentEscalationSchedule.deltas(for: [0, 8, 60, 300, 900]), [0, 8, 52, 240, 600])
        XCTAssertEqual(AgentEscalationSchedule.deltas(for: [5]), [5])
        XCTAssertEqual(AgentEscalationSchedule.deltas(for: []), [])
    }

    /// The steps are configurable, so a hostile or careless list must not produce
    /// a negative sleep or fire out of order.
    func testStepsAreNormalisedBeforeUse() {
        XCTAssertEqual(AgentEscalationSchedule.normalized([60, 0, 8]), [0, 8, 60])
        XCTAssertEqual(AgentEscalationSchedule.normalized([-5, 0, 10]), [0, 10])
        XCTAssertEqual(AgentEscalationSchedule.normalized([8, 8, 8]), [8])
        // And therefore no delta is ever negative.
        for delta in AgentEscalationSchedule.deltas(for: [900, 60, -1, 8, 0]) {
            XCTAssertGreaterThanOrEqual(delta, 0)
        }
    }

    func testDueCountGrowsWithElapsedTime() {
        XCTAssertEqual(AgentEscalationSchedule.dueCount(elapsed: 0), 1)
        XCTAssertEqual(AgentEscalationSchedule.dueCount(elapsed: 7), 1)
        XCTAssertEqual(AgentEscalationSchedule.dueCount(elapsed: 8), 2)
        XCTAssertEqual(AgentEscalationSchedule.dueCount(elapsed: 301), 4)
        XCTAssertEqual(AgentEscalationSchedule.dueCount(elapsed: 5_000), 5)
    }

    func testDelayUntilNextWalksTheLadderThenStops() {
        XCTAssertEqual(AgentEscalationSchedule.delayUntilNext(elapsed: 0, firedCount: 0), 0)
        XCTAssertEqual(AgentEscalationSchedule.delayUntilNext(elapsed: 0, firedCount: 1), 8)
        XCTAssertEqual(AgentEscalationSchedule.delayUntilNext(elapsed: 30, firedCount: 2), 30)
        XCTAssertNil(AgentEscalationSchedule.delayUntilNext(elapsed: 0, firedCount: 5),
                     "The ladder must end rather than repeat forever.")
        XCTAssertNil(AgentEscalationSchedule.delayUntilNext(elapsed: 0, firedCount: -1))
    }

    /// A reminder whose moment has already passed is due now, never overdue by a
    /// negative amount.
    func testDelayIsNeverNegative() {
        XCTAssertEqual(AgentEscalationSchedule.delayUntilNext(elapsed: 1_000, firedCount: 1), 0)
    }

    /// Privacy mode silences the nudge but must not hide the request — the user
    /// asked not to be interrupted, not to be kept in the dark.
    func testRemindersAreSuppressedByPrivacyModeAndFocus() {
        XCTAssertFalse(AgentEscalationSchedule.shouldSuppressReminder(privacyMode: false, doNotDisturbActive: false))
        XCTAssertTrue(AgentEscalationSchedule.shouldSuppressReminder(privacyMode: true, doNotDisturbActive: false))
        XCTAssertTrue(AgentEscalationSchedule.shouldSuppressReminder(privacyMode: false, doNotDisturbActive: true))
    }

    // MARK: - Terminal identification and jump

    /// `TERM_PROGRAM` is set by the terminal itself, so it wins over a bundle
    /// identifier that may describe a wrapper.
    func testTerminalProgramIsPreferredOverBundleIdentifier() {
        XCTAssertEqual(
            TerminalJumpService.host(termProgram: "Apple_Terminal", bundleID: "com.googlecode.iterm2"),
            .appleTerminal
        )
        XCTAssertEqual(
            TerminalJumpService.host(termProgram: "iTerm.app", bundleID: "com.apple.Terminal"),
            .iTerm2
        )
    }

    func testTerminalProgramMatchingIsCaseInsensitive() {
        XCTAssertEqual(TerminalJumpService.host(termProgram: "apple_terminal", bundleID: nil), .appleTerminal)
        XCTAssertEqual(TerminalJumpService.host(termProgram: "ITERM.APP", bundleID: nil), .iTerm2)
    }

    func testBundleIdentifierIsTheFallback() {
        XCTAssertEqual(TerminalJumpService.host(termProgram: nil, bundleID: "com.apple.Terminal"), .appleTerminal)
        XCTAssertEqual(TerminalJumpService.host(termProgram: nil, bundleID: "com.googlecode.iterm2"), .iTerm2)
    }

    /// A terminal Atoll cannot script is still recognised, so the fallback can
    /// raise the right application rather than giving up.
    func testUnscriptableTerminalsAreRecognisedButNotAddressable() {
        for bundleID in ["com.mitchellh.ghostty", "dev.warp.Warp-Stable",
                         "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm"] {
            let host = TerminalJumpService.host(termProgram: nil, bundleID: bundleID)
            XCTAssertEqual(host, .unaddressable(bundleID: bundleID.lowercased()), bundleID)
            XCTAssertFalse(host.supportsTabSelection, "\(bundleID) has no per-tab addressing.")
        }
    }

    func testNoInformationAtAllIsUnknown() {
        let host = TerminalJumpService.host(termProgram: nil, bundleID: nil)
        XCTAssertEqual(host, .unknown)
        XCTAssertFalse(host.supportsTabSelection)
    }

    func testOnlyScriptableTerminalsClaimTabSelection() {
        XCTAssertTrue(TerminalHost.appleTerminal.supportsTabSelection)
        XCTAssertTrue(TerminalHost.iTerm2.supportsTabSelection)
        XCTAssertFalse(TerminalHost.unaddressable(bundleID: "x").supportsTabSelection)
        XCTAssertFalse(TerminalHost.unknown.supportsTabSelection)
    }

    /// The scripts must key on tty, not on a window title: titles collide as soon
    /// as two agents run in the same project, which is when this matters most.
    func testGeneratedScriptsMatchOnTtyAndReportAKnownResult() {
        let terminal = TerminalJumpService.appleTerminalScript(tty: "/dev/ttys004")
        XCTAssertTrue(terminal.contains("tty of t is \"/dev/ttys004\""))
        XCTAssertTrue(terminal.contains("return \"ok\""))
        XCTAssertTrue(terminal.contains("return \"notfound\""))
        XCTAssertFalse(terminal.contains("custom title"), "Title matching is not reliable enough.")

        let iterm = TerminalJumpService.iTerm2Script(tty: "/dev/ttys009")
        XCTAssertTrue(iterm.contains("tty of s is \"/dev/ttys009\""),
                      "iTerm2 exposes tty on a session, one level below the tab.")
        XCTAssertTrue(iterm.contains("sessions of t"))
        XCTAssertTrue(iterm.contains("return \"ok\""))
    }

    /// A missing tab must not abort the whole script — `try` blocks keep the loop
    /// going so a later tab can still match.
    func testScriptsToleratePerTabErrors() {
        XCTAssertTrue(TerminalJumpService.appleTerminalScript(tty: "/dev/ttys1").contains("try"))
        XCTAssertTrue(TerminalJumpService.iTerm2Script(tty: "/dev/ttys1").contains("try"))
    }

    // MARK: - Process tree

    /// Reads the real process table for this test host, which is the only honest
    /// way to check the sysctl plumbing.
    func testProcessTreeReadsThisProcessAndItsAncestors() throws {
        let me = getpid()
        let ancestors = ProcessTree.ancestors(of: me)
        XCTAssertEqual(ancestors.first, me, "The walk starts at the pid it was given.")
        XCTAssertEqual(Set(ancestors).count, ancestors.count, "The walk must not revisit a pid.")
        // The chain stops before `launchd`, so a process parented directly by it
        // yields exactly one entry — which is what the test host does.
        XCTAssertFalse(ancestors.contains(1))

        let parent = try XCTUnwrap(ProcessTree.parent(of: me))
        XCTAssertEqual(parent, getppid())
    }

    func testProcessTreeIsDepthCapped() {
        XCTAssertLessThanOrEqual(ProcessTree.ancestors(of: getpid(), limit: 3).count, 3)
    }

    func testProcessTreeReturnsNilForAProcessThatDoesNotExist() {
        // pid 0 is the kernel and has no parent; a huge pid does not exist.
        XCTAssertNil(ProcessTree.parent(of: 999_999))
        XCTAssertNil(ProcessTree.ttyPath(for: 999_999))
        XCTAssertTrue(ProcessTree.ancestors(of: 0).isEmpty)
    }

    /// The test host has no controlling terminal, so this exercises the
    /// no-tty path rather than asserting a device exists.
    func testTtyPathIsEitherADeviceOrNil() {
        if let tty = ProcessTree.ttyPath(for: getpid()) {
            XCTAssertTrue(tty.hasPrefix("/dev/"), "Got \(tty)")
        }
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

    /// Writes a request the way the shim does: into a `.tmp`, permissions set,
    /// then renamed into place. Writing the final name first and chmod-ing after
    /// races the directory watcher, which correctly discards a world-readable
    /// request.
    private func stageRequest(_ envelope: String, id: String) throws {
        let inbox = AgentTowerStorage.inboxDirectory
        let temporary = inbox.appendingPathComponent("\(id).json.tmp")
        let final = inbox.appendingPathComponent("\(id).json")
        try Data(envelope.utf8).write(to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try FileManager.default.moveItem(at: temporary, to: final)
    }

    // MARK: - Spool transport, end to end

    /// Drives the real spool with real files: a request appears, the handler is
    /// called, and a blocked shim would find the decision behind its sentinel.
    ///
    /// Covers the seam the pure tests cannot — that `out/<id>.json` is only
    /// readable once `out/<id>.done` exists.
    func testSpoolDeliversARequestAndPublishesTheDecision() throws {
        let spool = AgentHookSpool()
        let received = XCTestExpectation(description: "handler called")
        let body = Data(#"{"hookSpecificOutput":{"permissionDecision":"deny"}}"#.utf8)

        var seenEvent: String?
        XCTAssertTrue(spool.start { envelope in
            seenEvent = envelope.event
            received.fulfill()
            return body
        }, "The spool should arm in a private temp directory.")
        defer { spool.stop() }

        let requestID = "1700000000-1-abcdef"
        let envelope = """
        {"v":\(AgentHookSpool.protocolVersion),"id":"\(requestID)","event":"PreToolUse",\
        "agent":"claudeCode","wait":true,"pid":123,"term":"Apple_Terminal","termbid":"com.apple.Terminal",\
        "payload":{"session_id":"s1","hook_event_name":"PreToolUse","tool_name":"Bash",\
        "tool_input":{"command":"rm -rf /"}}}
        """
        try stageRequest(envelope, id: requestID)
        let requestURL = AgentTowerStorage.inboxDirectory.appendingPathComponent("\(requestID).json")

        wait(for: [received], timeout: 10)
        XCTAssertEqual(seenEvent, "PreToolUse")

        // The sentinel is what a waiting shim polls for.
        let doneURL = AgentTowerStorage.outboxDirectory.appendingPathComponent("\(requestID).done")
        let bodyURL = AgentTowerStorage.outboxDirectory.appendingPathComponent("\(requestID).json")
        let deadline = Date().addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: doneURL.path), Date() < deadline {
            usleep(50_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: doneURL.path), "No sentinel was published.")
        XCTAssertEqual(try Data(contentsOf: bodyURL), body)

        // The request is consumed, so a restart does not re-ask.
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestURL.path))
    }

    /// An observe-only request is consumed without anything being written back —
    /// the shim is not waiting, so a reply would be pointless work.
    func testSpoolWritesNoResponseForAnObserveOnlyRequest() throws {
        let spool = AgentHookSpool()
        let received = XCTestExpectation(description: "handler called")

        XCTAssertTrue(spool.start { _ in
            received.fulfill()
            return nil
        })
        defer { spool.stop() }

        let requestID = "1700000000-2-beefbeef"
        let envelope = """
        {"v":\(AgentHookSpool.protocolVersion),"id":"\(requestID)","event":"Stop",\
        "agent":"claudeCode","wait":false,"payload":{"session_id":"s1","hook_event_name":"Stop"}}
        """
        try stageRequest(envelope, id: requestID)

        wait(for: [received], timeout: 10)
        usleep(300_000)
        let outbox = try FileManager.default.contentsOfDirectory(atPath: AgentTowerStorage.outboxDirectory.path)
        XCTAssertTrue(outbox.isEmpty, "Nothing should be written for a request nobody is waiting on.")
    }

    /// Stopping removes the heartbeat, which is how a blocked shim learns to give
    /// up instead of waiting out its timeout.
    func testStoppingTheSpoolRemovesTheHeartbeat() {
        let spool = AgentHookSpool()
        XCTAssertTrue(spool.start { _ in nil })
        XCTAssertTrue(FileManager.default.fileExists(atPath: AgentTowerStorage.heartbeatURL.path))

        spool.stop()
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: AgentTowerStorage.heartbeatURL.path),
            "A stale heartbeat would leave shims waiting on an Atoll that is gone."
        )
    }

    /// A second decision for the same request must not overwrite the first.
    func testOnlyTheFirstDecisionForARequestIsPublished() throws {
        let spool = AgentHookSpool()
        XCTAssertTrue(spool.start { _ in nil })
        defer { spool.stop() }

        let requestID = "1700000000-3-cafecafe"
        spool.respond(to: requestID, body: Data("first".utf8))
        spool.respond(to: requestID, body: Data("second".utf8))

        let bodyURL = AgentTowerStorage.outboxDirectory.appendingPathComponent("\(requestID).json")
        XCTAssertEqual(try String(contentsOf: bodyURL, encoding: .utf8), "first")
    }

    func testSpoolRefusesAnUnsafeRequestIdentifier() throws {
        let spool = AgentHookSpool()
        XCTAssertTrue(spool.start { _ in nil })
        defer { spool.stop() }

        spool.respond(to: "../escaped", body: Data("nope".utf8))
        let outbox = try FileManager.default.contentsOfDirectory(atPath: AgentTowerStorage.outboxDirectory.path)
        XCTAssertTrue(outbox.isEmpty)
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

    /// Each agent's verification level must reflect what has actually been
    /// observed, not what would be convenient to claim.
    func testVerificationLevelsMatchWhatIsActuallyKnown() throws {
        let claude = try XCTUnwrap(AgentHookInstaller.descriptor(for: .claudeCode, includeApprovals: false))
        XCTAssertEqual(claude.verification, .verified)

        let codex = try XCTUnwrap(AgentHookInstaller.descriptor(for: .codex, includeApprovals: false))
        XCTAssertEqual(codex.verification, .schemaOnly,
                       "Codex's config shape is confirmed; acting on a decision is not.")

        for kind in [AgentKind.cursor, .geminiCLI, .qwenCode] {
            let descriptor = try XCTUnwrap(AgentHookInstaller.descriptor(for: kind, includeApprovals: false))
            XCTAssertEqual(descriptor.verification, .unverified, "\(kind.displayName)")
        }
    }

    /// A real `~/.codex/hooks.json` carries no `Notification` event, so Atoll must
    /// not introduce a key the agent may reject.
    func testCodexDoesNotRegisterNotification() throws {
        let codex = try XCTUnwrap(AgentHookInstaller.descriptor(for: .codex, includeApprovals: false))
        XCTAssertFalse(codex.events.contains { $0.wireName == "Notification" })

        let claude = try XCTUnwrap(AgentHookInstaller.descriptor(for: .claudeCode, includeApprovals: false))
        XCTAssertTrue(claude.events.contains { $0.wireName == "Notification" },
                      "Claude Code's own config does carry it.")
    }

    /// Every event Atoll registers for any agent must be one seen in a real
    /// config; an unknown key risks failing that agent's settings validation.
    func testOnlyEventNamesSeenInRealConfigsAreRegistered() {
        let observed: Set<String> = [
            "SessionStart", "SessionEnd", "Stop", "Notification", "UserPromptSubmit",
            "PreToolUse", "PostToolUse", "PermissionRequest",
            // Cursor's own vocabulary.
            "beforeShellExecution", "beforeSubmitPrompt", "stop"
        ]
        for kind in AgentKind.allCases {
            guard let descriptor = AgentHookInstaller.descriptor(for: kind, includeApprovals: true) else { continue }
            for event in descriptor.events {
                XCTAssertTrue(observed.contains(event.wireName),
                              "\(kind.displayName) registers an unobserved event: \(event.wireName)")
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
            verification: real.verification
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
            verification: .unverified
        )
        XCTAssertFalse(AgentHookInstaller.isAgentPresent(fake))
        XCTAssertThrowsError(try AgentHookInstaller.install(descriptor: fake))
    }
}
