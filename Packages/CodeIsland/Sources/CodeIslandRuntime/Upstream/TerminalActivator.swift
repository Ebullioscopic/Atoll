import AppKit
import ApplicationServices
import CodeIslandCore

/// Activates the terminal window/tab running a specific Claude Code session.
/// Supports tab-level switching for: Ghostty, iTerm2, Terminal.app, WezTerm, kitty.
/// Falls back to app-level activation for: Alacritty, Warp, Hyper, Tabby, Rio.
struct TerminalActivator {
    // Internal (not private) so support tests can assert a terminal is recognized,
    // matching sourceToNativeAppBundleId's visibility. See TeraxSupportTests.
    static let knownTerminals: [(name: String, bundleId: String)] = [
        ("cmux", "com.cmuxterm.app"),
        ("Ghostty", "com.mitchellh.ghostty"),
        ("iTerm2", "com.googlecode.iterm2"),
        ("WezTerm", "com.github.wez.wezterm"),
        ("Kaku", "fun.tw93.kaku"),
        ("kitty", "net.kovidgoyal.kitty"),
        ("Alacritty", "org.alacritty"),
        ("Terax", "app.crynta.terax"),
        ("Warp", "dev.warp.Warp-Stable"),
        ("Terminal", "com.apple.Terminal"),
    ]

    /// Bundle IDs that commonly host Zellij as a child multiplexer process.
    /// When we detect a Zellij session, we activate the parent terminal first,
    /// then drive `zellij action go-to-tab` inside it to focus the right pane.
    private static let zellijParentBundleIDs: [String] = [
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2",
        "com.github.wez.wezterm",
        "fun.tw93.kaku",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp-Stable",
        "com.apple.Terminal",
        "com.cmuxterm.app",
    ]

    /// Fallback: source-based app jump for CLIs with NO terminal mode.
    /// Most sources should use nativeAppBundles instead (by bundle ID).
    private static let appSources: [String: String] = [:]

    /// Reverse map: source → native app bundle ID. Used as a fallback when
    /// termBundleId is missing but the source's desktop app is running.
    static let sourceToNativeAppBundleId: [String: String] = [
        "codex": "com.openai.codex",
        "cursor": "com.todesktop.230313mzl4w4u92",
        "trae": "com.trae.app",
        "traecn": "com.trae.app",
        "qoder": "com.qoder.ide",
        "droid": "com.factory.app",
        "codebuddy": "com.tencent.codebuddy",
        "codybuddycn": "com.tencent.codebuddy.cn",
        "stepfun": "com.stepfun.app",
        "opencode": "ai.opencode.desktop",
        "workbuddy": "com.workbuddy.workbuddy",
    ]

    /// Bundle IDs of apps that have both APP and CLI modes.
    /// When termBundleId matches, bring that app to front;
    /// otherwise fall through to terminal tab-matching.
    private static let nativeAppBundles: [String: String] = [
        "com.openai.codex": "Codex",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.trae.app": "Trae",
        "com.qoder.ide": "Qoder",
        "com.factory.app": "Factory",
        "com.tencent.codebuddy": "CodeBuddy",
        "com.tencent.codebuddy.cn": "CodyBuddyCN",
        "com.stepfun.app": "StepFun",
        "ai.opencode.desktop": "OpenCode",
        "com.workbuddy.workbuddy": "WorkBuddy",
        // Claude Code Desktop (#211). Deliberately NOT in sourceToNativeAppBundleId:
        // most "claude" sessions are terminal CLI runs, and that fallback would
        // steal their click-to-jump whenever the desktop app happens to be open.
        "com.anthropic.claudefordesktop": "Claude",
    ]

