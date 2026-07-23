import Foundation

struct RemoteInstallResult: Sendable {
    let ok: Bool
    let message: String
}

private struct RemoteCommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var ok: Bool { exitCode == 0 }
}

enum RemoteInstaller {
    private static let remoteHookVersion = "0.1.3"
    private static let remoteOpencodePluginVersion = "v2"

    static func installAll(host: RemoteHost, remoteSocketPath: String) async -> RemoteInstallResult {
        guard let source = remoteHookSource() else {
            return RemoteInstallResult(ok: false, message: "Missing remote hook resource")
        }
        guard let opencodePlugin = remoteOpencodePluginSource() else {
            return RemoteInstallResult(ok: false, message: "Missing remote OpenCode plugin resource")
        }

        let upload = await uploadRemoteHook(source: source, host: host)
        guard upload.ok else {
            return RemoteInstallResult(ok: false, message: "Upload failed: \(upload.stderrSummary)")
        }

        let uploadOpencode = await uploadRemoteOpencodePlugin(source: opencodePlugin, host: host, remoteSocketPath: remoteSocketPath)
        guard uploadOpencode.ok else {
            return RemoteInstallResult(ok: false, message: "OpenCode plugin upload failed: \(uploadOpencode.stderrSummary)")
        }

        let configure = await configureRemoteHooks(host: host, remoteSocketPath: remoteSocketPath)
        guard configure.ok else {
            return RemoteInstallResult(ok: false, message: "Install failed: \(configure.stderrSummary)")
        }

        let summary = configure.stdoutSummary.isEmpty ? "Claude/Qoder/Codex/CodeBuddy/Traecli/OpenCode remote hooks installed" : configure.stdoutSummary
        return RemoteInstallResult(ok: true, message: summary)
    }

    /// Probe the remote user's UID and return a per-user socket path so that multiple
    /// OS users on a shared host don't collide on a single `/tmp/codeisland.sock` (#193).
    /// Falls back to the legacy shared path when the probe fails (older / restricted host).
    static func prepareRemoteSocketPath(host: RemoteHost) async -> String {
        // `id -u` is a bare external command, so it returns the remote uid identically
        // under any login shell (bash / zsh / fish / csh). A fancier `$(...)` pipeline
        // would break under non-POSIX login shells like fish and silently fall back.
        let probe = await runSSH(host: host, command: "id -u", timeout: 8)
        let uid = probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if probe.ok, !uid.isEmpty, uid.allSatisfy({ $0.isNumber }) {
            return "/tmp/codeisland-\(uid).sock"
        }
        // Probe failed (old / restricted host) — fall back to the legacy shared path.
        // StreamLocalBindUnlink=yes on the forward already clears any stale socket, so
        // we avoid a second SSH round-trip here (it would just add latency on a host
        // that's likely failing to connect anyway).
        return host.remoteSocketPath
    }

    private static func remoteHookSource() -> String? {
        if let url = Bundle.appModule.url(forResource: "codeisland-remote-hook", withExtension: "py", subdirectory: "Resources"),
           let src = try? String(contentsOf: url) {
            return src
        }
        if let url = Bundle.appModule.url(forResource: "codeisland-remote-hook", withExtension: "py"),
           let src = try? String(contentsOf: url) {
            return src
        }
        return nil
    }

    private static func remoteOpencodePluginSource() -> String? {
        if let url = Bundle.appModule.url(forResource: "codeisland-opencode-remote", withExtension: "js", subdirectory: "Resources"),
           let src = try? String(contentsOf: url) {
            return src
        }
        if let url = Bundle.appModule.url(forResource: "codeisland-opencode-remote", withExtension: "js"),
           let src = try? String(contentsOf: url) {
            return src
        }
        return nil
    }

    private static func uploadRemoteHook(source: String, host: RemoteHost) async -> RemoteCommandResult {
        let encoded = Data(source.utf8).base64EncodedString()
        let py = """
import base64, os, pathlib

target = pathlib.Path.home() / ".codeisland" / "codeisland-remote-hook.py"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(base64.b64decode('''\(encoded)'''))
os.chmod(target, 0o755)
print(target)
"""
        return await runSSH(host: host, command: "python3 - <<'PY'\n\(py)\nPY", timeout: 25)
    }

    private static func uploadRemoteOpencodePlugin(source: String, host: RemoteHost, remoteSocketPath: String) async -> RemoteCommandResult {
        let configuredSource = remoteOpencodePluginForInstall(source: source, host: host, remoteSocketPath: remoteSocketPath)
        let encoded = Data(configuredSource.utf8).base64EncodedString()
        let py = """
import base64, os, pathlib

target = pathlib.Path.home() / ".codeisland" / "codeisland-opencode-remote.js"
target.parent.mkdir(parents=True, exist_ok=True)
target.write_bytes(base64.b64decode('''\(encoded)'''))
os.chmod(target, 0o644)
print(target)
"""
        return await runSSH(host: host, command: "python3 - <<'PY'\n\(py)\nPY", timeout: 25)
    }

