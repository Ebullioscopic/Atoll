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

    /// Whether there is a line to draw at all.
    ///
    /// Checked by the caller too, but kept here so the view is safe to mount on
    /// its own: an out-of-range index would otherwise trap.
    static func hasCurrentLine(index: Int, lineCount: Int) -> Bool {
        index >= 0 && index < lineCount
    }

    private var currentLine: String? {
        guard Self.hasCurrentLine(index: musicManager.currentLyricIndex, lineCount: musicManager.syncedLyrics.count) else {
            return nil
        }
        let text = musicManager.syncedLyrics[musicManager.currentLyricIndex].text
        return text.isEmpty ? nil : text
    }

    private var tint: Color {
        Defaults[.playerColorTinting]
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
            : .gray
    }

    var body: some View {
        if let line = currentLine {
            // Redrawn per frame while playing so the sweep tracks the music,
            // and frozen when paused so a paused notch is not animating.
            TimelineView(.animation(paused: !musicManager.isPlaying)) { timeline in
                SweptLyricText(
                    text: line,
                    fontSize: 11,
                    weight: .medium,
                    progress: musicManager.currentLyricSweepProgress(at: timeline.date),
                    isCurrent: true,
                    sung: .white,
                    unsung: tint.opacity(0.55),
                    idle: .white.opacity(0.5),
                    tint: tint
                )
                .multilineTextAlignment(.center)
                // One line only: a wrapping lyric would grow the strip under
                // the notch from frame to frame as the words change.
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .transition(.opacity.animation(.smooth(duration: 0.25)))
        }
    }
}
