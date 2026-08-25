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

/// Picking a row out of an lrclib search response.
final class LyricsSearchResultsTests: XCTestCase {

    private func result(
        title: String,
        artist: String,
        album: String = "",
        synced: String = "[00:01.00] la"
    ) -> [String: Any] {
        [
            "trackName": title,
            "artistName": artist,
            "albumName": album,
            "syncedLyrics": synced
        ]
    }

    // MARK: - Accented fields

    /// The request is folded to "Beyonce" before it is sent, but lrclib answers
    /// "Beyoncé". Folding one side only used to reject the correct lyrics.
    func testAccentedResultFieldsStillMatchAFoldedRequest() {
        let results = [result(title: "If I Were a Boy", artist: "Beyoncé")]

        XCTAssertNotNil(
            LyricsSearchResults.bestMatch(in: results, artist: "Beyonce", title: "If I Were a Boy", album: "")
        )
    }

    func testAccentsAreFoldedInBothDirections() {
        let results = [result(title: "Déjà Vu", artist: "Olivia Rodrigo")]

        XCTAssertNotNil(
            LyricsSearchResults.bestMatch(in: results, artist: "Olivia Rodrigo", title: "Deja Vu", album: "")
        )
        XCTAssertNotNil(
            LyricsSearchResults.bestMatch(in: results, artist: "Olivia Rodrigo", title: "Déjà Vu", album: "")
        )
    }

    // MARK: - Filter before ranking

    /// A wrong artist can outscore a right one: an exact title, an exact album
    /// and synced lyrics beat an artist matched only by containment. Ranking
    /// first and checking the winner afterwards threw the good row away.
    func testAHighScoringWrongArtistDoesNotHideAValidResult() {
        let results = [
            result(title: "Crimewave", artist: "HEALTH", album: "Crimewave EP"),
            result(title: "Crimewave", artist: "Crystal Castles (Alice Glass)", album: "")
        ]

        let match = LyricsSearchResults.bestMatch(
            in: results,
            artist: "Crystal Castles",
            title: "Crimewave",
            album: "Crimewave EP"
        )

        XCTAssertEqual(match?["artistName"] as? String, "Crystal Castles (Alice Glass)")
    }

    // MARK: - The floor

    func testAResultAgreeingOnNeitherFieldIsRefused() {
        let results = [result(title: "Some Other Song", artist: "Another Band")]

        XCTAssertNil(
            LyricsSearchResults.bestMatch(in: results, artist: "Crystal Castles", title: "Crimewave", album: "")
        )
    }

    /// Agreeing on the title alone is how covers and karaoke versions get in.
    func testATitleOnlyAgreementIsRefused() {
        let results = [result(title: "Crimewave", artist: "Karaoke Hits Vol 3")]

        XCTAssertNil(
            LyricsSearchResults.bestMatch(in: results, artist: "Crystal Castles", title: "Crimewave", album: "")
        )
    }

    /// Nothing filters on the album, so an empty one must simply score
    /// nothing rather than earning a containment bonus against an empty needle.
    func testAnEmptyAlbumEarnsNoBonus() {
        let withAlbum = result(title: "Crimewave", artist: "Crystal Castles", album: "Crimewave EP")
        let withoutAlbum = result(title: "Crimewave", artist: "Crystal Castles", album: "")

        let match = LyricsSearchResults.bestMatch(
            in: [withoutAlbum, withAlbum],
            artist: "Crystal Castles",
            title: "Crimewave",
            album: "Crimewave EP"
        )

        XCTAssertEqual(match?["albumName"] as? String, "Crimewave EP")
        XCTAssertGreaterThan(
            LyricsSearchResults.score(for: withAlbum, artist: "crystal castles", title: "crimewave", album: "crimewave ep"),
            LyricsSearchResults.score(for: withoutAlbum, artist: "crystal castles", title: "crimewave", album: "crimewave ep")
        )
    }

    // MARK: - Version variants

