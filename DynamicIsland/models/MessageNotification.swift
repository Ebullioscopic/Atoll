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

struct MessageNotification: Identifiable, Equatable, Hashable {
    let id = UUID()
    let sender: String
    let content: String
    let profilePicture: NSImage?
    let appIcon: NSImage?
    let appBundleId: String
    let timestamp: Date

    var filteredContent: String {
        content.replacingOccurrences(of: "\u{fffc}", with: "")
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sender == rhs.sender &&
        lhs.content == rhs.content &&
        lhs.appBundleId == rhs.appBundleId &&
        lhs.timestamp == rhs.timestamp
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sender)
        hasher.combine(content)
        hasher.combine(appBundleId)
        hasher.combine(timestamp)
    }
}
