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
import Defaults

struct Alarm: Identifiable, Codable, Hashable, Defaults.Serializable {
    var id: UUID
    var label: String
    var fireDate: Date
    var isEnabled: Bool
    var repeatDaily: Bool

    init(id: UUID = UUID(), label: String, fireDate: Date, isEnabled: Bool = true, repeatDaily: Bool = false) {
        self.id = id
        self.label = label
        self.fireDate = fireDate
        self.isEnabled = isEnabled
        self.repeatDaily = repeatDaily
    }

    var isExpired: Bool {
        !repeatDaily && fireDate < Date()
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: fireDate)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .short
        return formatter.string(from: fireDate)
    }
}
