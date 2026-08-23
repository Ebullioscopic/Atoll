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

/// How much damage a shell command could do.
enum DestructiveRisk: Int, Codable, Comparable, Sendable {
    case none = 0
    /// Worth mentioning, not worth a warning colour.
    case low = 1
    /// Loses work that is recoverable with effort.
    case medium = 2
    /// Loses data, escalates privilege, or is visible outside this machine.
    case high = 3

    static func < (lhs: DestructiveRisk, rhs: DestructiveRisk) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// One reason a command was flagged.
struct CommandRiskFlag: Identifiable, Equatable, Codable, Sendable {
    /// Stable across evaluations of the same command, so the UI can animate.
    let id: String
    let risk: DestructiveRisk
    /// User-facing, already localized.
    let summary: String
}

/// Flags shell commands that could destroy something before they are approved.
///
/// ## The design constraint that shapes everything here
/// **A false positive is more expensive than a false negative.** A classifier
/// that warns about `echo "rm -rf /"` teaches the user to click through warnings,
/// which removes the value of the warnings that matter. So every rule is written
/// against ``ShellCommandLexer``'s parsed commands — never against raw text — and
/// constructs that are merely *common* are not flagged at all. Notably `$(…)`
/// substitution is ignored: `$(git rev-parse HEAD)` appears in ordinary commands
/// constantly, so flagging it would be pure noise.
///
/// This is advisory. It informs the approval card; it never decides. Pure and
/// total, and the most heavily table-tested piece of the feature.
enum DestructiveCommandClassifier {
    /// Paths where recursive deletion is categorically not a build-directory
    /// cleanup.
    private static let protectedRoots: Set<String> = [
        "/", "/*", "~", "~/", "~/*", "$HOME", "${HOME}", "$HOME/*",
        "/Users", "/Users/", "/Applications", "/System", "/Library",
        "/etc", "/var", "/usr", "/bin", "/sbin", "/opt", "/private", "/Volumes"
    ]

    /// Interpreters that turn piped text into execution.
    private static let shells: Set<String> = [
        "sh", "bash", "zsh", "fish", "dash", "ksh", "csh", "tcsh",
        "python", "python3", "perl", "ruby", "node", "osascript"
    ]

    /// Programs that fetch from the network.
    private static let fetchers: Set<String> = ["curl", "wget", "fetch", "httpie", "http"]

