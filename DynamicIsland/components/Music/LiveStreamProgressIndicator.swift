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

/// The stand-in for a progress bar on a stream that has no position to show.
///
/// Apple runs the line *through* the word rather than printing the word on top
/// of a bar: two thin rules meeting a plain "LIVE" in the middle, the rules
/// softening as they run away from it. The previous version drew a 10pt capsule
/// with a fill, a centre shade, a stroke and three blend modes, then dropped
/// shadowed text over the whole thing — which reads as a progress bar someone
/// has written on, and a stream has no progress to draw.
struct LiveStreamProgressIndicator: View {
    let tint: Color
    var labelSize: CGFloat = 12

    /// Thin, the way a rule is. The old bar was sized like a track you could
    /// scrub, which is the one thing this is not.
    private var ruleHeight: CGFloat { 3 }

    /// The rules fade as they run away from the word, so the eye is carried to
    /// it rather than along the full width.
    private func rule(fadingTowards edge: UnitPoint) -> some View {
        Capsule(style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.5), tint.opacity(0.16)],
                    startPoint: edge == .leading ? .trailing : .leading,
                    endPoint: edge
                )
            )
            .frame(height: ruleHeight)
    }

    var body: some View {
        HStack(spacing: 10) {
            rule(fadingTowards: .leading)

            Text("LIVE")
                .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(tint)
                .fixedSize()

            rule(fadingTowards: .trailing)
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Live stream")
    }
}
