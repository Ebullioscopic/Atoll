/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import CodeIslandCore
import CodeIslandRuntime
import Defaults
import Foundation

/// Atoll-owned bridge between sanitized origin handles and macOS applications.
///
/// Visibility is deliberately conservative: only Terminal.app's selected TTY
/// and iTerm2's selected session ID can currently produce an exact match.
/// Native-app or application-only visibility remains unknown and never
/// suppresses a presentation.
@MainActor
final class CodeIslandOriginAdapter {
    private let matcher = CodeIslandExactOriginMatcher()

    func exactMatch(for expected: OriginNavigation?) async -> CodeIslandExactOriginMatch {
        guard let expected else { return .unknown }
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let expectedBundleID = expected.applicationBundleIdentifier,
           let frontmostBundleID,
           expectedBundleID.caseInsensitiveCompare(frontmostBundleID) != .orderedSame {
            return .different
        }

        let visibleHandles: CodeIslandVisibleOrigin
        switch frontmostBundleID?.lowercased() {
        case "com.apple.terminal":
            let tty = await Self.runAppleScript(
                """
                tell application "Terminal"
                    try
                        return tty of selected tab of front window
                    on error
                        return ""
                    end try
                end tell
                """
            )
            visibleHandles = CodeIslandVisibleOrigin(
                applicationBundleIdentifier: frontmostBundleID,
                terminalSessionIdentifier: nil,
                workspaceIdentifier: nil,
                paneIdentifier: nil,
                tty: Self.nonempty(tty)
            )

        case "com.googlecode.iterm2":
            let sessionID = await Self.runAppleScript(
                """
                tell application "iTerm2"
                    try
                        return unique ID of current session of current tab of current window
                    on error
                        return ""
                    end try
                end tell
                """
            )
            visibleHandles = CodeIslandVisibleOrigin(
                applicationBundleIdentifier: frontmostBundleID,
                terminalSessionIdentifier: Self.nonempty(sessionID),
                workspaceIdentifier: nil,
                paneIdentifier: nil,
                tty: nil
            )

        default:
            visibleHandles = CodeIslandVisibleOrigin(
                applicationBundleIdentifier: frontmostBundleID,
                terminalSessionIdentifier: nil,
                workspaceIdentifier: nil,
                paneIdentifier: nil,
                tty: nil
            )
        }

        let currentFrontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard currentFrontmostBundleID?.lowercased() == frontmostBundleID?.lowercased() else {
            return .different
        }
        return matcher.match(expected: expected, visible: visibleHandles)
    }

    /// Returns the user to the provider-owned origin. No decision is submitted.
    func open(_ origin: OriginNavigation?) {
        guard let origin else { return }
        let bundleID = origin.applicationBundleIdentifier?.lowercased()

        if bundleID == "com.googlecode.iterm2",
           let sessionID = origin.terminalSessionIdentifier {
            activateRunningApplication(bundleIdentifier: "com.googlecode.iterm2")
            Self.runAppleScriptWithoutWaiting(
                """
                tell application "iTerm2"
                    repeat with aWindow in windows
                        repeat with aTab in tabs of aWindow
                            repeat with aSession in sessions of aTab
                                if unique ID of aSession is "\(Self.escapeAppleScript(sessionID))" then
                                    if miniaturized of aWindow then set miniaturized of aWindow to false
                                    try
                                        select aWindow
                                    end try
                                    select aTab
                                    select aSession
                                    activate
                                    return
                                end if
                            end repeat
                        end repeat
                    end repeat
                    activate
                end tell
                """
            )
            return
        }

        if bundleID == "com.apple.terminal", let tty = origin.tty {
            activateRunningApplication(bundleIdentifier: "com.apple.Terminal")
            Self.runAppleScriptWithoutWaiting(
                """
                tell application "Terminal"
                    set targetTty to "\(Self.escapeAppleScript(tty))"
                    repeat with aWindow in windows
                        repeat with aTab in tabs of aWindow
                            try
                                if tty of aTab is targetTty then
                                    if miniaturized of aWindow then set miniaturized of aWindow to false
                                    set selected tab of aWindow to aTab
                                    set index of aWindow to 1
                                    activate
                                    return
                                end if
                            end try
                        end repeat
                    end repeat
                    activate
                end tell
                """
            )
            return
        }

        if let bundleIdentifier = origin.applicationBundleIdentifier {
            activateRunningApplication(bundleIdentifier: bundleIdentifier)
        }
    }

    /// Selects Code Island inside Atoll and opens Atoll's existing notch window.
    func presentAttentionHandoff() {
        guard !Defaults[.enableMinimalisticUI] else { return }
        let coordinator = DynamicIslandViewCoordinator.shared
        coordinator.currentView = .codeIsland

        guard let delegate = AppDelegate.shared else { return }
        delegate.closeNotchWorkItem?.cancel()
        delegate.closeNotchWorkItem = nil

        if Defaults[.showOnAllDisplays],
           let mainScreen = NSScreen.main,
           let viewModel = delegate.viewModels[mainScreen] {
            viewModel.open()
        } else {
            delegate.vm.open()
        }
    }

    private func activateRunningApplication(bundleIdentifier: String) {
        guard let application = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier?.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
        }) else { return }
        if application.isHidden { application.unhide() }
        application.activate()
    }

    nonisolated private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runAppleScript(_ source: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else { return nil }
            var error: NSDictionary?
            return script.executeAndReturnError(&error).stringValue
        }.value
    }

    private static func runAppleScriptWithoutWaiting(_ source: String) {
        Task.detached(priority: .userInitiated) {
            guard let script = NSAppleScript(source: source) else { return }
            var error: NSDictionary?
            script.executeAndReturnError(&error)
        }
    }
}
