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

/// The line being sung, under the closed notch, for as long as lyrics are
/// pinned.
///
/// The side panel only exists while the notch is open, so pinning is the only
/// way to keep reading along without holding the pointer over the notch. Only
/// the current line is shown -- there is no room under a closed notch for a
/// list, and the line that matters is the one playing.
///
/// Applied as a modifier rather than added to the notch's stack, because the
/// notch panel sizes itself to its widest child and paints black behind the
/// result. Anything placed in that stack that reports a width -- a sized
/// `Text`, or a `GeometryReader`, which returns whatever width it is offered
/// and so claims the whole screen -- stretches the panel into a full-width
/// slab, and re-centres the music row inside it so the spectrum slides under
/// the physical notch cutout. Padding adds the height, and an overlay draws
/// the words into it: an overlay is proposed its parent's size and never
/// changes it.
struct PinnedLyricsModifier: ViewModifier {
    @ObservedObject private var musicManager = MusicManager.shared

    let isVisible: Bool

    /// One 10pt line, plus the gap between it and the notch body above.
    private static let stripHeight: CGFloat = 13
    private static let stripGap: CGFloat = 4

    private var currentLine: String? {
        guard PinnedLyricsView.hasCurrentLine(
            index: musicManager.currentLyricIndex,
            lineCount: musicManager.syncedLyrics.count
        ) else { return nil }

        let text = musicManager.syncedLyrics[musicManager.currentLyricIndex].text
        return text.isEmpty ? nil : text
    }

    private var isShowing: Bool {
        isVisible && currentLine != nil
    }

    private var tint: Color {
        Defaults[.playerColorTinting]
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
            : .gray
    }

    func body(content: Content) -> some View {
        content
            // Height only. Padding cannot widen the panel, so the music row
            // keeps the width -- and therefore the position -- it had before
            // lyrics were pinned.
            .padding(.bottom, isShowing ? Self.stripHeight + Self.stripGap : 0)
            .overlay(alignment: .bottom) { lyricLine }
            // Height as well as opacity, so the panel grows into the strip
            // rather than jumping taller a frame before the words arrive.
            .animation(.smooth(duration: 0.28), value: isShowing)
            // Separate and quicker: one line replacing another is a smaller
            // event than the strip arriving, and sharing the timing made every
            // line change feel like the panel resizing.
            .animation(.smooth(duration: 0.18), value: currentLine)
    }

    private var lyricLine: some View {
        // Redrawn per frame while playing so the sweep tracks the music, and
        // frozen when paused so a paused notch is not animating.
        TimelineView(.animation(paused: !musicManager.isPlaying)) { timeline in
            // A plain Text swept as one rather than the panel's word-by-word
            // layout: that exists to sweep a wrapped line in reading order,
            // and this is deliberately one line.
            Text(currentLine ?? "")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                // Truncated rather than wrapped: the overlay is only one line
                // tall, and a second row would be clipped.
                .truncationMode(.tail)
                .contentTransition(.opacity)
                .lyricSweep(
                    progress: musicManager.currentLyricSweepProgress(at: timeline.date),
                    isCurrent: true,
                    sung: .white,
                    unsung: tint.opacity(0.55),
                    idle: .white.opacity(0.5)
                )
        }
        .padding(.horizontal, 10)
        .frame(height: Self.stripHeight)
        .padding(.bottom, Self.stripGap)
        .opacity(isShowing ? 1 : 0)
    }
}

extension View {
    /// Draws the line currently being sung under this view, without changing
    /// its width. See `PinnedLyricsModifier`.
    func pinnedLyrics(isVisible: Bool) -> some View {
        modifier(PinnedLyricsModifier(isVisible: isVisible))
    }
}

/// Namespace for the bounds check the modifier and its tests share.
enum PinnedLyricsView {
    /// Whether there is a line to draw at all.
    ///
    /// `-1` is where a track sits before its first timestamp, and the index can
    /// briefly outlive a shorter set of lyrics when a new track's arrive first;
    /// both would trap on the subscript.
    static func hasCurrentLine(index: Int, lineCount: Int) -> Bool {
        index >= 0 && index < lineCount
    }
}
