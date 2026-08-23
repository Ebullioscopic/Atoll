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

import Foundation

/// One hook event Atoll asks an agent to fire.
struct AgentHookEventSpec: Sendable {
    /// The event name exactly as that agent spells it in its config.
    let wireName: String
    /// Tool-scoped events take a `matcher`; lifecycle events do not.
    let usesMatcher: Bool
    /// Whether the shim should block waiting for a decision.
    ///
    /// Observe-only events drop their request file and exit, which costs about a
    /// millisecond and can never delay an agent.
    let expectsDecision: Bool
}

/// Where and how to install hooks for one agent.
struct AgentHookConfigDescriptor: Sendable {
    let kind: AgentKind
    let configURL: URL
    let events: [AgentHookEventSpec]
    /// How much Atoll actually knows about this agent, as opposed to has assumed.
    let verification: VerificationLevel
}

/// What has been checked about an agent's hook contract.
///
/// Kept deliberately granular because "verified" was doing too much work: a
/// config whose *shape* is known is not the same as one whose *decision reply* is
/// known to be honoured, and telling the user otherwise would be a claim Atoll
/// cannot back.
enum VerificationLevel: Sendable {
    /// Config shape, event names and decision replies all confirmed against a
    /// real installation.
    case verified
    /// The config exists and its shape and event names are confirmed, but whether
    /// the agent acts on a decision reply has not been observed. Monitoring is
    /// reliable; approvals may simply do nothing, in which case the agent's own
    /// prompt appears — the fail-open contract makes that harmless.
    case schemaOnly
    /// Written from documentation. Not installed on this machine, so nothing has
    /// been confirmed.
    case unverified
}

/// Writes the hook shim and merges Atoll's entries into each agent's own config.
///
/// ## Ground rules
/// These files belong to the user and to another tool, so:
///
/// 1. **Never rewrite the whole file.** The config is parsed, only the `hooks`
///    subtree is touched, and every other key is written back unchanged. Real
///    configs carry `enabledPlugins`, `theme`, `model`, `language` and more; a
///    `Codable` round-trip would silently delete them, which is why this uses
///    `JSONSerialization` and dictionaries throughout.
/// 2. **Refuse rather than guess.** A file that will not parse as a JSON object
///    is left completely alone and the error is surfaced.
/// 3. **Atoll's entries are identified by the shim path inside `command`.** No
///    marker key is invented, because an unknown key may fail the other tool's
///    schema validation. Removal filters on exactly that, so uninstall is
///    surgical and install is remove-then-add — idempotent by construction.
/// 4. **Never merge into a group the user created.** Atoll always appends its own
///    matcher group, so removing it cannot disturb a sibling.
/// 5. **Back up before every write**, keeping the most recent few.
/// 6. **Only configure agents that are actually installed**, so Atoll does not
///    litter config files for tools the user does not have.
///
/// Only `type`, `command` and `timeout` are emitted. `args` and `statusMessage`
/// are documented for Claude Code but absent from every real-world config
/// inspected, so they are avoided — the event name and agent are passed as
/// arguments inside the `command` string instead.
///
/// `merging` and `removingAtollEntries` are pure dictionary transforms so they
/// can be unit-tested against real config fixtures without touching a file.
enum AgentHookInstaller {
    enum InstallError: LocalizedError {
        case unreadableConfig(URL)
        case agentNotInstalled(AgentKind)
        case shimNotWritable(String)
        case verificationFailed(URL)

        var errorDescription: String? {
            switch self {
            case .unreadableConfig(let url):
                return String(
                    format: String(localized: "%@ is not valid JSON, so Atoll left it alone. Fix or move the file, then try again."),
                    url.path
                )
            case .agentNotInstalled(let kind):
                return String(
                    format: String(localized: "%@ does not appear to be installed."),
                    kind.displayName
                )
            case .shimNotWritable(let reason):
                return reason
            case .verificationFailed(let url):
                return String(
                    format: String(localized: "Atoll could not verify its changes to %@ and restored the backup."),
                    url.path
                )
            }
        }
    }