    static func evaluate(command: String, cwd: String? = nil) -> [CommandRiskFlag] {
        var flags: [CommandRiskFlag] = []
        func add(_ id: String, _ risk: DestructiveRisk, _ summary: String) {
            guard !flags.contains(where: { $0.id == id }) else { return }
            flags.append(CommandRiskFlag(id: id, risk: risk, summary: summary))
        }

        // The fork bomb is a syntax construct rather than a command, so it is the
        // one signature matched against text. Whitespace is normalised first.
        let dense = command.filter { !$0.isWhitespace }
        if dense.contains(":(){:|:&};:") || dense.contains(":(){:|:&};") {
            add("fork-bomb", .high, String(localized: "Fork bomb: spawns processes until the machine stops responding"))
        }

        let lexed = ShellCommandLexer.lex(command)

        if lexed.obfuscation.hasEval {
            add("eval", .medium, String(localized: "Runs `eval`, so what executes is not visible here"))
        }
        if lexed.obfuscation.hasEncodedPayload {
            add("encoded", .medium, String(localized: "Decodes an encoded payload before running it"))
        }

        // Code the user cannot read, piped straight into an interpreter.
        //
        // Only flagged when the payload's origin is opaque — fetched from the
        // network, or decoded from a blob. `cat script.sh | sh` is left alone:
        // the script is on disk and readable, and the command text itself is
        // shown on the approval card anyway. The concern is *hidden* execution,
        // not execution.
        let programs = lexed.commands.compactMap(\.program)
        let pipedIntoShell = lexed.commands.contains { $0.isPipeTarget && shells.contains($0.program ?? "") }
        if pipedIntoShell {
            if programs.contains(where: fetchers.contains) {
                add("curl-pipe-shell", .high, String(localized: "Downloads a script and runs it immediately"))
            } else if lexed.obfuscation.hasEncodedPayload {
                add("decoded-pipe-shell", .high, String(localized: "Decodes hidden text and runs it as a script"))
            }
        }

        for shellCommand in lexed.commands {
            guard let program = shellCommand.program else { continue }
            let arguments = shellCommand.arguments

            switch program {
            case "sudo", "doas":
                add("sudo", .high, String(localized: "Runs as root"))

            case "rm":
                classifyRemove(arguments, cwd: cwd, add: add)

            case "dd":
                if arguments.contains(where: { $0.hasPrefix("of=/dev/") }) {
                    add("dd-device", .high, String(localized: "Writes directly to a disk device"))
                } else if arguments.contains(where: { $0.hasPrefix("of=") }) {
                    add("dd", .medium, String(localized: "Overwrites a file with raw data"))
                }

            case "shred", "srm":
                add("shred", .high, String(localized: "Irrecoverably overwrites files"))

            case "diskutil":
                let verbs: Set<String> = ["erasedisk", "erasevolume", "partitiondisk", "reformat", "zerodisk", "securityerase"]
                if arguments.contains(where: { verbs.contains($0.lowercased()) }) {
                    add("diskutil", .high, String(localized: "Erases or repartitions a disk"))
                }

            case "chmod":
                classifyChmod(arguments, add: add)

            case "chown", "chgrp":
                if hasRecursiveFlag(arguments) {
                    let risk: DestructiveRisk = arguments.contains(where: { protectedRoots.contains($0) }) ? .high : .medium
                    add("chown-recursive", risk, String(localized: "Changes ownership of a whole directory tree"))
                }

            case "git":
                classifyGit(arguments, add: add)

            case "killall", "pkill":
                add("killall", .medium, String(localized: "Force-quits processes by name"))

            case "launchctl":
                let verbs: Set<String> = ["unload", "bootout", "remove", "disable"]
                if arguments.contains(where: { verbs.contains($0.lowercased()) }) {
                    add("launchctl", .medium, String(localized: "Disables a system or login service"))
                }

            case "defaults":
                if arguments.first?.lowercased() == "delete" {
                    add("defaults-delete", .medium, String(localized: "Deletes an app's saved preferences"))
                }

            case "security":
                if arguments.contains(where: { $0.hasPrefix("delete-") }) {
                    add("security-delete", .high, String(localized: "Deletes Keychain items"))
                }

            case "tccutil":
                if arguments.first?.lowercased() == "reset" {
                    add("tccutil", .high, String(localized: "Resets privacy permissions for apps"))
                }

            case "npm", "pnpm", "yarn", "bun":
                if arguments.contains("publish") {
                    add("publish", .high, String(localized: "Publishes a package publicly"))
                }
                if arguments.contains("unpublish") {
                    add("unpublish", .high, String(localized: "Removes a published package"))
                }

            case "gh":
                if arguments.contains("delete") {
                    add("gh-delete", .high, String(localized: "Deletes something on GitHub"))
                }

            case "aws":
                let joined = arguments.joined(separator: " ")
                if joined.contains("s3 rb") || (joined.contains("s3 rm") && arguments.contains("--recursive")) {
                    add("aws-s3-rm", .high, String(localized: "Deletes cloud storage contents"))
                }

            case "terraform":
                if arguments.contains("destroy") {
                    let risk: DestructiveRisk = arguments.contains("-auto-approve") ? .high : .medium
                    add("terraform-destroy", risk, String(localized: "Destroys provisioned infrastructure"))
                }

            case "kubectl":
                if arguments.first?.lowercased() == "delete" {
                    let broad = arguments.contains("--all") || arguments.contains("namespace") || arguments.contains("ns")
                    add("kubectl-delete", broad ? .high : .medium, String(localized: "Deletes cluster resources"))
                }

            case "find":
                classifyFind(arguments, add: add)

            case "truncate":
                if arguments.contains(where: { $0 == "-s" }) || arguments.contains(where: { $0.hasPrefix("--size") }) {
                    add("truncate", .medium, String(localized: "Empties a file in place"))
                }

            case "mv":
                // Moving onto a protected root replaces it.
                if let destination = arguments.last, protectedRoots.contains(destination) {
                    add("mv-root", .high, String(localized: "Moves something over a system directory"))
                }

            default:
                if program.hasPrefix("mkfs") || program.hasPrefix("newfs") {
                    add("mkfs", .high, String(localized: "Formats a filesystem"))
                }
            }
        }

        return flags.sorted { $0.risk > $1.risk }
    }

