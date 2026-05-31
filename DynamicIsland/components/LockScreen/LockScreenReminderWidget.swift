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

struct LockScreenReminderWidget: View {
    let snapshot: LockScreenReminderWidgetSnapshot

    private let primaryFont = Font.system(size: 19, weight: .semibold, design: .rounded)
    private let iconSize: CGFloat = 20
    private let chipWidth: CGFloat = 9

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: snapshot.iconName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(accentColor)

            RoundedRectangle(cornerRadius: 2)
                .fill(chipColor)
                .frame(width: chipWidth, height: iconSize)

            Text(snapshot.title)
                .font(primaryFont)
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
                .layoutPriority(1)
                .frame(height: iconSize, alignment: .center)

            if let relative = snapshot.relativeDescription {
                Text("•")
                    .font(primaryFont)
                    .foregroundStyle(separatorColor)
                    .frame(height: iconSize, alignment: .center)

                Text(relative)
                    .font(primaryFont)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .layoutPriority(0.75)
                    .frame(height: iconSize, alignment: .center)
            }

            Text("•")
                .font(primaryFont)
                .foregroundStyle(separatorColor)
                .frame(height: iconSize, alignment: .center)

            Text(snapshot.eventTimeText)
                .font(primaryFont)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)
                .layoutPriority(0.75)
                .frame(height: iconSize, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 240, idealWidth: 360, maxWidth: 520, alignment: .leading)
        .foregroundStyle(Color.white)
        .background(Color.clear)
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accentColor: Color {
        snapshot.isCritical ? .red : snapshot.accent.color
    }

    private var chipColor: Color {
        if snapshot.isCritical {
            return .red
        }
        switch snapshot.chipStyle {
        case .eventColor:
            return accentColor.ensureMinimumBrightness(factor: 0.7)
        case .monochrome:
            return Color.white.opacity(0.85)
        }
    }

    private var primaryTextColor: Color {
        Color.white.opacity(0.92)
    }

    private var secondaryTextColor: Color {
        snapshot.isCritical ? Color.white : Color.white.opacity(0.78)
    }

    private var separatorColor: Color {
        Color.white.opacity(0.65)
    }

    private var accessibilityLabel: String {
        var components: [String] = [snapshot.title]
        if let relative = snapshot.relativeDescription {
            components.append(relative)
        }
        components.append(snapshot.eventTimeText)
        return components.joined(separator: ", ")
    }
}

