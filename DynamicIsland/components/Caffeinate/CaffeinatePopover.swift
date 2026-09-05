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
import SwiftUI

/// Duration picker for the notch's caffeinate button.
///
/// Tapping a duration while a session is already running re-asserts with the
/// new duration rather than stacking a second one, so the list doubles as the
/// "extend this" control.
struct CaffeinatePopover: View {
    @ObservedObject private var caffeinateManager = CaffeinateManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()
                .padding(.horizontal, -8)

            VStack(spacing: 2) {
                ForEach(CaffeinateDuration.allCases) { duration in
                    durationRow(duration)
                }
            }

            if caffeinateManager.isActive {
                Divider()
                    .padding(.horizontal, -8)

                Button {
                    withAnimation(.smooth) {
                        caffeinateManager.deactivate()
                    }
                    dismiss()
                } label: {
                    Text("Turn Off")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(width: 240)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(12)
        )
    }

    private var header: some View {
        HStack {
            Image(systemName: caffeinateManager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .foregroundStyle(caffeinateManager.isActive ? .yellow : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Keep Awake")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    // A countdown that reflows the popover every second is
                    // distracting, so the row keeps a fixed baseline.
                    .monospacedDigit()
            }
            Spacer()
        }
    }

    private var statusText: String {
        guard caffeinateManager.isActive else {
            return String(localized: "Off")
        }
        if let remaining = caffeinateManager.remainingTime {
            return String(localized: "\(CaffeinateManager.remainingLabel(remaining)) left")
        }
        return String(localized: "On until turned off")
    }

    private func durationRow(_ duration: CaffeinateDuration) -> some View {
        let isRunning = caffeinateManager.isActive && caffeinateManager.activeDuration == duration

        return Button {
            withAnimation(.smooth) {
                caffeinateManager.activate(for: duration)
            }
            dismiss()
        } label: {
            HStack {
                Text(duration.displayName)
                Spacer()
                if isRunning {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.yellow)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

#Preview {
    CaffeinatePopover()
}
