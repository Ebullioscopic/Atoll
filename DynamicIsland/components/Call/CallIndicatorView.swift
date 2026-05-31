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
import Defaults

// MARK: - Call Indicator Animation View (#248)
// Shows an animated pill indicator when a phone/FaceTime call is active.

struct CallIndicatorView: View {
    @ObservedObject private var callManager = CallDetectionManager.shared
    @State private var isPulsing = false

    var body: some View {
        if callManager.isOnCall {
            HStack(spacing: 6) {
                // Animated phone icon with pulsing green dot
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .scaleEffect(isPulsing ? 1.3 : 1.0)
                        .opacity(isPulsing ? 0.6 : 1.0)

                    Circle()
                        .fill(Color.green.opacity(0.3))
                        .frame(width: 14, height: 14)
                        .scaleEffect(isPulsing ? 1.5 : 0.8)
                        .opacity(isPulsing ? 0.0 : 0.4)
                }
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)

                Image(systemName: "phone.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)

                Text(callManager.formattedDuration)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.25))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.green.opacity(0.5), lineWidth: 0.5)
                    )
            )
            .onAppear {
                isPulsing = true
            }
            .onDisappear {
                isPulsing = false
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .scale(scale: 0.8).combined(with: .opacity)
            ))
        }
    }
}

// MARK: - Compact Call Indicator (for closed notch state)

struct CompactCallIndicatorView: View {
    @ObservedObject private var callManager = CallDetectionManager.shared
    @State private var glowOpacity: Double = 0.4

    var body: some View {
        if callManager.isOnCall {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .shadow(color: .green.opacity(glowOpacity), radius: 3)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: glowOpacity)
                .onAppear {
                    glowOpacity = 0.9
                }
                .transition(.opacity)
        }
    }
}
