//
//  SyncedLyricsList.swift
//  DynamicIsland
//
//  The scrolling, swept lyrics list shared by the notch's lyrics tab and the
//  expanded lock screen player, so the two cannot drift apart in how they
//  decide what a row is or which one is current.
//

import SwiftUI

/// A row in the lyrics list: either a sung line or a stretch of music with no
/// words, which is shown as a note rather than as blank space.
enum LyricRow: Identifiable {
    case line(index: Int, text: String)
    case instrumental(index: Int)

    /// The index into `syncedLyrics` this row is driven by, which is also what
    /// the scroll position and the current-line highlight key off.
    var index: Int {
        switch self {
        case let .line(index, _), let .instrumental(index): return index
        }
    }

    var id: Int { index }
}

enum SyncedLyricsRows {
    /// Gaps shorter than this are breaths between lines, not instrumental
    /// breaks, and showing a note for them would flicker.
    ///
    /// Read from `MusicManager` rather than restated here. The manager decides
    /// whether playback is *in* a break and this decides which rows are drawn
    /// as one; two copies of the number would let the notes on screen and the
    /// state behind them disagree about what counts as a break.
    static var instrumentalGapThreshold: TimeInterval { MusicManager.instrumentalBreakThreshold }

    /// Builds the display rows, inserting an instrumental marker wherever the
    /// track goes long enough without words.
    ///
    /// LRC marks where singing stops with a bare timestamp, so a gap is the
    /// stretch between such a marker and the next line. The run-up to the first
    /// line is treated the same way, which is what covers a song's intro.
    static func rows(for lines: [LyricLine], duration: TimeInterval) -> [LyricRow] {
        var rows: [LyricRow] = []

        // An intro long enough to sit through gets a marker of its own, keyed to
        // -1 -- the index the current line holds before the first line starts.
        // Decided from the first timestamp alone: keying it off "nothing added
        // yet" missed the case where the first entry is itself a qualifying gap
        // marker, which claims the first row and leaves the intro without one.
        if let first = lines.first, first.timestamp >= instrumentalGapThreshold {
            rows.append(.instrumental(index: -1))
        }

        for (index, lyric) in lines.enumerated() {
            let isBlank = lyric.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if isBlank {
                let end = index + 1 < lines.count ? lines[index + 1].timestamp : duration
                if end - lyric.timestamp >= instrumentalGapThreshold {
                    rows.append(.instrumental(index: index))
                }
                continue
            }

            rows.append(.line(index: index, text: lyric.text))
        }

        return rows
    }
}

/// The colours and metrics a host gives the list, so the notch and the lock
/// screen can look like themselves while sharing the behaviour.
struct SyncedLyricsStyle {
    var fontSize: CGFloat = 14
    var currentFontSize: CGFloat?
    var lineSpacing: CGFloat = 8
    var lineLimit: Int = 2
    /// The note glyphs read as decoration rather than as words, so they stay
    /// smaller than the surrounding text.
    var instrumentalFontSize: CGFloat = 12
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 4
    /// Colour a line has already been sung in.
    var sung: Color = .white
    /// Colour the remainder of the current line is drawn in.
    var unsung: Color
    /// Colour every line that is not the current one is drawn in.
    var idle: Color
    /// Shown when the track has no synced lyrics at all.
    var placeholder: String = "Show lyrics here"
}

struct SyncedLyricsList: View {
    @ObservedObject var musicManager = MusicManager.shared
    let style: SyncedLyricsStyle

