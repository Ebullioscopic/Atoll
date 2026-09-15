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

/// The volume control from the iOS Now Playing screen: a capsule that
/// fills from the leading edge, flanked by a quiet and a loud speaker glyph,
/// which swells while it is being dragged and settles back when released.
///
/// Deliberately not a `Slider`. The stock control draws a thumb and a thin
/// track, which reads as a form field next to the transport buttons; the point
/// here is a single soft bar you can shove anywhere along its length.
struct VolumeCapsuleSlider: View {
    @Binding var value: Double
    /// Foreground colour of the surface this is drawn on — white over the
    /// lock-screen glass, black over a light one.
    let tint: Color
    let compact: Bool
    var onEditingChanged: ((Bool) -> Void)?

    @State private var isDragging = false
    @State private var isHovering = false

    private var trackHeight: CGFloat { compact ? 10 : 13 }
    private var glyphSize: CGFloat { compact ? 10 : 11.5 }

    /// Whether the control is being touched -- hovered or dragged.
    private var isEngaged: Bool { isDragging || isHovering }

    /// Apple leaves the volume bar grey until you reach for it, and only then
    /// gives it full colour and full brightness. Resting at full strength made
    /// it compete with the artwork it sits under.
    private var trackSaturation: Double { isEngaged ? 1 : 0 }
    private var fillOpacity: Double { isDragging ? 1 : (isHovering ? 0.8 : 0.55) }

    /// iOS dims the glyph you are moving away from and lights the one you are
    /// moving toward, so the pair reads as a scale rather than decoration.
    private var quietGlyphOpacity: Double { 0.3 + (1 - fraction) * 0.55 }
    private var loudGlyphOpacity: Double { 0.3 + fraction * 0.55 }

    private var quietGlyphName: String {
        fraction <= 0.001 ? "speaker.slash.fill" : "speaker.fill"
    }

    private var fraction: Double { min(max(value, 0), 1) }

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: quietGlyphName)
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(tint.opacity(quietGlyphOpacity))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: glyphSize + 4, alignment: .leading)

            track

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(tint.opacity(loudGlyphOpacity))
                .frame(width: glyphSize + 4, alignment: .trailing)
        }
        .animation(.easeOut(duration: 0.2), value: fraction)
        .saturation(trackSaturation)
        .animation(.easeOut(duration: 0.2), value: trackSaturation)
        .animation(.easeOut(duration: 0.2), value: fillOpacity)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(round(fraction * 100)))%")
        .accessibilityAdjustableAction { direction in
            let step = 1.0 / 16.0
            switch direction {
            case .increment: value = min(value + step, 1)
            case .decrement: value = max(value - step, 0)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // Never let the fill collapse to nothing: iOS keeps a rounded nub
            // at zero so the control still reads as a control.
            let filled = max(trackHeight, width * fraction)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(tint.opacity(isEngaged ? 0.22 : 0.14))

                Capsule(style: .continuous)
                    .fill(tint.opacity(fillOpacity))
                    .frame(width: filled)
            }
            .frame(height: trackHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                isDragging = true
                            }
                            onEditingChanged?(true)
                        }
                        update(to: gesture.location.x, width: width)
                    }
                    .onEnded { gesture in
                        update(to: gesture.location.x, width: width)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                            isDragging = false
                        }
                        onEditingChanged?(false)
                    }
            )
        }
        .frame(height: trackHeight)
        // The swell is vertical only — growing it horizontally would move the
        // point under the finger away from the value it is setting.
        .scaleEffect(x: 1, y: isDragging ? 1.14 : 1, anchor: .center)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isDragging)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHovering = hovering
            }
        }
    }

    /// Sets the volume from a horizontal position within the capsule.
    ///
    /// - Parameters:
    ///   - x: Distance from the capsule's leading edge, in points. Positions
    ///     outside the capsule are clamped rather than ignored, so a drag that
    ///     runs off either end pins the volume to that end instead of sticking.
    ///   - width: The capsule's width. A zero width would divide by nothing, and
    ///     happens on the first layout pass before the frame is known.
    private func update(to x: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        value = min(max(Double(x / width), 0), 1)
    }
}
