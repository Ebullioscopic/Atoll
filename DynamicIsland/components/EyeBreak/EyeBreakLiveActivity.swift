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

/// Closed-notch presentation of an eye break: an eye on the left wing, the
/// remaining seconds and a Skip affordance on the right. Laid out like
/// `ReminderLiveActivity` so the wings clear the physical notch.
struct EyeBreakLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var manager = EyeBreakManager.shared

    @State private var isHoveringSkip = false

    private let wingPadding: CGFloat = 16
    private let iconDiameter: CGFloat = 20

    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight)
    }

    var body: some View {
        if manager.isBreakVisible {
            content
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var content: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: leftWingWidth, height: notchContentHeight)
                .background(alignment: .leading) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.teal)
                        .frame(width: iconDiameter, height: notchContentHeight)
                        .padding(.leading, wingPadding / 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width, height: notchContentHeight)

            Color.clear
                .frame(width: rightWingWidth, height: notchContentHeight)
                .background(alignment: .trailing) {
                    rightSection
                        .padding(.trailing, wingPadding / 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
        }
        .frame(height: notchContentHeight, alignment: .center)
        .help(Text("Look about 20 feet away until the countdown ends"))
    }

    private var rightSection: some View {
        HStack(spacing: 6) {
            Text(countdownText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))

            Button {
                manager.skipBreak()
            } label: {
                Text("Skip")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHoveringSkip ? .white : .white.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.white.opacity(isHoveringSkip ? 0.22 : 0.12))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHoveringSkip = $0 }
            .accessibilityLabel(Text("Skip eye break"))
        }
        .frame(height: notchContentHeight)
    }

    private var countdownText: String {
        guard let remaining = manager.remainingSeconds else { return "" }
        return "\(remaining)s"
    }

    private var leftWingWidth: CGFloat {
        iconDiameter + wingPadding
    }

    private var rightWingWidth: CGFloat {
        // Countdown text plus the Skip capsule; the notch itself sits between the
        // two wings, so this only has to cover the trailing content.
        76 + wingPadding
    }
}
