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

import AppKit
import Foundation

/// Which terminal an agent is running in, as far as Atoll can tell.
enum TerminalHost: Equatable, Sendable {
    case appleTerminal
    case iTerm2
    /// Recognised, but with no way to address an individual tab.
    case unaddressable(bundleID: String?)
    case unknown

    /// Whether an exact tab can be selected, as opposed to only raising the app.
    var supportsTabSelection: Bool {
        self == .appleTerminal || self == .iTerm2
    }
}

/// Brings the terminal tab an agent is running in to the front.
///
/// ## How the tab is identified
/// By **controlling tty**, read from the kernel via ``ProcessTree``, not by
/// window title. Both Terminal.app and iTerm2 expose a `tty` on their tabs and
/// sessions, so the match is exact — titles collide as soon as two agents run in
/// the same project, which is precisely when this feature matters.
///
/// The agent's pid comes from the hook shim's own parent, so nothing extra had to
/// be added to the spool protocol to make this work.
///
/// ## Degrading
/// Escalates downwards and never fails loudly:
/// 1. Select the exact tab (Terminal.app, iTerm2) — needs Automation consent.
/// 2. Raise the application the agent's process lives inside, found by walking
///    the process tree. Works for **every** terminal, including Ghostty, Warp,
///    Alacritty and VS Code, and needs no consent at all.
/// 3. Report failure to the caller, which shows the path instead.
enum TerminalJumpService {
    enum Outcome: Equatable, Sendable {
        /// The exact tab came forward.
        case selectedTab
        /// Only the application was raised.
        case raisedApplication
        case failed
    }

    /// Identifies the terminal from what the shim reported and what the process
    /// tree says.
    ///
    /// `TERM_PROGRAM` is preferred because it is set by the terminal itself; the
    /// bundle identifier is the fallback for terminals that do not set it.
    static func host(termProgram: String?, bundleID: String?) -> TerminalHost {
        switch termProgram?.lowercased() {
        case "apple_terminal":
            return .appleTerminal
        case "iterm.app":
            return .iTerm2
        default:
            break
        }

        switch bundleID?.lowercased() {
        case "com.apple.terminal":
            return .appleTerminal
        case "com.googlecode.iterm2":
            return .iTerm2
        case .some(let identifier):
            return .unaddressable(bundleID: identifier)
        case .none:
            return .unknown
        }
    }

    /// Brings the session's terminal forward.
    @MainActor
    @discardableResult
    static func jump(to session: AgentSession) async -> Outcome {
        let host = host(termProgram: session.terminalProgram, bundleID: session.terminalBundleID)
        let tty = session.agentPID.flatMap { ProcessTree.ttyPath(for: $0) }

        if host.supportsTabSelection, let tty {
            if await selectTab(host: host, tty: tty) {
                activateHost(for: session, host: host)
                return .selectedTab
            }
            // Consent refused, the terminal quit, or the tab is gone — fall through.
            Logger.log("Agent Tower: could not select the tab for \(tty), raising the app instead", category: .agents)
        }

        return activateHost(for: session, host: host) ? .raisedApplication : .failed
    }

    // MARK: - Tab selection

    /// An unresponsive terminal must not suspend `jump(to:)` indefinitely, so
    /// tab selection gives up after this long and falls back to raising the app.
    private static let tabSelectionTimeout: Duration = .seconds(3)

    private static func selectTab(host: TerminalHost, tty: String) async -> Bool {
        let script: String
        switch host {
        case .appleTerminal:
            script = appleTerminalScript(tty: tty)
        case .iTerm2:
            script = iTerm2Script(tty: tty)
        case .unaddressable, .unknown:
            return false
        }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                do {
                    let descriptor = try await AppleScriptHelper.execute(script)
                    return descriptor?.stringValue == "ok"
                } catch {
                    Logger.log("Agent Tower: terminal AppleScript failed: \(error.localizedDescription)", category: .agents)
                    return false
                }
            }
            group.addTask {
                try? await Task.sleep(for: tabSelectionTimeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    /// Terminal.app exposes `tty` on a tab, so this is an exact lookup.
    static func appleTerminalScript(tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            set frontmost of w to true
                            return "ok"
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "notfound"
        """
    }

    /// iTerm2 exposes `tty` on a session, one level deeper than Terminal.app.
    static func iTerm2Script(tty: String) -> String {
        """
        tell application "iTerm"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                return "ok"
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
        end tell
        return "notfound"
        """
    }

    // MARK: - Raising the application

    /// Raises the terminal application, preferring the one the agent's process
    /// actually lives inside over the bundle identifier it claimed.
    @MainActor
    @discardableResult
    private static func activateHost(for session: AgentSession, host: TerminalHost) -> Bool {
        if let pid = session.agentPID, let app = ProcessTree.hostApplication(for: pid) {
            return app.activate(options: [.activateAllWindows])
        }

        let bundleID: String?
        switch host {
        case .appleTerminal: bundleID = "com.apple.Terminal"
        case .iTerm2: bundleID = "com.googlecode.iterm2"
        case .unaddressable(let identifier): bundleID = identifier
        case .unknown: bundleID = session.terminalBundleID
        }

        guard let bundleID, !bundleID.isEmpty,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        else { return false }
        return app.activate(options: [.activateAllWindows])
    }
}
