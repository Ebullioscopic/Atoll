/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI

/// The highlight that travels across a lyric line as it is sung.
enum LyricSweep {
    /// Half-width of the soft edge between sung and unsung, as a fraction of the
    /// line. A hard boundary reads as a wipe rather than as singing.
    private static let feather = 0.06

    static func gradient(progress: Double, sung: Color, unsung: Color) -> LinearGradient {
        let clamped = min(max(progress, 0), 1)
        return LinearGradient(
            stops: [
                .init(color: sung, location: 0),
                .init(color: sung, location: max(0, clamped - feather)),
                .init(color: unsung, location: min(1, clamped + feather)),
                .init(color: unsung, location: 1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private struct LyricSweepModifier: ViewModifier {
    let progress: Double
    let isCurrent: Bool
    let sung: Color
    let unsung: Color
    let idle: Color

    func body(content: Content) -> some View {
        if isCurrent {
            // Overlaid and masked rather than handed to foregroundStyle: a gradient
            // used as a foreground style is resolved against each leaf view's own
            // bounds, so a line built from several glyphs gets the whole gradient
            // repeated inside every one of them and none of them appear to sweep.
            content
                .hidden()
                .overlay { LyricSweep.gradient(progress: progress, sung: sung, unsung: unsung) }
                .mask { content }
        } else {
            content.foregroundStyle(idle)
        }
    }
}

extension View {
    /// Paints this view with the sweep when it is the current line, or dims it.
    func lyricSweep(
        progress: Double,
        isCurrent: Bool,
        sung: Color = .white,
        unsung: Color,
        idle: Color
    ) -> some View {
        modifier(
            LyricSweepModifier(
                progress: progress,
                isCurrent: isCurrent,
                sung: sung,
                unsung: unsung,
                idle: idle
            )
        )
    }
}

/// The three notes shown where a track carries on without words.
struct InstrumentalBreakNotes: View {
    var fontSize: CGFloat = 12
    var weight: Font.Weight = .semibold

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                Image(systemName: "music.note")
                    .font(.system(size: fontSize, weight: weight))
            }
        }
    }
}
