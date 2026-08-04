import Foundation
import AppKit
import SwiftUI
import CodeIslandCore

extension AppState {
    /// Session ID prefix applied to Codex threads surfaced via the app-server.
    /// The rollout-file discovery path uses the raw UUID; the `codexapp:` prefix
    /// keeps the two channels' session namespaces disjoint so a user running
    /// Codex Desktop AND Codex CLI simultaneously doesn't see them collapse.
    static let codexAppSessionPrefix = "codexapp:"
    // Plain `let` constants — nonisolated so NSWorkspace notification
    // handlers on background queues can read them without Swift 6
    // Sendable warnings.
    nonisolated static let codexAppBundleId = "com.openai.codex"

    // MARK: - Public lifecycle

    /// Start watching `com.openai.codex` in NSWorkspace and, whenever it's
    /// running, maintain a JSON-RPC client connected to `codex app-server`.
    /// Idempotent — safe to call multiple times.
    func startCodexAppServerWatcher() {
        if codexAppServerObservers != nil { return }

        var observers: [NSObjectProtocol] = []
        let center = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == AppState.codexAppBundleId else { return }
            Task { @MainActor in self?.startCodexAppServerClientIfPossible() }
        })

        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == AppState.codexAppBundleId else { return }
            Task { @MainActor in self?.stopCodexAppServerClient() }
        })

        codexAppServerObservers = observers

        // Catch up with whatever state we booted into.
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == AppState.codexAppBundleId }) {
            startCodexAppServerClientIfPossible()
        }
    }

    func stopCodexAppServerWatcher() {
        if let observers = codexAppServerObservers {
            let center = NSWorkspace.shared.notificationCenter
            for observer in observers { center.removeObserver(observer) }
            codexAppServerObservers = nil
        }
        stopCodexAppServerClient()
    }

    // MARK: - Client lifecycle

    private func startCodexAppServerClientIfPossible() {
        guard codexAppServerClient == nil else { return }
        guard let executable = Self.codexAppServerExecutableURL() else { return }

        let client = CodexAppServerClient(executableURL: executable)
        client.onMessage = { [weak self] message in
            Task { @MainActor in self?.handleCodexAppServerMessage(message) }
        }
        client.onExit = { [weak self] _ in
            Task { @MainActor in
                self?.codexAppServerClient = nil
                self?.removeCodexAppServerSessions()
            }
        }

        do {
            try client.start()
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            try client.initializeHandshake(clientName: "CodeIsland", clientVersion: version)
        } catch {
            client.stop()
            return
        }
        codexAppServerClient = client
    }

    static func codexAppServerExecutableURL(
        runningBundleURLs: [URL] = NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier == AppState.codexAppBundleId ? app.bundleURL : nil
        },
        fallbackPaths: [String] = [
            CodexAppServerClient.defaultExecutablePath,
            NSHomeDirectory() + "/Applications/Codex.app/Contents/Resources/codex"
        ],
        fileManager: FileManager = .default
    ) -> URL? {
        var candidates: [URL] = []
        for bundleURL in runningBundleURLs {
            candidates.append(bundleURL.appendingPathComponent("Contents/Resources/codex"))
        }
        candidates.append(contentsOf: fallbackPaths.map { URL(fileURLWithPath: $0) })

        var seen = Set<String>()
        for candidate in candidates {
            let path = candidate.path
            guard seen.insert(path).inserted else { continue }
            if fileManager.isExecutableFile(atPath: path) {
                return candidate
            }
        }
        return nil
    }

    private func stopCodexAppServerClient() {
        codexAppServerClient?.stop()
        codexAppServerClient = nil
        removeCodexAppServerSessions()
    }

    private func removeCodexAppServerSessions() {
        let stale = sessions.keys.filter { $0.hasPrefix(AppState.codexAppSessionPrefix) }
        for id in stale {
            sessions.removeValue(forKey: id)
        }
        refreshDerivedState()
    }

    // MARK: - Notification dispatch

    func handleCodexAppServerMessage(_ message: CodexJSONRPCMessage) {
        let params = message.raw["params"]?.asObject ?? [:]

        switch message.kind {
        case .notification(let method):
            switch method {
            case "thread/started":
                applyCodexThreadStartedNotification(params: params)
            case "thread/status/changed":
                applyCodexThreadStatusNotification(params: params)
            case "thread/closed":
                applyCodexThreadClosedNotification(params: params)
            case "serverRequest/resolved":
                applyCodexServerRequestResolvedNotification(params: params)
            default:
                break
            }
        case .request(let method, let id):
            // The Codex app-server surfaces plan-mode / free-form prompts as a
            // server->client *request* (not a notification). Hooks never see
            // these, so this is the only channel that carries the question text.
            switch method {
            case "item/tool/requestUserInput":
                applyCodexRequestUserInput(params: params, requestId: id)
            default:
                break
            }
        case .response, .error:
            break
        }
    }

    // MARK: - request_user_input (plan-mode / free-form questions)

    /// Handle a server->client `item/tool/requestUserInput` request by surfacing
    /// each question in CodeIsland's popup and wiring the answer back as a
    /// JSON-RPC response to `requestId`. See issue #209.
    private func applyCodexRequestUserInput(params: [String: AnyCodableLike], requestId: CodexRequestID) {
        guard let threadId = params["threadId"]?.asString else { return }
        let sessionId = AppState.codexAppSessionPrefix + threadId

        guard case .array(let rawQuestions)? = params["questions"], !rawQuestions.isEmpty else { return }

        var askItems: [AskUserQuestionItem] = []
        var usedAnswerKeys = Set<String>()
        for entry in rawQuestions {
            guard let q = entry.asObject else { continue }
            let questionText = q["question"]?.asString ?? "Question"
            let header = q["header"]?.asString
            let isSecret = q["isSecret"]?.asBool ?? false

            var optionLabels: [String] = []
            var optionDescs: [String] = []
            if case .array(let opts)? = q["options"] {
                for opt in opts {
                    guard let o = opt.asObject else { continue }
                    optionLabels.append(o["label"]?.asString ?? "")
                    optionDescs.append(o["description"]?.asString ?? "")
                }
            }

            // answerKey = question.id (the wire key we must echo in the reply).
            // Fall back to a synthetic key and de-duplicate to keep the wizard's
            // position->answerKey mapping unambiguous.
            var answerKey = q["id"]?.asString ?? questionText
            if answerKey.isEmpty { answerKey = questionText }
            if usedAnswerKeys.contains(answerKey) {
                var suffix = 2
                while usedAnswerKeys.contains("\(answerKey)_\(suffix)") { suffix += 1 }
                answerKey = "\(answerKey)_\(suffix)"
            }
            usedAnswerKeys.insert(answerKey)

            let payload = QuestionPayload(
                question: questionText,
                options: optionLabels.isEmpty ? nil : optionLabels,
                descriptions: optionDescs.contains(where: { !$0.isEmpty }) ? optionDescs : nil,
                header: header,
                isSecret: isSecret
            )
            askItems.append(AskUserQuestionItem(payload: payload, answerKey: answerKey, multiSelect: false))
        }

        guard !askItems.isEmpty else { return }

        // Make sure the session exists so the popup has context to render.
        if sessions[sessionId] == nil {
            var snapshot = SessionSnapshot(startTime: Date())
            snapshot.source = "codex"
            snapshot.termBundleId = AppState.codexAppBundleId
            snapshot.providerSessionId = threadId
            sessions[sessionId] = snapshot
        }
        sessions[sessionId]?.status = .waitingQuestion
        sessions[sessionId]?.lastActivity = Date()

        // Build the synthetic HookEvent carrying the correct sessionId so the
        // existing queue / drain / showNextPending plumbing routes it correctly.
        let event = AppState.makeCodexAppServerQuestionEvent(sessionId: sessionId)

        // Reply closure: write a JSON-RPC response back to the captured request id.
        let client = codexAppServerClient
        let resolution = QuestionResolution.codexAppServer { [weak client] answersByKey in
            guard let client else { return }
            let result = AppState.codexRequestUserInputResult(answersByKey: answersByKey)
            try? client.sendResponse(id: requestId, result: result)
        }

        let askState = AskUserQuestionState(items: askItems, answers: [:])
        let request = QuestionRequest(
            event: event,
            question: askItems[0].payload,
            resolution: resolution,
            isFromPermission: false,
            askUserQuestionState: askState
        )
        questionQueue.append(request)

        if questionQueue.count == 1 {
            activeSessionId = sessionId
            withAnimation(NotchAnimation.open) {
                surface = .questionCard(sessionId: sessionId)
            }
            SoundManager.shared.handleEvent("PermissionRequest")
        }
        refreshDerivedState()
    }

    /// Codex resolved the request in its own TUI (or otherwise) — drop the
    /// matching queued question WITHOUT replying (the server already moved on).
    private func applyCodexServerRequestResolvedNotification(params: [String: AnyCodableLike]) {
        guard let threadId = params["threadId"]?.asString else { return }
        let sessionId = AppState.codexAppSessionPrefix + threadId
        let before = questionQueue.count
        questionQueue.removeAll { $0.isCodexAppServer && $0.event.sessionId == sessionId }
        guard questionQueue.count != before else { return }

        if sessions[sessionId]?.status == .waitingQuestion {
            sessions[sessionId]?.status = .processing
        }
        showNextPending()
        refreshDerivedState()
    }

    /// Build the `ToolRequestUserInputResponse`-shaped result for a reply to a
    /// Codex `item/tool/requestUserInput` request:
    ///   `{ "answers": { <questionId>: { "answers": [<chosen>] } } }`
    /// `nil` answers (skip / abandon) produce an empty `answers` object so the
    /// server can move on without crashing on a missing key.
    static func codexRequestUserInputResult(answersByKey: [String: [String]]?) -> [String: Any] {
        var answers: [String: Any] = [:]
        if let answersByKey {
            for (key, values) in answersByKey {
                answers[key] = ["answers": values]
            }
        }
        return ["answers": answers]
    }

    /// Synthesize a HookEvent that only carries the sessionId. Codex app-server
    /// questions don't originate from a hook payload, but the question queue keys
    /// everything off `event.sessionId`, so we mint a minimal envelope.
    static func makeCodexAppServerQuestionEvent(sessionId: String) -> HookEvent {
        let payload: [String: Any] = [
            "hook_event_name": "Notification",
            "session_id": sessionId,
        ]
        // This JSON always parses, but fall back defensively rather than force-unwrap.
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let event = HookEvent(from: data) {
            return event
        }
        let escaped = sessionId.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let fallback = #"{"hook_event_name":"Notification","session_id":"\#(escaped)"}"#
        return HookEvent(from: Data(fallback.utf8))!
    }

    private func applyCodexThreadStartedNotification(params: [String: AnyCodableLike]) {
        guard let thread = params["thread"]?.asObject else { return }
        guard let threadId = thread["id"]?.asString else { return }
        let sessionId = AppState.codexAppSessionPrefix + threadId

        var snapshot = sessions[sessionId] ?? SessionSnapshot(startTime: Date())
        snapshot.source = "codex"
        snapshot.termBundleId = AppState.codexAppBundleId
        snapshot.providerSessionId = threadId
        if let cwd = thread["cwd"]?.asString, !cwd.isEmpty {
            snapshot.cwd = cwd
        }
        if let preview = thread["preview"]?.asString, !preview.isEmpty {
            snapshot.lastUserPrompt = preview
        }
        if let name = thread["name"]?.asString, !name.isEmpty {
            snapshot.sessionTitle = name
        }
        if let path = thread["path"]?.asString, !path.isEmpty {
            snapshot.transcriptPath = path
        }

        applyCodexThreadStatus(&snapshot, status: thread["status"]?.asObject)
        snapshot.lastActivity = Date()
        sessions[sessionId] = snapshot
        attachTranscriptTailerIfNeeded(sessionId: sessionId)
        refreshDerivedState()
    }

    private func applyCodexThreadStatusNotification(params: [String: AnyCodableLike]) {
        guard let threadId = params["threadId"]?.asString else { return }
        let sessionId = AppState.codexAppSessionPrefix + threadId
        guard var snapshot = sessions[sessionId] else { return }

        applyCodexThreadStatus(&snapshot, status: params["status"]?.asObject)
        snapshot.lastActivity = Date()
        sessions[sessionId] = snapshot
        refreshDerivedState()
    }

    private func applyCodexThreadClosedNotification(params: [String: AnyCodableLike]) {
        guard let threadId = params["threadId"]?.asString else { return }
        let sessionId = AppState.codexAppSessionPrefix + threadId
        sessions.removeValue(forKey: sessionId)
        detachTranscriptTailer(sessionId: sessionId)
        refreshDerivedState()
    }

    /// Map a ThreadStatus union onto our flat AgentStatus enum. Shared between the
    /// initial `thread/started` payload (which embeds the status) and the incremental
    /// `thread/status/changed` notification.
    static func applyCodexThreadStatus(
        _ snapshot: inout SessionSnapshot,
        status: [String: AnyCodableLike]?
    ) {
        guard let typeLabel = status?["type"]?.asString else { return }
        switch typeLabel {
        case "active":
            let flags: [AnyCodableLike]
            if case .array(let a) = status?["activeFlags"] ?? .null { flags = a } else { flags = [] }
            let flagStrings = flags.compactMap { $0.asString }
            if flagStrings.contains("waitingOnApproval") {
                snapshot.status = .waitingApproval
            } else if flagStrings.contains("waitingOnUserInput") {
                snapshot.status = .waitingQuestion
            } else {
                snapshot.status = .running
                snapshot.currentTool = nil
                snapshot.toolDescription = nil
            }
        case "idle":
            snapshot.status = .idle
            snapshot.currentTool = nil
            snapshot.toolDescription = nil
        case "systemError", "notLoaded":
            snapshot.status = .idle
        default:
            break
        }
    }

    // Instance method kept for convenience on call sites that already have `self`.
    fileprivate func applyCodexThreadStatus(
        _ snapshot: inout SessionSnapshot,
        status: [String: AnyCodableLike]?
    ) {
        AppState.applyCodexThreadStatus(&snapshot, status: status)
    }
}