    /// Seconds the agent should wait for a decision, plus the margin the shim
    /// needs to clean up. The shim's own polling deadline is shorter, so the
    /// normal outcome is always a clean exit rather than the agent timing out.
    static let decisionTimeout = 300
    static var configuredTimeout: Int { decisionTimeout + 15 }
    /// Observe-only hooks return instantly; a small timeout keeps a pathological
    /// filesystem stall from ever slowing an agent down.
    static let observeTimeout = 5

    // MARK: - Descriptors

    /// Lifecycle events, all observe-only.
    ///
    /// This list is deliberately restricted to events verified as accepted by a
    /// real Claude Code config. `SubagentStart` / `SubagentStop` are documented
    /// but were absent from every config inspected, and an unknown key under
    /// `hooks` risks failing the agent's own settings validation — which would
    /// break the user's agent, not just Atoll's feature. Subagent progress
    /// therefore waits until the events are confirmed to fire.
    private static func monitoringEvents(includeNotification: Bool) -> [AgentHookEventSpec] {
        var events: [AgentHookEventSpec] = [
            AgentHookEventSpec(wireName: "SessionStart", usesMatcher: false, expectsDecision: false),
            AgentHookEventSpec(wireName: "SessionEnd", usesMatcher: false, expectsDecision: false),
            AgentHookEventSpec(wireName: "Stop", usesMatcher: false, expectsDecision: false),
            AgentHookEventSpec(wireName: "UserPromptSubmit", usesMatcher: false, expectsDecision: false)
        ]
        if includeNotification {
            events.insert(
                AgentHookEventSpec(wireName: "Notification", usesMatcher: false, expectsDecision: false),
                at: 3
            )
        }
        return events
    }

    /// Cursor uses its own vocabulary — `beforeShellExecution` rather than
    /// `PreToolUse` — and answers with a `permission` key instead of
    /// `hookSpecificOutput`. Unverified against a real install.
    private static let cursorMonitoringEvents: [AgentHookEventSpec] = [
        AgentHookEventSpec(wireName: "beforeSubmitPrompt", usesMatcher: false, expectsDecision: false),
        AgentHookEventSpec(wireName: "stop", usesMatcher: false, expectsDecision: false)
    ]

    /// Returns the install plan for an agent, or `nil` when Atoll cannot
    /// configure it.
    ///
    /// - Parameter includeApprovals: adds the blocking permission events. Stays
    ///   `false` until the approval flow exists, so monitoring can ship without
    ///   Atoll ever being able to answer a permission prompt.
    static func descriptor(for kind: AgentKind, includeApprovals: Bool) -> AgentHookConfigDescriptor? {
        guard kind.supportsHookInstallation else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser

        switch kind {
        case .claudeCode:
            var events = monitoringEvents(includeNotification: true)
            if includeApprovals {
                events.append(AgentHookEventSpec(wireName: "PreToolUse", usesMatcher: true, expectsDecision: true))
            }
            return AgentHookConfigDescriptor(
                kind: kind,
                configURL: home.appendingPathComponent(".claude/settings.json"),
                events: events,
                verification: .verified
            )

        case .codex:
            // `~/.codex/hooks.json` uses the same
            // `hooks.<Event>[].{matcher, hooks[]}` shape as Claude Code — but a
            // real one carries no `Notification` event, so Atoll does not
            // register one either rather than introduce a key the agent may
            // reject. Whether Codex acts on a decision reply is unobserved.
            var events = monitoringEvents(includeNotification: false)
            if includeApprovals {
                events.append(AgentHookEventSpec(wireName: "PreToolUse", usesMatcher: true, expectsDecision: true))
            }
            return AgentHookConfigDescriptor(
                kind: kind,
                configURL: home.appendingPathComponent(".codex/hooks.json"),
                events: events,
                verification: .schemaOnly
            )

        case .cursor:
            var events = cursorMonitoringEvents
            if includeApprovals {
                events.append(AgentHookEventSpec(wireName: "beforeShellExecution", usesMatcher: false, expectsDecision: true))
            }
            return AgentHookConfigDescriptor(
                kind: kind,
                configURL: home.appendingPathComponent(".cursor/hooks.json"),
                events: events,
                verification: .unverified
            )

        case .geminiCLI, .qwenCode:
            // Qwen Code is a Gemini CLI fork and shares the settings schema.
            let folder = kind == .geminiCLI ? ".gemini" : ".qwen"
            var events = monitoringEvents(includeNotification: true)
            if includeApprovals {
                events.append(AgentHookEventSpec(wireName: "PreToolUse", usesMatcher: true, expectsDecision: true))
            }
            return AgentHookConfigDescriptor(
                kind: kind,
                configURL: home.appendingPathComponent("\(folder)/settings.json"),
                events: events,
                verification: .unverified
            )

        case .opencode:
            return nil
        }
    }