    static func activate(session: SessionSnapshot, sessionId: String? = nil) {
        guard !session.isRemote else { return }

        // Native app by bundle ID (e.g. Codex APP vs Codex CLI). These are IDE-style
        // apps (Cursor, Trae, Qoder, Factory, …) that can hold several workspace
        // windows at once, so match the one whose title contains the session's
        // project folder instead of just raising the most-recently-used window (#199).
        // activateIDEWindow falls back to a plain app-level activation when there's
        // no cwd or no matching window, so this never regresses single-window apps.
        if let bundleId = session.termBundleId,
           nativeAppBundles[bundleId] != nil {
            activateIDEWindow(bundleId: bundleId, cwd: session.cwd)
            return
        }

        // IDE integrated terminal: try window-level matching by CWD, fall back to app-level
        if session.isIDETerminal,
           let bundleId = session.termBundleId {
            activateIDEWindow(bundleId: bundleId, cwd: session.cwd)
            return
        }

        // IDE sources: just bring the app to front
        if let appName = appSources[session.source] {
            if let app = NSWorkspace.shared.runningApplications.first(where: {
                $0.localizedName == appName
            }) {
                if app.isHidden { app.unhide() }
                app.activate()
            } else {
                bringToFront(appName)
            }
            return
        }

        // --- Host GUI client detection (e.g. OpenChamber embedding OpenCode as a server) ---
        // When an agent is spawned by a GUI client app — not from a terminal and not the
        // agent's own desktop app — clicking the session should bring that host client to
        // front instead of falling through to the terminal or the agent's native desktop
        // app. Walk the CLI process ancestry looking for the nearest running regular GUI
        // app that is neither a known terminal nor a known agent-native app; that app is
        // the host. Generic by design: any current/future client (OpenChamber, …) works
        // without hardcoding bundle IDs. Runs BEFORE the sourceToNativeAppBundleId branch
        // below so a coincidentally-running agent desktop app never wins over the real host.
        if let hostBid = resolveHostClientBundleId(for: session) {
            activateByBundleId(hostBid)
            return
        }

        // When the source has a known desktop app that's running, prefer the desktop
        // app over the terminal. This handles e.g. OpenCode CLI launched from Ghostty but
        // editing in VS Code — without this, the inherited TERM_PROGRAM=ghostty would jump
        // to the wrong terminal. Also covers cases where the terminal bundle ID is present
        // but the user wants to focus the desktop IDE instead (e.g. opencode → OpenCode).
        if let nativeBundleId = sourceToNativeAppBundleId[session.source],
           NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == nativeBundleId }) {
            activateByBundleId(nativeBundleId)
            return
        }

        // Resolve terminal: bundle ID (most accurate) → TERM_PROGRAM → scan running apps
        let termApp: String
        if let bundleId = session.termBundleId,
           let resolved = knownTerminals.first(where: { $0.bundleId == bundleId })?.name {
            termApp = resolved
        } else {
            let raw = session.termApp ?? ""
            // "tmux" / "screen" etc. are not GUI apps — fall back to scanning
            if raw.isEmpty || raw.lowercased() == "tmux" || raw.lowercased() == "screen" {
                termApp = detectRunningTerminal()
            } else {
                termApp = raw
            }
        }
        let lower = termApp.lowercased()

        // --- Superset (Electron agent-orchestration terminal): app-level activation ---
        // Must come before the kitty/cmux/iTerm branches. Superset spoofs TERM_PROGRAM to
        // "kitty" (so claude-code parses CSI-u keyboard input) and strips __CFBundleIdentifier
        // from the PTY env, so without this the loose `lower.contains("kitty")` branch would
        // launch/raise the REAL kitty app instead. Superset is a single-window Electron app with
        // internal xterm.js panes and ships no focus/activate CLI or AppleScript dictionary, so
        // pane precision is impossible upstream — we can only bring the Superset window forward
        // (same app-level behavior as Warp / Alacritty fallback). The presence of any SUPERSET_*
        // env var (captured into supersetWorkspaceId / supersetPaneId) uniquely identifies it.
        // __CFBundleIdentifier is stripped so we can't tell canary from stable; default to the
        // stable bundle and fall back to whichever variant is actually running. (#213)
        if session.supersetWorkspaceId != nil || session.supersetPaneId != nil {
            let supersetBundles = ["com.superset.desktop", "com.superset.desktop.canary"]
            let runningBundle = supersetBundles.first(where: { bid in
                NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bid })
            })
            activateByBundleId(runningBundle ?? "com.superset.desktop")
            return
        }

        // --- Zellij multiplexer: precise pane → tab focus, then activate parent terminal ---
        // Must come before tmux/cmux/iTerm/Ghostty branches AND the Terax branch below:
        // Zellij runs *inside* one of those terminals, so termApp/termBundleId points to
        // the host shell. The presence of zellijPaneId is what disambiguates "running
        // inside Zellij" from "plain shell".
        if let zellijPane = session.zellijPaneId, !zellijPane.isEmpty {
            activateZellij(
                paneId: zellijPane,
                sessionName: session.zellijSessionName,
                preferredParentBundleId: session.termBundleId
            )
            return
        }

        // --- Terax (native webview terminal): app-level activation only ---
        // Like Superset, Terax (app.crynta.terax) is a single-window app whose tabs are
        // drawn inside a webview. It exports no per-pane env id (only TERAX_TERMINAL /
        // TERAX_BLOCKS) and ships no URL scheme, AppleScript dictionary, focus CLI, or
        // native tab shortcut — and its tabs are absent from the accessibility tree — so
        // per-tab precision is impossible upstream. Without this branch Terax has no
        // TERM_PROGRAM, so detectRunningTerminal() would misroute the click to whichever
        // other terminal happens to be running. Bring its window forward (Space-aware,
        // same as Superset) via bundle id. Kept AFTER the Zellij branch so a Zellij
        // session hosted in Terax still gets precise pane focus first.
        if session.termBundleId == "app.crynta.terax" || lower == "terax" {
            activateByBundleId("app.crynta.terax")
            return
        }

        // --- tmux: switch pane first, then fall through to terminal-specific activation ---
        if let pane = session.tmuxPane, !pane.isEmpty {
            activateTmux(pane: pane, tmuxEnv: session.tmuxEnv)
        }

        // In tmux, use the client TTY (outer terminal) for tab matching,
        // since ttyPath is the inner tmux pty which won't match the terminal's tab.
        // When tmux is detached (no client TTY), set effectiveTty to nil so terminal-specific
        // handlers skip useless TTY matching and fall back to CWD or app-level activation.
        let inTmux = session.tmuxPane != nil && !(session.tmuxPane ?? "").isEmpty
        let effectiveTty: String?
        if inTmux {
            effectiveTty = session.tmuxClientTty  // nil when detached — intentional
        } else {
            effectiveTty = session.ttyPath
        }

        // --- cmux: surface-level precise jump (workspace + surface) ---
        // Must be handled before generic tab-switching logic to avoid degrading to bringToFront
        if lower.contains("cmux") {
            activateCmux(
                surfaceId: session.cmuxSurfaceId,
                workspaceId: session.cmuxWorkspaceId
            )
            return
        }

        // --- Tab-level switching (5 terminals) ---

        if lower.contains("iterm") {
            if let itermId = session.itermSessionId, !itermId.isEmpty {
                activateITerm(sessionId: itermId)
            } else {
                // No session ID — fall back to tty or cwd matching
                activateITermByTtyOrCwd(tty: effectiveTty, cwd: session.cwd)
            }
            return
        }

        if lower == "ghostty" {
            activateGhostty(
                cwd: session.cwd,
                tty: effectiveTty,
                sessionId: sessionId,
                source: session.source,
                tmuxPane: session.tmuxPane,
                tmuxEnv: session.tmuxEnv
            )
            return
        }

        // Match Terminal.app by bundle ID only — Warp sets TERM_PROGRAM=Apple_Terminal
        if session.termBundleId == "com.apple.Terminal" || (session.termBundleId == nil && lower == "terminal") {
            activateTerminalApp(ttyPath: effectiveTty, cwd: session.cwd)
            return
        }

        // Kaku is a WezTerm fork: same `cli list` JSON shape, different binary + bundle id.
        // Match by bundle id (most reliable) or termApp string fallback.
        if session.termBundleId == "fun.tw93.kaku" || lower == "kaku" {
            activateKaku(ttyPath: effectiveTty, cwd: session.cwd, paneId: session.weztermPaneId, cliPid: session.cliPid)
            return
        }

        if lower.contains("wezterm") || lower.contains("wez") {
            activateWezTerm(ttyPath: effectiveTty, cwd: session.cwd, paneId: session.weztermPaneId, cliPid: session.cliPid)
            return
        }

        if lower.contains("kitty") {
            activateKitty(windowId: session.kittyWindowId, cwd: session.cwd, source: session.source)
            return
        }

        // --- Warp (SQLite pane precision jump + Cmd+N tab switch) ---
        if lower.contains("warp") {
            activateWarp(cwd: session.cwd)
            return
        }

        // --- Other terminals (Alacritty, Hyper, Tabby, Rio, etc.) ---
        // Try window-level matching via System Events (title contains CWD folder name),
        // similar to IDE window matching. Falls back to app-level if no match.
        if let bundleId = session.termBundleId, let cwd = session.cwd, !cwd.isEmpty {
            activateTerminalWindow(bundleId: bundleId, cwd: cwd, fallbackName: termApp)
        } else {
            bringToFront(termApp)
        }
    }

    /// Walks the CLI process ancestry looking for the nearest running GUI app that is
    /// neither a known terminal nor a known agent-native app. Returns its bundle ID, or
    /// nil when the agent runs in a plain terminal / its own desktop app / under launchd.
    /// Used to jump back to GUI host clients (e.g. OpenChamber) that embed an agent such
    /// as OpenCode as a managed server process. The ancestor walk is bounded (≤32 hops)
    /// and click-driven, so cost is negligible.
    private static func resolveHostClientBundleId(for session: SessionSnapshot) -> String? {
        guard let pid = session.cliPid, pid > 0 else { return nil }

        // Bundle IDs that must NEVER be treated as a "host client": known terminals
        // (handled by tab/window-level switching further down) and agent-native desktop
        // apps (handled by the nativeAppBundles / sourceToNativeAppBundleId branches).
        var excluded = Set(knownTerminals.map { $0.bundleId })
        excluded.formUnion(nativeAppBundles.keys)
        excluded.formUnion(sourceToNativeAppBundleId.values)

        // Snapshot once; match by processIdentifier while walking up the tree.
        let regularApps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }

        var current = pid
        var seen = Set<pid_t>()
        for _ in 0..<32 {
            guard current > 1, !seen.contains(current) else { break }
            seen.insert(current)
            if let app = regularApps.first(where: { $0.processIdentifier == current }),
               let bid = app.bundleIdentifier,
               !excluded.contains(bid) {
                return bid
            }
            guard let ppid = parentPID(of: current), ppid > 1 else { break }
            current = ppid
        }
        return nil
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
        guard ret > 0, info.pbi_ppid > 0 else { return nil }
        return pid_t(info.pbi_ppid)
    }

    // MARK: - Ghostty (AppleScript: match by CWD + session ID in title)

    private static func activateGhostty(
        cwd: String?,
        tty: String? = nil,
        sessionId: String? = nil,
        source: String = "claude",
        tmuxPane: String? = nil,
        tmuxEnv: String? = nil
    ) {
        guard let cwd = cwd, !cwd.isEmpty else { bringToFront("Ghostty"); return }
        // Ensure app is running, unhidden, and brought to front (Space switching)
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.mitchellh.ghostty"
        }) else {
            bringToFront("Ghostty")
            return
        }
        if app.isHidden { app.unhide() }
        // Don't call app.activate() here — it triggers Ghostty's quick terminal.
        // The AppleScript's `focus t; activate` below will activate after focusing
        // the correct terminal window.

        // The remaining work (tmux key resolution + AppleScript construction +
        // osascript dispatch) is the last subprocess-bound path that wasn't
        // already off-main — match the rest of the activator and run it on a
        // userInitiated background queue so a stuck `tmux display-message`
        // can't freeze the UI. See #139.
        DispatchQueue.global(qos: .userInitiated).async {
        // Resolve tmux title prefix (most reliable for tmux sessions in Ghostty).
        // Example Ghostty title often contains: "<session>:<winIdx>:<winName> - ..."
        var tmuxKey = ""
        var tmuxSession = ""
        if let pane = tmuxPane?.trimmingCharacters(in: .whitespacesAndNewlines),
           !pane.isEmpty,
           let tmuxBin = findBinary("tmux") {
            // Try full key first, fall back to session name only
            let formats = [
                "#{session_name}:#{window_index}:#{window_name}",
                "#{session_name}",
            ]
            for fmt in formats {
                if let data = runProcess(tmuxBin, args: ["display-message", "-p", "-t", pane, "-F", fmt], env: tmuxProcessEnv(tmuxEnv)),
                   let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !result.isEmpty {
                    if fmt.contains("window_index") {
                        tmuxKey = result
                        if let first = result.split(separator: ":").first { tmuxSession = String(first) }
                    } else {
                        tmuxSession = result
                    }
                    break
                }
            }
        }

        // Normalize CWD variants:
        // - trim whitespace
        // - strip trailing slashes (except "/")
        // - include symlink-resolved path variant
        func stripTrailingSlashes(_ path: String) -> String {
            var p = path
            while p.count > 1, p.hasSuffix("/") { p.removeLast() }
            return p
        }
        let trimmedCwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwd1 = stripTrailingSlashes(trimmedCwd)
        let cwd2 = stripTrailingSlashes(URL(fileURLWithPath: cwd1).resolvingSymlinksInPath().path)
        let dirName = (cwd1 as NSString).lastPathComponent

        let home = NSHomeDirectory()
        let tildeCwd: String = {
            if cwd1 == home { return "~" }
            if cwd1.hasPrefix(home + "/") {
                return "~" + String(cwd1.dropFirst(home.count))
            }
            return ""
        }()

        let escapedCwd1 = escapeAppleScript(cwd1)
        let escapedCwd2 = escapeAppleScript(cwd2)
        let escapedDir = escapeAppleScript(dirName)
        let escapedTilde = escapeAppleScript(tildeCwd)
        let escapedTmux = escapeAppleScript(tmuxKey)
        let escapedTmuxSession = escapeAppleScript(tmuxSession)

        // Match order:
        // 1) tmux title prefix (when available)
        // 2) session ID in title (disambiguates same-CWD sessions)
        // 3) source keyword in title ("claude"/"codex"/...)
        // 4) CWD match (working directory), then title-based fallback
        let idFilter: String
        if let sid = sessionId, !sid.isEmpty {
            let escapedSid = escapeAppleScript(String(sid.prefix(8)))
            idFilter = """
                repeat with t in matches
                    if name of t contains "\(escapedSid)" then
                        focus t
                        activate
                        return
                    end if
                end repeat
            """
        } else {
            idFilter = ""
        }
        let keyword = escapeAppleScript(source)
        let script = """
        tell application "Ghostty"
            set allTerms to terminals

            -- 1) tmux: match by tmux title prefix first (more robust than CWD in tmux)
            set tmuxKey to "\(escapedTmux)"
            set tmuxSession to "\(escapedTmuxSession)"

            -- 1a) exact window key when available: "<session>:<winIdx>:<winName>"
            if tmuxKey is not "" then
                repeat with t in allTerms
                    try
                        if name of t contains tmuxKey then
                            focus t
                            activate
                            return
                        end if
                    end try
                end repeat
            end if

            -- 1b) tmuxcc-style fallback: title starts with "<session>:"
            if tmuxSession is not "" then
                repeat with t in allTerms
                    try
                        set tname to (name of t as text)
                        if tname starts with (tmuxSession & ":") then
                            focus t
                            activate
                            return
                        end if
                    end try
                end repeat
            end if

            -- 2) TTY: Ghostty does not currently expose a `tty` property (only uuid,
            -- title, working directory). This block is kept for future-proofing and
            -- silently skips via try if the property doesn't exist.
            \(tty.map { t in
                let escaped = escapeAppleScript(t)
                return """
                if "\(escaped)" is not "" then
                    try
                        set ttyMatches to (every terminal whose tty is "\(escaped)")
                        if (count of ttyMatches) > 0 then
                            focus (item 1 of ttyMatches)
                            activate
                            return
                        end if
                    end try
                end if
                """
            } ?? "")

            -- 3) CWD: exact match on Ghostty's working directory property
            set matches to {}
            set cwd1 to "\(escapedCwd1)"
            set cwd2 to "\(escapedCwd2)"
            if cwd1 is not "" then
                try
                    set matches to (every terminal whose working directory is cwd1)
                end try
            end if
            if (count of matches) = 0 and cwd2 is not "" and cwd2 is not cwd1 then
                try
                    set matches to (every terminal whose working directory is cwd2)
                end try
            end if

            -- 4) Fallback: match by title when Ghostty can't report the true working directory (common in tmux)
            if (count of matches) = 0 then
                set dirName to "\(escapedDir)"
                set tildeCwd to "\(escapedTilde)"
                repeat with t in allTerms
                    try
                        set tname to (name of t as text)
                        if (tildeCwd is not "" and tname contains tildeCwd) or (cwd1 is not "" and tname contains cwd1) or (dirName is not "" and tname contains dirName) then
                            set end of matches to t
                        end if
                    end try
                end repeat
            end if

            \(idFilter)
            repeat with t in matches
                if name of t contains "\(keyword)" then
                    focus t
                    activate
                    return
                end if
            end repeat
            if (count of matches) > 0 then
                focus (item 1 of matches)
            end if
            activate
        end tell

        -- Final fallback via System Events: Ghostty's own `focus`/`activate` is unreliable
        -- in some versions (issue #84), and even when it brings the app to front it doesn't
        -- deminiaturize a window that's currently minimized to the dock. System Events
        -- Accessibility API forces both. Wrapped in `try` so it silently no-ops if the
        -- user hasn't granted Accessibility permission.
        try
            tell application "System Events"
                tell process "Ghostty"
                    set frontmost to true
                    repeat with w in windows
                        try
                            if value of attribute "AXMinimized" of w is true then
                                set value of attribute "AXMinimized" of w to false
                            end if
                        end try
                    end repeat
                end tell
            end tell
        end try
        """
        // Use /usr/bin/osascript to run AppleScript out-of-process (tmuxcc uses the same approach).
        // This avoids relying on NSAppleScript execution inside the app process.
        // Already on a background queue (see DispatchQueue.global wrap above) — call the
        // _Sync variant to skip an extra dispatch hop.
        runOsaScriptSync(script)
        } // end DispatchQueue.global async
    }

    // MARK: - iTerm2 (AppleScript: match by session ID, tty, or cwd)

    /// Fallback when iTerm2 session ID is unavailable: try tty match, then cwd/name match.
    private static func activateITermByTtyOrCwd(tty: String?, cwd: String?) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.googlecode.iterm2"
        }) else {
            bringToFront("iTerm2")
            return
        }
        if app.isHidden { app.unhide() }
        app.activate()
        // Strategy 1: match by tty (precise)
        if let tty = tty, !tty.isEmpty {
            let fullTty = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
            let script = """
            try
                tell application "iTerm2"
                    repeat with w in windows
                        repeat with t in tabs of w
                            repeat with s in sessions of t
                                try
                                    if tty of s is "\(escapeAppleScript(fullTty))" then
                                        try
                                            select w
                                        end try
                                        select t
                                        select s
                                        set index of w to 1
                                        return
                                    end if
                                end try
                            end repeat
                        end repeat
                    end repeat
                end tell
            end try
            """
            runAppleScript(script)
            return
        }
        // Strategy 2: match by cwd directory name in session name/path
        guard let cwd = cwd, !cwd.isEmpty else { return }
        let dirName = (cwd as NSString).lastPathComponent
        let script = """
        try
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            try
                                if name of s contains "\(escapeAppleScript(dirName))" or path of s contains "\(escapeAppleScript(dirName))" then
                                    try
                                        select w
                                    end try
                                    select t
                                    select s
                                    set index of w to 1
                                    return
                                end if
                            end try
                        end repeat
                    end repeat
                end repeat
            end tell
        end try
        """
        runAppleScript(script)
    }

    private static func activateITerm(sessionId: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.googlecode.iterm2"
        }) else {
            bringToFront("iTerm2")
            return
        }
        if app.isHidden { app.unhide() }
        app.activate()
        let script = """
        try
            tell application "iTerm2"
                repeat with aWindow in windows
                    if miniaturized of aWindow then set miniaturized of aWindow to false
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            if unique ID of aSession is "\(escapeAppleScript(sessionId))" then
                                set miniaturized of aWindow to false
                                try
                                    select aWindow
                                end try
                                select aTab
                                select aSession
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
        end try
        """
        runAppleScript(script)
    }

    // MARK: - Terminal.app (AppleScript: match by TTY, fallback to CWD)

    private static func activateTerminalApp(ttyPath: String?, cwd: String?) {
        // If Terminal.app is not running, launch it and return — no tab matching possible.
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.Terminal"
        }) else {
            bringToFront("Terminal")
            return
        }
        if app.isHidden { app.unhide() }
        app.activate()

        let ttyEscaped = ttyPath.map(escapeAppleScript) ?? ""
        let dirEscaped = cwd.map { escapeAppleScript(($0 as NSString).lastPathComponent) } ?? ""

        // Try tty → tab auto-name → user custom title → deminiaturize any window as a last resort.
        // Terminal.app auto-generates `name of t` containing the running command + cwd; `custom title`
        // only exists when the user set it explicitly, so matching against `name` works for the
        // overwhelming default case.
        // Note: locals named `targetTty` / `targetDir` (NOT `tty` / `dir`). AppleScript's
        // resolver can't reliably tell `if tty of t is tty` apart from `if tty of t is
        // tty of <implicit object>` — `tty` is also a tab property name, so reusing it as
        // a local variable causes Strategy 1 to silently misfire and Strategy 2 to
        // fall through, which manifested as "click any session, jumps to the same tab"
        // (issue #124).
        let script = """
        tell application "Terminal"
            set targetTty to "\(ttyEscaped)"
            set targetDir to "\(dirEscaped)"
            set found to false

            -- Strategy 1: precise tty match
            if targetTty is not "" then
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if tty of t is targetTty then
                                if miniaturized of w then set miniaturized of w to false
                                set selected tab of w to t
                                set index of w to 1
                                set found to true
                                exit repeat
                            end if
                        end try
                    end repeat
                    if found then exit repeat
                end repeat
            end if

            -- Strategy 2: auto tab title contains the cwd folder name
            if not found and targetDir is not "" then
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if (name of t as text) contains targetDir then
                                if miniaturized of w then set miniaturized of w to false
                                set selected tab of w to t
                                set index of w to 1
                                set found to true
                                exit repeat
                            end if
                        end try
                    end repeat
                    if found then exit repeat
                end repeat
            end if

            -- Strategy 3: user-set custom title
            if not found and targetDir is not "" then
                repeat with w in windows
                    repeat with t in tabs of w
                        try
                            if custom title of t contains targetDir then
                                if miniaturized of w then set miniaturized of w to false
                                set selected tab of w to t
                                set index of w to 1
                                set found to true
                                exit repeat
                            end if
                        end try
                    end repeat
                    if found then exit repeat
                end repeat
            end if

            -- Fallback: unminimize the first miniaturized window so the user always sees something.
            if not found then
                repeat with w in windows
                    try
                        if miniaturized of w then
                            set miniaturized of w to false
                            set index of w to 1
                            exit repeat
                        end if
                    end try
                end repeat
            end if

            activate
        end tell

        -- Final fallback via System Events: when Terminal.app's `windows` collection doesn't
        -- include a minimized window (some macOS 14 cases), or when osascript silently no-ops,
        -- force both frontmost and AXMinimized=false through Accessibility (issue #124).
        try
            tell application "System Events"
                tell process "Terminal"
                    set frontmost to true
                    repeat with w in windows
                        try
                            if value of attribute "AXMinimized" of w is true then
                                set value of attribute "AXMinimized" of w to false
                            end if
                        end try
                    end repeat
                end tell
            end tell
        end try
        """
        runAppleScript(script)
    }

    // MARK: - WezTerm (CLI: wezterm cli list + activate-tab)

    private static func activateWezTerm(ttyPath: String?, cwd: String?, paneId: String? = nil, cliPid: pid_t? = nil) {
        activateWeztermFamily(
            displayName: "WezTerm",
            cliName: "wezterm",
            bundleCandidates: [
                "/Applications/WezTerm.app/Contents/MacOS/wezterm",
                NSHomeDirectory() + "/Applications/WezTerm.app/Contents/MacOS/wezterm",
            ],
            ttyPath: ttyPath,
            cwd: cwd,
            paneId: paneId,
            cliPid: cliPid
        )
    }

    // MARK: - Kaku (WezTerm fork, bundle id fun.tw93.kaku, CLI: `kaku cli ...`)

    private static func activateKaku(ttyPath: String?, cwd: String?, paneId: String? = nil, cliPid: pid_t? = nil) {
        activateWeztermFamily(
            displayName: "Kaku",
            cliName: "kaku",
            bundleCandidates: [
                "/Applications/Kaku.app/Contents/MacOS/kaku",
                NSHomeDirectory() + "/Applications/Kaku.app/Contents/MacOS/kaku",
            ],
            ttyPath: ttyPath,
            cwd: cwd,
            paneId: paneId,
            cliPid: cliPid
        )
    }

    /// Shared WezTerm-family pane activation: bring app to front, then ask its CLI
    /// to focus the matching pane. Match precedence: explicit paneId → TTY → CWD.
    private static func activateWeztermFamily(
        displayName: String,
        cliName: String,
        bundleCandidates: [String],
        ttyPath: String?,
        cwd: String?,
        paneId: String?,
        cliPid: pid_t?
    ) {
        bringToFront(displayName)
        guard let bin = findBinary(cliName, extraPaths: bundleCandidates) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            // Fast path: bridge captured WEZTERM_PANE — activate that pane directly without listing.
            if let pid = paneId,
               !pid.isEmpty,
               Int(pid) != nil {
                if runProcess(bin, args: ["cli", "activate-pane", "--pane-id", pid]) != nil {
                    return
                }
                // Fall through to list-based matching if activate-pane failed (older CLI etc.)
            }

            guard let json = runProcess(bin, args: ["cli", "list", "--format", "json"]),
                  let panes = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { return }

            // Find pane: prefer process-resolved TTY, then captured TTY, then CWD.
            var matchedPaneId: Int?
            var matchedTabId: Int?
            let processTty = cliPid.flatMap(ProcessRunner.ttyForPid)
            let candidateTtys = [processTty, ttyPath]
                .compactMap { $0 }
                .filter { !$0.isEmpty && $0 != "/dev/tty" }
            for tty in candidateTtys where matchedPaneId == nil && matchedTabId == nil {
                if let pane = panes.first(where: { ($0["tty_name"] as? String) == tty }) {
                    matchedPaneId = pane["pane_id"] as? Int
                    matchedTabId = pane["tab_id"] as? Int
                }
            }
            if matchedPaneId == nil, matchedTabId == nil, let cwd = cwd {
                let cwdUrl = "file://" + cwd
                if let pane = panes.first(where: {
                    guard let paneCwd = $0["cwd"] as? String else { return false }
                    return paneCwd == cwdUrl || paneCwd == cwd
                }) {
                    matchedPaneId = pane["pane_id"] as? Int
                    matchedTabId = pane["tab_id"] as? Int
                }
            }

            // Prefer pane-level activation (more precise — picks the right pane within a split tab),
            // fall back to tab-level if pane id wasn't reported.
            if let pid = matchedPaneId {
                _ = runProcess(bin, args: ["cli", "activate-pane", "--pane-id", "\(pid)"])
            } else if let tid = matchedTabId {
                _ = runProcess(bin, args: ["cli", "activate-tab", "--tab-id", "\(tid)"])
            }
        }
    }

    // MARK: - kitty (CLI: kitten @ focus-window/focus-tab)

    private static func activateKitty(windowId: String?, cwd: String?, source: String = "claude") {
        bringToFront("kitty")
        guard let bin = findBinary("kitten") else { return }

        // Prefer window ID for precise switching
        if let windowId = windowId, !windowId.isEmpty {
            DispatchQueue.global(qos: .userInitiated).async {
                _ = runProcess(bin, args: ["@", "focus-window", "--match", "id:\(windowId)"])
            }
            return
        }

        // Fallback to CWD matching, then title with source keyword
        guard let cwd = cwd, !cwd.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            if runProcess(bin, args: ["@", "focus-tab", "--match", "cwd:\(cwd)"]) == nil {
                _ = runProcess(bin, args: ["@", "focus-tab", "--match", "title:\(source)"])
            }
        }
    }

    // MARK: - tmux (CLI: tmux switch-client + select-window/select-pane)

    private static func activateTmux(pane: String, tmuxEnv: String? = nil) {
        guard let bin = findBinary("tmux") else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            // 1) Switch the attached client to the target session — needed when the user is
            //    currently attached to session A but the agent runs in session B. tmux derives
            //    the session from the pane target, so "switch-client -t <pane>" is sufficient.
            //    Failure is fine (e.g. no client attached, or pane belongs to current session).
            _ = runProcess(bin, args: ["switch-client", "-t", pane], env: tmuxProcessEnv(tmuxEnv))
            // 2) Within that session, switch to the window containing the pane, then select the pane
            _ = runProcess(bin, args: ["select-window", "-t", pane], env: tmuxProcessEnv(tmuxEnv))
            _ = runProcess(bin, args: ["select-pane", "-t", pane], env: tmuxProcessEnv(tmuxEnv))
        }
    }

    // MARK: - Zellij (CLI: zellij action list-panes → go-to-tab + activate parent terminal)

    /// Zellij is a terminal multiplexer (no .app bundle of its own); it lives inside a parent
    /// terminal emulator. Activation strategy:
    ///   1. Look up the tab position for the given pane id via `zellij action list-panes`
    ///   2. Drive `zellij action go-to-tab <position>` (1-indexed in Zellij)
    ///   3. Bring the parent terminal forward so the user actually sees the focus change
    private static func activateZellij(
        paneId: String,
        sessionName: String?,
        preferredParentBundleId: String?
    ) {
        // Fire-and-forget: subprocess + parent activation can take a couple hundred ms,
        // we don't want to block the click handler thread.
        DispatchQueue.global(qos: .userInitiated).async {
            // Activate the parent terminal as soon as we know which one — even if zellij CLI
            // is missing or list-panes fails, the user at least gets the right window forward.
            // Use the non-activating raise path: `app.activate()` triggers Ghostty's quick
            // terminal pop-up (issue same shape as #84 / activateGhostty's note), which is
            // worse UX than just bringing the existing window forward via openApplication.
            let parentBundleId = resolveZellijParentBundleId(preferred: preferredParentBundleId)
            if let parent = parentBundleId {
                DispatchQueue.main.async { raiseAppWithoutQuickTerminal(bundleId: parent) }
            }

            guard let zellijBin = findBinary("zellij", extraPaths: [
                NSHomeDirectory() + "/.local/bin/zellij",
            ]) else {
                return
            }

            // ZELLIJ_PANE_ID may be a bare integer "N" or prefixed "terminal_N"
            // depending on Zellij version. list-panes JSON returns numeric `id`,
            // so we have to normalise the env-derived value back to Int.
            guard let paneIDInt = parseZellijPaneId(paneId) else { return }

            // List panes (optionally scoped to a specific session) and find the tab position.
            var listArgs: [String] = []
            if let sessionName, !sessionName.isEmpty {
                listArgs += ["--session", sessionName]
            }
            listArgs += ["action", "list-panes", "--json", "--tab"]

            guard let listJSON = runProcess(zellijBin, args: listArgs) else { return }

            // Zellij prints either `[ {pane}, ... ]` or `{tabIndex: [ {pane}, ... ]}` depending
            // on version; handle both shapes by flattening.
            let parsed = try? JSONSerialization.jsonObject(with: listJSON)
            let panes: [[String: Any]] = {
                if let arr = parsed as? [[String: Any]] { return arr }
                if let dict = parsed as? [String: [[String: Any]]] {
                    return dict.values.flatMap { $0 }
                }
                return []
            }()

            let tabPosition = panes.first(where: {
                ($0["id"] as? Int) == paneIDInt
            })?["tab_position"] as? Int

            guard let tabPosition else { return }

            // Zellij `go-to-tab` is 1-indexed
            var goArgs: [String] = []
            if let sessionName, !sessionName.isEmpty {
                goArgs += ["--session", sessionName]
            }
            goArgs += ["action", "go-to-tab", "\(tabPosition + 1)"]
            _ = runProcess(zellijBin, args: goArgs)
        }
    }

    /// Parse Zellij's `ZELLIJ_PANE_ID` env value into a numeric pane id.
    /// Zellij's `PaneId` enum Display impl formats as `"terminal_N"` / `"plugin_N"`, so
    /// recent versions may inject the prefixed form; older versions / docs suggest a
    /// bare integer N (documented as equivalent to terminal_N). Plugin panes are not
    /// terminal panes — agents don't run there, so we return nil and skip activation.
    static func parseZellijPaneId(_ raw: String) -> Int? {
        if let n = Int(raw) { return n }
        if raw.hasPrefix("terminal_"), let n = Int(raw.dropFirst("terminal_".count)) { return n }
        return nil
    }

    /// Pick the parent terminal app to raise for a Zellij session. Prefer the bundle id the
    /// hook captured (`__CFBundleIdentifier`); fall back to the first running app from the
    /// known-host list so we always raise *something* and don't leave the user staring at
    /// the previous app.
    private static func resolveZellijParentBundleId(preferred: String?) -> String? {
        let running = NSWorkspace.shared.runningApplications
        if let preferred,
           !preferred.isEmpty,
           zellijParentBundleIDs.contains(preferred),
           running.contains(where: { $0.bundleIdentifier == preferred }) {
            return preferred
        }
        return zellijParentBundleIDs.first { id in
            running.contains(where: { $0.bundleIdentifier == id })
        }
    }

    // MARK: - IDE window-level activation (JetBrains, VS Code, Zed, etc.)

    /// Activate the specific IDE window whose title contains the project folder name.
    /// Falls back to app-level activation if no CWD or no matching window found.
    private static func activateIDEWindow(bundleId: String, cwd: String?) {
        guard let cwd = cwd, !cwd.isEmpty else {
            activateByBundleId(bundleId)
            return
        }
        let folderName = (cwd as NSString).lastPathComponent
        guard !folderName.isEmpty else {
            activateByBundleId(bundleId)
            return
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }) else {
            activateByBundleId(bundleId)
            return
        }

        if app.isHidden { app.unhide() }
        app.activate()

        // Use System Events to iterate windows and AXRaise the best match.
        // Priority: exact folder name at word boundary > shortest title containing folder name.
        // This avoids jumping to the wrong window when multiple projects share a folder name
        // (e.g., /work/app vs /backup/app).
        let appName = app.localizedName ?? "Application"
        let escapedFolder = escapeAppleScript(folderName)
        let script = """
        tell application "System Events"
            tell process "\(escapeAppleScript(appName))"
                set frontmost to true
                set bestWindow to missing value
                set bestLen to 999999
                repeat with w in windows
                    try
                        set wName to name of w as text
                        if wName contains "\(escapedFolder)" then
                            set wLen to count of wName
                            if wLen < bestLen then
                                set bestWindow to w
                                set bestLen to wLen
                            end if
                        end if
                    end try
                end repeat
                if bestWindow is not missing value then
                    perform action "AXRaise" of bestWindow
                end if
            end tell
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - Generic terminal window matching (Alacritty, Warp, Hyper, etc.)

    /// For terminals without tab-switching APIs, try to raise the window whose title
    /// contains the project folder name via System Events. Falls back to app-level.
    private static func activateTerminalWindow(bundleId: String, cwd: String, fallbackName: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }) else {
            bringToFront(fallbackName)
            return
        }
        if app.isHidden { app.unhide() }
        app.activate()

        let folderName = (cwd as NSString).lastPathComponent
        guard !folderName.isEmpty else { return }

        let appName = app.localizedName ?? fallbackName
        let script = """
        tell application "System Events"
            tell process "\(escapeAppleScript(appName))"
                repeat with w in windows
                    try
                        if name of w contains "\(escapeAppleScript(folderName))" then
                            perform action "AXRaise" of w
                            return
                        end if
                    end try
                end repeat
            end tell
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - Activate by bundle ID

    private static func activateByBundleId(_ bundleId: String) {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }) {
            if app.isHidden { app.unhide() }
            app.activate()
        }
        // Also use openApplication for reliable Space switching (Electron apps like VSCode)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Bring an app forward without calling `NSRunningApplication.activate()`.
    /// `activate()` triggers Ghostty's quick-terminal pop-up when Ghostty has no visible
    /// window — that's why activateGhostty avoids it too. Using only unhide +
    /// `NSWorkspace.openApplication` is safe across all parent terminals (Ghostty, iTerm2,
    /// WezTerm, Kaku, kitty, Warp, Terminal.app, cmux) and still handles Space switching.
    private static func raiseAppWithoutQuickTerminal(bundleId: String) {
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleId
        }) {
            if app.isHidden { app.unhide() }
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: - Generic (bring app to front)

    private static func bringToFront(_ termApp: String) {
        let name: String
        let lower = termApp.lowercased()
        if lower.contains("cmux") { name = "cmux" }
        else if lower == "ghostty" { name = "Ghostty" }
        else if lower.contains("iterm") { name = "iTerm2" }
        else if lower.contains("terminal") || lower.contains("apple_terminal") { name = "Terminal" }
        else if lower == "kaku" { name = "Kaku" }
        else if lower.contains("wezterm") || lower.contains("wez") { name = "WezTerm" }
        else if lower.contains("alacritty") || lower.contains("lacritty") { name = "Alacritty" }
        else if lower.contains("kitty") { name = "kitty" }
        else if lower.contains("warp") { name = "Warp" }
        else if lower.contains("hyper") { name = "Hyper" }
        else if lower.contains("tabby") { name = "Tabby" }
        else if lower.contains("rio") { name = "Rio" }
        else { name = termApp }

        // Try NSRunningApplication first — handles Space switching and unhide
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == name || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(name)
        }) {
            if app.isHidden { app.unhide() }
            app.activate()
            return
        }
        // Fallback: open -a (app not running yet)
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", name]
            try? proc.run()
        }
    }

    // MARK: - Helpers

    private static func detectRunningTerminal() -> String {
        let running = NSWorkspace.shared.runningApplications
        for (name, bundleId) in knownTerminals {
            if running.contains(where: { $0.bundleIdentifier == bundleId }) {
                return name
            }
        }
        return "Terminal"
    }

    private static func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let script = NSAppleScript(source: source) {
                var error: NSDictionary?
                script.executeAndReturnError(&error)
            }
        }
    }

    private static func runOsaScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            runOsaScriptSync(source)
        }
    }

    /// Run osascript on the current queue (no extra dispatch). Use from
    /// callers that are already on a background queue to avoid the double
    /// hop activateGhostty would otherwise pay (#139 review).
    private static func runOsaScriptSync(_ source: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", source]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
    }

    /// Escape special characters for AppleScript string interpolation
    private static func escapeAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Find a CLI binary in common paths (Homebrew Intel + Apple Silicon, system)
    /// Support extraPaths for priority search (e.g. app-bundled binaries like cmux)
    private static func findBinary(_ name: String, extraPaths: [String] = []) -> String? {
        let paths = extraPaths + [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Run a process and return stdout. Returns nil on failure or timeout.
    /// 10s cap on each call so a stuck osascript / tmux invocation can't
    /// freeze the UI when activate() is dispatched on the main thread (#139).
    @discardableResult
    private static func runProcess(_ path: String, args: [String], env: [String: String]? = nil) -> Data? {
        ProcessRunner.run(path: path, args: args, env: env, timeout: 10)
    }

    private static func tmuxProcessEnv(_ tmuxEnv: String?) -> [String: String]? {
        guard let tmuxEnv = tmuxEnv?.trimmingCharacters(in: .whitespacesAndNewlines),
              !tmuxEnv.isEmpty else { return nil }
        return ["TMUX": tmuxEnv]
    }

    // MARK: - cmux (CLI: focus-panel cross-workspace surface jump)

    /// Activate cmux and precisely focus on the specified surface.
    /// Prefers surface UUID (CMUX_SURFACE_ID); optionally pass workspace UUID to narrow scope.
    /// - Parameters:
    ///   - surfaceId: cmux surface UUID string (from CMUX_SURFACE_ID env var)
    ///   - workspaceId: cmux workspace UUID string (from CMUX_WORKSPACE_ID env var, optional)
    private static func activateCmux(surfaceId: String?, workspaceId: String?) {
        // Reuse activateByBundleId: unified handling of Space switching, hidden state, app not running, etc.
        activateByBundleId("com.cmuxterm.app")

        // No surface ID — degrade to app-level activation (already done above)
        guard let sid = surfaceId, !sid.isEmpty else { return }

        // Prefer bundle-embedded binary, then fall back to Homebrew / system paths
        guard let cmuxBin = findBinary("cmux", extraPaths: [
            "/Applications/cmux.app/Contents/Resources/bin/cmux",
            NSHomeDirectory() + "/Applications/cmux.app/Contents/Resources/bin/cmux",
        ]) else { return }

        // Invoke focus-panel CLI asynchronously to avoid blocking the main thread
        DispatchQueue.global(qos: .userInitiated).async {
            var args = ["focus-panel", "--panel", sid]
            if let wid = workspaceId, !wid.isEmpty {
                args += ["--workspace", wid]
            }
            _ = runProcess(cmuxBin, args: args)
        }
    }

    // MARK: - Warp (SQLite pane lookup + optional tab keystroke)

    /// Bring Warp forward, and when the SQLite state shows that the target cwd lives
    /// in a non-active tab, send the default "go to tab N" keystroke (Cmd+digit).
    ///
    /// The keystroke path requires Accessibility permission; without it CGEvent.post
    /// becomes a silent no-op and we gracefully degrade to plain app activation —
    /// which is what the previous implementation did unconditionally, so this is a
    /// strict improvement rather than a regression risk.
    private static func activateWarp(cwd: String?) {
        let warpBundleId = "dev.warp.Warp-Stable"

        guard let warpApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == warpBundleId
        }) else {
            bringToFront("Warp")
            return
        }
        raiseAppWithoutQuickTerminal(bundleId: warpBundleId)

        guard let cwd, !cwd.isEmpty else { return }

        // SQLite I/O is fast (sub-ms on a warm cache) but run it off the main thread
        // anyway; we've already handed the user a visible activation.
        DispatchQueue.global(qos: .userInitiated).async {
            let resolver = WarpPaneResolver()
            let matches: [WarpPaneMatch]
            do {
                matches = try resolver.resolve(cwd: cwd)
            } catch {
                return
            }
            guard let best = matches.first else { return }
            if best.isActiveTab { return }

            guard let targetPosition = warpShortcutPosition(for: best) else {
                return
            }
            guard hasAccessibilityPermission(prompt: true) else { return }

            sendWarpGoToTabWhenFrontmost(
                position: targetPosition,
                bundleId: warpBundleId,
                pid: warpApp.processIdentifier
            )
        }
    }

    /// Convert Warp's 0-based tab index to its built-in shortcut semantics:
    /// Cmd+1...Cmd+8 select tabs 1...8, and Cmd+9 selects the last tab.
    private static func warpShortcutPosition(for match: WarpPaneMatch) -> Int? {
        let targetPosition = match.tabIndexInWindow + 1
        if (1...8).contains(targetPosition) { return targetPosition }
        if targetPosition == match.tabCountInWindow { return 9 }
        return nil
    }

    /// Synthesize Warp's default "jump to tab" shortcut for the frontmost window.
    /// Positions 1...8 mean tabs 1...8; position 9 means the last tab.
    private static func sendWarpGoToTab(position: Int, pid: pid_t) {
        guard (1...9).contains(position) else { return }
        // ANSI virtual keycodes for digits 1..9 (QWERTY layout).
        let digitKeyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let keyCode = digitKeyCodes[position - 1]
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        if let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            down.flags = .maskCommand
            down.postToPid(pid)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
            up.flags = .maskCommand
            up.postToPid(pid)
        }
    }

    private static func sendWarpGoToTabWhenFrontmost(
        position: Int,
        bundleId: String,
        pid: pid_t,
        attemptsRemaining: Int = 6
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let frontBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if frontBundleId == bundleId {
                sendWarpGoToTab(position: position, pid: pid)
                return
            }

            guard attemptsRemaining > 0 else { return }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
            sendWarpGoToTabWhenFrontmost(
                position: position,
                bundleId: bundleId,
                pid: pid,
                attemptsRemaining: attemptsRemaining - 1
            )
        }
    }

    private static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