    @State private var lyrics: [LyricRow] = []

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                if lyrics.isEmpty {
                    Text(musicManager.currentLyrics.isEmpty ? style.placeholder : musicManager.currentLyrics)
                        .font(.system(size: style.fontSize, weight: .medium))
                        .foregroundStyle(style.idle)
                        .padding(.horizontal, style.horizontalPadding)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Redraw on every frame while playing so the highlight
                    // tracks the music instead of stepping line by line.
                    TimelineView(.animation(paused: !musicManager.isPlaying)) { timeline in
                        let current = musicManager.currentLyricIndex
                        let progress = musicManager.currentLyricSweepProgress(at: timeline.date)

                        LazyVStack(alignment: .leading, spacing: style.lineSpacing) {
                            ForEach(lyrics) { row in
                                // Padding inside the width claim, not outside
                                // it: the other order made each row the full
                                // column wide *plus* its own insets, so long
                                // lines ran off the panel instead of wrapping.
                                lyricRow(row, isCurrent: row.index == current, progress: progress)
                                    .padding(.horizontal, style.horizontalPadding)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(row.index)
                            }
                        }
                        .padding(.vertical, style.verticalPadding)
                    }
                }
            }
            .scrollIndicators(.never)
            .onAppear {
                lyrics = SyncedLyricsRows.rows(for: musicManager.syncedLyrics, duration: musicManager.songDuration)
                // Nothing to animate away from: the list has only just appeared.
                DispatchQueue.main.async {
                    scroll(proxy, to: musicManager.currentLyricIndex, animated: false)
                }
            }
            .onChange(of: musicManager.currentLyricIndex) { _, index in
                scroll(proxy, to: index, animated: true)
            }
            // Inside the reader, not outside it. Out there these two had no
            // proxy to scroll with, so a new track rebuilt the rows underneath
            // a list still parked wherever the last one had scrolled it to.
            .onChange(of: musicManager.syncedLyrics) { _, newLyrics in
                lyrics = SyncedLyricsRows.rows(for: newLyrics, duration: musicManager.songDuration)
                // The rows have to exist before anything can be scrolled to
                // them, and they are only built on the line above.
                DispatchQueue.main.async {
                    scroll(proxy, to: musicManager.currentLyricIndex, animated: false)
                }
            }
            .onChange(of: musicManager.songDuration) { _, duration in
                // Duration closes the last line's window, so a trailing outro is only
                // marked once it is known -- and it can arrive after the lyrics do.
                lyrics = SyncedLyricsRows.rows(for: musicManager.syncedLyrics, duration: duration)
            }
        }
    }

    /// Brings the row for `index` into view.
    ///
    /// Not every index has a row of its own. A blank LRC marker too short to
    /// count as an instrumental break has none, and neither does -1 -- the
    /// index a track sits at before its first line -- unless the track opens
    /// with an intro long enough to be marked with notes.
    ///
    /// Mid-track a missing row means staying put, because the words on screen
    /// are still the right ones. Before the first line it means going to the
    /// top, and that is the case that was broken: the guard simply gave up, so
    /// whether a new song rewound the list came down to whether it happened to
    /// open with a long enough intro to have earned a marker.
    private func scroll(_ proxy: ScrollViewProxy, to index: Int, animated: Bool) {
        let target: Int?
        if lyrics.contains(where: { $0.index == index }) {
            target = index
        } else if index < 0 {
            target = lyrics.first?.index
        } else {
            target = nil
        }

        guard let target else { return }

        guard animated else {
            proxy.scrollTo(target, anchor: .center)
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    @ViewBuilder
    private func lyricRow(_ row: LyricRow, isCurrent: Bool, progress: Double) -> some View {
        let size = isCurrent ? (style.currentFontSize ?? style.fontSize) : style.fontSize

        switch row {
        case let .line(_, text):
            // Word by word rather than one sweep across the whole block: a line
            // that wraps used to light its second row level with its first,
            // since a gradient over a two-line Text runs straight down both.
            SweptLyricText(
                text: text,
                fontSize: size,
                weight: isCurrent ? .semibold : .regular,
                progress: progress,
                isCurrent: isCurrent,
                sung: style.sung,
                unsung: style.unsung,
                idle: style.idle
            )

        case .instrumental:
            swept(isCurrent: isCurrent, progress: progress) {
                InstrumentalBreakNotes(
                    fontSize: style.instrumentalFontSize,
                    weight: isCurrent ? .semibold : .regular
                )
            }
        }
    }

    @ViewBuilder
    private func swept<Content: View>(
        isCurrent: Bool,
        progress: Double,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .lyricSweep(
                progress: progress,
                isCurrent: isCurrent,
                sung: style.sung,
                unsung: style.unsung,
                idle: style.idle
            )
    }
}
