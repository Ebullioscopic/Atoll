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
struct PinnedLyricsView: View {
    @ObservedObject private var musicManager = MusicManager.shared

    /// Whether the strip should be showing at all.
    ///
    /// Passed in rather than branched on by the caller so the view is always
    /// mounted: an `if` in the caller inserts and removes it outright, and the
    /// strip pops in and out with nothing to animate.
    let isVisible: Bool

    /// Whether there is a line to draw at all.
    ///
    /// Checked here rather than only by the caller so the view is safe to
    /// mount on its own: an out-of-range index would otherwise trap.
    static func hasCurrentLine(index: Int, lineCount: Int) -> Bool {
        index >= 0 && index < lineCount
    }

    /// One 10pt line and no taller. The GeometryReader below has no intrinsic
    /// height, so without this the strip collapses.
    private static let stripHeight: CGFloat = 13

    private var currentLine: String? {
        guard Self.hasCurrentLine(index: musicManager.currentLyricIndex, lineCount: musicManager.syncedLyrics.count) else {
            return nil
        }
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

    var body: some View {
        // A GeometryReader, like the music sneak peek under the notch uses.
        //
        // It reports no width of its own and simply fills what it is offered,
        // so the strip cannot widen the closed notch panel. A plain sized Text
        // here did: the panel sizes to its widest child, so a long lyric
        // stretched it, and the music row -- being narrower -- was then centred
        // inside that wider panel, which slid the spectrum under the physical
        // notch cutout.
        GeometryReader { geometry in
            // Redrawn per frame while playing so the sweep tracks the music,
            // and frozen when paused so a paused notch is not animating.
            TimelineView(.animation(paused: !musicManager.isPlaying)) { timeline in
                // A plain Text swept as one rather than the panel's
                // word-by-word layout: that exists to sweep a wrapped line in
                // reading order, and this is deliberately one line.
                Text(currentLine ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    // Truncated rather than wrapped: a second row would grow
                    // the panel downwards from lyric to lyric.
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                    .lyricSweep(
                        progress: musicManager.currentLyricSweepProgress(at: timeline.date),
                        isCurrent: true,
                        sung: .white,
                        unsung: tint.opacity(0.55),
                        idle: .white.opacity(0.5)
                    )
                    .frame(width: max(0, geometry.size.width - 16), alignment: .center)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        // Height as well as opacity, so the notch panel grows into the strip
        // instead of jumping taller a frame before the words arrive.
        .frame(height: isShowing ? Self.stripHeight : 0)
        .opacity(isShowing ? 1 : 0)
        .padding(.bottom, isShowing ? 4 : 0)
        .clipped()
        .animation(.smooth(duration: 0.28), value: isShowing)
        // Separate and quicker: one line replacing another is a smaller event
        // than the strip arriving, and sharing the timing made every line
        // change feel like the panel resizing.
        .animation(.smooth(duration: 0.18), value: currentLine)
    }
}
