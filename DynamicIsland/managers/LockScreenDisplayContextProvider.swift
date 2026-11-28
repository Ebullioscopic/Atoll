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
import CoreGraphics

struct LockScreenDisplayContext {
    let screen: NSScreen
    let frame: NSRect
    let identifier: String
}

@MainActor
final class LockScreenDisplayContextProvider {
    static let shared = LockScreenDisplayContextProvider()

    private(set) var context: LockScreenDisplayContext?
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        refresh(reason: "init")
        registerObservers()
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
    }

    @discardableResult
    func refresh(reason: String) -> LockScreenDisplayContext? {
        guard let screen = preferredLockScreen() else {
            context = nil
            return nil
        }

        let snapshot = LockScreenDisplayContext(
            screen: screen,
            frame: screen.frame,
            identifier: screen.localizedName
        )

        context = snapshot
        return snapshot
    }

    /// Returns the cached context. It is rebuilt on lock, wake, Space and
    /// screen-parameter changes (which also fire when the main display changes),
    /// so reads stay cheap while the lock screen widgets lay themselves out.
    func contextSnapshot() -> LockScreenDisplayContext? {
        if let context {
            return context
        }
        return refresh(reason: "snapshot-miss")
    }

    private func preferredLockScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let displays: [(displayID: CGDirectDisplayID?, isBuiltin: Bool)] = screens.map { screen in
            let displayID = screen.displayID
            return (displayID: displayID, isBuiltin: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false)
        }
        let index = Self.preferredDisplayIndex(displays: displays, mainDisplayID: CGMainDisplayID())
        return index.map { screens[$0] }
    }

    /// macOS draws the login window on the main display (the one with the menu
    /// bar in System Settings > Displays), so the widgets follow it. This
    /// supersedes the built-in-first order from ebcd2f6e, which put the widgets
    /// on the laptop panel even when an external monitor was the main display.
    /// The bug that commit fixed — widgets jumping between screens because
    /// `NSScreen.main` follows keyboard focus — stays fixed: the choice never
    /// depends on focus. In clamshell mode the built-in panel is offline and
    /// absent from `NSScreen.screens`, so the main (external) display is used.
    nonisolated static func preferredDisplayIndex(
        displays: [(displayID: CGDirectDisplayID?, isBuiltin: Bool)],
        mainDisplayID: CGDirectDisplayID
    ) -> Int? {
        displays.firstIndex { $0.displayID == mainDisplayID }
            ?? displays.firstIndex { $0.isBuiltin }
            ?? displays.indices.first
    }

    private func registerObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh(reason: "screen-parameters")
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh(reason: "screens-did-wake")
        }

        let spaceObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh(reason: "space-changed")
        }

        workspaceObservers = [wakeObserver, spaceObserver]
    }
}
