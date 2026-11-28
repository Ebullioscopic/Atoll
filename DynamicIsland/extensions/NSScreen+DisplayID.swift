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

extension NSScreen {
    /// UserDefaults key holding the UUID of the display picked in Settings.
    static let preferredDisplayUUIDDefaultsKey = "preferred_screen_uuid"

    /// `CGDirectDisplayID` of the underlying display. Only valid for the current
    /// session: it can change across reconnects and reboots, so never persist it.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Persistent identifier of the physical display. Unlike `localizedName` it
    /// tells identical monitors apart, and unlike `displayID` it survives
    /// reconnects and reboots.
    var displayUUID: String? {
        guard let displayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// Resolves a display by its localized name. When several connected displays
    /// share that name (e.g. two identical monitors), the one the user picked in
    /// Settings wins, so name-keyed lookups land on the same display as the window.
    static func screen(named name: String?) -> NSScreen? {
        guard let name else { return nil }
        let matches = screens.filter { $0.localizedName == name }
        guard matches.count > 1,
              let uuid = UserDefaults.standard.string(forKey: preferredDisplayUUIDDefaultsKey),
              !uuid.isEmpty,
              let preferred = matches.first(where: { $0.displayUUID == uuid })
        else { return matches.first }
        return preferred
    }

    /// `(uuid, label)` rows for display pickers.
    ///
    /// When several connected displays share a localized name (e.g. two identical
    /// external monitors), a `" (n)"` suffix is appended so they stay distinguishable.
    static func displayPickerItems() -> [(uuid: String, label: String)] {
        let screens = NSScreen.screens
        var seen: [String: Int] = [:]
        return screens.compactMap { screen in
            guard let uuid = screen.displayUUID else { return nil }
            let name = screen.localizedName
            seen[name, default: 0] += 1
            let isDuplicated = screens.contains { $0 != screen && $0.localizedName == name }
            let label = isDuplicated ? "\(name) (\(seen[name, default: 1]))" : name
            return (uuid, label)
        }
    }
}
