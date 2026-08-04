import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class AppStatePermissionFlowTests: XCTestCase {
    private var savedCodexHome: String?
    private var savedSmartSuppress: Any?

    override func setUp() {
        super.setUp()
        savedCodexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
        savedSmartSuppress = UserDefaults.standard.object(forKey: SettingsKey.smartSuppress)
    }

    override func tearDown() {
        if let savedCodexHome {
            setenv("CODEX_HOME", savedCodexHome, 1)
        } else {
            unsetenv("CODEX_HOME")
        }
        if let savedSmartSuppress {
            UserDefaults.standard.set(savedSmartSuppress, forKey: SettingsKey.smartSuppress)
        } else {
            UserDefaults.standard.removeObject(forKey: SettingsKey.smartSuppress)
        }
        super.tearDown()
    }

    func testSmartSuppressKeepsPendingSurfaceCollapsedWhenTerminalIsFrontmost() {
        UserDefaults.standard.set(true, forKey: SettingsKey.smartSuppress)
        let appState = AppState()
        var session = SessionSnapshot()
        session.termApp = "Ghostty"
        appState.sessions["s-smart"] = session

        XCTAssertFalse(appState.shouldAutoOpenPendingSurface(for: "s-smart") { _ in true })
        XCTAssertTrue(appState.shouldAutoOpenPendingSurface(for: "s-smart") { _ in false })
    }

    func testPendingSurfaceAutoOpensWhenSmartSuppressIsOff() {
        UserDefaults.standard.set(false, forKey: SettingsKey.smartSuppress)
        let appState = AppState()
        var session = SessionSnapshot()
        session.termApp = "Ghostty"
        appState.sessions["s-smart-off"] = session

        XCTAssertTrue(appState.shouldAutoOpenPendingSurface(for: "s-smart-off") { _ in true })
    }

    func testDismissPermissionSkipsAlreadyDismissedSessions() async throws {
        let appState = AppState()

        let eventA = try makePermissionRequestEvent(sessionId: "s1", toolName: "Bash")
        let eventB = try makePermissionRequestEvent(sessionId: "s2", toolName: "Read")

        let responseTaskA = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(eventA, continuation: continuation)
            }
        }
        let responseTaskB = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(eventB, continuation: continuation)
            }
        }

        await Task.yield()

        XCTAssertEqual(appState.permissionQueue.count, 2)
        XCTAssertEqual(appState.surface, .approvalCard(sessionId: "s1"))

        appState.dismissPermissionPrompt()
        XCTAssertEqual(appState.surface, .approvalCard(sessionId: "s2"))
        XCTAssertEqual(appState.permissionQueue.count, 2)

        appState.dismissPermissionPrompt()
        XCTAssertEqual(appState.surface, .collapsed)
        XCTAssertEqual(appState.permissionQueue.count, 2)

        await assertTaskNotResolved(responseTaskA)
        await assertTaskNotResolved(responseTaskB)

        appState.handlePeerDisconnect(sessionId: "s1")
        appState.handlePeerDisconnect(sessionId: "s2")

        let responseA = await responseTaskA.value
        let responseB = await responseTaskB.value

        XCTAssertEqual(try extractPermissionBehavior(from: responseA), "deny")
        XCTAssertEqual(try extractPermissionBehavior(from: responseB), "deny")
        XCTAssertEqual(appState.permissionQueue.count, 0)
    }

    func testDismissSinglePermissionCollapsesAndKeepsPending() async throws {
        let appState = AppState()
        let sessionId = "s-single"
        let event = try makePermissionRequestEvent(sessionId: sessionId, toolName: "Bash")

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }

        await Task.yield()

        XCTAssertEqual(appState.surface, .approvalCard(sessionId: sessionId))
        XCTAssertEqual(appState.permissionQueue.count, 1)
        XCTAssertEqual(appState.sessions[sessionId]?.status, .waitingApproval)

        appState.dismissPermissionPrompt()

        XCTAssertEqual(appState.surface, .collapsed)
        XCTAssertEqual(appState.permissionQueue.count, 1)
        XCTAssertEqual(appState.sessions[sessionId]?.status, .waitingApproval)

        await assertTaskNotResolved(responseTask)

        appState.handlePeerDisconnect(sessionId: sessionId)
        let response = await responseTask.value
        XCTAssertEqual(try extractPermissionBehavior(from: response), "deny")
    }

    func testDismissedSessionGetsShownAgainWhenNewPermissionArrivesAfterDrain() async throws {
        let appState = AppState()
        let sessionId = "s-reappear"

        let firstEvent = try makePermissionRequestEvent(sessionId: sessionId, toolName: "Edit")
        let firstResponseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(firstEvent, continuation: continuation)
            }
        }

        await Task.yield()
        appState.dismissPermissionPrompt()
        XCTAssertEqual(appState.surface, .collapsed)
        XCTAssertEqual(appState.permissionQueue.count, 1)

        appState.handlePeerDisconnect(sessionId: sessionId)
        let firstResponse = await firstResponseTask.value
        XCTAssertEqual(try extractPermissionBehavior(from: firstResponse), "deny")
        XCTAssertEqual(appState.permissionQueue.count, 0)

        let secondEvent = try makePermissionRequestEvent(sessionId: sessionId, toolName: "Write")
        let secondResponseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(secondEvent, continuation: continuation)
            }
        }

        await Task.yield()

        XCTAssertEqual(appState.surface, .approvalCard(sessionId: sessionId))
        XCTAssertEqual(appState.permissionQueue.count, 1)

        appState.approvePermission()

        let secondResponse = await secondResponseTask.value
        XCTAssertEqual(try extractPermissionBehavior(from: secondResponse), "allow")
        XCTAssertEqual(appState.permissionQueue.count, 0)
    }

    func testBuddyApproveCommandResolvesPendingPermission() async throws {
        let appState = AppState()
        let event = try makePermissionRequestEvent(sessionId: "s-buddy-approve", toolName: "Bash")

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }

        await Task.yield()
        XCTAssertEqual(appState.permissionQueue.count, 1)

        appState.handleBuddyControlCommand(.approveCurrentPermission)

        let response = await responseTask.value
        XCTAssertEqual(try extractPermissionBehavior(from: response), "allow")
        XCTAssertEqual(appState.permissionQueue.count, 0)
    }

    func testBuddyDenyCommandResolvesPendingPermission() async throws {
        let appState = AppState()
        let event = try makePermissionRequestEvent(sessionId: "s-buddy-deny", toolName: "Bash")

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }

        await Task.yield()
        XCTAssertEqual(appState.permissionQueue.count, 1)

        appState.handleBuddyControlCommand(.denyCurrentPermission)

        let response = await responseTask.value
        XCTAssertEqual(try extractPermissionBehavior(from: response), "deny")
        XCTAssertEqual(appState.permissionQueue.count, 0)
    }

    func testPendingApprovalPreviewSplitsLongDescriptionAcrossMultipleWatchFrames() async throws {
        let appState = AppState()
        let sessionId = "s-buddy-preview"
        let description = "Allow npm run build --filter watch package and update generated artifacts before merge"
        let command = "npm run build --filter watch -- --mode production"
        let expectedDetail = "\(description)\nCommand:\n\(command)"
        let event = try makePermissionRequestEvent(
            sessionId: sessionId,
            toolName: "Bash",
            toolInput: [
                "description": description,
                "command": command
            ]
        )

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }

        await Task.yield()

        let previews = appState.esp32MessagePreviewPayloads()
        XCTAssertGreaterThan(previews.count, 1)
        XCTAssertTrue(previews.allSatisfy { ($0.text ?? "").utf8.count <= ESP32Protocol.maxMessagePreviewBytes })
        XCTAssertEqual(previews.map(\.total).last, UInt8(previews.count))
        XCTAssertEqual(previews.compactMap(\.text).joined(), expectedDetail)

        appState.handlePeerDisconnect(sessionId: sessionId)
        _ = await responseTask.value
    }

    func testInteractiveDeliveryKeyChangesWhenApprovalDescriptionChanges() {
        let appState = AppState()
        let first = appState.esp32MessagePreviewSegments(text: "Need approval for npm run build --filter watch")
        let second = appState.esp32MessagePreviewSegments(text: "Need approval for npm run build --filter watch and package")

        XCTAssertNotEqual(first.joined(separator: "|"), second.joined(separator: "|"))
    }

    func testCodexAlwaysAllowPersistsRuleWithoutUnsupportedUpdatedPermissions() async throws {
        let codexHome = makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }

        let appState = AppState()
        let event = try makePermissionRequestEvent(
            sessionId: "s-codex-always-allow",
            toolName: "Bash",
            toolInput: [
                "command": "php vendor/bin/phpstan analyse $(git diff --name-only origin/master...HEAD | rg '\\.php$' | tr '\\n' ' ' )"
            ],
            source: "codex"
        )

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }

        await Task.yield()
        appState.approvePermission(always: true)

        let decision = try extractPermissionDecision(from: await responseTask.value)
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        XCTAssertNil(decision["updatedPermissions"])

        let rules = try readCodeIslandRules(in: codexHome)
        XCTAssertTrue(rules.contains(#"pattern = ["php", "vendor/bin/phpstan", "analyse"]"#))
        XCTAssertTrue(rules.contains(#"decision = "allow""#))
    }

    func testCodexAlwaysAllowEscapesMultilineRuleArguments() throws {
        let codexHome = makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }

        let event = try makePermissionRequestEvent(
            sessionId: "s-codex-multiline-rule",
            toolName: "Bash",
            toolInput: [
                "command": "node -e 'console.log(\"a\")\nconsole.log(\"b\")\r\n'"
            ],
            source: "codex"
        )

        let rules = CodexPermissionRules()
        XCTAssertTrue(rules.persistAlwaysAllowRule(for: event))

        let contents = try readCodeIslandRules(in: codexHome)
        XCTAssertTrue(contents.contains(#"pattern = ["node", "-e", "console.log(\"a\")\nconsole.log(\"b\")\r\n"]"#))
        XCTAssertFalse(contents.contains("console.log(\\\"a\\\")\nconsole.log(\\\"b\\\")\r\n"))
    }

    func testCodexAlwaysAllowMCPToolPersistsApprovalModeWithoutUnsupportedUpdatedPermissions() async throws {
        let codexHome = makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }

        let appState = AppState()
        let event = try makePermissionRequestEvent(
            sessionId: "s-codex-mcp-always",
            toolName: "mcp__sh_wiki__fetch_page",
            toolInput: ["page_id": "432458668"],
            source: "codex"
        )

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }

        await Task.yield()
        appState.approvePermission(always: true)

        let decision = try extractPermissionDecision(from: await responseTask.value)
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        XCTAssertNil(decision["updatedPermissions"])

        let config = try String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains("[mcp_servers.sh_wiki.tools.fetch_page]"))
        XCTAssertTrue(config.contains(#"approval_mode = "approve""#))
    }

    /// #224: "Always allow" for an MCP tool (`mcp__server__tool`) must emit a
    /// bare-tool-name rule with NO `ruleContent` specifier. Claude Code's MCP
    /// permission rules don't take a specifier; sending `ruleContent: "*"`
    /// assembles `mcp__server__tool(*)`, which never matches a real MCP call, so
    /// the rule silently fails to persist and the same approval re-prompts.
    func testAlwaysAllowMCPToolOmitsRuleSpecifier() async throws {
        let appState = AppState()
        let event = try makePermissionRequestEvent(
            sessionId: "s-mcp-always",
            toolName: "mcp__sh_wiki__fetch_page",
            toolInput: ["page_id": "432458668"]
        )

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }

        await Task.yield()
        appState.approvePermission(always: true)

        let rule = try firstAlwaysAllowRule(from: await responseTask.value)
        XCTAssertEqual(rule["toolName"] as? String, "mcp__sh_wiki__fetch_page")
        XCTAssertNil(rule["ruleContent"], "MCP tool rules must not carry a specifier (#224)")
    }

    /// Non-MCP tools keep the wildcard specifier so "always allow" still applies
    /// to every future call of that tool. The #224 fix must not change them.
    func testAlwaysAllowNonMCPToolKeepsWildcardSpecifier() async throws {
        let appState = AppState()
        let event = try makePermissionRequestEvent(
            sessionId: "s-bash-always",
            toolName: "Bash"
        )

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }

        await Task.yield()
        appState.approvePermission(always: true)

        let rule = try firstAlwaysAllowRule(from: await responseTask.value)
        XCTAssertEqual(rule["toolName"] as? String, "Bash")
        XCTAssertEqual(rule["ruleContent"] as? String, "*")
    }

    /// #258: ZCode validates hook stdout with a STRICT schema — "always allow"
    /// must ship the rule in `permissionUpdates` (bare toolName, no
    /// `destination`), never Claude's `updatedPermissions` shape, or the whole
    /// decision is silently voided and ZCode re-prompts in its own dialog.
    func testZcodeAlwaysAllowEmitsPermissionUpdatesNotUpdatedPermissions() async throws {
        let appState = AppState()
        let event = try makePermissionRequestEvent(
            sessionId: "s-zcode-always",
            toolName: "Bash",
            toolInput: ["command": "npm run build"],
            source: "zcode"
        )

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }

        await Task.yield()
        appState.approvePermission(always: true)

        let decision = try extractPermissionDecision(from: await responseTask.value)
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        XCTAssertNil(decision["updatedPermissions"])

        let updates = try XCTUnwrap(decision["permissionUpdates"] as? [[String: Any]])
        let update = try XCTUnwrap(updates.first)
        XCTAssertEqual(update["type"] as? String, "addRules")
        XCTAssertEqual(update["behavior"] as? String, "allow")
        XCTAssertNil(update["destination"])
        let rules = try XCTUnwrap(update["rules"] as? [[String: Any]])
        XCTAssertEqual(rules.first?["toolName"] as? String, "Bash")
        XCTAssertNil(rules.first?["ruleContent"])
    }

    /// Plain (one-time) allow and deny for ZCode use the shared minimal shape,
    /// which is already strict-schema-valid — lock that in so a future refactor
    /// doesn't leak Claude-only keys into zcode responses.
    func testZcodeSingleAllowStaysMinimal() async throws {
        let appState = AppState()
        let event = try makePermissionRequestEvent(
            sessionId: "s-zcode-once",
            toolName: "Bash",
            source: "zcode"
        )

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }

        await Task.yield()
        appState.approvePermission()

        let decision = try extractPermissionDecision(from: await responseTask.value)
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        XCTAssertNil(decision["permissionUpdates"])
        XCTAssertNil(decision["updatedPermissions"])
    }

    func testCodexAlwaysAllowDoesNotDuplicateExistingCodeIslandRule() throws {
        let codexHome = makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }

        let event = try makePermissionRequestEvent(
            sessionId: "s-codex-dedupe",
            toolName: "Bash",
            toolInput: ["command": "npm run build -- --mode production"],
            source: "codex"
        )

        let rules = CodexPermissionRules()
        XCTAssertTrue(rules.persistAlwaysAllowRule(for: event))
        XCTAssertTrue(rules.persistAlwaysAllowRule(for: event))

        let contents = try readCodeIslandRules(in: codexHome)
        XCTAssertEqual(contents.components(separatedBy: #"pattern = ["npm", "run", "build"]"#).count - 1, 1)
    }

    func testCodexAutoReviewConfigDefersPermissionRequestToCodex() throws {
        let codexHome = makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try #"approvals_reviewer = "auto_review""#
            .write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let event = try makePermissionRequestEvent(
            sessionId: "s-codex-auto-review",
            toolName: "Bash",
            source: "codex"
        )

        XCTAssertTrue(HookServer.shouldDeferPermissionRequestToProvider(event))
    }

    func testCodexAutoReviewConfigDoesNotDeferAskUserQuestion() throws {
        let codexHome = makeTemporaryCodexHome()
        defer { try? FileManager.default.removeItem(at: codexHome) }
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try #"approvals_reviewer = "guardian_subagent""#
            .write(to: codexHome.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        let event = try makePermissionRequestEvent(
            sessionId: "s-codex-question",
            toolName: "AskUserQuestion",
            toolInput: ["question": "Continue?", "options": ["Yes", "No"]],
            source: "codex"
        )

        XCTAssertFalse(HookServer.shouldDeferPermissionRequestToProvider(event))
    }

    func testCodexProfileAutoReviewConfigIsDetected() throws {
        let config = """
        profile = "work"
        approvals_reviewer = "user"

        [profiles.work]
        approvals_reviewer = "auto_review"
        """

        XCTAssertTrue(CodexPermissionRules.configEnablesAutoReview(config))
    }

    func testCodexUserReviewerConfigDoesNotDefer() throws {
        let config = """
        approvals_reviewer = "user"

        [profiles.work]
        approvals_reviewer = "auto_review"
        """

        XCTAssertFalse(CodexPermissionRules.configEnablesAutoReview(config))
    }

    // MARK: - Helpers

    private func makeTemporaryCodexHome() -> URL {
        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        setenv("CODEX_HOME", codexHome.path, 1)
        return codexHome
    }

    private func codeIslandRulesPath(in codexHome: URL) -> URL {
        codexHome
            .appendingPathComponent("rules", isDirectory: true)
            .appendingPathComponent("codeisland.rules")
    }

    private func readCodeIslandRules(in codexHome: URL) throws -> String {
        try String(contentsOf: codeIslandRulesPath(in: codexHome), encoding: .utf8)
    }

    private func makePermissionRequestEvent(
        sessionId: String,
        toolName: String,
        toolInput: [String: Any] = ["command": "echo test"],
        source: String? = nil
    ) throws -> HookEvent {
        var payload: [String: Any] = [
            "hook_event_name": "PermissionRequest",
            "session_id": sessionId,
            "tool_name": toolName,
            "tool_input": toolInput
        ]
        if let source {
            payload["_source"] = source
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let event = HookEvent(from: data) else {
            XCTFail("Failed to parse HookEvent")
            throw NSError(domain: "AppStatePermissionFlowTests", code: 1)
        }
        return event
    }

    private func extractPermissionBehavior(from responseData: Data) throws -> String {
        let decision = try extractPermissionDecision(from: responseData)
        return try XCTUnwrap(decision["behavior"] as? String)
    }

    private func extractPermissionDecision(from responseData: Data) throws -> [String: Any] {
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: responseData) as? [String: Any])
        let hookSpecificOutput = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        return try XCTUnwrap(hookSpecificOutput["decision"] as? [String: Any])
    }

    private func firstAlwaysAllowRule(from responseData: Data) throws -> [String: Any] {
        let decision = try extractPermissionDecision(from: responseData)
        let updated = try XCTUnwrap(decision["updatedPermissions"] as? [[String: Any]])
        let first = try XCTUnwrap(updated.first)
        let rules = try XCTUnwrap(first["rules"] as? [[String: Any]])
        return try XCTUnwrap(rules.first)
    }

    private func assertTaskNotResolved(_ task: Task<Data, Never>, timeout: TimeInterval = 0.05) async {
        let exp = expectation(description: "task should stay pending")
        exp.isInverted = true

        Task {
            _ = await task.value
            exp.fulfill()
        }

        await fulfillment(of: [exp], timeout: timeout)
    }
}