    static func highestRisk(in flags: [CommandRiskFlag]) -> DestructiveRisk {
        flags.map(\.risk).max() ?? .none
    }

    // MARK: - Per-program rules

    private static func classifyRemove(
        _ arguments: [String],
        cwd: String?,
        add: (String, DestructiveRisk, String) -> Void
    ) {
        let recursive = hasRecursiveFlag(arguments)
        let forced = hasFlag(arguments, short: "f", long: "force")
        let targets = arguments.filter { !$0.hasPrefix("-") }

        let hitsProtectedRoot = targets.contains { protectedRoots.contains($0) || isProtectedRootPath($0) }
        if hitsProtectedRoot {
            add("rm-root", .high, String(localized: "Recursively deletes a system or home directory"))
            return
        }

        // An unbounded target — `*`, `.`, `./*` — deletes the entire current
        // directory, and a preceding `cd` means that directory is not necessarily
        // the project. Since the classifier cannot know where the shell ended up,
        // this is treated as the worst case rather than the best one.
        if recursive, targets.contains(where: isUnboundedTarget) {
            add("rm-wildcard", .high, String(localized: "Recursively deletes everything in the current directory"))
            return
        }

        let leavesWorkspace = targets.contains { escapesWorkspace($0, cwd: cwd) }

        if recursive, leavesWorkspace {
            add("rm-outside", .high, String(localized: "Recursively deletes a path outside the project folder"))
        } else if recursive {
            add("rm-recursive", .medium, String(localized: "Recursively deletes a directory"))
        } else if forced, leavesWorkspace {
            add("rm-force-outside", .medium, String(localized: "Force-deletes files outside the project folder"))
        }
    }

    private static func classifyChmod(_ arguments: [String], add: (String, DestructiveRisk, String) -> Void) {
        // The mode is the first non-flag operand; everything after it is a
        // target path and must not be misread as a mode string.
        let worldWritable: Bool
        if let mode = arguments.first(where: { !$0.hasPrefix("-") }) {
            if mode.allSatisfy(\.isNumber), mode.count >= 3 {
                // Last digit is "other"; 2, 3, 6, 7 all include write.
                worldWritable = mode.last.flatMap { Int(String($0)) }.map { $0 & 2 != 0 } ?? false
            } else {
                let lowered = mode.lowercased()
                worldWritable = lowered.contains("o+w") || lowered.contains("a+w") || lowered.contains("ugo+w")
            }
        } else {
            worldWritable = false
        }
        if worldWritable {
            add("chmod-world-writable", .high, String(localized: "Makes files writable by every user on the Mac"))
        } else if hasRecursiveFlag(arguments) {
            add("chmod-recursive", .medium, String(localized: "Changes permissions across a whole directory tree"))
        }
    }

    private static func classifyGit(_ arguments: [String], add: (String, DestructiveRisk, String) -> Void) {
        guard let subcommand = arguments.first?.lowercased() else { return }
        switch subcommand {
        case "push":
            if arguments.contains("--force-with-lease") || arguments.contains("--force-if-includes") {
                add("git-push-lease", .medium, String(localized: "Rewrites a remote branch, but refuses if someone else pushed"))
            } else if hasFlag(arguments, short: "f", long: "force")
                || arguments.contains(where: { $0.hasPrefix("+") && $0.contains(":") }) {
                add("git-push-force", .high, String(localized: "Force-pushes, overwriting history other people may have"))
            }
            if arguments.contains("--delete") || arguments.contains("-d") {
                add("git-push-delete", .medium, String(localized: "Deletes a remote branch"))
            }
        case "reset":
            if arguments.contains("--hard") {
                add("git-reset-hard", .medium, String(localized: "Discards all uncommitted changes"))
            }
        case "clean":
            // Only flag arguments carry the "f"/"d"/"x" letters; a path like
            // "drafts/" must not be scanned for them.
            let joined = arguments.filter { $0.hasPrefix("-") }.joined()
            if joined.contains("f"), joined.contains("d") || joined.contains("x") {
                add("git-clean", .medium, String(localized: "Deletes untracked files, including ignored ones"))
            }
        case "checkout", "restore":
            if arguments.contains(".") || arguments.contains("--") {
                add("git-discard", .low, String(localized: "Discards changes in tracked files"))
            }
        case "filter-branch", "filter-repo":
            add("git-filter", .high, String(localized: "Rewrites the entire repository history"))
        case "branch":
            if arguments.contains("-D") {
                add("git-branch-delete", .low, String(localized: "Deletes a branch without merge checks"))
            }
        default:
            break
        }
    }

