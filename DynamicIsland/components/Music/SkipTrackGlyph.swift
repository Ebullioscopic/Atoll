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

    /// Accumulated travel: one whole step per skip, never reset. Interpolation
    /// happens inside `SkipArrows`, which is `Animatable`, so a press landing
    /// mid-flight simply extends the target and the chevrons keep marching.
    @State private var phase: CGFloat = 0

    // Tuned by rendering this glyph beside `forward.fill` at the same point
    // size and comparing triangle size and gap; these are the values at which
    // the resting pair became indistinguishable from the symbol it replaces.

    /// Triangle size as a fraction of the nominal point size. `play.fill` at
    /// full size is visibly larger than the triangles inside `forward.fill`,
    /// which fits two into a comparable box.
    private static let glyphSizeRatio: CGFloat = 0.88

    /// Distance between adjacent triangles, and therefore how far each one
    /// travels per press.
    private static let stepRatio: CGFloat = 0.52

    /// One press worth of travel. Short enough to keep up with repeated
    /// presses, which chain rather than queue.
    private static let travelDuration: TimeInterval = 0.26

    private var glyphSize: CGFloat { size * SkipTrackGlyph.glyphSizeRatio }
    private var step: CGFloat { size * SkipTrackGlyph.stepRatio }

    var body: some View {
        SkipArrows(phase: phase, glyphSize: glyphSize, step: step)
            .frame(width: size * 1.5, height: size)
            .rotationEffect(direction.rotation)
            .onChange(of: trigger) { oldValue, newValue in
                // Advance by however many presses this delivers. SwiftUI
                // coalesces state changes within a run loop turn, so two
                // presses in the same turn arrive as a single call with a
                // trigger two higher — advancing by one would drop a skip's
                // worth of travel.
                let presses = max(newValue - oldValue, 1)
                withAnimation(.easeOut(duration: SkipTrackGlyph.travelDuration)) {
                    phase += CGFloat(presses)
                }
            }
    }
}

/// The three triangles, positioned from an accumulated phase.
///
/// This has to be `Animatable`. Deriving the cycle position in a plain view's
/// body does not animate: SwiftUI interpolates the *rendered* values, and since
/// a whole step lands the triangles exactly where the previous ones sat, the
/// old and new frames are identical and there is no delta to interpolate.
/// Conforming to `Animatable` moves the interpolation onto `phase` itself, so
/// the body is re-evaluated per frame with the intermediate values.
private struct SkipArrows: View, Animatable {
    var phase: CGFloat
    let glyphSize: CGFloat
    let step: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    /// Position within the current step: 0 at rest, approaching 1 as the
    /// leading triangle slides out.
    private var cyclePhase: CGFloat {
        phase - phase.rounded(.down)
    }

    var body: some View {
        ZStack {
            // Slot 2 is the leading triangle, 1 the trailing one, 0 the spare
            // waiting off-glyph to replace it.
            ForEach(0 ..< 3, id: \.self) { slot in
                Image(systemName: "play.fill")
                    .font(.system(size: glyphSize, weight: .medium))
                    .opacity(opacity(for: slot))
                    .offset(x: offset(for: slot))
            }
        }
    }

    private func offset(for slot: Int) -> CGFloat {
        ((CGFloat(slot) - 1.5) + cyclePhase) * step
    }

    private func opacity(for slot: Int) -> Double {
        switch slot {
        case 2: return Double(1 - cyclePhase)  // leading: fades as it slides out
        case 0: return Double(cyclePhase)      // spare: fades in behind
        default: return 1
        }
    }
}
