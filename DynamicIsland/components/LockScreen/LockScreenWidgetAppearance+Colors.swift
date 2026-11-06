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

import SwiftUI

extension LockScreenWidgetAppearance {
    var materialColorScheme: ColorScheme {
        usesLightGlyphs ? .dark : .light
    }

    func primary(opacity: Double = 1) -> Color {
        (usesLightGlyphs ? Color.white : Color.black).opacity(opacity)
    }

    var contentShadow: Color {
        usesLightGlyphs ? Color.black.opacity(0.35) : Color.white.opacity(0.5)
    }
}