    /// Whether the agent looks installed, judged by its config directory
    /// existing. Atoll will not create a config tree for a tool the user does
    /// not have.
    static func isAgentPresent(_ descriptor: AgentHookConfigDescriptor) -> Bool {
        FileManager.default.fileExists(atPath: descriptor.configURL.deletingLastPathComponent().path)
    }

    // MARK: - Shim

    /// Writes the hook shim, embedding the spool paths and the timeout.
    ///
    /// The shim's contract is the entire safety story:
    ///
    /// - It checks the heartbeat **before doing any work**. If Atoll is gone or
    ///   wedged, the hook is a sub-millisecond no-op instead of a stall.
    /// - Every failure path prints nothing and exits 0, which every supported
    ///   agent reads as "no decision" — so the agent's own permission prompt
    ///   still appears.
    /// - It never exits non-zero. Exit 2 would *block* the tool call, turning an
    ///   Atoll bug into a broken agent.
    ///
    /// Written as POSIX `sh` so it does not depend on bash, and placed in a
    /// space-free path so the `command` string needs no quoting.
    ///
    /// Creates the spool itself rather than assuming a caller did: on a fresh
    /// install this runs before anything else has touched `~/.atoll`, and the
    /// shim cannot exist without the directories it reads and writes.
    static func writeShim() throws {
        guard AgentTowerStorage.prepareSpool() else {
            throw InstallError.shimNotWritable(
                String(localized: "Atoll could not prepare its hook folder. Check that ~/.atoll is owned by you and not shared.")
            )
        }

        let spool = AgentTowerStorage.spoolDirectory.path
        let script = """
        #!/bin/sh
        # Generated by Atoll (Agent Tower). Do not edit — Atoll rewrites this file.
        #
        # usage: atoll-hook.sh <EventName> <agentKind> <wait|nowait>
        #
        # Hands this hook's stdin to Atoll through a spool directory and, when
        # asked to wait, echoes Atoll's decision as the hook's stdout.
        #
        # Every failure path prints nothing and exits 0, which means "no decision":
        # your agent's own prompt still appears. Atoll being closed, busy or broken
        # can never block or hang a session.
        #
        # To disable without touching any config: export ATOLL_HOOKS_DISABLED=1

        set -u

        BASE='\(spool)'
        ALIVE="$BASE/alive"
        EVENT="${1:-}"
        AGENT="${2:-}"
        MODE="${3:-nowait}"
        TIMEOUT=\(decisionTimeout)
        STALE=\(AgentTowerStorage.heartbeatStaleAfter)

        # --- Kill switches, cheapest first -----------------------------------
        [ -n "${ATOLL_HOOKS_DISABLED:-}" ] && exit 0
        [ -n "${ATOLL_HOOK_DEPTH:-}" ] && exit 0
        [ -n "$EVENT" ] || exit 0
        [ -d "$BASE/in" ] || exit 0

        # Atoll touches `alive` every few seconds. A missing or stale heartbeat
        # means Atoll is not answering, so stop here rather than wait.
        beat=$(stat -f %m "$ALIVE" 2>/dev/null) || exit 0
        now=$(date +%s)
        [ $((now - beat)) -le $STALE ] || exit 0

        # Read one byte past the cap so an oversized payload can be detected
        # rather than truncated: a cut-off body is invalid JSON, and writing it
        # would only give Atoll something to reject.
        payload=$(head -c 1048577)
        [ -n "$payload" ] || exit 0
        size=$(printf '%s' "$payload" | wc -c | tr -d ' ')
        [ "$size" -le 1048576 ] || exit 0

        rand=$(od -An -N8 -tx1 /dev/urandom 2>/dev/null | tr -d ' \\n')
        [ -n "$rand" ] || rand=$$
        REQ="${now}-$$-${rand}"
        IN="$BASE/in/$REQ.json"
        OUT="$BASE/out/$REQ"

        trap 'rm -f "$IN.tmp" "$IN"; exit 0' INT TERM HUP

        if [ "$MODE" = "wait" ]; then WAIT=true; else WAIT=false; fi

        # The payload is already JSON, so it is embedded as a value verbatim —
        # no escaping, no reformatting, nothing to get wrong. The terminal hints
        # come from the environment, though, so anything that could break out of
        # a JSON string is stripped before they are embedded.
        sanitize() { printf '%s' "$1" | tr -d '"\\\\[:cntrl:]' | cut -c1-128; }
        TERM_HINT=$(sanitize "${TERM_PROGRAM:-}")
        TERM_BID=$(sanitize "${__CFBundleIdentifier:-}")

        {
          printf '{"v":%s,"id":"%s","event":"%s","agent":"%s","wait":%s,"pid":%s,"term":"%s","termbid":"%s","payload":' \\
            '\(AgentHookSpool.protocolVersion)' "$REQ" "$EVENT" "$AGENT" "$WAIT" "$PPID" \\
            "$TERM_HINT" "$TERM_BID"
          printf '%s' "$payload"
          printf '}'
        } > "$IN.tmp" 2>/dev/null || { rm -f "$IN.tmp"; exit 0; }

        chmod 600 "$IN.tmp" 2>/dev/null
        mv -f "$IN.tmp" "$IN" 2>/dev/null || { rm -f "$IN.tmp"; exit 0; }

        # Observe-only hooks are done: one file write, no round trip.
        [ "$WAIT" = true ] || exit 0

        # Poll for the sentinel, which is only created after the body is complete.
        i=0
        limit=$((TIMEOUT * 10))
        while [ $i -lt $limit ]; do
          if [ -f "$OUT.done" ]; then
            cat "$OUT.json" 2>/dev/null
            rm -f "$OUT.json" "$OUT.done" "$IN"
            exit 0
          fi
          i=$((i + 1))
          # Re-check the heartbeat every 5s so a crash mid-wait releases us.
          if [ $((i % 50)) -eq 0 ]; then
            beat=$(stat -f %m "$ALIVE" 2>/dev/null) || break
            now=$(date +%s)
            [ $((now - beat)) -le $STALE ] || break
          fi
          sleep 0.1
        done

        rm -f "$IN"
        exit 0

        """

        let url = AgentTowerStorage.shimURL
        do {
            try Data(script.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            throw InstallError.shimNotWritable(error.localizedDescription)
        }
    }

    static func removeShim() {
        try? FileManager.default.removeItem(at: AgentTowerStorage.shimURL)
    }

    /// The `command` string written into an agent's config for one event.
    static func commandLine(for event: AgentHookEventSpec, kind: AgentKind) -> String {
        let mode = event.expectsDecision ? "wait" : "nowait"
        return "\(AgentTowerStorage.shimURL.path) \(event.wireName) \(kind.rawValue) \(mode)"
    }

    // MARK: - Install / uninstall

    /// Removes any previous Atoll entries and adds the current ones.
    ///
    /// After writing, the file is re-read and the non-Atoll part of `hooks` is
    /// compared against what was there before. A mismatch restores the backup —
    /// Atoll would rather do nothing than corrupt the user's agent config.
    static func install(descriptor: AgentHookConfigDescriptor, now: Date = Date()) throws {
        guard isAgentPresent(descriptor) else {
            throw InstallError.agentNotInstalled(descriptor.kind)
        }

        let shimPath = AgentTowerStorage.shimURL.path
        let original = try readConfig(at: descriptor.configURL)
        let foreignBefore = foreignHooksFingerprint(of: original, shimPath: shimPath)

        let backup = backUp(descriptor.configURL, now: now)

        var updated = removingAtollEntries(from: original, shimPath: shimPath)
        updated = merging(descriptor: descriptor, into: updated, shimPath: shimPath)
        try writeConfig(updated, to: descriptor.configURL)

        let reread = try? readConfig(at: descriptor.configURL)
        let foreignAfter = reread.map { foreignHooksFingerprint(of: $0, shimPath: shimPath) }
        guard let foreignAfter, foreignAfter == foreignBefore else {
            if let backup {
                // Restore via an atomic replacement rather than deleting first —
                // a failed copyItem must not leave the user with no config at all.
                if let restored = try? Data(contentsOf: backup) {
                    try? restored.write(to: descriptor.configURL, options: .atomic)
                }
            }
            throw InstallError.verificationFailed(descriptor.configURL)
        }

        Logger.log("Agent Tower: installed hooks for \(descriptor.kind.displayName)", category: .agents)
    }

    /// Strips every Atoll entry, leaving the user's own hooks and settings intact.
    static func uninstall(descriptor: AgentHookConfigDescriptor) throws {
        guard FileManager.default.fileExists(atPath: descriptor.configURL.path) else { return }

        let shimPath = AgentTowerStorage.shimURL.path
        let original = try readConfig(at: descriptor.configURL)
        let cleaned = removingAtollEntries(from: original, shimPath: shimPath)

        // Do not rewrite a file we did not change: that would bump its mtime and
        // reformat it for no reason.
        guard !NSDictionary(dictionary: cleaned).isEqual(to: original) else { return }

        try writeConfig(cleaned, to: descriptor.configURL)
        Logger.log("Agent Tower: removed hooks for \(descriptor.kind.displayName)", category: .agents)
    }

    /// Whether this agent's config currently points at Atoll's shim.
    static func isInstalled(descriptor: AgentHookConfigDescriptor) -> Bool {
        guard let root = try? readConfig(at: descriptor.configURL) else { return false }
        return containsAtollEntry(root, shimPath: AgentTowerStorage.shimURL.path)
    }

    // MARK: - Pure JSON transforms (unit-tested seam)

    /// Appends Atoll's hook entry for every event in the descriptor.
    ///
    /// Assumes `removingAtollEntries` already ran, so it never has to reason
    /// about duplicates. Always appends its own group rather than joining one the
    /// user wrote, so removal cannot disturb a sibling entry.
    static func merging(
        descriptor: AgentHookConfigDescriptor,
        into root: [String: Any],
        shimPath: String
    ) -> [String: Any] {
        var result = root
        var hooks = (result["hooks"] as? [String: Any]) ?? [:]

        for event in descriptor.events {
            let mode = event.expectsDecision ? "wait" : "nowait"
            let entry: [String: Any] = [
                "type": "command",
                "command": "\(shimPath) \(event.wireName) \(descriptor.kind.rawValue) \(mode)",
                "timeout": event.expectsDecision ? configuredTimeout : observeTimeout
            ]

            var group: [String: Any] = ["hooks": [entry]]
            if event.usesMatcher {
                group["matcher"] = "*"
            }

            var groups = (hooks[event.wireName] as? [[String: Any]]) ?? []
            groups.append(group)
            hooks[event.wireName] = groups
        }

        result["hooks"] = hooks
        return result
    }

    /// Drops every hook entry whose `command` references Atoll's shim, then
    /// prunes the containers left empty.
    ///
    /// Pruning matters: an event key holding an empty array, or a matcher group
    /// with no hooks, is dead weight that would accumulate on every toggle. A
    /// group is removed only once *all* its entries are Atoll's, so a group the
    /// user also put their own hook into survives with that hook intact.
    static func removingAtollEntries(from root: [String: Any], shimPath: String) -> [String: Any] {
        guard let hooks = root["hooks"] as? [String: Any] else { return root }

        var result = root
        var cleanedHooks: [String: Any] = [:]

        for (eventName, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                // Preserve shapes Atoll does not understand rather than dropping them.
                cleanedHooks[eventName] = value
                continue
            }

            var cleanedGroups: [[String: Any]] = []
            for group in groups {
                guard let entries = group["hooks"] as? [[String: Any]] else {
                    cleanedGroups.append(group)
                    continue
                }
                let remaining = entries.filter { !isAtollEntry($0, shimPath: shimPath) }
                if remaining.isEmpty { continue }

                var cleanedGroup = group
                cleanedGroup["hooks"] = remaining
                cleanedGroups.append(cleanedGroup)
            }

            if !cleanedGroups.isEmpty {
                cleanedHooks[eventName] = cleanedGroups
            }
        }

        if cleanedHooks.isEmpty {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = cleanedHooks
        }
        return result
    }

