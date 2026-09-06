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
    /// Stable identifier of the underlying physical display (its `CGDirectDisplayID`).
    ///
    /// Unlike `localizedName`, the display ID tells identical monitors apart and
    /// does not change when the display is renamed or the system locale changes.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// `(id, label)` rows for display pickers.
    ///
    /// When several connected displays share a localized name (e.g. two identical
    /// external monitors), a `" (n)"` suffix is appended so they stay distinguishable.
    static func displayPickerItems() -> [(id: CGDirectDisplayID, label: String)] {
        let screens = NSScreen.screens
        var seen: [String: Int] = [:]
        return screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            let name = screen.localizedName
            seen[name, default: 0] += 1
            let isDuplicated = screens.contains { $0 != screen && $0.localizedName == name }
            let label = isDuplicated ? "\(name) (\(seen[name, default: 1]))" : name
            return (id, label)
        }
    }
}