    private static func configureRemoteHooks(host: RemoteHost, remoteSocketPath: String) async -> RemoteCommandResult {
        let py = configureRemoteHooksScript(host: host, remoteSocketPath: remoteSocketPath)
        // Run via the remote user's login shell so ~/.zprofile / ~/.bash_profile etc. are
        // sourced — that's how $CODEX_HOME (and similar) reach a non-interactive ssh session.
        // base64 keeps the script intact regardless of shell quoting.
        let encoded = Data(py.utf8).base64EncodedString()
        let inner = "echo '\(encoded)' | base64 -d | python3"
        let command = "\"${SHELL:-/bin/bash}\" -lc \"\(inner)\""
        return await runSSH(host: host, command: command, timeout: 30)
    }

    static func configureRemoteHooksScript(
        host: RemoteHost,
        remoteSocketPath: String? = nil,
        customCLIs: [CLIConfig] = ConfigInstaller.customCLIs()
    ) -> String {
        let hostId = pythonStringLiteral(host.id)
        let hostName = pythonStringLiteral(host.name)
        let version = pythonStringLiteral(remoteHookVersion)
        let opencodePluginVersion = pythonStringLiteral(remoteOpencodePluginVersion)
        let socketPath = pythonStringLiteral(remoteSocketPath ?? host.remoteSocketPath)
        let customCLIsLiteral = remoteCustomCLIsLiteral(customCLIs)
        return """
import json
import pathlib
import shutil
import os
import re

home = pathlib.Path.home()
hook_path = home / ".codeisland" / "codeisland-remote-hook.py"
host_id = \(hostId)
host_name = \(hostName)
version = \(version)
opencode_plugin_version = \(opencodePluginVersion)
socket_path = \(socketPath)
custom_clis = \(customCLIsLiteral)

def _codex_home():
    raw = (os.environ.get("CODEX_HOME") or "").strip()
    if not raw:
        return home / ".codex"
    expanded = os.path.expanduser(raw)
    return pathlib.Path(expanded)

def ensure_json(path):
    if path.exists():
        try:
            return json.loads(path.read_text())
        except Exception:
            return {}
    return {}

def strip_json_comments(text):
    out = []
    i = 0
    in_string = False
    escaped = False
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_string:
            out.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\\\":
                escaped = True
            elif ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue
        if ch == "/" and nxt == "/":
            i += 2
            while i < len(text) and text[i] != "\\n":
                i += 1
            continue
        if ch == "/" and nxt == "*":
            i += 2
            while i + 1 < len(text) and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(ch)
        i += 1
    return "".join(out)

def ensure_jsonc_object(path):
    if path.exists():
        try:
            data = json.loads(strip_json_comments(path.read_text()))
            return data if isinstance(data, dict) else None
        except Exception:
            return None
    return {}

def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\\n")

def write_text_atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)

def write_opencode_config(path, data):
    write_json(path, data)

def command_for(source):
    return f"CODEISLAND_SOCKET_PATH={socket_path} CODEISLAND_REMOTE_HOST_ID={json.dumps(host_id)} CODEISLAND_REMOTE_HOST_NAME={json.dumps(host_name)} CODEISLAND_SOURCE={source} python3 ~/.codeisland/codeisland-remote-hook.py"

def append_our_hooks(hooks, event, entries):
    # Preserve user-authored entries (#242): remove_our_hooks() already dropped our
    # stale entries, so append the fresh managed ones AFTER whatever the user has,
    # mirroring the local ConfigInstaller merge semantics. Never replace the event key.
    existing = hooks.get(event)
    if not isinstance(existing, list):
        existing = []
    hooks[event] = existing + entries

def remove_our_hooks(hooks):
    for event in list(hooks.keys()):
        entries = hooks.get(event)
        if not isinstance(entries, list):
            continue
        next_entries = []
        for entry in entries:
            if not isinstance(entry, dict):
                next_entries.append(entry)
                continue
            commands = []
            if isinstance(entry.get("hooks"), list):
                commands.extend([h.get("command", "") for h in entry["hooks"] if isinstance(h, dict)])
            if isinstance(entry.get("command"), str):
                commands.append(entry["command"])
            if isinstance(entry.get("bash"), str):
                commands.append(entry["bash"])
            if any("codeisland-remote-hook.py" in c for c in commands):
                continue
            next_entries.append(entry)
        if next_entries:
            hooks[event] = next_entries
        else:
            hooks.pop(event, None)

TRAECLI_EVENTS = [
    ("session_start", 5),
    ("session_end", 5),
    ("user_prompt_submit", 5),
    ("pre_tool_use", 5),
    ("post_tool_use", 5),
    ("post_tool_use_failure", 5),
    ("permission_request", 86400),
    ("notification", 86400),
    ("subagent_start", 5),
    ("subagent_stop", 5),
    ("stop", 5),
    ("pre_compact", 5),
    ("post_compact", 5),
]

def _normalize_traecli_hooks_list_indentation(contents):
    # Best-effort repair for invalid YAML produced by mixed indentation under top-level `hooks:`.
    #
    # Only normalize indentation of *hook items* ("- type:" / "- command:")
    # and shift the entire list item block left to match the smallest indent.
    normalized = contents.replace("\\r\\n", "\\n")
    lines = normalized.split("\\n")

    hooks_index = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if line != stripped:
            continue
        if stripped.startswith("hooks:"):
            hooks_index = i
            break
    if hooks_index is None:
        return normalized

    def _is_top_level_key(line):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            return False
        if line != stripped:
            return False
        return ":" in stripped and not stripped.startswith("hooks:")

    # Find the smallest indent among hook items.
    indents = []
    i = hooks_index + 1
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            i += 1
            continue
        if _is_top_level_key(line):
            break
        if stripped.startswith("- type:") or stripped.startswith("- command:"):
            indents.append(len(line) - len(line.lstrip(" ")))
        i += 1
    if not indents:
        return normalized
    base_indent = min(indents)

    out = list(lines)
    i = hooks_index + 1
    while i < len(out):
        line = out[i]
        stripped = line.strip()
        if not stripped:
            i += 1
            continue
        if _is_top_level_key(line):
            break
        if stripped.startswith("- type:") or stripped.startswith("- command:"):
            indent = len(line) - len(line.lstrip(" "))
            if indent > base_indent:
                delta = indent - base_indent
                j = i
                while j < len(out):
                    nxt = out[j]
                    nxt_stripped = nxt.strip()
                    nxt_indent = len(nxt) - len(nxt.lstrip(" "))
                    if j != i:
                        if nxt_indent == indent and nxt_stripped.startswith("- "):
                            break
                        if nxt_indent < indent and nxt_stripped != "":
                            break
                    if nxt.startswith(" " * delta):
                        out[j] = nxt[delta:]
                    j += 1
                i = j
                continue
        i += 1

    return "\\n".join(out)

def _detect_traecli_hook_item_indent(lines, hooks_index):
    def _is_top_level_key(line):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            return False
        if line != stripped:
            return False
        return ":" in stripped and not stripped.startswith("hooks:")

    indents = []
    i = hooks_index + 1
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            i += 1
            continue
        if _is_top_level_key(line):
            break
        if stripped.startswith("- type:") or stripped.startswith("- command:"):
            indents.append(len(line) - len(line.lstrip(" ")))
        i += 1
    return min(indents) if indents else 2

def _render_managed_traecli_hooks(cmd, indent=2):
    # Escape single quotes for YAML single-quoted string
    escaped = cmd.replace("'", "''")
    timeout = max([t for (_, t) in TRAECLI_EVENTS] or [5])
    pad = " " * indent
    pad2 = " " * (indent + 2)
    pad4 = " " * (indent + 4)
    lines = [f"{pad}- type: command"]
    lines.append(f"{pad2}command: '{escaped}'")
    lines.append(f"{pad2}timeout: '{timeout}s'")
    lines.append(f"{pad2}matchers:")
    for (event, _) in TRAECLI_EVENTS:
        lines.append(f"{pad4}- event: {event}")
    return "\\n".join(lines)

def _remove_managed_traecli_hooks(contents):
    normalized = _normalize_traecli_hooks_list_indentation(contents)
    lines = normalized.split("\\n")
    result = []

    # Legacy compatibility: previous versions could leave extra comment lines around our hook.
    # We do NOT key off any marker token. Instead, when removing a hook by command match,
    # we also remove contiguous same-indent comment lines adjacent to that hook.

    def _parse_scalar(raw):
        raw = raw.strip()
        if raw.startswith("'") and raw.endswith("'") and len(raw) >= 2:
            return raw[1:-1].replace("''", "'")
        if raw.startswith('"') and raw.endswith('"') and len(raw) >= 2:
            inner = raw[1:-1]
            bs = chr(92)
            return inner.replace(bs + bs, bs).replace(bs + '"', '"')
        return raw

    def _normalize_cmd(cmd):
        s = " ".join((cmd or "").strip().split())
        if not s:
            return s
        # Normalize first token: allow quoted executable path.
        if s.startswith('"'):
            end = s.find('"', 1)
            if end != -1:
                first = s[1:end]
                rest = s[end+1:].strip()
                s = first + (" " + rest if rest else "")
        parts = s.split(" ", 1)
        first = parts[0]
        rest = parts[1] if len(parts) > 1 else ""
        if first.startswith("~/"):
            first = str(home) + "/" + first[2:]
        return first + (" " + rest if rest else "")

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        prefix = "- type: command"
        if stripped.startswith(prefix) and (stripped == prefix or stripped[len(prefix):].startswith((" ", "\t", "#"))):
            indent = len(line) - len(line.lstrip(" "))
            j = i + 1
            cmd_value = None
            while j < len(lines):
                nxt = lines[j]
                nxt_stripped = nxt.strip()
                nxt_indent = len(nxt) - len(nxt.lstrip(" "))
                if nxt_indent == indent and nxt_stripped.startswith("- "):
                    break
                if nxt_indent < indent and nxt_stripped != "":
                    break
                if nxt_stripped.startswith("command:"):
                    cmd_value = _parse_scalar(nxt_stripped.split(":", 1)[1])
                j += 1

            if cmd_value and _normalize_cmd(cmd_value) == _normalize_cmd(command_for("traecli")):
                # Remove adjacent same-indent comment lines already appended.
                while result:
                    prev = result[-1]
                    prev_stripped = prev.strip()
                    prev_indent = len(prev) - len(prev.lstrip(" "))
                    if prev_indent == indent and prev_stripped.startswith("#"):
                        result.pop()
                        continue
                    break

                # Skip forward adjacent same-indent comment lines.
                k = j
                while k < len(lines):
                    nxt = lines[k]
                    nxt_stripped = nxt.strip()
                    nxt_indent = len(nxt) - len(nxt.lstrip(" "))
                    if nxt_indent == indent and nxt_stripped.startswith("#"):
                        k += 1
                        continue
                    break

                i = k
                continue

            result.extend(lines[i:j])
            i = j
            continue

        result.append(line)
        i += 1
    # Trim trailing empty lines (keep one newline at end)
    while len(result) >= 2 and (result[-1] == "") and (result[-2] == ""):
        result.pop()
    return "\\n".join(result)

def _merge_traecli_hooks(contents, cmd):
    normalized = _normalize_traecli_hooks_list_indentation(contents)
    cleaned = _remove_managed_traecli_hooks(normalized)
    lines = cleaned.split("\\n")
    hooks_index = None
    hooks_scalar = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if line != stripped:
            continue
        if not stripped.startswith("hooks:"):
            continue
        tail = stripped[len("hooks:"):]
        before_comment = tail.split("#", 1)[0].strip()
        if before_comment in ("", "[]", "{}", "null", "~"):
            hooks_index = i
            hooks_scalar = before_comment
            break
    if hooks_index is not None:
        indent = _detect_traecli_hook_item_indent(lines, hooks_index)
        managed_lines = _render_managed_traecli_hooks(cmd, indent=indent).split("\\n")
        if hooks_scalar and hooks_scalar != "":
            lines[hooks_index] = "hooks:"
        lines[hooks_index+1:hooks_index+1] = managed_lines
    else:
        managed_lines = _render_managed_traecli_hooks(cmd, indent=2).split("\\n")
        while lines and lines[-1] == "":
            lines.pop()
        if lines:
            lines.append("")
        lines.append("hooks:")
        lines.extend(managed_lines)
    merged = "\\n".join(lines)
    if not merged.endswith("\\n"):
        merged += "\\n"
    return merged

def install_claude():
    claude_root = home / ".claude"
    if not claude_root.exists() and shutil.which("claude") is None:
        return "Claude skipped"

    settings_path = claude_root / "settings.json"
    data = ensure_json(settings_path)
    hooks = data.get("hooks") or {}
    remove_our_hooks(hooks)

    cmd = command_for("claude")
    without_matcher = [{"hooks": [{"type": "command", "command": cmd, "timeout": 60}]}]
    with_matcher = [{"matcher": "*", "hooks": [{"type": "command", "command": cmd, "timeout": 60}]}]
    with_long_timeout = [{"matcher": "*", "hooks": [{"type": "command", "command": cmd, "timeout": 86400}]}]
    precompact = [
        {"matcher": "auto", "hooks": [{"type": "command", "command": cmd, "timeout": 60}]},
        {"matcher": "manual", "hooks": [{"type": "command", "command": cmd, "timeout": 60}]},
    ]
    append_our_hooks(hooks, "UserPromptSubmit", without_matcher)
    append_our_hooks(hooks, "PermissionRequest", with_long_timeout)
    append_our_hooks(hooks, "Notification", with_matcher)
    append_our_hooks(hooks, "Stop", without_matcher)
    append_our_hooks(hooks, "SessionStart", without_matcher)
    append_our_hooks(hooks, "SessionEnd", without_matcher)
    append_our_hooks(hooks, "PreCompact", precompact)
    data["hooks"] = hooks
    write_json(settings_path, data)
    return "Claude ok"

def install_qoder():
    qoder_root = home / ".qoder"
    if not qoder_root.exists() and shutil.which("qodercli") is None and shutil.which("qoder") is None:
        return "Qoder skipped"

    settings_path = qoder_root / "settings.json"
    data = ensure_json(settings_path)
    hooks = data.get("hooks") or {}
    remove_our_hooks(hooks)

    cmd = command_for("qoder")
    without_matcher = [{"hooks": [{"type": "command", "command": cmd, "timeout": 60}]}]
    with_matcher = [{"matcher": "*", "hooks": [{"type": "command", "command": cmd, "timeout": 60}]}]
    with_long_timeout = [{"matcher": "*", "hooks": [{"type": "command", "command": cmd, "timeout": 86400}]}]
    precompact = [
        {"matcher": "auto", "hooks": [{"type": "command", "command": cmd, "timeout": 60}]},
        {"matcher": "manual", "hooks": [{"type": "command", "command": cmd, "timeout": 60}]},
    ]
    append_our_hooks(hooks, "UserPromptSubmit", without_matcher)
    append_our_hooks(hooks, "PermissionRequest", with_long_timeout)
    append_our_hooks(hooks, "Notification", with_matcher)
    append_our_hooks(hooks, "Stop", without_matcher)
    append_our_hooks(hooks, "SessionStart", without_matcher)
    append_our_hooks(hooks, "SessionEnd", without_matcher)
    append_our_hooks(hooks, "PreCompact", precompact)
    data["hooks"] = hooks
    write_json(settings_path, data)
    return "Qoder ok"

# Hermes (Nous Research) is NOT a Claude Code fork. It reads shell hooks from
# ~/.hermes/config.yaml under a `hooks:` MAP keyed by snake_case event names whose
# values are lists of { command, timeout }. settings.json is never parsed (#226).
HERMES_EVENTS = [
    ("pre_tool_call", 5),
    ("post_tool_call", 5),
    ("on_session_start", 5),
    ("on_session_end", 5),
    ("subagent_stop", 5),
]

def _parse_yaml_scalar(raw):
    raw = raw.strip()
    if raw.startswith("'") and raw.endswith("'") and len(raw) >= 2:
        return raw[1:-1].replace("''", "'")
    if raw.startswith('"') and raw.endswith('"') and len(raw) >= 2:
        inner = raw[1:-1]
        bs = chr(92)
        return inner.replace(bs + bs, bs).replace(bs + '"', '"')
    return raw

def _normalize_hook_cmd(c):
    s = " ".join((c or "").strip().split())
    if not s:
        return s
    if s.startswith('"'):
        end = s.find('"', 1)
        if end != -1:
            first = s[1:end]
            rest = s[end+1:].strip()
            s = first + (" " + rest if rest else "")
    parts = s.split(" ", 1)
    first = parts[0]
    rest = parts[1] if len(parts) > 1 else ""
    if first.startswith("~/"):
        first = str(home) + "/" + first[2:]
    return first + (" " + rest if rest else "")

def _merge_hermes_hooks(contents, cmd):
    # Event-key-aware merge for Hermes' nested `hooks:` MAP. We parse the existing
    # map into an ordered {event: [item-blocks]} structure, drop our prior managed
    # entries (matched by command), prepend a fresh managed entry under each of our
    # status events, then re-emit a single `hooks:` block. This is idempotent and
    # never produces duplicate event keys (#226).
    normalized = contents.replace("\\r\\n", "\\n")
    lines = normalized.split("\\n")
    target_cmd = _normalize_hook_cmd(cmd)

    def _is_top_level_key(line):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            return False
        if line != stripped:
            return False
        return ":" in stripped

    # Locate a top-level `hooks:` mapping key (empty scalar or block-mapping).
    hooks_index = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if line != stripped:
            continue
        if stripped == "hooks:" or stripped.startswith("hooks:"):
            tail = stripped[len("hooks:"):].split("#", 1)[0].strip()
            if tail in ("", "{}", "null", "~"):
                hooks_index = i
                break

    # Ordered list of (event, [item_blocks]); item_block is a list of raw lines
    # for one `- ...` list entry, re-indented to 4 spaces on emit.
    order = []
    events = {}

    def _ensure_event(ev):
        if ev not in events:
            events[ev] = []
            order.append(ev)

    head_lines = []
    tail_lines = []
    if hooks_index is not None:
        head_lines = lines[:hooks_index]
        j = hooks_index + 1
        current_event = None
        while j < len(lines):
            line = lines[j]
            stripped = line.strip()
            if stripped and _is_top_level_key(line):
                break  # left the hooks: block
            if stripped == "" or stripped.startswith("#"):
                j += 1
                continue
            indent = len(line) - len(line.lstrip(" "))
            # An event sub-key like "  pre_tool_call:".
            if not stripped.startswith("- ") and stripped.endswith(":") and indent >= 1:
                current_event = stripped[:-1].strip()
                _ensure_event(current_event)
                j += 1
                continue
            # A list item under the current event.
            if stripped.startswith("- ") and current_event is not None:
                item_indent = indent
                k = j + 1
                while k < len(lines):
                    nxt = lines[k]
                    nxt_stripped = nxt.strip()
                    nxt_indent = len(nxt) - len(nxt.lstrip(" "))
                    if nxt_stripped == "":
                        k += 1
                        continue
                    if nxt_indent <= item_indent:
                        break
                    k += 1
                raw_block = [bl for bl in lines[j:k] if bl.strip() != ""]
                cmd_value = None
                for bl in raw_block:
                    bstr = bl.strip()
                    key = bstr[2:].strip() if bstr.startswith("- ") else bstr
                    if key.startswith("command:"):
                        cmd_value = _parse_yaml_scalar(key.split(":", 1)[1])
                        break
                # Re-indent the user item to a canonical 4-space list indent so it
                # composes with our managed entries (avoids mixed-indent YAML).
                base = min(len(bl) - len(bl.lstrip(" ")) for bl in raw_block)
                block = []
                for bl in raw_block:
                    cur = len(bl) - len(bl.lstrip(" "))
                    block.append(" " * (4 + (cur - base)) + bl.lstrip(" "))
                # Drop our prior managed entries; keep user entries.
                if not (cmd_value is not None and _normalize_hook_cmd(cmd_value) == target_cmd):
                    events[current_event].append(block)
                j = k
                continue
            j += 1
        tail_lines = lines[j:]
    else:
        head_lines = list(lines)
        while head_lines and head_lines[-1] == "":
            head_lines.pop()

    # Prepend our managed entry under each status event.
    escaped = cmd.replace("'", "''")
    for (event, timeout) in HERMES_EVENTS:
        _ensure_event(event)
        managed_item = [
            f"    - command: '{escaped}'",
            f"      timeout: {timeout}",
        ]
        events[event].insert(0, managed_item)

    out = list(head_lines)
    if out and out[-1].strip() != "":
        out.append("")
    out.append("hooks:")
    for event in order:
        out.append(f"  {event}:")
        for block in events[event]:
            out.extend(block)
    out.extend(tail_lines)

    merged = "\\n".join(out)
    if not merged.endswith("\\n"):
        merged += "\\n"
    return merged

def install_hermes():
    hermes_root = home / ".hermes"
    if not hermes_root.exists() and shutil.which("hermes") is None:
        return "Hermes skipped"

    config_path = hermes_root / "config.yaml"
    try:
        original = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    except Exception:
        return "Hermes read failed"
    cmd = command_for("hermes")
    merged = _merge_hermes_hooks(original, cmd)
    write_text_atomic(config_path, merged)
    return "Hermes ok"

def ensure_toml_codex_hooks(path):
    content = path.read_text() if path.exists() else ""
    current_hooks_pattern = r"(?m)^\\s*hooks\\s*=\\s*(true|false)\\s*(#.*)?$"
    hooks_true_pattern = r"(?m)^\\s*hooks\\s*=\\s*true\\s*(#.*)?$"
    hooks_false_pattern = r"(?m)^\\s*hooks\\s*=\\s*false\\s*(#.*)?$"
    legacy_hooks_pattern = r"(?m)^\\s*codex_hooks\\s*=\\s*(true|false)\\s*(#.*)?$"
    has_current_hooks = re.search(current_hooks_pattern, content) is not None
    had_legacy_hooks = re.search(legacy_hooks_pattern, content) is not None
    if re.search(legacy_hooks_pattern, content):
        replacement = "" if has_current_hooks else "hooks = true"
        content = re.sub(legacy_hooks_pattern, replacement, content)
    if re.search(hooks_true_pattern, content):
        if had_legacy_hooks:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content.rstrip() + "\\n")
        return
    if re.search(hooks_false_pattern, content):
        content = re.sub(hooks_false_pattern, "hooks = true", content)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content.rstrip() + "\\n")
        return
    lines = content.splitlines()
    try:
        idx = next(i for i, line in enumerate(lines) if line.strip() == "[features]")
        lines.insert(idx + 1, "hooks = true")
    except StopIteration:
        if lines and lines[-1].strip():
            lines.append("")
        lines.extend(["[features]", "hooks = true"])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\\n".join(lines).rstrip() + "\\n")

def install_codex():
    codex_root = _codex_home()
    if not codex_root.exists() and shutil.which("codex") is None:
        return "Codex skipped"

    hooks_path = codex_root / "hooks.json"
    data = ensure_json(hooks_path)
    hooks = data.get("hooks") or {}
    remove_our_hooks(hooks)

    cmd = command_for("codex")
    entry = [{"hooks": [{"type": "command", "command": cmd, "timeout": 60}]}]
    append_our_hooks(hooks, "SessionStart", entry)
    append_our_hooks(hooks, "UserPromptSubmit", entry)
    append_our_hooks(hooks, "Stop", entry)
    data["hooks"] = hooks
    write_json(hooks_path, data)
    ensure_toml_codex_hooks(codex_root / "config.toml")
    return "Codex ok"

def install_codebuddy():
    codebuddy_root = home / ".codebuddy"
    if not codebuddy_root.exists() and shutil.which("codebuddy") is None:
        return "CodeBuddy skipped"

    settings_path = codebuddy_root / "settings.json"
    data = ensure_json(settings_path)
    hooks = data.get("hooks") or {}
    remove_our_hooks(hooks)

    cmd = command_for("codebuddy")
    without_matcher = [{"hooks": [{"type": "command", "command": cmd, "timeout": 60}]}]
    with_matcher = [{"matcher": "*", "hooks": [{"type": "command", "command": cmd, "timeout": 60}]}]
    with_long_timeout = [{"matcher": "*", "hooks": [{"type": "command", "command": cmd, "timeout": 86400}]}]
    precompact = [
        {"matcher": "auto", "hooks": [{"type": "command", "command": cmd, "timeout": 60}]},
        {"matcher": "manual", "hooks": [{"type": "command", "command": cmd, "timeout": 60}]},
    ]
    append_our_hooks(hooks, "UserPromptSubmit", without_matcher)
    append_our_hooks(hooks, "PermissionRequest", with_long_timeout)
    append_our_hooks(hooks, "Notification", with_matcher)
    append_our_hooks(hooks, "Stop", without_matcher)
    append_our_hooks(hooks, "SessionStart", without_matcher)
    append_our_hooks(hooks, "SessionEnd", without_matcher)
    append_our_hooks(hooks, "PreCompact", precompact)
    data["hooks"] = hooks
    write_json(settings_path, data)
    return "CodeBuddy ok"

def install_traecli():
    traecli_root = home / ".trae"
    if not traecli_root.exists() and shutil.which("traecli") is None:
        return "Traecli skipped"

    config_path = traecli_root / "traecli.yaml"
    try:
        original = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
    except Exception:
        return "Traecli read failed"
    cmd = command_for("traecli")
    merged = _merge_traecli_hooks(original, cmd)
    write_text_atomic(config_path, merged)
    return "Traecli ok"

def install_opencode():
    opencode_root = home / ".config" / "opencode"
    if not opencode_root.exists() and shutil.which("opencode") is None:
        return "OpenCode skipped"

    plugin_path = home / ".codeisland" / "codeisland-opencode-remote.js"
    if not plugin_path.exists():
        return "OpenCode plugin missing"

    target_path = opencode_root / "opencode.jsonc"
    if not target_path.exists():
        target_path = opencode_root / "opencode.json"
    data = ensure_jsonc_object(target_path)
    if data is None:
        return "OpenCode config unreadable"

    plugin_ref = "file://" + str(plugin_path)
    plugins = data.get("plugin")
    if not isinstance(plugins, list):
        plugins = []
    plugins = [
        p for p in plugins
        if not (isinstance(p, str) and ("vibe-island" in p or "codeisland" in p))
    ]
    plugins.append(plugin_ref)
    data["plugin"] = plugins
    data.setdefault("$schema", "https://opencode.ai/config.json")
    write_opencode_config(target_path, data)

    legacy_path = opencode_root / "config.json"
    if legacy_path.exists():
        legacy = ensure_jsonc_object(legacy_path)
        if isinstance(legacy, dict) and isinstance(legacy.get("plugin"), list):
            cleaned = [p for p in legacy["plugin"] if not (isinstance(p, str) and ("vibe-island" in p or "codeisland" in p))]
            if cleaned != legacy["plugin"]:
                if cleaned:
                    legacy["plugin"] = cleaned
                else:
                    legacy.pop("plugin", None)
                write_opencode_config(legacy_path, legacy)
    return "OpenCode ok"

def install_custom():
    results = []
    for cli in custom_clis:
        source = cli["source"]
        config_path = home / cli["config_path"]
        if not config_path.parent.exists() and shutil.which(source) is None:
            results.append(cli["name"] + " skipped")
            continue
        data = ensure_json(config_path)
        if not isinstance(data, dict):
            data = {}
        hooks = data.get(cli["config_key"])
        if not isinstance(hooks, dict):
            hooks = {}
        remove_our_hooks(hooks)
        cmd = command_for(source)
        for ev in cli["events"]:
            event = ev[0]
            timeout = ev[1]
            if cli["format"] == "claude":
                append_our_hooks(hooks, event, [{"matcher": "*", "hooks": [{"type": "command", "command": cmd, "timeout": timeout}]}])
            else:
                append_our_hooks(hooks, event, [{"hooks": [{"type": "command", "command": cmd, "timeout": timeout}]}])
        data[cli["config_key"]] = hooks
        write_json(config_path, data)
        results.append(cli["name"] + " ok")
    return results

parts = [install_claude(), install_qoder(), install_hermes(), install_codex(), install_codebuddy(), install_traecli(), install_opencode()] + install_custom()
print(" · ".join(parts))
"""
    }