    private static func classifyFind(_ arguments: [String], add: (String, DestructiveRisk, String) -> Void) {
        let deletes = arguments.contains("-delete")
            || (arguments.contains("-exec") && arguments.contains(where: { $0 == "rm" }))
            || (arguments.contains("-execdir") && arguments.contains(where: { $0 == "rm" }))
        guard deletes else { return }

        // The search root is the first non-flag argument.
        let root = arguments.first { !$0.hasPrefix("-") } ?? "."
        if protectedRoots.contains(root) || isProtectedRootPath(root) {
            add("find-delete-root", .high, String(localized: "Deletes matching files across the whole system"))
        } else {
            add("find-delete", .medium, String(localized: "Deletes every file matching a pattern"))
        }
    }

    // MARK: - Helpers

    /// `-r`, `-R`, `--recursive`, and bundled forms like `-rf`.
    static func hasRecursiveFlag(_ arguments: [String]) -> Bool {
        hasFlag(arguments, short: "r", long: "recursive")
            || hasFlag(arguments, short: "R", long: "recursive")
    }

    /// Matches a short flag whether it is alone or bundled (`-rf`, `-fr`), and its
    /// long form. Case-sensitive for the short flag, because `-r` and `-R` differ.
    static func hasFlag(_ arguments: [String], short: Character, long: String) -> Bool {
        for argument in arguments {
            if argument == "--\(long)" { return true }
            guard argument.hasPrefix("-"), !argument.hasPrefix("--"), argument.count > 1 else { continue }
            if argument.dropFirst().contains(short) { return true }
        }
        return false
    }

    /// Targets whose extent depends on where the shell happens to be.
    static func isUnboundedTarget(_ target: String) -> Bool {
        ["*", ".", "./", "./*", "..", "../*", ".*"].contains(target)
    }

    /// Whether a path is one of the roots that must never be deleted recursively.
    ///
    /// Also catches a trailing glob (`/Users/*`) and a home-relative root.
    static func isProtectedRootPath(_ path: String) -> Bool {
        var candidate = path
        if candidate.hasSuffix("/*") { candidate = String(candidate.dropLast(2)) }
        if candidate.hasSuffix("/") && candidate.count > 1 { candidate = String(candidate.dropLast()) }
        if candidate.isEmpty || candidate == "/" { return true }
        if protectedRoots.contains(candidate) { return true }

        // `/Users/someone` with nothing further is a whole home directory.
        let components = candidate.split(separator: "/", omittingEmptySubsequences: true)
        if components.count == 2, components[0] == "Users" { return true }
        // A bare `~` expansion.
        if candidate == NSHomeDirectory() { return true }
        return false
    }

    /// Whether a target is outside the session's working directory.
    ///
    /// Relative paths that climb out with `..` count too. A temporary directory is
    /// treated as inside, since build scratch space is not the user's work.
    static func escapesWorkspace(_ target: String, cwd: String?) -> Bool {
        guard let cwd, !cwd.isEmpty else { return false }
        if target.hasPrefix("/tmp") || target.hasPrefix("/var/folders") || target.hasPrefix("/private/tmp") {
            return false
        }
        if target.hasPrefix("/") {
            return !(target == cwd || target.hasPrefix(cwd.hasSuffix("/") ? cwd : cwd + "/"))
        }
        if target.hasPrefix("~") || target.hasPrefix("$HOME") || target.hasPrefix("${HOME}") {
            return true
        }
        // Resolve `..` without touching the filesystem.
        let resolved = (cwd as NSString).appendingPathComponent(target)
        let standardised = (resolved as NSString).standardizingPath
        return !(standardised == cwd || standardised.hasPrefix(cwd.hasSuffix("/") ? cwd : cwd + "/"))
    }
}