    /// The words are right but the timings are not, so these drift.
    func testUnrequestedVersionVariantsAreRefused() {
        for variant in [
            "Crimewave (Karaoke Version)",
            "Crimewave (Sped Up)",
            "Crimewave - Nightcore",
            "Crimewave (Slowed + Reverb)",
            "Crimewave (Instrumental)",
            "Crimewave (Bloody Beetroots Remix)",
            "Crimewave (Remixed)",
            "Crimewave (Re-Recorded)",
            "Crimewave (Rerecorded)",
            "Crimewave (Re-Recording)",
            "Crimewave (Taylor's Version)",
            "Crimewave (Acapella)"
        ] {
            XCTAssertNil(
                LyricsSearchResults.bestMatch(
                    in: [result(title: variant, artist: "Crystal Castles")],
                    artist: "Crystal Castles",
                    title: "Crimewave",
                    album: ""
                ),
                "\(variant) has different timings than the requested track"
            )
        }
    }

    /// Playing the sped-up version should still find the sped-up lyrics.
    func testARequestedVariantStillMatches() {
        let results = [result(title: "Crimewave (Sped Up)", artist: "Crystal Castles")]

        XCTAssertNotNil(
            LyricsSearchResults.bestMatch(in: results, artist: "Crystal Castles", title: "Crimewave (Sped Up)", album: "")
        )
    }

    /// The request has remaster, live, mono and stereo stripped before it gets
    /// here, so those must not be treated as markers.
    func testStrippedSuffixesAreNotTreatedAsVariants() {
        for suffix in ["Crimewave (Remastered)", "Crimewave (Live)", "Crimewave (Mono)", "Crimewave - 2011 Remaster"] {
            XCTAssertNotNil(
                LyricsSearchResults.bestMatch(
                    in: [result(title: suffix, artist: "Crystal Castles")],
                    artist: "Crystal Castles",
                    title: "Crimewave",
                    album: ""
                ),
                "\(suffix) is what the request was stripped to find"
            )
        }
    }

    /// A marker covers its own inflections, because only the leading boundary
    /// is anchored.
    func testMarkersMatchTheirInflections() {
        for variant in ["Crimewave (Remixes)", "Crimewave (Re-Recorded Version)", "Crimewave (Karaoke)"] {
            XCTAssertNil(
                LyricsSearchResults.bestMatch(
                    in: [result(title: variant, artist: "Crystal Castles")],
                    artist: "Crystal Castles",
                    title: "Crimewave",
                    album: ""
                ),
                "\(variant) is still a variant"
            )
        }
    }

    /// A bare "version" is not a marker: "(Album Version)" is just the track.
    func testAlbumAndSingleVersionsAreNotVariants() {
        for title in ["Crimewave (Album Version)", "Crimewave (Single Version)"] {
            XCTAssertNotNil(
                LyricsSearchResults.bestMatch(
                    in: [result(title: title, artist: "Crystal Castles")],
                    artist: "Crystal Castles",
                    title: "Crimewave",
                    album: ""
                ),
                "\(title) is the track itself"
            )
        }
    }

    /// Whole-word matching, so a real title is not caught by a substring.
    func testTitlesContainingMarkerSubstringsSurvive() {
        for title in ["Undercover Martyn", "Coverdale Blues", "Live and Let Die"] {
            XCTAssertNotNil(
                LyricsSearchResults.bestMatch(
                    in: [result(title: title, artist: "Some Artist")],
                    artist: "Some Artist",
                    title: title,
                    album: ""
                ),
                "\(title) is a real title"
            )
        }
    }

    /// The plain row still wins when both exist -- the variant guard is only
    /// load-bearing when the variant is all there is.
    func testThePlainRowIsPreferredOverAVariant() {
        let results = [
            result(title: "Crimewave (Sped Up)", artist: "Crystal Castles"),
            result(title: "Crimewave", artist: "Crystal Castles")
        ]

        let match = LyricsSearchResults.bestMatch(in: results, artist: "Crystal Castles", title: "Crimewave", album: "")
        XCTAssertEqual(match?["trackName"] as? String, "Crimewave")
    }

    func testEmptyResultsYieldNoMatch() {
        XCTAssertNil(
            LyricsSearchResults.bestMatch(in: [], artist: "Crystal Castles", title: "Crimewave", album: "")
        )
    }
}
