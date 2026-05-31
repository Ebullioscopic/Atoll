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
    private var preferredScreenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        refresh(reason: "init")
        registerObservers()
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        if let preferredScreenObserver {
            NotificationCenter.default.removeObserver(preferredScreenObserver)
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

    func contextSnapshot() -> LockScreenDisplayContext? {
        if let context {
            return context
        }
        return refresh(reason: "snapshot-miss")
    }

    private func preferredLockScreen() -> NSScreen? {
        // Follow the notch window's preferred screen (issue #374).
        // The notch screen is stored in UserDefaults as "preferred_screen_name".
        let preferredScreenName = UserDefaults.standard.string(forKey: "preferred_screen_name")

        if let preferredScreenName,
           let matched = NSScreen.screens.first(where: { $0.localizedName == preferredScreenName }) {
            return matched
        }

        // Fallback: built-in display
        if let builtin = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }) {
            return builtin
        }

        let mainDisplayID = CGMainDisplayID()
        if let mainScreen = NSScreen.screens.first(where: { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == mainDisplayID
        }) {
            return mainScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func registerObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh(reason: "screen-parameters")
        }

        preferredScreenObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("SelectedScreenChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh(reason: "preferred-screen-changed")
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
