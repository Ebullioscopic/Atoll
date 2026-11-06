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

import XCTest
@testable import Atoll

/// A track with no timed lyrics available still shows its words, but nothing
/// may claim to know which of them is being sung.
final class UnsyncedLyricsTests: XCTestCase {
    private let body = """
    No smoke with no fire
    No silence if there's no sound

    One way or another
    You're going to put me out
    """

    func testAPlainBodyBecomesOneLinePerLine() {
        let lines = LyricLine.untimedLines(from: body)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines.first?.text, "No smoke with no fire")
        XCTAssertEqual(lines.last?.text, "You're going to put me out")
    }

    func testBlankLinesAreDropped() {
        XCTAssertFalse(LyricLine.untimedLines(from: body).contains { $0.text.isEmpty })
    }

    func testSurroundingWhitespaceIsTrimmed() {
        let lines = LyricLine.untimedLines(from: "   padded line   \n\tanother\t")
        XCTAssertEqual(lines.map(\.text), ["padded line", "another"])
    }

    func testUntimedLinesAreMarkedAsSuch() {
        XCTAssertTrue(LyricLine.untimedLines(from: body).allSatisfy { !$0.isTimed })
    }

    func testAParsedLRCLineIsTimed() {
        XCTAssertTrue(LyricLine(timestamp: 12, text: "sung here").isTimed)
    }

    func testAnEmptyBodyYieldsNothing() {
        XCTAssertTrue(LyricLine.untimedLines(from: "\n\n   \n").isEmpty)
    }

    func testEqualityDistinguishesTimedFromUntimed() {
        XCTAssertNotEqual(
            LyricLine(timestamp: 0, text: "same words", isTimed: true),
            LyricLine(timestamp: 0, text: "same words", isTimed: false)
        )
    }
}

/// Whether the words can be followed at all outranks which pressing they came
/// from, so a row with timings is chosen over a better-matching row without.
final class SyncedLyricsPreferenceTests: XCTestCase {
    private func row(title: String, artist: String, album: String, synced: String?) -> [String: Any] {
        var result: [String: Any] = ["trackName": title, "artistName": artist, "albumName": album]
        if let synced { result["syncedLyrics"] = synced }
        return result
    }

    /// The case that put plain lyrics on screen: an exact album is worth four
    /// points and timings were worth three, so the untimed row used to win.
    func testTimingsBeatAnExactAlbumMatch() {
        let untimedButExact = row(title: "Passenger", artist: "Alex Warren", album: "You'll Be Alright, Kid", synced: nil)
        let timedOtherPressing = row(title: "Passenger", artist: "Alex Warren", album: "Singles", synced: "[00:12.00] a line")

        let best = LyricsSearchResults.bestMatch(
            in: [untimedButExact, timedOtherPressing],
            artist: "Alex Warren",
            title: "Passenger",
            album: "You'll Be Alright, Kid"
        )

        XCTAssertTrue(LyricsSearchResults.carriesSyncedLyrics(best ?? [:]))
    }

    func testAmongTimedRowsTheBetterMatchStillWins() {
        let looseMatch = row(title: "Passenger", artist: "Alex Warren", album: "Compilation", synced: "[00:01.00] a")
        let exactMatch = row(title: "Passenger", artist: "Alex Warren", album: "You'll Be Alright, Kid", synced: "[00:01.00] b")

        let best = LyricsSearchResults.bestMatch(
            in: [looseMatch, exactMatch],
            artist: "Alex Warren",
            title: "Passenger",
            album: "You'll Be Alright, Kid"
        )

        XCTAssertEqual(best?["albumName"] as? String, "You'll Be Alright, Kid")
    }

    func testAnUntimedRowIsStillUsedWhenNothingIsTimed() {
        let only = row(title: "Passenger", artist: "Alex Warren", album: "Singles", synced: nil)
        XCTAssertNotNil(LyricsSearchResults.bestMatch(in: [only], artist: "Alex Warren", title: "Passenger", album: "Singles"))
    }

    func testWhitespaceOnlySyncedLyricsDoNotCount() {
        XCTAssertFalse(LyricsSearchResults.carriesSyncedLyrics(["syncedLyrics": "   \n  "]))
    }
}
