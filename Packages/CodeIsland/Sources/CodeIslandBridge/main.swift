// ============================================================
// codeisland-bridge — Native Claude Code hook event forwarder
// ============================================================
// Replaces shell script + nc with:
// • Proper JSON parsing (no string manipulation)
// • Deep terminal environment detection (tmux, Kitty, iTerm, Ghostty)
// • Native POSIX socket communication
// • session_id validation (drop events without it)
// • CODEISLAND_SKIP env var support
// • Debug logging (CODEISLAND_DEBUG)
// ============================================================

import Foundation
import Darwin
import CodeIslandCore

// MARK: - Global Safety Net

// Never let a broken pipe kill the bridge — just fail the write silently
signal(SIGPIPE, SIG_IGN)

// Hard deadline: if anything hangs beyond this, bail out cleanly.
// Non-blocking events get 8s; blocking (permission/question) gets no alarm
// since those legitimately wait for user interaction.
// The alarm is armed later once we know the event type.
signal(SIGALRM) { _ in
    _exit(0)  // immediate, no cleanup — we're stuck anyway
}

// MARK: - Helper Functions

func detectTTY() -> String {
    let fd = open("/dev/tty", O_RDONLY | O_NOCTTY)
    if fd >= 0 {
        if let name = ttyname(fd) {
            close(fd)
            return String(cString: name)
        }
        close(fd)
    }
    return ""
}

func findBinary(_ name: String) -> String? {
    let searchPaths = [
        "/opt/homebrew/bin/\(name)",
        "/usr/local/bin/\(name)",
        "/usr/bin/\(name)",
    ]
    return searchPaths.first { access($0, X_OK) == 0 }
}

func runCommand(_ path: String, args: [String]) -> String? {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: path)
    proc.arguments = args
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (str?.isEmpty == false) ? str : nil
    } catch {
        return nil
    }
}

func executablePath(for pid: pid_t) -> String? {
    var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    let len = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
    guard len > 0 else { return nil }
    return String(cString: pathBuffer)
}

func parentPID(of pid: pid_t) -> pid_t? {
    var info = proc_bsdinfo()
    let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
    guard ret > 0, info.pbi_ppid > 0 else { return nil }
    return pid_t(info.pbi_ppid)
}

func buildAncestry(startingAt pid: pid_t, maxDepth: Int = 6) -> [(pid: pid_t, executablePath: String?)] {
    guard pid > 0 else { return [] }
    var result: [(pid: pid_t, executablePath: String?)] = []
    var current: pid_t? = pid
    var visited = Set<pid_t>()

    while let currentPid = current, currentPid > 0, result.count < maxDepth, !visited.contains(currentPid) {
        visited.insert(currentPid)
        result.append((pid: currentPid, executablePath: executablePath(for: currentPid)))
        current = parentPID(of: currentPid)
    }

    return result
}

func debugLog(_ message: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(message)\n"
    let path = "/tmp/codeisland-bridge.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
    }
}

func nonEmptyString(_ value: Any?) -> String? {
    guard let raw = value as? String else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func connectSocket(_ path: String, timeoutMs: Int32 = 3000) -> Int32? {
    let sock = socket(AF_UNIX, SOCK_STREAM, 0)
    guard sock >= 0 else { return nil }

    // Suppress per-write SIGPIPE on this socket (belt-and-suspenders with global SIG_IGN)
    var on: Int32 = 1
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
        path.withCString { _ = strcpy(ptr, $0) }
    }

    // Non-blocking connect with 3s timeout — prevents hanging if the listener is stuck
    let origFlags = fcntl(sock, F_GETFL)
    _ = fcntl(sock, F_SETFL, origFlags | O_NONBLOCK)

    let result = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    if result != 0 && errno != EINPROGRESS {
        close(sock)
        return nil
    }

    if result != 0 {
        // Wait for connect to complete (or timeout)
        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&pfd, 1, timeoutMs)
        if ready <= 0 {
            close(sock)
            return nil
        }
        // Check for socket error
        var sockErr: Int32 = 0
        var errLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &sockErr, &errLen)
        if sockErr != 0 {
            close(sock)
            return nil
        }
    }

    // Restore blocking mode for send/recv
    _ = fcntl(sock, F_SETFL, origFlags)
    return sock
}

