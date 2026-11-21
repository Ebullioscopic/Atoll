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

/// SwiftUI view displayed when no update is available.
/// Shows a checkmark animation with "You're up to date!" message,
/// current version, and channel information.
struct UpdateNotFoundView: View {
    @ObservedObject var state: UpdateUIState
    @State private var showCheckmark: Bool = false
    @State private var ringScale: CGFloat = 0.5

    private var channel: UpdateChannel {
        Defaults[.updateChannel]
    }

    private var channelColor: Color {
        Color(channel.badgeColor)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Animated checkmark
            ZStack {
                // Expanding ring
                Circle()
                    .stroke(Color.green.opacity(0.3), lineWidth: 3)
                    .frame(width: 100, height: 100)
                    .scaleEffect(ringScale)
                    .opacity(showCheckmark ? 0.0 : 0.8)

                // Background circle
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 90, height: 90)

                // Checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.green)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(showCheckmark ? 1.0 : 0.3)
                    .opacity(showCheckmark ? 1.0 : 0)
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
                    showCheckmark = true
                }
                withAnimation(.easeOut(duration: 1.2)) {
                    ringScale = 1.5
                }
            }

            // Title
            Text("You're up to date!")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .opacity(showCheckmark ? 1.0 : 0)
                .animation(.easeIn(duration: 0.3).delay(0.3), value: showCheckmark)

            // Version info
            VStack(spacing: 6) {
                Text("Atoll \(Bundle.main.releaseVersionNumber ?? String(localized: "Unknown"))")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Image(systemName: channel.badgeIcon)
                        .font(.caption2)
                    Text("\(channel.displayName) channel")
                        .font(.caption)
                }
                .foregroundStyle(channelColor)
            }
            .opacity(showCheckmark ? 1.0 : 0)
            .animation(.easeIn(duration: 0.3).delay(0.5), value: showCheckmark)

            Text("Atoll will automatically check for updates periodically.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .opacity(showCheckmark ? 1.0 : 0)
                .animation(.easeIn(duration: 0.3).delay(0.7), value: showCheckmark)

            Spacer()

            // Dismiss button
            Button {
                state.acknowledgeAction?()
            } label: {
                Text("OK")
                    .font(.system(.body, weight: .medium))
                    .frame(width: 120)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green.opacity(0.8))
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .frame(width: 460, height: 380)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Preview

#Preview("Up to Date") {
    UpdateNotFoundView(state: {
        let s = UpdateUIState()
        s.phase = .upToDate
        return s
    }())
}
