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

import AppKit
import Defaults
import SwiftUI

/// Height-only padding plus an overlay: lyrics never report an intrinsic width
/// to the closed notch's stack. Keep this invariant when changing rendering.
struct PinnedLyricsModifier: ViewModifier {
    @ObservedObject private var musicManager = MusicManager.shared
    @Default(.pinnedLyricContext) private var context
    let isVisible: Bool
    let isContentHidden: Bool

    private var tint: Color {
        Defaults[.playerColorTinting]
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
            : .gray
    }

    func body(content: Content) -> some View {
        let height = PinnedLyricsView.reservedHeight(isEligible: isVisible,
            availability: musicManager.lyricsAvailability, context: context)
        content
            .padding(.bottom, height)
            .overlay(alignment: .bottom) {
                if height > 0 {
                    lyricRows
                        .opacity(isContentHidden ? 0 : 1)
                        .accessibilityHidden(isContentHidden)
                }
            }
            .animation(.smooth(duration: 0.28), value: height)
    }

    private var lyricRows: some View {
        let slots = PinnedLyricsContextRows.slots(lines: musicManager.syncedLyrics,
            duration: musicManager.songDuration, currentIndex: musicManager.currentLyricIndex,
            context: context)
        return TimelineView(.animation(paused: !musicManager.isPlaying || isContentHidden)) { timeline in
            VStack(spacing: 0) {
                ForEach(slots.indices, id: \.self) { index in
                    let slot = slots[index]
                    Text(slot.text)
                        .font(.system(size: PinnedLyricsView.fontSize, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentTransition(.opacity)
                        .lyricSweep(
                            progress: musicManager.currentLyricSweepProgress(at: timeline.date),
                            isCurrent: slot.isCurrent,
                            sung: .white,
                            unsung: tint.opacity(0.55),
                            idle: .white.opacity(0.45)
                        )
                        .frame(height: PinnedLyricsView.rowHeight)
                }
            }
            .animation(.smooth(duration: 0.18), value: slots)
        }
        .padding(.horizontal, 10)
        .frame(height: PinnedLyricsView.rowHeight * CGFloat(context.rawValue))
        .padding(.bottom, PinnedLyricsView.gap)
        .clipped()
    }
}

extension View {
    func pinnedLyrics(isVisible: Bool, isContentHidden: Bool = false) -> some View {
        modifier(PinnedLyricsModifier(isVisible: isVisible, isContentHidden: isContentHidden))
    }
}

enum PinnedLyricsView {
    static let fontSize: CGFloat = 10
    static let gap: CGFloat = 4
    static let rowHeight: CGFloat = {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        return (font.ascender - font.descender + font.leading).rounded(.up) + 1
    }()

    static func shouldReserve(lyricsEnabled: Bool, pinEnabled: Bool,
                              surfaceEligible: Bool, availability: LyricsAvailability) -> Bool {
        lyricsEnabled && pinEnabled && surfaceEligible && availability == .timed
    }

    /// Deliberately takes no current index, current text, or HUD state.
    static func reservedHeight(isEligible: Bool, availability: LyricsAvailability,
                               context: PinnedLyricContext) -> CGFloat {
        isEligible && availability == .timed ? rowHeight * CGFloat(context.rawValue) + gap : 0
    }
}