func sendAll(_ sock: Int32, data: Data) {
    data.withUnsafeBytes { buf in
        guard let base = buf.baseAddress else { return }
        var sent = 0
        while sent < buf.count {
            let n = send(sock, base + sent, buf.count - sent, 0)
            if n < 0 {
                if errno == EINTR { continue }
                break
            }
            if n == 0 { break }
            sent += n
        }
    }
}

func recvAll(_ sock: Int32) -> Data {
    var response = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = recv(sock, &buf, buf.count, 0)
        if n < 0 {
            if errno == EINTR { continue }
            break
        }
        if n == 0 { break }
        response.append(contentsOf: buf[..<n])
    }
    return response
}

// MARK: - Main

let socketPath = SocketPath.path
let env = ProcessInfo.processInfo.environment
let args = CommandLine.arguments

// Parse --source flag (e.g. --source codex)
var sourceTag: String? = nil
if let idx = args.firstIndex(of: "--source"), idx + 1 < args.count {
    sourceTag = args[idx + 1]
}

// Parse --event flag (e.g. --event sessionStart) for CLIs that lack hook_event_name in stdin
var eventTag: String? = nil
if let idx = args.firstIndex(of: "--event"), idx + 1 < args.count {
    eventTag = args[idx + 1]
}

// Quick exit: skip if CODEISLAND_SKIP is set
guard env["CODEISLAND_SKIP"] == nil else { exit(0) }

// Quick exit: socket doesn't exist or isn't a socket
var statBuf = stat()
guard stat(socketPath, &statBuf) == 0, (statBuf.st_mode & S_IFMT) == S_IFSOCK else { exit(0) }

// Safety: arm a short alarm before reading stdin — if the calling process
// forgot to close its pipe, we bail out instead of blocking forever.
alarm(5)
let input = FileHandle.standardInput.readDataToEndOfFile()
alarm(0)  // stdin done, cancel preliminary alarm
if let inputStr = String(data: input, encoding: .utf8) {
    debugLog("raw input: \(inputStr)")
}

guard !input.isEmpty,
      var json = try? JSONSerialization.jsonObject(with: input) as? [String: Any] else {
    exit(0)
}

// Generic compatibility: accept common camelCase aliases from third-party forks
if json["hook_event_name"] == nil {
    if let event = nonEmptyString(json["hookEventName"]) {
        json["hook_event_name"] = event
    } else if let event = nonEmptyString(json["eventName"]) {
        json["hook_event_name"] = event
    } else if let event = nonEmptyString(json["event"]) {
        json["hook_event_name"] = event
    } else if let event = eventTag {
        json["hook_event_name"] = event
    }
}
if json["session_id"] == nil {
    if let sessionId = nonEmptyString(json["sessionId"]) {
        json["session_id"] = sessionId
    } else if let payload = json["payload"] as? [String: Any],
              let sessionId = nonEmptyString(payload["session_id"]) ?? nonEmptyString(payload["sessionId"]) {
        json["session_id"] = sessionId
    } else if let data = json["data"] as? [String: Any],
              let sessionId = nonEmptyString(data["session_id"]) ?? nonEmptyString(data["sessionId"]) {
        json["session_id"] = sessionId
    } else if let conversationId = nonEmptyString(json["conversationId"]) {
        // Google Antigravity (Gemini-based) stdin carries no session_id; it uses
        // `conversationId` as the stable per-conversation key (#215).
        json["session_id"] = conversationId
    }
}

// Google Antigravity sends the transcript path as camelCase `transcriptPath`;
// the rest of CodeIsland reads snake_case `transcript_path` (used by the JSONL
// tailer + cwd inference). Bridge the alias when only the camelCase form exists.
if json["transcript_path"] == nil, let tp = nonEmptyString(json["transcriptPath"]) {
    json["transcript_path"] = tp
}

// Copilot CLI adaptation: its stdin JSON lacks session_id and hook_event_name.
// Normalize Copilot's camelCase payload and pass through sessionId when present.
if sourceTag == "copilot" {
    if json["hook_event_name"] == nil, let event = eventTag {
        json["hook_event_name"] = event
    }
    if json["session_id"] == nil, let sessionId = nonEmptyString(json["sessionId"]) {
        json["session_id"] = sessionId
    }
    // Map Copilot-specific field names to internal conventions
    if let toolName = json["toolName"] as? String {
        json["tool_name"] = toolName
    }
    if let toolArgsStr = json["toolArgs"] as? String,
       let argsData = toolArgsStr.data(using: .utf8),
       let argsObj = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
        json["tool_input"] = argsObj
    }
}

