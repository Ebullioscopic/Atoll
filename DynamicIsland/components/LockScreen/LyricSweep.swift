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

/// A lyric line drawn one word at a time, so the highlight travels in reading
/// order instead of wiping straight across the block.
///
/// A single `Text` sweeps as one rectangle: on a line that wraps, the second
/// row lights up level with the first rather than after it, which is nothing
/// like being sung. Laying the words out individually and giving each its own
/// slice of the line's progress fixes that, and reads as word by word.
///
/// The slices come from each word's length, not from real per-word timestamps
/// -- lrclib is line-level only. This is still an estimate; it just estimates
/// in reading order.
struct SweptLyricText: View {
    let text: String
    let fontSize: CGFloat
    let weight: Font.Weight
    let progress: Double
    let isCurrent: Bool
    let sung: Color
    let unsung: Color
    let idle: Color

    /// A word and the stretch of the line's progress that belongs to it.
    private struct Word {
        let text: String
        let start: Double
        let end: Double
    }

    private var words: [Word] {
        let pieces = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !pieces.isEmpty else { return [] }

        // Longer words take longer to sing, near enough. Counting characters
        // rather than measuring pixels keeps the pace even across a wide glyph.
        let weights = pieces.map { Double($0.count) + 1 }
        let total = weights.reduce(0, +)
        guard total > 0 else { return [] }

        var cursor: Double = 0
        return zip(pieces, weights).map { piece, share in
            let start = cursor / total
            cursor += share
            return Word(text: piece, start: start, end: cursor / total)
        }
    }

    var body: some View {
        WordFlowLayout(spacing: spaceWidth, lineSpacing: fontSize * 0.28) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                Text(word.text)
                    .font(.system(size: fontSize, weight: weight))
                    .lyricSweep(
                        progress: localProgress(for: word),
                        isCurrent: isCurrent && localProgress(for: word) > 0,
                        sung: sung,
                        unsung: unsung,
                        idle: isCurrent ? unsung : idle
                    )
            }
        }
    }

    private func localProgress(for word: Word) -> Double {
        let span = word.end - word.start
        guard span > 0 else { return progress >= word.end ? 1 : 0 }
        return min(max((progress - word.start) / span, 0), 1)
    }

    /// The real width of a space in this face, so the words sit where the text
    /// engine would have put them.
    private var spaceWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight.nsWeight)
        return (" " as NSString).size(withAttributes: [.font: font]).width
    }
}

private extension Font.Weight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

/// Wraps its subviews the way text wraps, which is all a line of words needs.
private struct WordFlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                widest = max(widest, x - spacing)
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        widest = max(widest, x - spacing)
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
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
