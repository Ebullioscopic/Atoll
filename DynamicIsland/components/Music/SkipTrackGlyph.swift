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

/// The skip-track glyph, animated the way Apple animates it.
///
/// `forward.fill` / `backward.fill` are a pair of triangles. Apple doesn't move
/// the button when you press it — it marches the triangles in the direction of
/// travel: the leading one slides out and fades, the trailing one takes its
/// place, and a fresh one fades in behind. Because the end state is identical
/// to the rest state, the phase snaps back to zero and the glyph is ready to
/// fire again on a fast double-tap.
struct SkipTrackGlyph: View {
    enum Direction {
        case forward
        case backward

        var rotation: Angle { self == .forward ? .zero : .degrees(180) }
    }

    let direction: Direction
    let size: CGFloat
    /// Increment to play the animation.
    let trigger: Int

    @State private var phase: CGFloat = 0

    /// Triangle size and spacing, tuned against `forward.fill` rendered at the
    /// same point size so the resting glyph is indistinguishable from it.
    private var glyphSize: CGFloat { size * 0.88 }
    private var step: CGFloat { size * 0.52 }
    private var travelDuration: TimeInterval { 0.26 }

    var body: some View {
        ZStack {
            // Slot 2 is the leading triangle, 1 the trailing one, 0 the spare
            // waiting off-glyph to replace it.
            ForEach(0 ..< 3, id: \.self) { slot in
                triangle
                    .opacity(opacity(for: slot))
                    .offset(x: offset(for: slot))
            }
        }
        .frame(width: size * 1.5, height: size)
        .rotationEffect(direction.rotation)
        .onChange(of: trigger) { _, _ in
            advance()
        }
    }

    private var triangle: some View {
        Image(systemName: "play.fill")
            .font(.system(size: glyphSize, weight: .medium))
    }

    private func offset(for slot: Int) -> CGFloat {
        ((CGFloat(slot) - 1.5) + phase) * step
    }

    private func opacity(for slot: Int) -> Double {
        switch slot {
        case 2: return 1 - phase       // leading: fades as it slides out
        case 0: return Double(phase)   // spare: fades in behind
        default: return 1
        }
    }

    private func advance() {
        // Land exactly on the rest state, then reset without animating so the
        // glyph can fire again immediately.
        withAnimation(.easeOut(duration: travelDuration)) {
            phase = 1
        } completion: {
            phase = 0
        }
    }
}
