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

enum ClosedNotchSatelliteChrome {
    static let autoHideDelay: TimeInterval = 4
    static let morphDuration: TimeInterval = 0.42

    static func buttonHeight(for notchHeight: CGFloat) -> CGFloat {
        max(notchHeight - 12, 20)
    }

    static func bottomRadius(for cornerRadius: CGFloat) -> CGFloat {
        max(cornerRadius - 2, 10)
    }

    static func pillBackground(cornerRadius: CGFloat) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius(for: cornerRadius),
            bottomTrailingRadius: bottomRadius(for: cornerRadius),
            topTrailingRadius: 0,
            style: .continuous
        )
        .fill(Color.black)
    }
}
