import Foundation
import CodeIslandCore

/// Metadata-safe context collected by the helper outside the provider payload.
public struct CodexHookContext: Equatable, Sendable {
    /// Current directory used only when the hook payload omits `cwd`.
    public let currentDirectory: String?

    /// Pre-sanitized terminal or native-app navigation handles.
    public let origin: OriginNavigation?

    /// Creates a context from already-collected metadata.
    public init(currentDirectory: String?, origin: OriginNavigation?) {
        self.currentDirectory = currentDirectory
        self.origin = origin?.isEmpty == true ? nil : origin
    }

    /// Creates a context from the helper's process environment.
    /// Only navigation identifiers are read; no arbitrary environment data is
    /// retained on the resulting value.
    public init(environment: [String: String], currentDirectory: String?) {
        let terminalSessionIdentifier = Self.firstValue(
            in: environment,
            keys: ["ITERM_SESSION_ID", "TERM_SESSION_ID"]
        )
        let workspaceIdentifier = Self.firstValue(
            in: environment,
            keys: ["CMUX_WORKSPACE_ID", "SUPERSET_WORKSPACE_ID", "ZELLIJ_SESSION_NAME"]
        )
        let paneIdentifier = Self.firstValue(
            in: environment,
            keys: [
                "TMUX_PANE",
                "CMUX_SURFACE_ID",
                "ZELLIJ_PANE_ID",
                "WEZTERM_PANE",
                "KITTY_WINDOW_ID",
                "SUPERSET_PANE_ID",
                "SUPERSET_TERMINAL_ID",
            ]
        )
        let origin = OriginNavigation(
            applicationBundleIdentifier: environment["__CFBundleIdentifier"],
            terminalSessionIdentifier: Self.itermIdentifier(terminalSessionIdentifier),
            workspaceIdentifier: workspaceIdentifier,
            paneIdentifier: paneIdentifier,
            tty: environment["TTY"]
        )

        self.currentDirectory = currentDirectory
        self.origin = origin.isEmpty ? nil : origin
    }

    private static func firstValue(in environment: [String: String], keys: [String]) -> String? {
        keys.lazy.compactMap { environment[$0] }.first { !$0.isEmpty }
    }

    private static func itermIdentifier(_ rawValue: String?) -> String? {
        guard let rawValue, let separator = rawValue.firstIndex(of: ":") else {
            return rawValue
        }
        return String(rawValue[rawValue.index(after: separator)...])
    }
}

/// The safe result of evaluating one transient Codex hook payload.
public struct CodexHookEvaluation: Equatable, Sendable {
    /// Sanitized lifecycle observation, or `nil` for invalid/unsupported input.
    public let observation: SessionObservation?

    /// Recognized Codex hook event used only to select a native no-op response.
    public let hookEvent: CodexManagedHookEvent?

    /// Immediate completion that leaves Codex's origin flow authoritative.
    public let completion: ProviderHookCompletion

    init(observation: SessionObservation?, hookEvent: CodexManagedHookEvent?) {
        self.observation = observation
        self.hookEvent = hookEvent
        self.completion = .continueInOrigin(for: hookEvent)
    }
}

/// Converts a transient Codex lifecycle payload directly into safe metadata.
/// No raw dictionary or content-bearing field escapes this adapter.
public struct CodexHookAdapter: Sendable {
    private static let maximumPayloadSize = 1_048_576

    /// Creates the stateless Codex lifecycle adapter.
    public init() {}

    /// Evaluates one transient payload and discards all content-bearing fields.
    public func evaluate(
        payload: Data,
        context: CodexHookContext,
        observedAt: Date
    ) -> CodexHookEvaluation {
        let parsed = parsedObservation(
            from: payload,
            context: context,
            observedAt: observedAt
        )
        return CodexHookEvaluation(
            observation: parsed?.observation,
            hookEvent: parsed?.hookEvent
        )
    }

    private func parsedObservation(
        from payload: Data,
        context: CodexHookContext,
        observedAt: Date
    ) -> (observation: SessionObservation, hookEvent: CodexManagedHookEvent?)? {
        guard payload.count <= Self.maximumPayloadSize,
              let raw = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let rawSessionID = safeString(raw["session_id"], maximumUTF8Count: 256),
              let sessionID = OpaqueSessionID(rawSessionID),
              let eventName = safeString(raw["hook_event_name"], maximumUTF8Count: 64),
              let transition = transition(for: eventName, payload: raw) else {
            return nil
        }

        let workingDirectory = safeString(raw["cwd"], maximumUTF8Count: 4_096)
            ?? context.currentDirectory
        let project = workingDirectory.flatMap(ProjectIdentity.init(workingDirectory:))
        let origin = origin(from: raw, fallback: context.origin)

        return (
            SessionObservation(
                provider: .codex,
                sessionID: sessionID,
                project: project,
                origin: origin,
                transition: transition,
                observedAt: observedAt
            ),
            CodexManagedHookEvent(rawValue: eventName)
        )
    }

    private func transition(
        for eventName: String,
        payload: [String: Any]
    ) -> SessionTransition? {
        switch eventName {
        case "SessionStart":
            // Codex reuses SessionStart after compaction. It is continuity for
            // the same session, not a new start.
            return safeString(payload["source"], maximumUTF8Count: 32) == "compact"
                ? .active
                : .started
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PreCompact", "PostCompact",
             "SubagentStart", "SubagentStop":
            return .active
        case "PermissionRequest":
            return .waitingForOrigin(.approval)
        case "Stop":
            return .completed
        case "SessionEnd":
            return .ended
        default:
            return nil
        }
    }

    private func origin(
        from raw: [String: Any],
        fallback: OriginNavigation?
    ) -> OriginNavigation? {
        let rawOrigin = OriginNavigation(
            applicationBundleIdentifier: safeString(raw["_term_bundle"], maximumUTF8Count: 255)
                ?? fallback?.applicationBundleIdentifier,
            terminalSessionIdentifier: firstSafeString(
                raw,
                keys: ["_iterm_session"],
                maximumUTF8Count: 512
            ) ?? fallback?.terminalSessionIdentifier,
            workspaceIdentifier: firstSafeString(
                raw,
                keys: ["_cmux_workspace_id", "_superset_workspace_id", "_zellij_session_name"],
                maximumUTF8Count: 512
            ) ?? fallback?.workspaceIdentifier,
            paneIdentifier: firstSafeString(
                raw,
                keys: [
                    "_tmux_pane",
                    "_cmux_surface_id",
                    "_zellij_pane_id",
                    "_wezterm_pane",
                    "_kitty_window",
                    "_superset_pane_id",
                ],
                maximumUTF8Count: 512
            ) ?? fallback?.paneIdentifier,
            tty: safeString(raw["_tty"], maximumUTF8Count: 4_096) ?? fallback?.tty
        )
        return rawOrigin.isEmpty ? nil : rawOrigin
    }

    private func firstSafeString(
        _ raw: [String: Any],
        keys: [String],
        maximumUTF8Count: Int
    ) -> String? {
        keys.lazy.compactMap { safeString(raw[$0], maximumUTF8Count: maximumUTF8Count) }.first
    }

    private func safeString(_ rawValue: Any?, maximumUTF8Count: Int) -> String? {
        guard let rawValue = rawValue as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= maximumUTF8Count,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return nil
        }
        return value
    }
}
