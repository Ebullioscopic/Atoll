/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import ApplicationServices
import Defaults
import MacroVisionKit
import SwiftUI

@MainActor
class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    private let detector = FullScreenMonitor.shared
    @ObservedObject private var musicManager = MusicManager.shared
    @Published private(set) var fullscreenStatus: [String: Bool] = [:]
    private var notificationTask: Task<Void, Never>?

    private init() {
        setupNotificationObservers()
        Task { await updateFullScreenStatus() }
    }

    private func setupNotificationObservers() {
        notificationTask = Task { @Sendable [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let activeSpaceNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.activeSpaceDidChangeNotification
                    )
                    
                    for await _ in activeSpaceNotifications {
                        await self?.handleChange()
                    }
                }
                
                group.addTask {
                    let screenParameterNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named:  NSApplication.didChangeScreenParametersNotification
                    )
                    
                    for await _ in screenParameterNotifications {
                        await  self?.handleChange()
                    }
                }
            }
        }
    }

    private func handleChange() async {
        try? await Task.sleep(for: .milliseconds(500))
        await self.updateFullScreenStatus()
    }

    private func updateFullScreenStatus() async {
        guard Defaults[.enableFullscreenMediaDetection] else {
            let reset = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { ($0.localizedName, false) })
            if reset != fullscreenStatus {
                fullscreenStatus = reset
            }
            return
        }
        

        let spaces = await detector.detectFullscreenApps(debug: false)
        let screens = NSScreen.screens
        let hideOption = Defaults[.hideNotchOption]

        var newStatus: [String: Bool] = [:]
        for screen in screens {
            let screenUUID = Self.uuidString(for: screen)
            newStatus[screen.localizedName] = spaces.contains { space in
                guard space.screenUUID == screenUUID else { return false }
                let bundleIdentifiers = space.runningApps.filter { $0 != "com.apple.finder" }
                guard !bundleIdentifiers.isEmpty else { return false }

                // The notch stays on display by default (the window's collectionBehavior
                // rides along with fullscreen spaces). It only hides when the user's
                // "Hide DynamicIsland" option asks for it.
                switch hideOption {
                case .always:
                    // Hide for any app in genuine native fullscreen on this screen.
                    return true
                case .nowPlayingOnly:
                    // Hide only when the currently playing media app is in fullscreen.
                    guard let currentBundleIdentifier = musicManager.bundleIdentifier else { return false }
                    return bundleIdentifiers.contains(currentBundleIdentifier)
                case .never:
                    // Always on display; never hide.
                    return false
                }
            }
        }

        if newStatus != fullscreenStatus {
            fullscreenStatus = newStatus
            NSLog("✅ Fullscreen status: \(newStatus)")
        }
    }

    private static func uuidString(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    private func cleanupNotificationObservers() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