// Cline adaptation: sends hookName and taskId instead of hook_event_name and session_id.
if sourceTag == "cline" {
    if json["hook_event_name"] == nil, let name = nonEmptyString(json["hookName"]) {
        json["hook_event_name"] = name
    }
    if json["session_id"] == nil, let taskId = nonEmptyString(json["taskId"]) {
        json["session_id"] = taskId
    }
    // Cline structures tool info as flat fields inside preToolUse/postToolUse objects:
    // PreToolUse:  { preToolUse:  { toolName: "execute_command", parameters: { ... } } }
    // PostToolUse: { postToolUse: { toolName: "execute_command", parameters: { ... }, result: ..., success: bool } }
    if json["tool_name"] == nil {
        if let preToolUse = json["preToolUse"] as? [String: Any],
           let toolName = nonEmptyString(preToolUse["toolName"] as? String) {
            json["tool_name"] = toolName
            if json["tool_input"] == nil, let parameters = preToolUse["parameters"] as? [String: Any] {
                json["tool_input"] = parameters
            }
        } else if let postToolUse = json["postToolUse"] as? [String: Any],
                  let toolName = nonEmptyString(postToolUse["toolName"] as? String) {
            json["tool_name"] = toolName
        }
    }
}

// Resolve process ancestry once — used for both session_id fallback (#148) and
// _ppid resolution downstream. Some CLIs execute hooks through `sh -c`, so
// `getppid()` is a transient shell rather than the long-lived CLI process.
let immediateParentPID = getppid()
let ancestry = buildAncestry(startingAt: immediateParentPID)
let coreAncestry = ancestry.map { (pid: Int32($0.pid), executablePath: $0.executablePath) }

// Source tag (e.g. "codex" when called via --source codex). If the caller did not pass
// one (e.g. the omo OpenCode plugin triggering Claude hooks without --source), infer
// the real source from the process ancestry so we don't misattribute the event to
// whichever hook path fired it. See issue #95.
// In addition, the cursor-agent / qodercli CLIs share their hooks file with
// the matching desktop IDE, so a `--source cursor` tag from a hook fired by
// cursor-agent should be promoted to "cursor-cli" (#134). The override only
// applies when ancestry actually shows a CLI binary.
let inferredSource = sourceTag ?? CLIProcessResolver.inferSource(ancestry: coreAncestry)
let cliPromoted = CLIProcessResolver.cliVariantOverride(
    declaredSource: inferredSource,
    ancestry: coreAncestry
)
let effectiveSource = cliPromoted ?? inferredSource
if let source = effectiveSource {
    json["_source"] = source
}
// Mark events that arrived via a plugin proxy (no explicit --source but
// ancestry inferred a real source — e.g. the omo OpenCode plugin firing
// Claude hooks) so the host app can route them per pluginSessionMode.
// See issue #123.
if sourceTag == nil && effectiveSource != nil {
    json["_via_plugin"] = true
}

let resolvedTrackedPID = CLIProcessResolver.resolvedTrackedPID(
    immediateParentPID: Int32(immediateParentPID),
    source: effectiveSource,
    ancestry: coreAncestry
)
json["_ppid"] = resolvedTrackedPID
if resolvedTrackedPID != immediateParentPID {
    json["_hook_ppid"] = Int32(immediateParentPID)
}
// Cline hooks are shell scripts spawned by a VSCode extension — the immediate
// parent is a transient shell, not a persistent agent process. Tracking this
// short-lived PID as cliPid causes cleanupIdleSessions to detect it as dead
// within seconds and remove the session. Clear it so no PID is tracked.
if effectiveSource == "cline" {
    json["_ppid"] = 0
}

// Validate: must have non-empty session_id
if json["session_id"] == nil,
   let source = sourceTag,
   !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    // Fallback for third-party providers that don't include a stable session ID.
    // Use the root same-source binary in the ancestry so sub-agent processes
    // (e.g. Cursor IDE spawning multiple parallel agent subprocesses, #148)
    // collapse onto a single session card instead of fanning into N cards
    // (one per sub-agent ppid).
    let sessionPID = CLIProcessResolver.resolvedSessionPID(
        immediateParentPID: Int32(immediateParentPID),
        source: effectiveSource ?? source,
        ancestry: coreAncestry
    )
    json["session_id"] = "\(source)-ppid-\(sessionPID)"
    debugLog("session_id missing, generated fallback id: \(json["session_id"] ?? "")")
}
guard let sessionId = json["session_id"] as? String, !sessionId.isEmpty else {
    debugLog("no session_id, dropping")
    exit(0)
}

