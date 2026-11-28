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

import Defaults

public enum TimerDisplayMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case tab
    case popover

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tab:
            return String(localized:"Tab")
        case .popover:
            return String(localized:"Popover")
        }
    }

    var description: String {
        switch self {
        case .tab:
            return String(localized: "Shows timer controls as a dedicated tab inside the open notch.")
        case .popover:
            return String(localized: "Keeps the current popover button beside the notch instead of adding a tab.")
        }
    }
}