    private static func runSSH(host: RemoteHost, command: String, timeout: TimeInterval) async -> RemoteCommandResult {
        guard !host.sshTarget.isEmpty else {
            return RemoteCommandResult(stdout: "", stderr: "invalid host", exitCode: -1)
        }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = sshArguments(host: host) + [command]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.standardInput = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continuation.resume(returning: RemoteCommandResult(stdout: "", stderr: error.localizedDescription, exitCode: -1))
                return
            }

            let timeoutTask = Task.detached {
                let ns = UInt64(timeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                if process.isRunning {
                    process.terminate()
                }
            }

            Task.detached {
                process.waitUntilExit()
                timeoutTask.cancel()
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""
                continuation.resume(returning: RemoteCommandResult(stdout: out, stderr: err, exitCode: process.terminationStatus))
            }
        }
    }

    private static func sshArguments(host: RemoteHost) -> [String] {
        var args: [String] = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
        ]
        if let port = host.port {
            args += ["-p", String(port)]
        }
        let trimmedIdentity = host.identityFile.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedIdentity.isEmpty {
            args += ["-i", trimmedIdentity]
        }
        args.append(host.sshTarget)
        return args
    }

    /// Serialize custom CLI configs into a Python list literal for the remote install
    /// script. Only `.claude` / `.nested` formats are emitted — their stdin carries
    /// `hook_event_name`, so the remote hook handles them with no `--event` flag.
    /// Other formats (flat/Cursor, traecli, copilot, kimi, …) are skipped remotely (#192).
    private static func remoteCustomCLIsLiteral(_ clis: [CLIConfig]) -> String {
        let supported = clis.filter { $0.format == .claude || $0.format == .nested }
        let entries = supported.map { cli -> String in
            let fmt = cli.format == .claude ? "claude" : "nested"
            let events = cli.events
                .map { "[\(pythonStringLiteral($0.0)), \($0.1)]" }
                .joined(separator: ", ")
            return "{"
                + "\"name\": \(pythonStringLiteral(cli.name)), "
                + "\"source\": \(pythonStringLiteral(cli.source)), "
                + "\"config_path\": \(pythonStringLiteral(cli.configPath)), "
                + "\"config_key\": \(pythonStringLiteral(cli.configKey)), "
                + "\"format\": \(pythonStringLiteral(fmt)), "
                + "\"events\": [\(events)]"
                + "}"
        }
        return "[\(entries.joined(separator: ", "))]"
    }

    private static func pythonStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    static func remoteOpencodePluginForInstall(source: String, host: RemoteHost, remoteSocketPath: String? = nil) -> String {
        let socketPath = remoteSocketPath ?? host.remoteSocketPath
        return source
            .replacingOccurrences(
                of: #"const SOCKET_PATH = process.env.CODEISLAND_SOCKET_PATH || "/tmp/codeisland.sock";"#,
                with: #"const SOCKET_PATH = \#(jsonStringLiteral(socketPath));"#
            )
            .replacingOccurrences(
                of: #"const REMOTE_HOST_ID = process.env.CODEISLAND_REMOTE_HOST_ID || "";"#,
                with: #"const REMOTE_HOST_ID = \#(jsonStringLiteral(host.id));"#
            )
            .replacingOccurrences(
                of: #"const REMOTE_HOST_NAME = process.env.CODEISLAND_REMOTE_HOST_NAME || "";"#,
                with: #"const REMOTE_HOST_NAME = \#(jsonStringLiteral(host.name));"#
            )
    }

    private static func jsonStringLiteral(_ value: String) -> String {
        let escaped = value.reduce(into: "") { result, ch in
            switch ch {
            case "\\":
                result += "\\\\"
            case "\"":
                result += "\\\""
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            default:
                result.append(ch)
            }
        }
        return "\"\(escaped)\""
    }
}

private extension RemoteCommandResult {
    var stderrSummary: String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown error" : trimmed
    }

    var stdoutSummary: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
