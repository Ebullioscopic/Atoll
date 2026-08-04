import Foundation
import Network
import os.log
import CodeIslandCore

private let log = Logger(subsystem: "com.codeisland", category: "HookServer")

@MainActor
class HookServer {
    enum RouteKind: Equatable {
        case permission
        case question
        case event
    }

    private let appState: AppState
    nonisolated static var socketPath: String { SocketPath.path }
    private var listener: NWListener?

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        // Clean up stale socket
        unlink(HookServer.socketPath)

        // Set umask to 0o077 BEFORE the listener creates the socket file,
        // ensuring it is never world-readable even briefly (closes TOCTOU window).
        let previousUmask = umask(0o077)

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: HookServer.socketPath)

        do {
            listener = try NWListener(using: params)
        } catch {
            umask(previousUmask)
            log.error("Failed to create NWListener: \(error.localizedDescription)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handleConnection(connection)
            }
        }

        listener?.stateUpdateHandler = { [previousUmask] state in
            switch state {
            case .ready:
                // Restore previous umask now that the socket file exists with safe permissions
                umask(previousUmask)
                // Belt-and-suspenders: explicitly set 0o700 in case umask didn't take effect
                chmod(HookServer.socketPath, 0o700)
                log.info("HookServer listening on \(HookServer.socketPath)")
            case .failed(let error):
                umask(previousUmask)
                log.error("HookServer failed: \(error.localizedDescription)")
            default:
                break
            }
        }

        listener?.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        // Delay socket removal so in-flight hooks can finish sending their payload
        // before the file disappears — prevents intermittent errors on session end (#45).
        let path = HookServer.socketPath
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            unlink(path)
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveAll(connection: connection, accumulated: Data())
    }

    private static let maxPayloadSize = 10_485_760  // 10MB safety limit

    /// Recursively receive all data until EOF, then process
    private func receiveAll(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }

                // On error with no data, just drop the connection
                if error != nil && accumulated.isEmpty && content == nil {
                    connection.cancel()
                    return
                }

                var data = accumulated
                if let content { data.append(content) }

                // Safety: reject oversized payloads
                if data.count > Self.maxPayloadSize {
                    log.warning("Payload too large (\(data.count) bytes), dropping connection")
                    let denyResponse = Data(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#.utf8)
                    self.sendResponse(connection: connection, data: denyResponse)
                    return
                }

                if isComplete || error != nil {
                    self.processRequest(data: data, connection: connection)
                } else {
                    self.receiveAll(connection: connection, accumulated: data)
                }
            }
        }
    }

    /// Internal tools that are safe to auto-approve without user confirmation.
    /// Read from user settings; defaults to all known internal tools.
    private static var autoApproveTools: Set<String> {
        SettingsManager.shared.autoApproveTools
    }

    /// User-configured cwd substring blocklist for plugin/background hooks (e.g. claude-mem).
    /// Empty default = no filtering. Trimmed, blank entries skipped.
    private static func eventMatchesExcludedCwd(_ cwd: String) -> Bool {
        cwdMatchesAnyPattern(cwd, patternsCSV: SettingsManager.shared.excludedHookCwdSubstrings)
    }

    /// Pure substring blocklist match — returns true if `cwd` contains any
    /// non-empty trimmed entry of `patternsCSV`. Extracted for testability;
    /// `nonisolated` because it touches no actor state.
    nonisolated static func cwdMatchesAnyPattern(_ cwd: String, patternsCSV: String) -> Bool {
        guard !patternsCSV.isEmpty else { return false }
        for entry in patternsCSV.split(separator: ",", omittingEmptySubsequences: false) {
            let pattern = entry.trimmingCharacters(in: .whitespaces)
            if !pattern.isEmpty, cwd.contains(pattern) { return true }
        }
        return false
    }

    /// Per-host cwd ALLOW-list for remote sessions (#240) — on shared remote
    /// accounts, users can scope the panel to their own project directories.
    /// Empty filter = allow everything (previous behavior). With a filter set,
    /// events must carry a cwd containing one of the entries; events without a
    /// cwd are dropped too — on a shared account they can't be attributed.
    nonisolated static func remoteEventPassesCwdFilter(
        cwd: String?,
        workspaceRoots: [String]? = nil,
        filterCSV: String
    ) -> Bool {
        let hasPattern = filterCSV
            .split(separator: ",", omittingEmptySubsequences: false)
            .contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard hasPattern else { return true }
        if let cwd, !cwd.isEmpty, cwdMatchesAnyPattern(cwd, patternsCSV: filterCSV) {
            return true
        }
        if let roots = workspaceRoots {
            for root in roots where !root.isEmpty {
                if cwdMatchesAnyPattern(root, patternsCSV: filterCSV) {
                    return true
                }
            }
        }
        // No cwd or workspace root matched — on a shared account they can't be attributed.
        return false
    }

    /// Remote cwd allow-lists drop hooks from other users' directories on shared
    /// SSH accounts (#240). Lifecycle and blocking hooks for sessions we already
    /// track must still flow through — otherwise SessionEnd/Stop never tears
    /// sessions down and PermissionRequest/Notification stall the remote agent.
    nonisolated static func remoteEventBypassesCwdFilter(
        eventName: String,
        sessionId: String?,
        trackedSessionIds: Set<String>
    ) -> Bool {
        guard let sessionId, trackedSessionIds.contains(sessionId) else { return false }
        switch EventNormalizer.normalize(eventName) {
        case "SessionEnd", "Stop", "SubagentStop", "PermissionRequest", "Notification", "AfterAgentResponse":
            return true
        default:
            return false
        }
    }

    /// Looks up the configured cwd filter for a remote host id. Nil when the
    /// event is not remote or the host is no longer configured.
    private static func remoteCwdFilter(for event: HookEvent) -> String? {
        guard let hostId = event.rawJSON["_remote_host_id"] as? String,
              !hostId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return RemoteManager.shared.hosts.first(where: { $0.id == hostId })?.cwdFilter
    }

    /// Fire-and-forget POST of the hook event to a user-configured webhook URL.
    /// Wraps the raw event in a small envelope (event/source/session/cwd/tool/raw)
    /// so users on the receiving side don't need to dig through bridge-internal
    /// fields. Optional event-name allow-list filters noisy event types. (#115)
    private static func forwardEventToWebhook(_ event: HookEvent) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.webhookEnabled) else { return }
        // Trim whitespace — users routinely paste URLs with leading/trailing space
        // and URL(string:) silently rejects those (RFC 3986 forbids whitespace).
        let urlString = (defaults.string(forKey: SettingsKey.webhookURL) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty,
              let endpoint = URL(string: urlString) else { return }

        let normalizedName = EventNormalizer.normalize(event.eventName)

        // Event filter: comma-separated allow-list. Empty = forward all.
        // Match on either the normalized name (PreToolUse) or raw name (pre_tool_use).
        if let filter = defaults.string(forKey: SettingsKey.webhookEventFilter),
           !filter.trimmingCharacters(in: .whitespaces).isEmpty {
            let allowed = filter.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard allowed.contains(normalizedName) || allowed.contains(event.eventName) else { return }
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let envelope: [String: Any] = [
            "event": normalizedName,
            "raw_event": event.eventName,
            "session_id": event.sessionId ?? "",
            "source": event.rawJSON["_source"] as? String ?? "",
            "cwd": event.rawJSON["cwd"] as? String ?? "",
            "tool_name": event.toolName ?? "",
            "timestamp": isoFormatter.string(from: Date()),
            "raw": event.rawJSON,
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: envelope) else { return }

        var request = URLRequest(url: endpoint, timeoutInterval: 5)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CodeIsland-Webhook/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, _, _ in
            // Fire-and-forget. Failures are intentionally swallowed: a flaky
            // webhook should never break the hook event pipeline.
        }.resume()
    }

    private static func hiddenPluginResponse(for raw: [String: Any]) -> Data {
        // Hidden PermissionRequest must allow so the plugin's tool execution
        // doesn't block waiting on a UI prompt the user said to suppress.
        let eventName = (raw["hook_event_name"] as? String
            ?? raw["hookEventName"] as? String
            ?? raw["event_name"] as? String
            ?? "").lowercased()
        if eventName.contains("permission") {
            return Data(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#.utf8)
        }
        return Data("{}".utf8)
    }

    private static func pluginPpid(from raw: [String: Any]) -> Int? {
        if let p = raw["_ppid"] as? Int { return p }
        if let p = raw["_ppid"] as? Int32 { return Int(p) }
        if let p = raw["_ppid"] as? NSNumber { return p.intValue }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : string
    }

    private static func rawSessionId(from raw: [String: Any]) -> String? {
        nonEmptyString(raw["session_id"]) ?? nonEmptyString(raw["sessionId"])
    }

    private static func rawEventName(from raw: [String: Any]) -> String? {
        nonEmptyString(raw["hook_event_name"])
            ?? nonEmptyString(raw["hookEventName"])
            ?? nonEmptyString(raw["event_name"])
            ?? nonEmptyString(raw["eventName"])
    }

    static func routeKind(for event: HookEvent) -> RouteKind {
        let normalizedEventName = EventNormalizer.normalize(event.eventName)
        let source = event.rawJSON["_source"] as? String
        let normalizedSource = SessionSnapshot.normalizedSupportedSource(source)
        let isGeminiBasedSource = normalizedSource == "google-antigravity" || normalizedSource == "gemini"
        // Gemini CLI and Google Antigravity send their blocking approval as PreToolUse.
        // Route those source-tagged events through the same permission UI path.
        if normalizedEventName == "PermissionRequest" || (isGeminiBasedSource && normalizedEventName == "PreToolUse") {
            return .permission
        }
        if normalizedEventName == "Notification", QuestionPayload.from(event: event) != nil {
            return .question
        }
        return .event
    }

    nonisolated static func shouldDeferPermissionRequestToProvider(_ event: HookEvent) -> Bool {
        guard EventNormalizer.normalize(event.eventName) == "PermissionRequest",
              event.toolName != "AskUserQuestion" else {
            return false
        }
        return CodexPermissionRules.shouldDeferToCodexAutoReview(for: event)
    }

    private static let pluginMarkerBytes = Data("_via_plugin".utf8)
    private static let sourceMarkerBytes = Data(#""_source""#.utf8)
    private static let codexMarkerBytes = Data("codex".utf8)
    private static let cursorTranscriptMarkerBytes = Data("agent-transcripts".utf8)
    private static let cursorSourceMarkerBytes = Data("cursor".utf8)

    private static func codexSubagentMetadata(from raw: [String: Any]) -> CodexSubagentMetadata? {
        guard let path = nonEmptyString(raw["transcript_path"]) else { return nil }
        return AppState.codexSubagentMetadata(inTranscriptPath: path)
    }

    private func codexNativeSubsessionParentId(from raw: [String: Any]) -> String? {
        guard (raw["_via_plugin"] as? Bool) != true,
              SessionSnapshot.normalizedSupportedSource(raw["_source"] as? String) == "codex",
              let childSessionId = Self.rawSessionId(from: raw) else {
            return nil
        }

        if let metadata = Self.codexSubagentMetadata(from: raw),
           let parentSessionId = appState.findSessionId(providerSessionId: metadata.parentThreadId) {
            return parentSessionId
        }

        guard let ppid = Self.pluginPpid(from: raw) else { return nil }

        // Current Codex hook payloads do not expose parent session metadata for
        // native subagents, but child sessions run inside the same Codex CLI
        // process as their parent. Require an already-active same-PID Codex
        // session so a normal follow-up thread in an idle process stays separate.
        let hasExplicitSubagentMarker = Self.nonEmptyString(raw["agent_id"]) != nil
        return appState.findSessionId(
            forSource: "codex",
            ppid: ppid,
            excluding: childSessionId,
            requireActive: !hasExplicitSubagentMarker
        )
    }

    private func routeSubsessionPayloadIfNeeded(data: Data) -> (processedData: Data, responseData: Data?) {
        let mayNeedPluginOrCodex = data.range(of: Self.pluginMarkerBytes) != nil
            || (data.range(of: Self.sourceMarkerBytes) != nil && data.range(of: Self.codexMarkerBytes) != nil)
        let mayNeedCursor = data.range(of: Self.cursorTranscriptMarkerBytes) != nil
            && data.range(of: Self.cursorSourceMarkerBytes) != nil

        let mode = UserDefaults.standard.string(forKey: SettingsKey.pluginSessionMode)
            ?? SettingsDefaults.pluginSessionMode

        // Cursor Task routing is a no-op in separate mode; skip JSON parse when
        // the payload is Cursor-only (Codex/plugin may still need it below).
        if mayNeedCursor && !mayNeedPluginOrCodex && mode != "hide" && mode != "merge" {
            return (data, nil)
        }

        guard mayNeedPluginOrCodex || mayNeedCursor,
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (data, nil)
        }

        // Cursor Task/subagent: apply Agent Sub-Sessions (separate / merge / hide).
        switch CursorSubsessionRouter.decide(raw: raw, mode: mode) {
        case .leave:
            break
        case .hide:
            return (data, Self.hiddenPluginResponse(for: raw))
        case .merge(let parentSessionId, let childSessionId):
            var rewritten = raw
            CursorSubsessionRouter.applyMerge(
                to: &rewritten,
                parentSessionId: parentSessionId,
                childSessionId: childSessionId
            )
            if let newData = try? JSONSerialization.data(withJSONObject: rewritten) {
                return (newData, nil)
            }
            return (data, nil)
        }

        guard mode == "hide" || mode == "merge" else {
            return (data, nil)
        }

        if (raw["_via_plugin"] as? Bool) == true {
            switch mode {
            case "hide":
                return (data, Self.hiddenPluginResponse(for: raw))
            case "merge":
                if let source = raw["_source"] as? String,
                   let ppid = Self.pluginPpid(from: raw),
                   let mainSessionId = appState.findSessionId(forSource: source, ppid: ppid) {
                    var rewritten = raw
                    rewritten["session_id"] = mainSessionId
                    if let newData = try? JSONSerialization.data(withJSONObject: rewritten) {
                        return (newData, nil)
                    }
                }
            default:
                break
            }
            return (data, nil)
        }

        guard let childSessionId = Self.rawSessionId(from: raw) else {
            return (data, nil)
        }
        let codexMetadata = Self.codexSubagentMetadata(from: raw)
        let parentSessionId = codexNativeSubsessionParentId(from: raw)
        guard codexMetadata != nil || parentSessionId != nil else {
            return (data, nil)
        }

        switch mode {
        case "hide":
            return (data, Self.hiddenPluginResponse(for: raw))
        case "merge":
            guard let parentSessionId else { return (data, nil) }
            var rewritten = raw
            rewritten["session_id"] = parentSessionId
            rewritten["agent_id"] = Self.nonEmptyString(raw["agent_id"]) ?? childSessionId
            rewritten["agent_type"] = Self.nonEmptyString(raw["agent_type"])
                ?? codexMetadata?.agentType
                ?? "default"
            rewritten["_codex_subagent"] = true
            rewritten["_codex_subagent_session_id"] = childSessionId
            if let eventName = Self.rawEventName(from: raw) {
                rewritten["_codex_subagent_event"] = EventNormalizer.normalize(eventName)
            }
            if let newData = try? JSONSerialization.data(withJSONObject: rewritten) {
                return (newData, nil)
            }
        default:
            break
        }
        return (data, nil)
    }

    private func processRequest(data: Data, connection: NWConnection) {
        // Sub-session pre-filter (#123, #151): plugin, Codex, or Cursor Task hooks
        // (Cursor: transcript parent ≠ session_id) follow Agent Sub-Sessions —
        // merge into the parent, hide, or keep separate.
        //
        // Cheap byte probes first; avoid JSONSerialization on every PostToolUse.
        let routed = routeSubsessionPayloadIfNeeded(data: data)
        if let responseData = routed.responseData {
            sendResponse(connection: connection, data: responseData)
            return
        }
        let processedData = routed.processedData

        guard let event = HookEvent(from: processedData) else {
            sendResponse(connection: connection, data: Data("{\"error\":\"parse_failed\"}".utf8))
            return
        }

        // Diagnostics ring buffer (#103): record the post-merge view of the
        // event so the export reflects what was actually dispatched. Also
        // capture the field names the hook arrived with and a prompt preview
        // so future "prompt not showing" reports can be diagnosed without
        // round-tripping for more data.
        let payloadKeys = event.rawJSON.keys
            .filter { !$0.hasPrefix("_") }  // drop bridge-injected metadata fields
            .sorted()
        let promptPreview: String? = {
            let candidates = ["prompt", "user_prompt", "userPrompt", "message", "input", "content", "text"]
            for key in candidates {
                if let s = event.rawJSON[key] as? String {
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return String(trimmed.prefix(80))
                    }
                }
            }
            return nil
        }()
        appState.recordHookEvent(
            source: event.rawJSON["_source"] as? String,
            sessionId: event.sessionId,
            eventName: event.eventName,
            toolName: event.toolName,
            viaPlugin: (event.rawJSON["_via_plugin"] as? Bool) == true,
            payloadKeys: payloadKeys,
            promptPreview: promptPreview
        )

        if let rawSource = event.rawJSON["_source"] as? String,
           SessionSnapshot.normalizedSupportedSource(rawSource) == nil {
            sendResponse(connection: connection, data: Data("{}".utf8))
            return
        }

        // User-configured cwd exclusion: drop hooks fired by background plugins
        // (e.g. claude-mem, agent loops) whose cwd matches any user-provided
        // substring. Default empty list = no filtering, matches existing behavior. (#125)
        if let cwd = event.rawJSON["cwd"] as? String,
           !cwd.isEmpty,
           Self.eventMatchesExcludedCwd(cwd) {
            sendResponse(connection: connection, data: Data("{}".utf8))
            return
        }

        // Per-host cwd allow-list for remote sessions (#240): on a shared remote
        // account every user's hooks reach every connected client — scope this
        // panel to the configured working directories and drop the rest.
        if let filterCSV = Self.remoteCwdFilter(for: event),
           !Self.remoteEventPassesCwdFilter(
               cwd: event.rawJSON["cwd"] as? String,
               workspaceRoots: event.rawJSON["workspace_roots"] as? [String],
               filterCSV: filterCSV
           ),
           !Self.remoteEventBypassesCwdFilter(
               eventName: event.eventName,
               sessionId: event.sessionId,
               trackedSessionIds: Set(appState.sessions.keys)
           ) {
            sendResponse(connection: connection, data: Data("{}".utf8))
            return
        }

        // User-configured webhook forwarding: fire-and-forget POST to an external URL.
        // Runs *before* the route handlers so it doesn't add latency to user-facing
        // permission/question UI. Disabled by default. (#115)
        Self.forwardEventToWebhook(event)

        switch Self.routeKind(for: event) {
        case .permission:
            let sessionId = event.sessionId ?? "default"

            // Auto-approve safe internal tools without showing UI
            if let toolName = event.toolName, Self.autoApproveTools.contains(toolName) {
                let response = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
                sendResponse(connection: connection, data: Data(response.utf8))
                return
            }

            // AskUserQuestion is a question, not a permission — route to QuestionBar
            if event.toolName == "AskUserQuestion" {
                monitorPeerDisconnect(connection: connection, sessionId: sessionId)
                Task {
                    let responseBody = await withCheckedContinuation { continuation in
                        appState.handleAskUserQuestion(event, continuation: continuation)
                    }
                    self.sendResponse(connection: connection, data: responseBody)
                }
                return
            }

            if Self.shouldDeferPermissionRequestToProvider(event) {
                sendResponse(connection: connection, data: Data("{}".utf8))
                return
            }

            monitorPeerDisconnect(connection: connection, sessionId: sessionId)
            Task {
                let responseBody = await withCheckedContinuation { continuation in
                    appState.handlePermissionRequest(event, continuation: continuation)
                }
                self.sendResponse(connection: connection, data: responseBody)
            }

        case .question:
            let questionSessionId = event.sessionId ?? "default"
            monitorPeerDisconnect(connection: connection, sessionId: questionSessionId)
            Task {
                let responseBody = await withCheckedContinuation { continuation in
                    appState.handleQuestion(event, continuation: continuation)
                }
                self.sendResponse(connection: connection, data: responseBody)
            }

        case .event:
            appState.handleEvent(event)
            sendResponse(connection: connection, data: Data("{}".utf8))
        }
    }

    /// Per-connection state used by the disconnect monitor.
    /// `responded` flips to true once we've sent the response, so our own
    /// `connection.cancel()` inside `sendResponse` does not masquerade as a
    /// peer disconnect.
    private final class ConnectionContext {
        var responded: Bool = false
    }

    private var connectionContexts: [ObjectIdentifier: ConnectionContext] = [:]

    /// Watch for bridge process disconnect — indicates the bridge process actually died
    /// (e.g. user Ctrl-C'd Claude Code), NOT a normal half-close.
    ///
    /// Previously this used `connection.receive(min:1, max:1)` which triggered on EOF.
    /// But the bridge always does `shutdown(SHUT_WR)` after sending the request (see
    /// CodeIslandBridge/main.swift), which produces an immediate EOF on the read side.
    /// That caused every PermissionRequest to be auto-drained as `deny` before the UI
    /// card was even visible. We now rely on `stateUpdateHandler` transitioning to
    /// `cancelled`/`failed` — which only happens on real socket teardown, not half-close.
    private func monitorPeerDisconnect(connection: NWConnection, sessionId: String) {
        let context = ConnectionContext()
        let connId = ObjectIdentifier(connection)
        connectionContexts[connId] = context

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self = self else { return }
                switch state {
                case .cancelled, .failed:
                    if !context.responded {
                        self.appState.handlePeerDisconnect(sessionId: sessionId)
                    }
                    self.connectionContexts.removeValue(forKey: connId)
                default:
                    break
                }
            }
        }

        // Safety net: if the connection context is still around after 5 minutes
        // (e.g. stuck continuation, NWConnection never transitions), clean it up.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000_000)  // 5 minutes
            guard let self = self else { return }
            if self.connectionContexts.removeValue(forKey: connId) != nil {
                log.warning("Connection context for session \(sessionId) timed out — cleaning up")
                if !context.responded {
                    connection.cancel()
                }
            }
        }
    }

    private func sendResponse(connection: NWConnection, data: Data) {
        // Mark as responded BEFORE cancel() so the disconnect monitor ignores our own teardown.
        if let context = connectionContexts[ObjectIdentifier(connection)] {
            context.responded = true
        }
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
