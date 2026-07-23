import Foundation

public enum SessionTitleSource: String, Sendable, Codable {
    case codexThreadName
    case claudeCustomTitle
    case claudeAiTitle
}

public struct SessionSnapshot: Sendable {
    public static let customCLIConfigsKey = "custom_cli_configs_v1"

    public static let supportedSources: Set<String> = [
        "claude",
        "codex",
        "gemini",
        "cursor",
        "cursor-cli",
        "trae",
        "traecn",
        "traecli",
        "copilot",
        "qoder",
        "qoder-cli",
        "qoderwork",
        "droid",
        "codebuddy",
        "codybuddycn",
        "stepfun",
        "opencode",
        "antigravity",
        "google-antigravity",
        "workbuddy",
        "hermes",
        "openclaw",
        "qwen",
        "kimi",
        "pi",
        "kiro",
        "cline",
        "zcode",
    ]

    public static let ideCompletionSources: Set<String> = [
        "cursor",
        "cursor-cli",
        "qoder",
        "qoder-cli",
        "trae",
        "traecn",
        "codebuddy",
        "codybuddycn",
    ]

    /// Desktop-IDE *host* sources. Their GUI host/helper processes (e.g.
    /// "Cursor Helper", "Trae Helper", the IDE's own `.../MacOS/<App>` binary)
    /// appear in the process ancestry of ANY CLI agent launched from that IDE's
    /// integrated terminal, and would be greedily matched by the loose
    /// `/<source>` substring rule in `CLIProcessResolver.sourceMatchesExecutablePath`.
    /// These must never be recovered via ancestry inference: a desktop IDE always
    /// reports itself explicitly through `--source`, or is detected via its
    /// dedicated `-cli` variant (`cursor-cli`, `qoder-cli`, `traecli`). Excluding
    /// them keeps e.g. Claude Code run inside Cursor's terminal — whose `claude`
    /// process is a source-less Node binary — from being mis-attributed to
    /// "cursor". (#220)
    public static let ideHostSources: Set<String> = [
        "cursor",
        "trae",
        "traecn",
        "qoder",
        "codebuddy",
        "codybuddycn",
        "stepfun",
        "antigravity",
        "google-antigravity",
    ]

    public var status: AgentStatus = .idle
    public var currentTool: String?
    public var toolDescription: String?
    public var lastActivity: Date = Date()
    public var cwd: String?
    public var model: String?
    public var permissionMode: String?
    public var toolHistory: [ToolHistoryEntry] = []
    public var totalToolCallCount: Int = 0
    public var subagents: [String: SubagentState] = [:]
    /// Agent ids closed by SubagentStop/Stop/SessionEnd.
    /// Blocks merge/fold from putting a finished subagent back on the parent.
    public var closedSubagentIds: Set<String> = []
    public var startTime: Date = Date()
    public var lastUserPrompt: String?
    public var lastAssistantMessage: String?
    /// Absolute path to the JSONL transcript currently backing this session. Populated
    /// by hooks (`transcript_path` field) and by filesystem discovery, consumed by the
    /// JSONLTailer for incremental streaming of the latest assistant reply.
    public var transcriptPath: String?
    /// Recent chat messages (max 3) for preview
    public var recentMessages: [ChatMessage] = []
    // Terminal info for window activation
    public var termApp: String?        // "iTerm.app", "Apple_Terminal", etc.
    public var itermSessionId: String?  // iTerm2 session ID for direct activation
    public var ttyPath: String?         // /dev/ttys00X
    public var kittyWindowId: String?   // Kitty window ID for precise focus
    public var tmuxPane: String?        // tmux pane identifier (%0, %1, etc.)
    public var tmuxClientTty: String?   // tmux client TTY for real terminal detection
    public var tmuxEnv: String?         // raw TMUX env var (socket info for non-default tmux server)
    public var termBundleId: String?    // __CFBundleIdentifier for precise terminal ID
    public var cmuxSurfaceId: String?   // cmux surface UUID (from CMUX_SURFACE_ID env var)
    public var cmuxWorkspaceId: String? // cmux workspace UUID (from CMUX_WORKSPACE_ID env var)
    public var zellijPaneId: String?    // Zellij pane id (numeric string) from ZELLIJ_PANE_ID env var
    public var zellijSessionName: String? // Zellij session name from ZELLIJ_SESSION_NAME env var
    public var weztermPaneId: String?   // WezTerm / Kaku pane id (numeric string) from WEZTERM_PANE env var
    public var supersetWorkspaceId: String? // Superset workspace UUID (from SUPERSET_WORKSPACE_ID env var); presence means running inside Superset
    public var supersetPaneId: String?  // Superset pane/terminal id (from SUPERSET_PANE_ID / SUPERSET_TERMINAL_ID env var)
    public var cliPid: pid_t?            // CLI process PID (from bridge _ppid)
    public var cliStartTime: Date?       // Start time of the tracked CLI PID (guards PID reuse)
    public var source: String = "claude" // "claude" or "codex"
    public var interrupted: Bool = false
    /// Cline-specific: true after TaskComplete/TaskCancel until the next TaskStart/TaskResume.
    /// Cline runs hooks asynchronously (background bridge), so events from prior tools can
    /// arrive after a TaskCancel and revive the session. This flag drops those stale events.
    public var taskRoundEnded: Bool = false
    public var sessionTitle: String?
    public var sessionTitleSource: SessionTitleSource?
    public var providerSessionId: String?
    public var remoteHostId: String?
    public var remoteHostName: String?
    /// nil = unchecked, false = not YOLO, true = YOLO
    public var isYoloMode: Bool?
    /// Checked-out git branch for cwd; refreshed on cwd changes and Stop
    /// (a turn may have switched branches). nil for non-repo and remote cwds.
    public var gitBranch: String?
    public var gitIsWorktree: Bool = false

    public init(startTime: Date = Date()) {
        self.startTime = startTime
    }

    public static func normalizedSupportedSource(_ source: String?) -> String? {
        guard let source else { return nil }
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        let aliases: [String: String] = [
            "factory": "droid",
            "ag": "antigravity",
            "anti-gravity": "antigravity",
            "anti gravity": "antigravity",
            // Google Antigravity (Gemini-based IDE/CLI). A SEPARATE product from
            // the "antigravity" Claude-Code fork above — it reads
            // ~/.gemini/config/hooks.json, not .antigravity/settings.json. Keep
            // the "ag"/"anti-gravity" aliases pointed at the fork; only these
            // explicit google-prefixed / -ide variants resolve here (#215).
            "googleantigravity": "google-antigravity",
            "google antigravity": "google-antigravity",
            "google-anti-gravity": "google-antigravity",
            "antigravity-ide": "google-antigravity",
            "antigravity-cli": "google-antigravity",
            "agy": "google-antigravity",
            "work-buddy": "workbuddy",
            "work body": "workbuddy",
            "work-body": "workbuddy",
            "workbody": "workbuddy",
            "hermes-agent": "hermes",
            "hermes-agents": "hermes",
            "hermes agent": "hermes",
            "hermes agents": "hermes",
            // OpenClaw (openclaw.ai) — personal-assistant Gateway daemon,
            // formerly branded Clawdbot. Keep the old name as an alias so
            // events from a not-yet-renamed install land on the same source.
            "open-claw": "openclaw",
            "open claw": "openclaw",
            "clawdbot": "openclaw",
            "qwen-code": "qwen",
            "qwencode": "qwen",
            "cursor-agent": "cursor-cli",
            "cursoragent": "cursor-cli",
            "cursorcli": "cursor-cli",
            "qodercli": "qoder-cli",
            // QoderWork — Qoder's standalone desktop assistant app (not the
            // IDE); own hooks file at ~/.qoderwork/settings.json (#249).
            "qoder-work": "qoderwork",
            "qoder work": "qoderwork",
            "kimi-cli": "kimi",
            "kimicli": "kimi",
            "kimi-code": "kimi",
            "kimicode": "kimi",
            "kimi_code": "kimi",
            "kimi-code-cli": "kimi",
            "kimicodecli": "kimi",
            "kimi_code_cli": "kimi",
            "kiro-cli": "kiro",
            "kirocli": "kiro",
            "codebuddycn": "codybuddycn",
            "codybuddy-cn": "codybuddycn",
            "step-fun": "stepfun",
            "step fun": "stepfun",
            "trae-cn": "traecn",
            "trae_cn": "traecn",
            "trae cn": "traecn",
            "traecli": "traecli",
            "omp": "pi",
            "oh-my-pi": "pi",
            "oh my pi": "pi",
            "z-code": "zcode",
            "z code": "zcode",
        ]
        let canonical = aliases[normalized] ?? normalized
        let dynamicSupportedSources = supportedSources.union(loadCustomSources())

        if dynamicSupportedSources.contains(canonical) { return canonical }
        // Match Google Antigravity variants BEFORE the bare "antigravity" prefix
        // clause below, so a "google-antigravity-*" sub-brand never falls through
        // to the Claude-fork source.
        if canonical.hasPrefix("google-antigravity") || canonical.hasPrefix("googleantigravity") { return "google-antigravity" }
        if canonical.hasPrefix("antigravity") { return "antigravity" }
        if canonical.hasPrefix("workbuddy") { return "workbuddy" }
        if canonical.hasPrefix("hermes") { return "hermes" }
        if canonical.hasPrefix("openclaw") { return "openclaw" }
        if canonical.hasPrefix("qwen") { return "qwen" }
        if canonical.hasPrefix("kiro") { return "kiro" }
        if canonical.hasPrefix("kimi") { return "kimi" }
        if canonical.hasPrefix("codybuddycn") || canonical.hasPrefix("codebuddycn") { return "codybuddycn" }
        if canonical.hasPrefix("stepfun") { return "stepfun" }
        if canonical.hasPrefix("traecn") { return "traecn" }
        if canonical.hasPrefix("traecli") { return "traecli" }
        if canonical.hasPrefix("trae") { return "trae" }
        return nil
    }