// Event type detection
let eventName = json["hook_event_name"] as? String ?? ""
let normalizedEventName = EventNormalizer.normalize(eventName)
// Gemini CLI (--source gemini) and Google Antigravity (--source google-antigravity) both
// send PreToolUse in the JSON payload; treat it as a blocking permission event for both.
let isGeminiBasedSource = sourceTag == "google-antigravity" || sourceTag == "gemini"
    || effectiveSource == "google-antigravity" || effectiveSource == "gemini"
let isPermission = normalizedEventName == "PermissionRequest"
    || (isGeminiBasedSource && normalizedEventName == "PreToolUse")
let isQuestion = (normalizedEventName == "Notification" || eventName == "afterAgentThought")
    && json["question"] as? String != nil
let isBlocking = isPermission || isQuestion

debugLog("event=\(eventName) normalized=\(normalizedEventName) session=\(sessionId) permission=\(isPermission) question=\(isQuestion)")

// Arm deadline for env collection + connect + send (protects all events).
// For blocking events, this is disarmed right before the long recvAll wait.
alarm(isBlocking ? 8 : 4)

// --- Deep terminal environment collection ---
// Terminal app identification (only include when present)
if let termApp = env["TERM_PROGRAM"], !termApp.isEmpty {
    json["_term_app"] = termApp
}
if let termBundle = env["__CFBundleIdentifier"], !termBundle.isEmpty {
    json["_term_bundle"] = termBundle
}

// iTerm2 session — extract GUID after "w0t0p0:" prefix for AppleScript matching
if let iterm = env["ITERM_SESSION_ID"], !iterm.isEmpty {
    if let colonIdx = iterm.firstIndex(of: ":") {
        json["_iterm_session"] = String(iterm[iterm.index(after: colonIdx)...])
    } else {
        json["_iterm_session"] = iterm
    }
}

// Kitty window
if let kitty = env["KITTY_WINDOW_ID"], !kitty.isEmpty {
    json["_kitty_window"] = kitty
}

// tmux detection — deep info collection
if let tmux = env["TMUX"], !tmux.isEmpty {
    json["_tmux"] = tmux
    if let pane = env["TMUX_PANE"], !pane.isEmpty {
        json["_tmux_pane"] = pane
        // Get client TTY — use explicit path (hook PATH may lack homebrew)
        if let tmuxBin = findBinary("tmux"),
           let clientTTY = runCommand(tmuxBin, args: ["display-message", "-p", "-t", pane, "-F", "#{client_tty}"]) {
            json["_tmux_client_tty"] = clientTTY
        }
    }
}

// TTY path
let tty = detectTTY()
if !tty.isEmpty {
    json["_tty"] = tty
}

// cmux surface / workspace (env vars injected by cmux)
// cmux auto-injects CMUX_SURFACE_ID and CMUX_WORKSPACE_ID into each terminal on launch
// Bridge simply carries them into the payload during env collection; no extra process calls needed
if let cmuxSurface = env["CMUX_SURFACE_ID"], !cmuxSurface.isEmpty {
    json["_cmux_surface_id"] = cmuxSurface
}
if let cmuxWorkspace = env["CMUX_WORKSPACE_ID"], !cmuxWorkspace.isEmpty {
    json["_cmux_workspace_id"] = cmuxWorkspace
}

// Zellij multiplexer detection — pane id + optional session name for precise tab focus
if let zellij = env["ZELLIJ"], !zellij.isEmpty {
    json["_zellij"] = zellij
    if let pane = env["ZELLIJ_PANE_ID"], !pane.isEmpty {
        json["_zellij_pane_id"] = pane
    }
    if let session = env["ZELLIJ_SESSION_NAME"], !session.isEmpty {
        json["_zellij_session_name"] = session
    }
}

// WezTerm / Kaku pane id — both forks set WEZTERM_PANE; Kaku is a WezTerm fork (bundle id fun.tw93.kaku)
if let weztermPane = env["WEZTERM_PANE"], !weztermPane.isEmpty {
    json["_wezterm_pane"] = weztermPane
}

