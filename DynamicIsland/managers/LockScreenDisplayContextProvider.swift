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

    func contextSnapshot() -> LockScreenDisplayContext? {
        refresh(reason: "snapshot")
    }

    private func preferredLockScreen() -> NSScreen? {
        let screens = NSScreen.screens
        let displays: [(displayID: CGDirectDisplayID?, isBuiltin: Bool)] = screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let displayID = number?.uint32Value
            return (displayID: displayID, isBuiltin: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false)
        }
        let index = Self.preferredDisplayIndex(
            displays: displays,
            mainDisplayID: CGMainDisplayID(),
            activeScreenIndex: NSScreen.main.flatMap { screens.firstIndex(of: $0) }
        )
        return index.map { screens[$0] }
    }

    nonisolated static func preferredDisplayIndex(
        displays: [(displayID: CGDirectDisplayID?, isBuiltin: Bool)],
        mainDisplayID: CGDirectDisplayID,
        activeScreenIndex: Int?
    ) -> Int? {
        displays.firstIndex { $0.displayID == mainDisplayID }
            ?? activeScreenIndex.flatMap { displays.indices.contains($0) ? $0 : nil }
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
