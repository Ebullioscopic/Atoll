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

/// The line between metadata that identifies a song and metadata that only
/// looks like it does.
///
/// The bug these guard: an untagged rip reported itself as "Track 7" by
/// "Unknown artist", lrclib returned twenty *different* songs filed under
/// exactly that title and artist, and the winner scrolled Beyoncé's lyrics
/// past an unrelated track.
final class LyricsMetadataTests: XCTestCase {

    // MARK: - Metadata that names nothing

    func testUnknownArtistNamesNoParticularTrack() {
        XCTAssertTrue(LyricsMetadata.namesNoParticularTrack(title: "Track 7", artist: "Unknown artist"))
        XCTAssertTrue(LyricsMetadata.namesNoParticularTrack(title: "Sweet Dreams", artist: "Unknown Artist"))
        XCTAssertTrue(LyricsMetadata.namesNoParticularTrack(title: "Sweet Dreams", artist: "  UNKNOWN  "))
    }

    func testNumberedTitlesNameAPositionNotASong() {
        for title in ["Track 7", "track7", "Track_02", "Audio Track 3", "Untitled 4"] {
            XCTAssertTrue(
                LyricsMetadata.namesNoParticularTrack(title: title, artist: "Crystal Castles"),
                "\(title) is a position on a disc, not a song"
            )
        }
    }

    func testEmptyFieldsNameNoParticularTrack() {
        XCTAssertTrue(LyricsMetadata.namesNoParticularTrack(title: "", artist: "Crystal Castles"))
        XCTAssertTrue(LyricsMetadata.namesNoParticularTrack(title: "Crimewave", artist: ""))
        XCTAssertTrue(LyricsMetadata.namesNoParticularTrack(title: "   ", artist: "   "))
    }

    // MARK: - Metadata that does name something

    func testRealMetadataIsLookedUp() {
        XCTAssertFalse(LyricsMetadata.namesNoParticularTrack(title: "Crimewave", artist: "Crystal Castles"))
        XCTAssertFalse(LyricsMetadata.namesNoParticularTrack(title: "If I Were a Boy", artist: "Beyoncé"))
    }

    /// "Untitled" is a title an artist chose, and the artist identifies it.
    /// Only "Untitled 4" -- a position again -- is refused.
    func testNamedUntitledTracksSurvive() {
        XCTAssertFalse(LyricsMetadata.namesNoParticularTrack(title: "Untitled", artist: "Interpol"))
        XCTAssertTrue(LyricsMetadata.namesNoParticularTrack(title: "Untitled 4", artist: "Interpol"))
    }

    /// Real songs whose titles merely contain a number must not be caught by
    /// the anchored patterns.
    func testTitlesContainingNumbersSurvive() {
        for title in ["Track 7 Blues", "1979", "99 Problems", "22", "Soundtrack 2 My Life"] {
            XCTAssertFalse(
                LyricsMetadata.namesNoParticularTrack(title: title, artist: "Smashing Pumpkins"),
                "\(title) is a real title"
            )
        }
    }
}
