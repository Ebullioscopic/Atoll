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

struct TogglLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject private var togglManager = TogglManager.shared

    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var wingPadding: CGFloat { 22 }

    var body: some View {
        HStack(spacing: 0) {
            // Left wing: Toggl icon (only the outer half of the wing padding is
            // reserved so the icon sits flush against the notch, no dead gap).
            Color.clear
                .frame(width: notchContentHeight + wingPadding / 2, height: notchContentHeight)
                .background(alignment: .leading) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.87, green: 0.36, blue: 0.22))
                        .frame(width: notchContentHeight, height: notchContentHeight)
                        .padding(.leading, wingPadding / 2)
                }

            // Middle: notch pill spacer
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width, height: notchContentHeight)

            // Right wing: elapsed time
            Color.clear
                .frame(width: elapsedWidth + wingPadding, height: notchContentHeight)
                .background(alignment: .trailing) {
                    Text(formattedElapsed)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        // ~6px trailing so the leading hour digit stays clear of the notch.
                        .padding(.trailing, wingPadding / 2 - 5)
                        .frame(height: notchContentHeight, alignment: .center)
                }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .contentShape(Rectangle())
    }

    private var elapsedWidth: CGFloat { 72 }

    private var formattedElapsed: String {
        let total = Int(togglManager.elapsed)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
