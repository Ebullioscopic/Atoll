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

struct CircularGaugeView: View {
    let title: String
    let value: Double
    let tint: Color
    let centerPrimaryText: String
    var centerSecondaryText: String?
    var subtitle: String?
    var size: CGFloat = 72
    var lineWidth: CGFloat = 8
    var backgroundTint: Color = Color.primary.opacity(0.08)

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(backgroundTint, lineWidth: lineWidth)
                    .frame(width: size, height: size)
                if value > 0 {
                    RingArc(start: 0, end: min(max(value, 0), 1), color: tint, lineWidth: lineWidth)
                        .frame(width: size, height: size)
                }
                VStack(spacing: 2) {
                    Text(centerPrimaryText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(tint)
                    if let centerSecondaryText, !centerSecondaryText.isEmpty {
                        Text(centerSecondaryText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            VStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}