// Superset (Electron agent-orchestration terminal) — TERM_PROGRAM is spoofed to "kitty"
// and __CFBundleIdentifier is stripped from the PTY env, so the only reliable Superset
// signal is its own SUPERSET_* env vars (which survive Superset's env allowlist). The mere
// presence of any SUPERSET_* var uniquely means "running inside Superset"; the activator
// uses that to route to com.superset.desktop instead of the real kitty app. (#213)
if let supersetWs = env["SUPERSET_WORKSPACE_ID"], !supersetWs.isEmpty {
    json["_superset_workspace_id"] = supersetWs
}
// Pane / terminal id — captured for future pane-precision if Superset ever ships a focus CLI;
// either var's presence is also a reliable Superset signal on its own.
if let supersetPane = env["SUPERSET_PANE_ID"] ?? env["SUPERSET_TERMINAL_ID"], !supersetPane.isEmpty {
    json["_superset_pane_id"] = supersetPane
}

// Inject cwd if not already present. Gemini CLI / Google Antigravity hooks do not
// include a `cwd` field, so CodeIsland cannot resolve the project name and falls back
// to "Session". Populating it here lets the approval card show the actual folder name.
if json["cwd"] == nil {
    json["cwd"] = FileManager.default.currentDirectoryPath
}

// --- Serialize enriched JSON ---
guard let enriched = try? JSONSerialization.data(withJSONObject: json) else { exit(0) }

// --- Connect to Unix socket ---
if isGeminiBasedSource && isPermission {
    // Delay slightly to give the terminal TTY time to display the prompt
    // before showing the notch approval card.
    usleep(250_000)
}
let connectTimeoutMs: Int32 = isBlocking ? 3000 : 1000
guard let sock = connectSocket(socketPath, timeoutMs: connectTimeoutMs) else {
    debugLog("socket connect failed")
    exit(0)
}

// Set socket timeouts
var sendTv = timeval(tv_sec: isBlocking ? 86400 : 1, tv_usec: 0)
setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &sendTv, socklen_t(MemoryLayout<timeval>.size))
// Recv timeout: server responds within ms, but allow headroom for main-thread scheduling
var recvTv = timeval(tv_sec: isBlocking ? 86400 : 1, tv_usec: 0)
setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &recvTv, socklen_t(MemoryLayout<timeval>.size))

// Send enriched event data
sendAll(sock, data: enriched)

// Signal end of write (half-close → server sees EOF)
shutdown(sock, SHUT_WR)

// Blocking events wait for user interaction (minutes/hours) — disarm the deadline.
// Non-blocking events keep the alarm; SO_RCVTIMEO (3s) + alarm(8) double-protect.
if isBlocking {
    alarm(0)
}

// Wait for server response — critical: without this, close() races ahead
// of NWListener's main-thread handler and the event is lost
let response = recvAll(sock)

// Blocking events: forward response to stdout
if isBlocking && !response.isEmpty {
    if sourceTag == "google-antigravity" || effectiveSource == "google-antigravity" || sourceTag == "gemini" || effectiveSource == "gemini" {
        if let jsonObj = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
           let hookOutput = jsonObj["hookSpecificOutput"] as? [String: Any],
           let decisionObj = hookOutput["decision"] as? [String: Any],
           let behavior = decisionObj["behavior"] as? String {
            let translatedBehavior = (behavior == "allow" || behavior == "always") ? "allow" : "deny"
            let responseDict = ["decision": translatedBehavior]
            if let responseData = try? JSONSerialization.data(withJSONObject: responseDict) {
                FileHandle.standardOutput.write(responseData)
            } else {
                FileHandle.standardOutput.write(response)
            }
        } else {
            // Fallback: search for "allow" or "deny" in raw string to be resilient
            let responseStr = String(data: response, encoding: .utf8) ?? ""
            if responseStr.contains("\"behavior\":\"allow\"") || responseStr.contains("\"behavior\":\"always\"") {
                FileHandle.standardOutput.write(Data("{\"decision\":\"allow\"}".utf8))
            } else if responseStr.contains("\"behavior\":\"deny\"") {
                FileHandle.standardOutput.write(Data("{\"decision\":\"deny\"}".utf8))
            } else {
                FileHandle.standardOutput.write(response)
            }
        }
    } else {
        FileHandle.standardOutput.write(response)
    }
}

close(sock)
exit(0)
