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

/// On-disk locations Agent Tower owns.
///
/// Split deliberately in two:
///
/// - **The spool** lives at `~/.atoll/agent-hooks/`. It is shell-facing — a
///   `/bin/sh` shim reads and writes it on every hook — so the path contains no
///   spaces and needs no quoting wherever an agent's config embeds it.
/// - **App state** lives under `Application Support/DynamicIsland/AgentTower/`,
///   the repo convention (see `ShelfPersistenceService` and
///   `AppIcon.iconDirectory`). Nothing outside Atoll reads it.
enum AgentTowerStorage {
    // MARK: - Spool (shell-facing)

    /// Redirects the spool somewhere else. Only set by tests, so a test run never
    /// writes into the real home directory.
    static var spoolRootOverride: URL?

    /// `~/.atoll/agent-hooks/`, created `0700`.
    ///
    /// Mode `0700` is the actual access boundary for everything in here.
    static var spoolDirectory: URL {
        let root = spoolRootOverride ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".atoll", isDirectory: true)
        return root.appendingPathComponent("agent-hooks", isDirectory: true)
    }

    /// Requests the shim has dropped and Atoll has not consumed.
    static var inboxDirectory: URL {
        spoolDirectory.appendingPathComponent("in", isDirectory: true)
    }

    /// Decisions Atoll has written for a blocked shim to collect.
    static var outboxDirectory: URL {
        spoolDirectory.appendingPathComponent("out", isDirectory: true)
    }

    /// The hook shim every supported agent is pointed at.
    static var shimURL: URL {
        spoolDirectory.appendingPathComponent("atoll-hook.sh")
    }

    /// Liveness heartbeat. Atoll touches this every few seconds; the shim refuses
    /// to wait on a stale one.
    ///
    /// This is the mechanism that makes the whole feature safe to ship: if Atoll
    /// crashes, is killed, or wedges, every hook becomes a sub-millisecond no-op
    /// instead of stalling its agent for the full approval timeout.
    static var heartbeatURL: URL {
        spoolDirectory.appendingPathComponent("alive")
    }

    /// How stale the heartbeat may be before the shim gives up, in seconds.
    /// Must stay comfortably above ``heartbeatInterval``.
    static let heartbeatStaleAfter = 15
    static let heartbeatInterval: TimeInterval = 5

    // MARK: - App state

    /// `~/Library/Application Support/DynamicIsland/AgentTower/`
    static let stateDirectory: URL = {
        let fm = FileManager.default
        let support = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = (support ?? fm.temporaryDirectory)
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("AgentTower", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }()

    /// Sessions restored after an Atoll restart.
    static var sessionsURL: URL {
        stateDirectory.appendingPathComponent("sessions.json")
    }

    /// Persisted approval rules (later phase).
    static var rulesURL: URL {
        stateDirectory.appendingPathComponent("rules.json")
    }

    /// Copies of agent config files taken before Atoll first edited them.
    static var backupsDirectory: URL {
        let dir = stateDirectory.appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The agent name is folded in because several agents use the same
    /// `hooks.json` / `settings.json` filename. Agent config directories are
    /// hidden (`.claude`, `.codex`, …), so this may start with a dot — callers
    /// pruning backups by this label must not split on "." to recover it.
    static func backupLabel(for configURL: URL) -> String {
        configURL.deletingLastPathComponent().lastPathComponent
            + "-" + configURL.lastPathComponent
    }

    static func backupURL(for configURL: URL, at date: Date) -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let stamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        return backupsDirectory.appendingPathComponent("\(backupLabel(for: configURL)).\(stamp).bak")
    }

    // MARK: - Preparation

    /// Creates the spool with the right modes and verifies it is ours.
    ///
    /// Returns `false` when the directory exists but is owned by someone else or
    /// is group/world-accessible. Callers must then refuse to arm the feature
    /// rather than run with a spool a third party can read or write — the spool
    /// carries command text and decides tool permissions.
    static func prepareSpool() -> Bool {
        let fm = FileManager.default
        for directory in [spoolDirectory, inboxDirectory, outboxDirectory] {
            do {
                try fm.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                Logger.log("Agent Tower: could not create \(directory.path): \(error.localizedDescription)", category: .agents)
                return false
            }
            guard isPrivatelyOwned(directory) else {
                Logger.log("Agent Tower: refusing to use \(directory.path) — wrong owner or permissions", category: .agents)
                return false
            }
        }
        return true
    }

    /// True when the item is owned by this user and not readable or writable by
    /// group or other.
    static func isPrivatelyOwned(_ url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return false
        }
        let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
        let mode = (attributes[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o777
        return owner == getuid() && (mode & 0o077) == 0
    }
}