    /// An entry is Atoll's when its command starts with the shim path.
    ///
    /// Prefix rather than equality, because the command carries the event name and
    /// agent as arguments.
    static func isAtollEntry(_ entry: [String: Any], shimPath: String) -> Bool {
        guard let command = entry["command"] as? String else { return false }
        return command == shimPath || command.hasPrefix(shimPath + " ")
    }

    static func containsAtollEntry(_ root: [String: Any], shimPath: String) -> Bool {
        guard let hooks = root["hooks"] as? [String: Any] else { return false }
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                guard let entries = group["hooks"] as? [[String: Any]] else { continue }
                if entries.contains(where: { isAtollEntry($0, shimPath: shimPath) }) {
                    return true
                }
            }
        }
        return false
    }

    /// A stable description of everything under `hooks` that is *not* Atoll's,
    /// used to prove an install did not disturb the user's own entries.
    static func foreignHooksFingerprint(of root: [String: Any], shimPath: String) -> String {
        let foreign = removingAtollEntries(from: root, shimPath: shimPath)
        guard let hooks = foreign["hooks"] else { return "" }
        guard let data = try? JSONSerialization.data(
            withJSONObject: hooks,
            options: [.sortedKeys]
        ) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - File I/O

    /// Reads a config, treating "missing" as "empty" but "unparseable" as fatal.
    static func readConfig(at url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else {
            throw InstallError.unreadableConfig(url)
        }
        return root
    }

    private static func writeConfig(_ root: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )

        let fm = FileManager.default
        let existingPermissions = (try? fm.attributesOfItem(atPath: url.path)[.posixPermissions]) as? NSNumber

        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)

        // An atomic write replaces the inode, so the original mode has to be
        // reapplied or a 0600 config silently becomes world-readable. A brand
        // new config has no prior mode to preserve, so it defaults private
        // rather than whatever the write left behind after umask.
        try? fm.setAttributes([.posixPermissions: existingPermissions ?? 0o600], ofItemAtPath: url.path)
    }

    /// Copies the config aside before a write and prunes old copies.
    private static let maxBackups = 5

    @discardableResult
    private static func backUp(_ url: URL, now: Date) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }

        let destination = AgentTowerStorage.backupURL(for: url, at: now)
        try? fm.removeItem(at: destination)
        try? fm.copyItem(at: url, to: destination)

        let directory = AgentTowerStorage.backupsDirectory
        let prefix = AgentTowerStorage.backupLabel(for: url) + "."
        let existing = ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix(prefix) }
            .sorted()
        if existing.count > maxBackups {
            for stale in existing.dropLast(maxBackups) {
                try? fm.removeItem(at: directory.appendingPathComponent(stale))
            }
        }

        return fm.fileExists(atPath: destination.path) ? destination : nil
    }
}