    private static func loadCustomSources() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: customCLIConfigsKey),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return Set(raw.compactMap { item in
            (item["source"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        }.filter { !$0.isEmpty })
    }

    private static func loadCustomSourceNames() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: customCLIConfigsKey),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }
        var names: [String: String] = [:]
        for item in raw {
            guard let source = (item["source"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                  !source.isEmpty else { continue }
            let display = (item["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let display, !display.isEmpty {
                names[source] = display
            }
        }
        return names
    }

    public var activeSubagentCount: Int {
        subagents.values.filter { $0.status != .idle }.count
    }

    public mutating func addRecentMessage(_ msg: ChatMessage, maxCount: Int = 3) {
        recentMessages.append(msg)
        if recentMessages.count > maxCount {
            recentMessages.removeFirst(recentMessages.count - maxCount)
        }
    }

    public mutating func insertRecentMessage(_ msg: ChatMessage, at index: Int, maxCount: Int = 3) {
        recentMessages.insert(msg, at: index)
        if recentMessages.count > maxCount {
            recentMessages.removeFirst(recentMessages.count - maxCount)
        }
    }

    public mutating func recordTool(_ tool: String, description: String?, success: Bool, agentType: String?, maxHistory: Int) {
        totalToolCallCount += 1
        let entry = ToolHistoryEntry(tool: tool, description: description, timestamp: Date(), success: success, agentType: agentType)
        toolHistory.append(entry)
        if toolHistory.count > maxHistory {
            toolHistory.removeFirst()
        }
    }

    /// Display name: project folder, or short session ID
    public var displayName: String {
        guard let cwd = cwd else { return "Session" }
        return Self.resolvedProjectDisplayName(from: cwd)
    }

    /// Directory names that are agent metadata, not user projects. Only these
    /// exact dot-dirs are peeled / treated as unhelpful — legitimate dot-named
    /// repos (.dotfiles, .config, .emacs.d) must keep their own name.
    static let agentMetadataDirNames: Set<String> = [
        ".claude", ".cursor", ".codex", ".gemini", ".qoder", ".qoderwork",
        ".trae", ".trae-cn", ".kiro", ".copilot", ".factory", ".codebuddy",
        ".codybuddycn", ".stepfun", ".workbuddy", ".hermes", ".kimi", ".kimi-code",
        ".pi", ".omp", ".qwen", ".zcode", ".openclaw", ".codeisland",
    ]

    /// Resolve a human project folder label from a cwd path.
    static func resolvedProjectDisplayName(from cwd: String) -> String {
        var name = displayNameLeafFromCursorProjectsPath(cwd)
            ?? (cwd as NSString).lastPathComponent

        // Agent metadata dirs (.claude, .cursor) are not project names (#248).
        if Self.agentMetadataDirNames.contains(name) {
            if let peeled = peelProjectNameBeforeMetadataDir(in: cwd, leaf: name) {
                name = peeled
            } else if isUnhelpfulHookCwd(cwd) {
                return "Session"
            }
        }

        if isHomeDirectoryPath(cwd) || isHomeDirectoryBasename(name, for: cwd) {
            return "Session"
        }

        if name.count >= 8 && name.allSatisfy(\.isNumber) {
            let parent = ((cwd as NSString).deletingLastPathComponent as NSString).lastPathComponent
            if !parent.isEmpty && parent != "/" && !isHomeDirectoryBasename(parent, for: cwd) {
                return parent
            }
        }
        return name
    }

    /// Cursor stores projects under `~/.cursor/projects/<encoded>/…` where slashes
    /// in the original workspace path become hyphens. Literal hyphens inside a
    /// folder name are preserved, so naive full-path reversal is ambiguous — walk
    /// hyphen segments from the right until the reconstructed path exists.
    /// Decode results are memoized: displayName is evaluated on every SwiftUI
    /// render of every session card, and the walk below stats the filesystem.
    /// NSCache is thread-safe and evicts under memory pressure.
    private static let cursorLeafCache = NSCache<NSString, NSString>()

    static func displayNameLeafFromCursorProjectsPath(_ cwd: String) -> String? {
        if let cached = cursorLeafCache.object(forKey: cwd as NSString) {
            return cached.length == 0 ? nil : (cached as String)
        }
        let result = computeDisplayNameLeafFromCursorProjectsPath(cwd)
        cursorLeafCache.setObject((result ?? "") as NSString, forKey: cwd as NSString)
        return result
    }

    private static func computeDisplayNameLeafFromCursorProjectsPath(_ cwd: String) -> String? {
        let marker = "/.cursor/projects/"
        guard let range = cwd.range(of: marker) else { return nil }
        let encoded = cwd[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        guard !encoded.isEmpty else { return nil }

        let homeEncoded = homeDirectoryProjectEncoded()
        let projectEncoded: String
        if encoded.hasPrefix(homeEncoded + "-") {
            projectEncoded = String(encoded.dropFirst(homeEncoded.count + 1))
        } else if encoded == homeEncoded {
            return nil
        } else {
            projectEncoded = encoded
        }
        guard !projectEncoded.isEmpty else { return nil }

        let parts = projectEncoded.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty else { return nil }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default
        // Prefer the longest leaf whose prefix reconstructs to a real directory.
        for k in stride(from: parts.count - 1, through: 0, by: -1) {
            let leaf = parts[k...].joined(separator: "-")
            guard !leaf.isEmpty else { continue }
            if k == 0 {
                return leaf
            }
            let relative = parts[..<k].joined(separator: "/") + "/" + leaf
            if fm.fileExists(atPath: "\(home)/\(relative)") {
                return leaf
            }
        }
        return parts.last
    }

    /// When cwd sits inside a metadata dir, or a Cursor-encoded leaf is one, peel
    /// back to the real project folder name.
    static func peelProjectNameBeforeMetadataDir(in cwd: String, leaf: String) -> String? {
        guard Self.agentMetadataDirNames.contains(leaf) else { return nil }

        if cwd.contains("/.cursor/projects/") {
            let marker = "/.cursor/projects/"
            guard let range = cwd.range(of: marker) else { return nil }
            let encoded = cwd[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
            if let peeled = peelEncodedProjectTailBeforeMetadataDir(encoded) {
                return peeled
            }
        }

        let parent = ((cwd as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let parentPath = (cwd as NSString).deletingLastPathComponent
        if !parent.isEmpty && parent != "/",
           !isHomeDirectoryPath(parentPath),
           !parent.contains("/.cursor/projects/"),
           !looksLikeCursorEncodedDir(parent) {
            return parent
        }
        return nil
    }

    /// Hook/bridge cwd values that carry no project identity — getcwd() inside
    /// `~/.claude` or at `$HOME` must not block workspace_roots / transcript_path.
    static func isUnhelpfulHookCwd(_ cwd: String) -> Bool {
        if isHomeDirectoryPath(cwd) { return true }
        let last = (cwd as NSString).lastPathComponent
        guard Self.agentMetadataDirNames.contains(last) else { return false }
        return isHomeDirectoryPath((cwd as NSString).deletingLastPathComponent)
    }

    static func isHomeDirectoryPath(_ path: String) -> Bool {
        let home = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).standardizingPath
        return (path as NSString).standardizingPath == home
    }

    static func isHomeDirectoryBasename(_ name: String, for cwd: String) -> Bool {
        name == (FileManager.default.homeDirectoryForCurrentUser.path as NSString).lastPathComponent
            && (isHomeDirectoryPath(cwd) || isUnhelpfulHookCwd(cwd))
    }

    static func peelEncodedProjectTailBeforeMetadataDir(_ encoded: String) -> String? {
        let homeEncoded = homeDirectoryProjectEncoded()
        let projectEncoded: String
        if encoded.hasPrefix(homeEncoded + "-") {
            projectEncoded = String(encoded.dropFirst(homeEncoded.count + 1))
        } else {
            projectEncoded = encoded
        }
        let parts = projectEncoded.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let last = parts.last,
              Self.agentMetadataDirNames.contains(last) else { return nil }
        let peeled = parts[parts.count - 2]
        return peeled.isEmpty ? nil : peeled
    }

    private static func looksLikeCursorEncodedDir(_ name: String) -> Bool {
        name.contains("-") && !name.hasPrefix(".")
    }

    private static func homeDirectoryProjectEncoded() -> String {
        var home = FileManager.default.homeDirectoryForCurrentUser.path
        if home.hasPrefix("/") { home = String(home.dropFirst()) }
        return home.replacingOccurrences(of: "/", with: "-")
    }

    public func displayTitle(sessionId: String) -> String {
        sessionLabel ?? sessionId
    }

    public func displaySessionId(sessionId: String) -> String {
        if let providerSessionId {
            let trimmed = providerSessionId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return sessionId
    }

    public var projectDisplayName: String {
        displayName
    }

    public var isRemote: Bool {
        guard let remoteHostId else { return false }
        return !remoteHostId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var remoteDisplayName: String? {
        guard let remoteHostName else { return nil }
        let trimmed = remoteHostName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public var sessionLabel: String? {
        guard let sessionTitle else { return nil }
        let trimmed = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Shortened model name: "claude-opus-4-6" → "opus"
    public var shortModelName: String? {
        guard let model = model else { return nil }
        let lower = model.lowercased()
        if lower.contains("opus") { return "opus" }
        if lower.contains("sonnet") { return "sonnet" }
        if lower.contains("haiku") { return "haiku" }
        if lower.contains("gemini") { return "gemini" }
        if let last = model.split(separator: "-").last, last.count <= 8 {
            return String(last)
        }
        return String(model.prefix(8))
    }

    /// Source label for display
    public var sourceLabel: String {
        switch source {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "gemini": return "Gemini"
        case "cursor": return "Cursor"
        case "cursor-cli": return "Cursor CLI"
        case "trae": return "Trae"
        case "traecn": return "Trae CN"
        case "traecli": return "Traecli"
        case "qoder": return "Qoder"
        case "qoder-cli": return "Qoder CLI"
        case "qoderwork": return "QoderWork"
        case "droid": return "Factory"
        case "codebuddy": return "CodeBuddy"
        case "codybuddycn": return "CodyBuddyCN"
        case "stepfun": return "StepFun"
        case "opencode": return "OpenCode"
        case "antigravity": return "AntiGravity"
        case "google-antigravity": return "Google Antigravity"
        case "workbuddy": return "WorkBuddy"
        case "hermes": return "Hermes"
        case "openclaw": return "OpenClaw"
        case "qwen": return "Qwen Code"
        case "kimi": return "Kimi Code CLI"
        case "pi": return "Pi"
        case "kiro": return "Kiro"
        case "cline": return "Cline"
        case "zcode": return "ZCode"
        default:
            if let customName = Self.loadCustomSourceNames()[source] {
                return customName
            }
            return source.capitalized
        }
    }

    public var isCodex: Bool { source == "codex" }
    public var isClaude: Bool { source == "claude" }

    /// True when the session runs inside a native app in APP mode (Cursor agent, Codex APP, etc.)
    /// — the app IS the agent, not just a terminal hosting a CLI.
    /// Requires both bundle ID AND source to match (Claude CLI in Cursor terminal ≠ native app mode).
    public var isNativeAppMode: Bool {
        guard let bid = termBundleId else { return false }
        guard let expectedSource = Self.appBundleSources[bid] else { return false }
        return source == expectedSource
    }

    /// True when the session runs inside an IDE's integrated terminal.
    /// We can't query IDE tab/pane state, so notification suppression should be skipped.
    public var isIDETerminal: Bool {
        guard let bid = termBundleId else { return false }
        if isNativeAppMode { return false }
        // Known apps used as terminal (e.g., Claude CLI in Cursor's integrated terminal)
        if Self.appBundleNames[bid] != nil { return true }
        let lower = bid.lowercased()
        return lower.contains("vscode") || lower.contains("vscodium")
            || lower == "com.trae.app"
            || lower.contains("windsurf") || lower.contains("codeium")
            || lower.contains("jetbrains")
            || lower.contains("zed")
            || lower.contains("xcode") || lower == "com.apple.dt.xcode"
            || lower.contains("panic.nova")
            || lower.contains("android.studio")
            || lower.contains("antigravity")
    }

    /// Bundle IDs of native apps (not terminals)
    private static let appBundleNames: [String: String] = [
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.trae.app": "Trae",
        "com.qoder.ide": "Qoder",
        "com.factory.app": "Factory",
        "com.tencent.codebuddy": "CodeBuddy",
        "com.tencent.codebuddy.cn": "CodyBuddyCN",
        "com.stepfun.app": "StepFun",
        "com.openai.codex": "Codex",
        "ai.opencode.desktop": "OpenCode",
        "com.google.antigravity": "Antigravity",
        // Claude Code Desktop (#211): local Code-tab sessions run the same engine
        // and fire the same ~/.claude/settings.json hooks as the CLI.
        "com.anthropic.claudefordesktop": "Claude",
    ]

    /// Maps native app bundle IDs to their expected source identifier.
    /// Used by isNativeAppMode to distinguish "Cursor agent" from "Claude CLI in Cursor terminal".
    private static let appBundleSources: [String: String] = [
        "com.todesktop.230313mzl4w4u92": "cursor",
        "com.trae.app": "trae",
        "com.qoder.ide": "qoder",
        "com.factory.app": "droid",
        "com.tencent.codebuddy": "codebuddy",
        "com.tencent.codebuddy.cn": "codybuddycn",
        "com.stepfun.app": "stepfun",
        "com.openai.codex": "codex",
        "ai.opencode.desktop": "opencode",
        // Google Antigravity IDE — its integrated terminal launches the agy CLI,
        // whose hooks report --source google-antigravity (#215).
        "com.google.antigravity": "google-antigravity",
        // Claude Code Desktop (#211) — hook subprocesses inherit the app's
        // __CFBundleIdentifier, so desktop Code sessions arrive tagged with it.
        "com.anthropic.claudefordesktop": "claude",
    ]

    /// Short terminal/app name for display tag
    public var terminalName: String? {
        if isRemote {
            return remoteDisplayName ?? "Remote"
        }
        // If termBundleId is a known app, show app name (APP mode)
        if let bid = termBundleId, let name = Self.appBundleNames[bid] {
            return name
        }
        // Check bundle ID for terminal identification (more reliable than TERM_PROGRAM)
        if let bid = termBundleId {
            let lower = bid.lowercased()
            if lower.contains("cmux") { return "cmux" }
            if lower.contains("warp") { return "Warp" }
            if lower == "com.mitchellh.ghostty" { return "Ghostty" }
            if lower.contains("iterm2") { return "iTerm2" }
            if lower.contains("kitty") { return "Kitty" }
            if lower.contains("alacritty") { return "Alacritty" }
            if lower.contains("wezterm") { return "WezTerm" }
            // IDE integrated terminals
            if lower.contains("vscode") || lower.contains("vscodium") { return "VS Code" }
            if lower == "com.trae.app" { return "Trae" }
            if lower.contains("windsurf") { return "Windsurf" }
            if lower.contains("jetbrains") {
                if lower.contains("intellij") { return "IDEA" }
                if lower.contains("pycharm") { return "PyCharm" }
                if lower.contains("webstorm") { return "WebStorm" }
                if lower.contains("goland") { return "GoLand" }
                if lower.contains("clion") { return "CLion" }
                if lower.contains("rider") { return "Rider" }
                if lower.contains("rubymine") { return "RubyMine" }
                if lower.contains("phpstorm") { return "PhpStorm" }
                if lower.contains("datagrip") { return "DataGrip" }
                return "JetBrains"
            }
            if lower.contains("zed") { return "Zed" }
            if lower.contains("xcode") || lower == "com.apple.dt.xcode" { return "Xcode" }
            if lower.contains("panic.nova") { return "Nova" }
            if lower.contains("android.studio") { return "Android Studio" }
            if lower.contains("antigravity") { return "Antigravity" }
        }
        // Superset spoofs TERM_PROGRAM to "kitty" and strips __CFBundleIdentifier, so the only
        // way to label it correctly is its own SUPERSET_* env vars. Check before the TERM_PROGRAM
        // fallback below, otherwise it would mislabel as "Kitty". (#213)
        if supersetWorkspaceId != nil || supersetPaneId != nil { return "Superset" }
        // Fallback to TERM_PROGRAM
        guard let app = termApp else { return nil }
        let lower = app.lowercased()
        if lower.contains("cmux") { return "cmux" }
        if lower == "ghostty" { return "Ghostty" }
        if lower.contains("iterm") { return "iTerm2" }
        if lower.contains("warp") { return "Warp" }
        if lower.contains("alacritty") { return "Alacritty" }
        if lower.contains("kitty") { return "Kitty" }
        if lower.contains("terminal") { return "Terminal" }
        return app
    }

    /// Subtitle: cwd path or model info
    public var subtitle: String? {
        if let cwd = cwd {
            // Show parent/folder instead of just folder
            let parts = cwd.split(separator: "/")
            let pathText: String
            if parts.count >= 2 {
                pathText = "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
            } else {
                pathText = cwd
            }
            if let remote = remoteDisplayName {
                return "\(pathText) · \(remote)"
            }
            return pathText
        }
        if let remote = remoteDisplayName {
            return remote
        }
        return model
    }
}

public struct SessionSummary {
    public let status: AgentStatus
    public let primarySource: String
    public let activeSessionCount: Int
    public let totalSessionCount: Int

    public init(status: AgentStatus, primarySource: String, activeSessionCount: Int, totalSessionCount: Int) {
        self.status = status
        self.primarySource = primarySource
        self.activeSessionCount = activeSessionCount
        self.totalSessionCount = totalSessionCount
    }
}

public func deriveSessionSummary(from sessions: [String: SessionSnapshot]) -> SessionSummary {
    var highestStatus: AgentStatus = .idle
    var source = "claude"
    var active = 0
    var mostRecentIdleSource: (source: String, time: Date)?

    for session in sessions.values {
        if session.status != .idle {
            active += 1
        } else if mostRecentIdleSource == nil || session.lastActivity > mostRecentIdleSource!.time {
            mostRecentIdleSource = (session.source, session.lastActivity)
        }

        switch session.status {
        case .waitingApproval:
            highestStatus = .waitingApproval
            source = session.source
        case .waitingQuestion:
            if highestStatus != .waitingApproval {
                highestStatus = .waitingQuestion
                source = session.source
            }
        case .running:
            if highestStatus == .idle || highestStatus == .processing {
                highestStatus = .running
                source = session.source
            }
        case .processing:
            if highestStatus == .idle {
                highestStatus = .processing
                source = session.source
            }
        case .idle:
            break
        }
    }

    if highestStatus == .idle, let idleSource = mostRecentIdleSource?.source {
        source = idleSource
    }

    return SessionSummary(
        status: highestStatus,
        primarySource: source,
        activeSessionCount: active,
        totalSessionCount: sessions.count
    )
}

// MARK: - Side Effects

public enum SideEffect: Equatable {
    case playSound(String)
    case tryMonitorSession(sessionId: String)
    case stopMonitor(sessionId: String)
    case removeSession(sessionId: String)
    case enqueueCompletion(sessionId: String)
    case setActiveSession(sessionId: String?)
}

// MARK: - Pure Reducer

/// Pure reducer: mutates sessions, returns side effects for the caller to execute.
public func reduceEvent(
    sessions: inout [String: SessionSnapshot],
    event: HookEvent,
    maxHistory: Int
) -> [SideEffect] {
    let sessionId = event.sessionId ?? "default"
    let eventName = EventNormalizer.normalize(event.eventName)
    var effects: [SideEffect] = []

    // Ensure session exists
    if sessions[sessionId] == nil {
        sessions[sessionId] = SessionSnapshot()
    }

    // Always update metadata from parent events. Subagent events are routed
    // through the parent session ID, so applying their full metadata here would
    // overwrite the parent's model/transcript/title with child-session values.
    // Still fill *missing* identity fields so a merge-first Task hook does not
    // leave the parent stuck as the default `source == "claude"`.
    if event.agentId == nil {
        extractMetadata(into: &sessions, sessionId: sessionId, event: event)
    } else {
        fillMissingParentMetadataFromSubagentEvent(into: &sessions, sessionId: sessionId, event: event)
    }
    let isRemote = sessions[sessionId]?.isRemote == true

    // Cline ships hooks via shell scripts that spawn the bridge in the background,
    // so events for the same session can arrive out of order. Once a task round
    // ends (TaskComplete/TaskCancel), drop any in-flight tool events that race in
    // afterwards — they would otherwise revive the session into .processing/.running.
    // The next TaskStart (SessionStart) or TaskResume (UserPromptSubmit) clears the flag.
    if sessions[sessionId]?.source == "cline",
       sessions[sessionId]?.taskRoundEnded == true,
       eventName != "SessionStart",
       eventName != "UserPromptSubmit" {
        return effects
    }

    // Route subagent-specific events
    if let agentId = event.agentId {
        let handled = handleSubagentEvent(
            sessions: &sessions,
            sessionId: sessionId,
            agentId: agentId,
            eventName: eventName,
            event: event,
            maxHistory: maxHistory,
            effects: &effects
        )
        if handled { return effects }
    }

    // Preserve actionable states: don't let activity updates overwrite waiting states
    let isWaiting = sessions[sessionId]?.status == .waitingApproval
        || sessions[sessionId]?.status == .waitingQuestion

    // Update this session's state
    switch eventName {
    case "UserPromptSubmit":
        sessions[sessionId]?.interrupted = false
        sessions[sessionId]?.taskRoundEnded = false
        sessions[sessionId]?.status = .processing
        sessions[sessionId]?.currentTool = nil
        sessions[sessionId]?.toolDescription = nil
        // Separate-mode Cursor Task Stop self-tombstones; a new prompt means relaunch.
        if let source = sessions[sessionId]?.source,
           source == "cursor" || source == "cursor-cli" {
            sessions[sessionId]?.closedSubagentIds.remove(sessionId)
        }
        // Probe a wider set of field names + nested containers. Qwen Code (#103),
        // Hermes (#117), and most Claude forks put the prompt at "prompt" top-level,
        // but some forks nest it inside `input` / `data` / `payload` / `params`,
        // and Cursor's `beforeSubmitPrompt` uses a different shape. Empty strings
        // are skipped so we don't insert blank chat rows when a hook fires with
        // a placeholder.
        let prompt = firstStringFromEvent(
            event,
            keys: ["prompt", "user_prompt", "userPrompt", "message", "input", "content", "text"],
            includeNested: true
        )
        if let prompt {
            sessions[sessionId]?.lastUserPrompt = prompt
            if sessions[sessionId]?.recentMessages.last?.isUser == true {
                sessions[sessionId]?.recentMessages.removeLast()
            }
            sessions[sessionId]?.addRecentMessage(ChatMessage(isUser: true, text: prompt))
        }
    case "PreToolUse":
        if !isWaiting {
            sessions[sessionId]?.status = .running
            sessions[sessionId]?.currentTool = event.toolName
            sessions[sessionId]?.toolDescription = event.toolDescription
        }
    case "PostToolUse":
        if let tool = sessions[sessionId]?.currentTool {
            let desc = sessions[sessionId]?.toolDescription
            sessions[sessionId]?.recordTool(tool, description: desc, success: true, agentType: nil, maxHistory: maxHistory)
        }
        if !isWaiting {
            sessions[sessionId]?.status = .processing
            sessions[sessionId]?.currentTool = nil
            sessions[sessionId]?.toolDescription = nil
        }
    case "PostToolUseFailure":
        if let tool = sessions[sessionId]?.currentTool {
            let desc = sessions[sessionId]?.toolDescription
            sessions[sessionId]?.recordTool(tool, description: desc, success: false, agentType: nil, maxHistory: maxHistory)
        }
        if !isWaiting {
            sessions[sessionId]?.status = .processing
            sessions[sessionId]?.currentTool = nil
            sessions[sessionId]?.toolDescription = nil
        }
    case "PermissionDenied":
        if !isWaiting {
            sessions[sessionId]?.status = .processing
            sessions[sessionId]?.currentTool = nil
            sessions[sessionId]?.toolDescription = nil
        }
    case "SubagentStart":
        if !isWaiting {
            sessions[sessionId]?.status = .running
            sessions[sessionId]?.currentTool = "Agent"
            sessions[sessionId]?.toolDescription = event.rawJSON["agent_type"] as? String
        }
    case "SubagentStop":
        if !isWaiting {
            sessions[sessionId]?.status = .processing
            sessions[sessionId]?.currentTool = nil
            sessions[sessionId]?.toolDescription = nil
        }
    case "AfterAgentResponse":
        // Cursor-specific: AI reply arrives here (in "text" field), not in Stop
        let responseText = firstStringFromEvent(
            event,
            keys: ["text", "message"],
            includeNested: true
        )
        if let text = responseText, !text.isEmpty {
            sessions[sessionId]?.lastAssistantMessage = text
            sessions[sessionId]?.addRecentMessage(ChatMessage(isUser: false, text: text))
        }
        let hasActiveSubagents = sessions[sessionId]?.subagents.values.contains {
            $0.status != .idle
        } == true
        if let source = sessions[sessionId]?.source,
           SessionSnapshot.ideCompletionSources.contains(source) {
            // Parent chat finished a turn while folded Tasks are still working —
            // keep the card active and do not pop a premature completion.
            if hasActiveSubagents {
                if !isWaiting {
                    sessions[sessionId]?.status = .running
                    if sessions[sessionId]?.currentTool == nil {
                        sessions[sessionId]?.currentTool = "Agent"
                    }
                }
            } else {
                sessions[sessionId]?.status = .idle
                sessions[sessionId]?.currentTool = nil
                sessions[sessionId]?.toolDescription = nil
                effects.append(.enqueueCompletion(sessionId: sessionId))
            }
        } else {
            sessions[sessionId]?.status = .processing
        }
    case "TaskRoundComplete":
        sessions[sessionId]?.interrupted = (event.eventName == "TaskCancel")
        sessions[sessionId]?.status = .processing
        sessions[sessionId]?.currentTool = nil
        sessions[sessionId]?.toolDescription = nil
        let assistantMsg = firstStringFromEvent(
            event,
            keys: ["last_assistant_message", "text", "message", "summary"],
            includeNested: true
        )
        if let msg = assistantMsg {
            sessions[sessionId]?.lastAssistantMessage = msg
            sessions[sessionId]?.addRecentMessage(ChatMessage(isUser: false, text: msg))
        } else if sessions[sessionId]?.lastAssistantMessage == nil,
                  sessions[sessionId]?.recentMessages.last?.isUser == true {
            sessions[sessionId]?.addRecentMessage(ChatMessage(isUser: false, text: "[回复完成]"))
        }
        // Cline tasks are single-round — treat completion/cancellation as session end,
        // and latch a flag so out-of-order in-flight tool events don't revive it.
        if sessions[sessionId]?.source == "cline" {
            sessions[sessionId]?.status = .idle
            sessions[sessionId]?.taskRoundEnded = true
        }
        effects.append(.enqueueCompletion(sessionId: sessionId))
    case "Stop":
        // Detect ESC/Ctrl+C interruption
        let stopReason = event.rawJSON["stop_reason"] as? String ?? ""
        let wasInterrupted = (stopReason == "user" || stopReason == "interrupted")
        let hasActiveSubagents = sessions[sessionId]?.subagents.values.contains {
            $0.status != .idle
        } == true
        // Separate-mode Cursor Tasks have no agent_id, so merge later must see
        // this id as closed — otherwise a still-live IDE `_ppid` resuscitates them.
        // Only self-tombstone foldable Task cards (transcript parent ≠ session id),
        // never the parent chat — that would suppress late Permission UI and wipe
        // the IDE `_ppid` monitor after a normal turn Stop.
        if !hasActiveSubagents,
           let source = sessions[sessionId]?.source,
           source == "cursor" || source == "cursor-cli",
           CursorSessionFolding.foldTarget(
               childSessionId: sessionId,
               transcriptPath: sessions[sessionId]?.transcriptPath
           ) != nil {
            sessions[sessionId]?.closedSubagentIds.insert(sessionId)
            // Drop process identity so a still-open IDE `_ppid` does not look like
            // a live Task after Stop when the card is later considered for merge.
            sessions[sessionId]?.cliPid = nil
            sessions[sessionId]?.cliStartTime = nil
        }

        let assistantMsg = firstStringFromEvent(
            event,
            keys: ["last_assistant_message", "text", "message", "summary"],
            includeNested: true
        )
        if let msg = assistantMsg {
            sessions[sessionId]?.lastAssistantMessage = msg
            sessions[sessionId]?.addRecentMessage(ChatMessage(isUser: false, text: msg))
        } else if sessions[sessionId]?.lastAssistantMessage == nil,
                  sessions[sessionId]?.recentMessages.last?.isUser == true {
            // No reply content from hook (e.g. CodeBuddy) -- add placeholder
            sessions[sessionId]?.addRecentMessage(ChatMessage(isUser: false, text: "[回复完成]"))
        }
        // Try to capture user prompt from Stop event if not already set
        if sessions[sessionId]?.lastUserPrompt == nil {
            if let prompt = event.rawJSON["last_user_message"] as? String {
                sessions[sessionId]?.lastUserPrompt = prompt
                let insertAt = max(0, (sessions[sessionId]?.recentMessages.count ?? 1) - 1)
                sessions[sessionId]?.insertRecentMessage(ChatMessage(isUser: true, text: prompt), at: insertAt)
            }
        }

        // Parent chat Stop while folded Tasks are still working — keep the card
        // active and do not pop a premature completion (same as AfterAgentResponse).
        if hasActiveSubagents {
            if !isWaiting {
                sessions[sessionId]?.status = .running
                if sessions[sessionId]?.currentTool == nil {
                    sessions[sessionId]?.currentTool = "Agent"
                }
            }
            // Do not latch `interrupted` onto a still-active parent+Task card.
        } else {
            sessions[sessionId]?.interrupted = wasInterrupted
            sessions[sessionId]?.status = .idle
            sessions[sessionId]?.currentTool = nil
            sessions[sessionId]?.toolDescription = nil
            effects.append(.enqueueCompletion(sessionId: sessionId))
        }
    case "SessionStart":
        effects.append(.stopMonitor(sessionId: sessionId))
        sessions[sessionId] = SessionSnapshot(startTime: Date())
        // Re-apply metadata from this event (common extraction above wrote to the old session)
        if let cwd = event.rawJSON["cwd"] as? String, !cwd.isEmpty { sessions[sessionId]?.cwd = cwd }
        if let model = event.rawJSON["model"] as? String, !model.isEmpty { sessions[sessionId]?.model = model }
        if let ppid = event.rawJSON["_ppid"] as? Int, ppid > 0 {
            let newPid = pid_t(ppid)
            if sessions[sessionId]?.cliPid != newPid {
                sessions[sessionId]?.cliPid = newPid
                sessions[sessionId]?.cliStartTime = nil
            }
        }
        if let source = SessionSnapshot.normalizedSupportedSource(event.rawJSON["_source"] as? String) {
            sessions[sessionId]?.source = source
        }
        if let app = event.rawJSON["_term_app"] as? String, !app.isEmpty { sessions[sessionId]?.termApp = app }
        if let bundle = event.rawJSON["_term_bundle"] as? String, !bundle.isEmpty { sessions[sessionId]?.termBundleId = bundle }
        if let ses = event.rawJSON["_iterm_session"] as? String, !ses.isEmpty { sessions[sessionId]?.itermSessionId = ses }
        if let tty = event.rawJSON["_tty"] as? String, !tty.isEmpty { sessions[sessionId]?.ttyPath = tty }
        if let kitty = event.rawJSON["_kitty_window"] as? String, !kitty.isEmpty { sessions[sessionId]?.kittyWindowId = kitty }
        if let pane = event.rawJSON["_tmux_pane"] as? String, !pane.isEmpty { sessions[sessionId]?.tmuxPane = pane }
        if let tmuxTty = event.rawJSON["_tmux_client_tty"] as? String, !tmuxTty.isEmpty { sessions[sessionId]?.tmuxClientTty = tmuxTty }
        if let tmux = event.rawJSON["_tmux"] as? String, !tmux.isEmpty { sessions[sessionId]?.tmuxEnv = tmux }
        if let mode = event.rawJSON["permission_mode"] as? String { sessions[sessionId]?.permissionMode = mode }
        if let roots = event.rawJSON["workspace_roots"] as? [String], let first = roots.first, !first.isEmpty {
            sessions[sessionId]?.cwd = first
        }
        // cmux surface / workspace (restore directly from payload on SessionStart to avoid extractMetadata ordering dependency)
        if let surface = event.rawJSON["_cmux_surface_id"] as? String, !surface.isEmpty {
            sessions[sessionId]?.cmuxSurfaceId = surface
        }
        if let workspace = event.rawJSON["_cmux_workspace_id"] as? String, !workspace.isEmpty {
            sessions[sessionId]?.cmuxWorkspaceId = workspace
        }
        if let zellijPane = event.rawJSON["_zellij_pane_id"] as? String, !zellijPane.isEmpty {
            sessions[sessionId]?.zellijPaneId = zellijPane
        }
        if let zellijSession = event.rawJSON["_zellij_session_name"] as? String, !zellijSession.isEmpty {
            sessions[sessionId]?.zellijSessionName = zellijSession
        }
        if let weztermPane = event.rawJSON["_wezterm_pane"] as? String, !weztermPane.isEmpty {
            sessions[sessionId]?.weztermPaneId = weztermPane
        }
        if let supersetWs = event.rawJSON["_superset_workspace_id"] as? String, !supersetWs.isEmpty {
            sessions[sessionId]?.supersetWorkspaceId = supersetWs
        }
        if let supersetPane = event.rawJSON["_superset_pane_id"] as? String, !supersetPane.isEmpty {
            sessions[sessionId]?.supersetPaneId = supersetPane
        }
        if let env = event.rawJSON["_env"] as? [String: String] {
            applyEnvMetadata(into: &sessions, sessionId: sessionId, env: env)
        }
        if let remoteHostId = event.rawJSON["_remote_host_id"] as? String, !remoteHostId.isEmpty {
            sessions[sessionId]?.remoteHostId = remoteHostId
        }
        if let remoteHostName = event.rawJSON["_remote_host_name"] as? String, !remoteHostName.isEmpty {
            sessions[sessionId]?.remoteHostName = remoteHostName
        }
        if let providerSessionId = event.rawJSON["session_id"] as? String, !providerSessionId.isEmpty,
           sessions[sessionId]?.isRemote == true {
            sessions[sessionId]?.providerSessionId = providerSessionId
        }
        if let sessionTitle = event.rawJSON["session_title"] as? String,
           !sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sessions[sessionId]?.sessionTitle = sessionTitle
        }
        if !isRemote {
            effects.append(.tryMonitorSession(sessionId: sessionId))
        }
    case "SessionEnd":
        // Side effect: AppState handles pending permission deny before removal
        effects.append(.removeSession(sessionId: sessionId))
        return effects
    case "Notification":
        let notificationText = firstStringFromEvent(
            event,
            keys: ["message", "text", "summary", "status", "detail"],
            includeNested: true
        )
        if let msg = notificationText, !msg.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            sessions[sessionId]?.toolDescription = msg
        }
        if QuestionPayload.from(event: event) != nil {
            sessions[sessionId]?.status = .waitingQuestion
        }
    case "PreCompact":
        sessions[sessionId]?.status = .processing
        sessions[sessionId]?.toolDescription = "Compacting context\u{2026}"
    default:
        break
    }

    sessions[sessionId]?.lastActivity = Date()

    // Ensure process monitor is set up (covers sessions created implicitly)
    if sessions[sessionId]?.cwd != nil, !isRemote {
        effects.append(.tryMonitorSession(sessionId: sessionId))
    }

    // Trigger sound for this event
    effects.append(.playSound(eventName))

    // Switch display to the session that just had activity
    if eventName == "Stop" {
        // Stop event: keep activeSessionId on completed session (set by enqueueCompletion)
    } else if sessions[sessionId]?.status != .idle {
        effects.append(.setActiveSession(sessionId: sessionId))
    }
    // Note: the "else if activeSessionId == sessionId → mostActive" case
    // is handled by AppState since it needs to check current activeSessionId

    return effects
}

// MARK: - Private Helpers

private func applyEnvMetadata(into sessions: inout [String: SessionSnapshot], sessionId: String, env: [String: String]) {
    if sessions[sessionId]?.termApp == nil,
       let app = env["TERM_PROGRAM"], !app.isEmpty {
        sessions[sessionId]?.termApp = app
    }
    if sessions[sessionId]?.termBundleId == nil,
       let bundle = env["__CFBundleIdentifier"], !bundle.isEmpty {
        sessions[sessionId]?.termBundleId = bundle
    }
    if sessions[sessionId]?.itermSessionId == nil,
       let ses = env["ITERM_SESSION_ID"], !ses.isEmpty {
        if let colonIdx = ses.firstIndex(of: ":") {
            sessions[sessionId]?.itermSessionId = String(ses[ses.index(after: colonIdx)...])
        } else {
            sessions[sessionId]?.itermSessionId = ses
        }
    }
    if sessions[sessionId]?.kittyWindowId == nil,
       let kitty = env["KITTY_WINDOW_ID"], !kitty.isEmpty {
        sessions[sessionId]?.kittyWindowId = kitty
    }
    if sessions[sessionId]?.tmuxEnv == nil,
       let tmux = env["TMUX"], !tmux.isEmpty {
        sessions[sessionId]?.tmuxEnv = tmux
    }
    if sessions[sessionId]?.tmuxPane == nil,
       let pane = env["TMUX_PANE"], !pane.isEmpty {
        sessions[sessionId]?.tmuxPane = pane
    }
    if sessions[sessionId]?.cmuxSurfaceId == nil,
       let surface = env["CMUX_SURFACE_ID"], !surface.isEmpty {
        sessions[sessionId]?.cmuxSurfaceId = surface
    }
    if sessions[sessionId]?.cmuxWorkspaceId == nil,
       let workspace = env["CMUX_WORKSPACE_ID"], !workspace.isEmpty {
        sessions[sessionId]?.cmuxWorkspaceId = workspace
    }
    if sessions[sessionId]?.zellijPaneId == nil,
       let pane = env["ZELLIJ_PANE_ID"], !pane.isEmpty {
        sessions[sessionId]?.zellijPaneId = pane
    }
    if sessions[sessionId]?.zellijSessionName == nil,
       let name = env["ZELLIJ_SESSION_NAME"], !name.isEmpty {
        sessions[sessionId]?.zellijSessionName = name
    }
    if sessions[sessionId]?.weztermPaneId == nil,
       let pane = env["WEZTERM_PANE"], !pane.isEmpty {
        sessions[sessionId]?.weztermPaneId = pane
    }
    if sessions[sessionId]?.supersetWorkspaceId == nil,
       let workspace = env["SUPERSET_WORKSPACE_ID"], !workspace.isEmpty {
        sessions[sessionId]?.supersetWorkspaceId = workspace
    }
    if sessions[sessionId]?.supersetPaneId == nil,
       let pane = env["SUPERSET_PANE_ID"] ?? env["SUPERSET_TERMINAL_ID"], !pane.isEmpty {
        sessions[sessionId]?.supersetPaneId = pane
    }
}

/// Fill identity fields on a parent card from a merged Task/subagent hook.
/// Unlike `extractMetadata`, never overwrites values already set on the parent
/// (child payloads can carry Task-specific cwd/model/title).
public func fillMissingParentMetadataFromSubagentEvent(
    into sessions: inout [String: SessionSnapshot],
    sessionId: String,
    event: HookEvent
) {
    // Default SessionSnapshot.source is "claude". Upgrade when the hook carries a
    // real source so merge-first Cursor Tasks are not branded as Claude forever.
    if sessions[sessionId]?.source == "claude",
       let source = SessionSnapshot.normalizedSupportedSource(event.rawJSON["_source"] as? String)
        ?? SessionSnapshot.normalizedSupportedSource(event.rawJSON["source"] as? String),
       source != "claude" {
        sessions[sessionId]?.source = source
    }

    let cwdMissing = sessions[sessionId]?.cwd == nil
        || SessionSnapshot.isUnhelpfulHookCwd(sessions[sessionId]?.cwd ?? "")
    if cwdMissing {
        if let cwd = event.rawJSON["cwd"] as? String, !cwd.isEmpty,
           !SessionSnapshot.isUnhelpfulHookCwd(cwd) {
            sessions[sessionId]?.cwd = cwd
        } else if let roots = event.rawJSON["workspace_roots"] as? [String],
                  let first = roots.first, !first.isEmpty {
            sessions[sessionId]?.cwd = first
        } else if let tp = event.rawJSON["transcript_path"] as? String,
                  tp.contains("/.cursor/projects/") {
            let parts = tp.split(separator: "/")
            if let idx = parts.firstIndex(of: "projects"), idx + 1 < parts.count {
                let projectName = String(parts[idx + 1])
                sessions[sessionId]?.cwd = "/\(parts[...idx].joined(separator: "/"))/\(projectName)"
            }
        }
    }

    if sessions[sessionId]?.transcriptPath == nil,
       let transcriptPath = event.rawJSON["transcript_path"] as? String, !transcriptPath.isEmpty {
        sessions[sessionId]?.transcriptPath = transcriptPath
    }

    if sessions[sessionId]?.cliPid == nil,
       let ppid = event.rawJSON["_ppid"] as? Int, ppid > 0 {
        sessions[sessionId]?.cliPid = pid_t(ppid)
    }
}

private func shouldReopenCursorSubagentOnPrompt(event: HookEvent, session: SessionSnapshot?) -> Bool {
    if (event.rawJSON["_cursor_subagent"] as? Bool) == true {
        return true
    }
    let source = SessionSnapshot.normalizedSupportedSource(event.rawJSON["_source"] as? String)
        ?? SessionSnapshot.normalizedSupportedSource(event.rawJSON["source"] as? String)
        ?? session?.source
    return source == "cursor" || source == "cursor-cli"
}

public func extractMetadata(into sessions: inout [String: SessionSnapshot], sessionId: String, event: HookEvent) {
    let eventCwd = event.rawJSON["cwd"] as? String
    if let cwd = eventCwd, !cwd.isEmpty,
       !SessionSnapshot.isUnhelpfulHookCwd(cwd) {
        sessions[sessionId]?.cwd = cwd
    }
    if sessions[sessionId]?.cwd == nil
        || SessionSnapshot.isUnhelpfulHookCwd(sessions[sessionId]?.cwd ?? ""),
       let roots = event.rawJSON["workspace_roots"] as? [String],
       let first = roots.first, !first.isEmpty {
        sessions[sessionId]?.cwd = first
    } else if sessions[sessionId]?.cwd == nil
        || SessionSnapshot.isUnhelpfulHookCwd(sessions[sessionId]?.cwd ?? ""),
              let tp = event.rawJSON["transcript_path"] as? String,
              tp.contains("/.cursor/projects/") {
        // Cursor: extract project dir from transcript_path
        // e.g. ~/.cursor/projects/<project>/agent-transcripts/... → ~/.cursor/projects/<project>
        // Must stay Cursor-scoped: Claude transcripts also contain a "projects"
        // component (~/.claude/projects/<encoded>/…) that is not a workspace.
        let parts = tp.split(separator: "/")
        if let idx = parts.firstIndex(of: "projects"), idx + 1 < parts.count {
            let projectName = String(parts[idx + 1])
            sessions[sessionId]?.cwd = "/\(parts[...idx].joined(separator: "/"))/\(projectName)"
        }
    } else if sessions[sessionId]?.cwd == nil, let cwd = eventCwd, !cwd.isEmpty {
        // Last resort: an unhelpful cwd ($HOME, ~/.claude) still beats nil —
        // transcript-based model lookup keys off it, and the display layer
        // already renders these paths as "Session".
        sessions[sessionId]?.cwd = cwd
    }
    // Git branch resolution is NOT done here: this reducer runs on the main
    // actor and .git probing can block on network mounts. AppState refreshes
    // it asynchronously after reduce (maybeRefreshGitBranch).
    if let model = event.rawJSON["model"] as? String, !model.isEmpty {
        sessions[sessionId]?.model = model
    }
    if let mode = event.rawJSON["permission_mode"] as? String {
        sessions[sessionId]?.permissionMode = mode
    }
    // Hooks frequently include the absolute transcript path — capture it so the tailer
    // can attach to live appends without needing a filesystem scan to rediscover it.
    if let transcriptPath = event.rawJSON["transcript_path"] as? String, !transcriptPath.isEmpty {
        sessions[sessionId]?.transcriptPath = transcriptPath
    }
    // Terminal info (injected by hook script)
    if let app = event.rawJSON["_term_app"] as? String, !app.isEmpty, app != "unknown" {
        sessions[sessionId]?.termApp = app
    }
    if let ses = event.rawJSON["_iterm_session"] as? String, !ses.isEmpty {
        sessions[sessionId]?.itermSessionId = ses
    }
    if let tty = event.rawJSON["_tty"] as? String, !tty.isEmpty {
        sessions[sessionId]?.ttyPath = tty
    }
    // Extended terminal info (from native bridge binary)
    if let kitty = event.rawJSON["_kitty_window"] as? String, !kitty.isEmpty {
        sessions[sessionId]?.kittyWindowId = kitty
    }
    if let pane = event.rawJSON["_tmux_pane"] as? String, !pane.isEmpty {
        sessions[sessionId]?.tmuxPane = pane
    }
    if let tmuxTty = event.rawJSON["_tmux_client_tty"] as? String, !tmuxTty.isEmpty {
        sessions[sessionId]?.tmuxClientTty = tmuxTty
    }
    if let tmux = event.rawJSON["_tmux"] as? String, !tmux.isEmpty {
        sessions[sessionId]?.tmuxEnv = tmux
    }
    if let bundle = event.rawJSON["_term_bundle"] as? String, !bundle.isEmpty {
        sessions[sessionId]?.termBundleId = bundle
    }
    // Fallback: extract terminal/multiplexer info from _env sub-object (direct plugin format)
    if let env = event.rawJSON["_env"] as? [String: String] {
        applyEnvMetadata(into: &sessions, sessionId: sessionId, env: env)
    }
    if let ppid = event.rawJSON["_ppid"] as? Int, ppid > 0 {
        let newPid = pid_t(ppid)
        if sessions[sessionId]?.cliPid != newPid {
            sessions[sessionId]?.cliPid = newPid
            sessions[sessionId]?.cliStartTime = nil
        }
    }
    if let source = SessionSnapshot.normalizedSupportedSource(event.rawJSON["_source"] as? String) {
        sessions[sessionId]?.source = source
    }
    // cmux surface / workspace (injected by bridge from CMUX_SURFACE_ID / CMUX_WORKSPACE_ID env vars)
    if let surface = event.rawJSON["_cmux_surface_id"] as? String, !surface.isEmpty {
        sessions[sessionId]?.cmuxSurfaceId = surface
    }
    if let workspace = event.rawJSON["_cmux_workspace_id"] as? String, !workspace.isEmpty {
        sessions[sessionId]?.cmuxWorkspaceId = workspace
    }
    // Zellij multiplexer pane / session (injected by bridge from ZELLIJ_* env vars)
    if let zellijPane = event.rawJSON["_zellij_pane_id"] as? String, !zellijPane.isEmpty {
        sessions[sessionId]?.zellijPaneId = zellijPane
    }
    if let zellijSession = event.rawJSON["_zellij_session_name"] as? String, !zellijSession.isEmpty {
        sessions[sessionId]?.zellijSessionName = zellijSession
    }
    // WezTerm / Kaku pane id (injected by bridge from WEZTERM_PANE env var)
    if let weztermPane = event.rawJSON["_wezterm_pane"] as? String, !weztermPane.isEmpty {
        sessions[sessionId]?.weztermPaneId = weztermPane
    }
    // Superset workspace / pane (injected by bridge from SUPERSET_* env vars). Presence routes
    // activation to com.superset.desktop instead of the spoofed kitty TERM_PROGRAM. (#213)
    if let supersetWs = event.rawJSON["_superset_workspace_id"] as? String, !supersetWs.isEmpty {
        sessions[sessionId]?.supersetWorkspaceId = supersetWs
    }
    if let supersetPane = event.rawJSON["_superset_pane_id"] as? String, !supersetPane.isEmpty {
        sessions[sessionId]?.supersetPaneId = supersetPane
    }
    if let remoteHostId = event.rawJSON["_remote_host_id"] as? String, !remoteHostId.isEmpty {
        sessions[sessionId]?.remoteHostId = remoteHostId
    }
    if let remoteHostName = event.rawJSON["_remote_host_name"] as? String, !remoteHostName.isEmpty {
        sessions[sessionId]?.remoteHostName = remoteHostName
    }
    if sessions[sessionId]?.isRemote == true,
       let providerSessionId = event.rawJSON["session_id"] as? String,
       !providerSessionId.isEmpty {
        sessions[sessionId]?.providerSessionId = providerSessionId
    }
    if let sessionTitle = event.rawJSON["session_title"] as? String,
       !sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        sessions[sessionId]?.sessionTitle = sessionTitle
    }
}

/// Pull a non-empty string from a hook JSON value.
/// Supports plain strings and content-part arrays such as Kimi Code CLI's
/// `prompt: [{ "type": "text", "text": "..." }]`.
private func stringFromHookJSONValue(_ value: Any?) -> String? {
    if let value = value as? String {
        // Trim only to detect empty / whitespace-only payloads; return the
        // original value so callers preserve any leading/trailing
        // whitespace inside code-snippet prompts and multi-line content.
        return value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
            ? nil : value
    }

    let parts: [[String: Any]]
    if let typed = value as? [[String: Any]] {
        parts = typed
    } else if let anyParts = value as? [Any] {
        parts = anyParts.compactMap { $0 as? [String: Any] }
        if parts.isEmpty { return nil }
    } else {
        return nil
    }

    let texts = parts.compactMap { part -> String? in
        if let type = part["type"] as? String, type != "text" { return nil }
        guard let text = part["text"] as? String,
              !text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }
    let joined = texts.joined()
    return joined.isEmpty ? nil : joined
}

private func firstStringFromDict(_ dict: [String: Any], keys: [String]) -> String? {
    for key in keys {
        if let value = stringFromHookJSONValue(dict[key]) {
            return value
        }
    }
    return nil
}

private func firstStringFromEvent(_ event: HookEvent, keys: [String], includeNested: Bool) -> String? {
    if let value = firstStringFromDict(event.rawJSON, keys: keys) {
        return value
    }
    if includeNested {
        for containerKey in ["payload", "data"] {
            if let nested = event.rawJSON[containerKey] as? [String: Any],
               let value = firstStringFromDict(nested, keys: keys) {
                return value
            }
        }
    }
    return nil
}

private func subagentType(from event: HookEvent) -> String {
    firstStringFromEvent(event, keys: ["agent_type", "agentType"], includeNested: false) ?? "Agent"
}

private func ensureSubagent(
    sessions: inout [String: SessionSnapshot],
    sessionId: String,
    agentId: String,
    event: HookEvent
) -> Bool {
    // Only SubagentStart/SessionStart may reopen a closed agent id for most
    // providers. Cursor Tasks relaunch via UserPromptSubmit (see handleSubagentEvent).
    // Later tool/response hooks with the same agent_id must not revive it.
    if sessions[sessionId]?.closedSubagentIds.contains(agentId) == true {
        return false
    }
    if sessions[sessionId]?.subagents[agentId] == nil {
        sessions[sessionId]?.subagents[agentId] = SubagentState(
            agentId: agentId,
            agentType: subagentType(from: event)
        )
    }
    return true
}

/// Handle subagent events. Returns true if the event was consumed.
private func handleSubagentEvent(
    sessions: inout [String: SessionSnapshot],
    sessionId: String,
    agentId: String,
    eventName: String,
    event: HookEvent,
    maxHistory: Int,
    effects: inout [SideEffect]
) -> Bool {
    switch eventName {
    case "SubagentStart", "SessionStart":
        let agentType = subagentType(from: event)
        sessions[sessionId]?.closedSubagentIds.remove(agentId)
        sessions[sessionId]?.subagents[agentId] = SubagentState(
            agentId: agentId,
            agentType: agentType
        )
        // Subagent spawned — parent session is actively processing
        if sessions[sessionId]?.status == .idle || sessions[sessionId]?.status == .processing {
            sessions[sessionId]?.status = .running
            sessions[sessionId]?.currentTool = "Agent"
            sessions[sessionId]?.toolDescription = agentType
        }
        sessions[sessionId]?.lastActivity = Date()
        effects.append(.setActiveSession(sessionId: sessionId))
        return true

    case "UserPromptSubmit":
        // Cursor has no SessionStart for Tasks; beforeSubmitPrompt is the relaunch signal.
        if shouldReopenCursorSubagentOnPrompt(event: event, session: sessions[sessionId]) {
            sessions[sessionId]?.closedSubagentIds.remove(agentId)
        }
        guard ensureSubagent(sessions: &sessions, sessionId: sessionId, agentId: agentId, event: event) else {
            return true
        }
        sessions[sessionId]?.subagents[agentId]?.status = .processing
        sessions[sessionId]?.subagents[agentId]?.lastActivity = Date()
        if sessions[sessionId]?.status != .waitingApproval && sessions[sessionId]?.status != .waitingQuestion {
            let agentType = sessions[sessionId]?.subagents[agentId]?.agentType
            sessions[sessionId]?.status = .running
            sessions[sessionId]?.currentTool = "Agent"
            sessions[sessionId]?.toolDescription = agentType
        }
        sessions[sessionId]?.lastActivity = Date()
        effects.append(.setActiveSession(sessionId: sessionId))
        return true

    case "SubagentStop", "Stop", "SessionEnd":
        sessions[sessionId]?.subagents.removeValue(forKey: agentId)
        sessions[sessionId]?.closedSubagentIds.insert(agentId)
        // If no more subagents, revert parent to processing (waiting for main thread to continue)
        if sessions[sessionId]?.subagents.isEmpty == true {
            if sessions[sessionId]?.status == .running && sessions[sessionId]?.currentTool == "Agent" {
                sessions[sessionId]?.status = .processing
                sessions[sessionId]?.currentTool = nil
                sessions[sessionId]?.toolDescription = nil
            }
        }
        sessions[sessionId]?.lastActivity = Date()
        return true

    case "PreToolUse":
        guard ensureSubagent(sessions: &sessions, sessionId: sessionId, agentId: agentId, event: event) else {
            return true
        }
        sessions[sessionId]?.subagents[agentId]?.status = .running
        sessions[sessionId]?.subagents[agentId]?.currentTool = event.toolName
        sessions[sessionId]?.subagents[agentId]?.toolDescription = event.toolDescription
        sessions[sessionId]?.subagents[agentId]?.lastActivity = Date()
        // Keep parent session showing as active while subagents work
        if sessions[sessionId]?.status != .waitingApproval && sessions[sessionId]?.status != .waitingQuestion {
            sessions[sessionId]?.status = .running
        }
        sessions[sessionId]?.lastActivity = Date()
        return true

    case "PostToolUse":
        guard ensureSubagent(sessions: &sessions, sessionId: sessionId, agentId: agentId, event: event) else {
            return true
        }
        if let tool = sessions[sessionId]?.subagents[agentId]?.currentTool {
            let agentType = sessions[sessionId]?.subagents[agentId]?.agentType
            let desc = sessions[sessionId]?.subagents[agentId]?.toolDescription
            sessions[sessionId]?.recordTool(tool, description: desc, success: true, agentType: agentType, maxHistory: maxHistory)
        }
        sessions[sessionId]?.subagents[agentId]?.status = .processing
        sessions[sessionId]?.subagents[agentId]?.currentTool = nil
        sessions[sessionId]?.subagents[agentId]?.toolDescription = nil
        sessions[sessionId]?.subagents[agentId]?.lastActivity = Date()
        sessions[sessionId]?.lastActivity = Date()
        return true

    case "PostToolUseFailure":
        guard ensureSubagent(sessions: &sessions, sessionId: sessionId, agentId: agentId, event: event) else {
            return true
        }
        if let tool = sessions[sessionId]?.subagents[agentId]?.currentTool {
            let agentType = sessions[sessionId]?.subagents[agentId]?.agentType
            let desc = sessions[sessionId]?.subagents[agentId]?.toolDescription
            sessions[sessionId]?.recordTool(tool, description: desc, success: false, agentType: agentType, maxHistory: maxHistory)
        }
        sessions[sessionId]?.subagents[agentId]?.status = .processing
        sessions[sessionId]?.subagents[agentId]?.currentTool = nil
        sessions[sessionId]?.subagents[agentId]?.toolDescription = nil
        sessions[sessionId]?.lastActivity = Date()
        return true

    case "AfterAgentResponse":
        // Merged Cursor Task events arrive with parent session_id + child agent_id.
        // Handle here so they do not overwrite the parent's reply or enqueue a false completion.
        guard ensureSubagent(sessions: &sessions, sessionId: sessionId, agentId: agentId, event: event) else {
            return true
        }
        sessions[sessionId]?.subagents[agentId]?.status = .processing
        sessions[sessionId]?.subagents[agentId]?.lastActivity = Date()
        sessions[sessionId]?.lastActivity = Date()
        if sessions[sessionId]?.status != .waitingApproval
            && sessions[sessionId]?.status != .waitingQuestion
            && sessions[sessionId]?.status != .running {
            sessions[sessionId]?.status = .processing
        }
        return true

    case "Notification":
        // Keep folded Tasks' ask/question notifications on the parent card.
        // Swallowing them here (as AfterAgentResponse did) dropped waitingQuestion.
        guard ensureSubagent(sessions: &sessions, sessionId: sessionId, agentId: agentId, event: event) else {
            return true
        }
        sessions[sessionId]?.subagents[agentId]?.lastActivity = Date()
        sessions[sessionId]?.lastActivity = Date()
        let notificationText = firstStringFromEvent(
            event,
            keys: ["message", "text", "summary", "status", "detail"],
            includeNested: true
        )
        if let msg = notificationText, !msg.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
            sessions[sessionId]?.toolDescription = msg
            sessions[sessionId]?.subagents[agentId]?.toolDescription = msg
        }
        if QuestionPayload.from(event: event) != nil {
            sessions[sessionId]?.status = .waitingQuestion
            sessions[sessionId]?.subagents[agentId]?.status = .waitingQuestion
            effects.append(.setActiveSession(sessionId: sessionId))
        } else if sessions[sessionId]?.status != .waitingApproval
            && sessions[sessionId]?.status != .waitingQuestion
            && sessions[sessionId]?.status != .running {
            sessions[sessionId]?.status = .processing
            sessions[sessionId]?.subagents[agentId]?.status = .processing
        }
        return true

    default:
        return false  // Fall through to normal session handling
    }
}
