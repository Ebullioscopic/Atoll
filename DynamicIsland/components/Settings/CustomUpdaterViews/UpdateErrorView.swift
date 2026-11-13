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

/// SwiftUI view displayed when a Sparkle update encounters an error.
/// Shows an error icon with shake animation, a human-readable message,
/// and "Try Again" / "Dismiss" buttons.
struct UpdateErrorView: View {
    @ObservedObject var state: UpdateUIState
    @State private var shakeOffset: CGFloat = 0
    @State private var showIcon: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Error icon with shake animation
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(showIcon ? 1.0 : 0.5)
                    .opacity(showIcon ? 1.0 : 0)
            }
            .offset(x: shakeOffset)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    showIcon = true
                }
                // Shake animation
                withAnimation(
                    .easeInOut(duration: 0.08)
                    .repeatCount(6, autoreverses: true)
                    .delay(0.3)
                ) {
                    shakeOffset = 8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        shakeOffset = 0
                    }
                }
            }

            // Error title
            Text("Update Failed")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            // Error message
            Text(state.errorMessage ?? String(localized: "An unknown error occurred while updating Atoll."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .lineLimit(4)

            Spacer()

            // Action buttons
            VStack(spacing: 8) {
                Button {
                    state.acknowledgeAction?()
                } label: {
                    Text("Try Again")
                        .font(.system(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.8))
                .controlSize(.large)

                Button("Dismiss") {
                    state.acknowledgeAction?()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
        .frame(width: 460, height: 380)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Preview

#Preview("Update Error") {
    UpdateErrorView(state: {
        let s = UpdateUIState()
        s.phase = .error
        s.errorMessage = "The update could not be downloaded. Please check your internet connection and try again."
        return s
    }())
}

#Preview("Unknown Error") {
    UpdateErrorView(state: {
        let s = UpdateUIState()
        s.phase = .error
        s.errorMessage = nil
        return s
    }())
}
