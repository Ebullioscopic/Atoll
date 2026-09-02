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

/// Finding the playing track again in NetEase's catalogue from nothing but
/// the metadata a player publishes.
///
/// The bug these guard: NetEase Cloud Music users saw "No lyrics found" for
/// most of their library because LRCLIB never had those songs, and the
/// fallback must not make that worse by scrolling a remix's or a cover's
/// timings past the original.
final class NetEaseLyricsTests: XCTestCase {

    private typealias Song = NetEaseLyrics.Song

    private let original = Song(id: 1, name: "晴天", artists: ["周杰伦"], duration: 269.0)
    private let duet = Song(id: 2, name: "千里之外", artists: ["周杰伦", "费玉清"], duration: 254.5)
    private let remix = Song(id: 3, name: "晴天 (Remix)", artists: ["周杰伦"], duration: 199.0)
    private let cover = Song(id: 4, name: "晴天", artists: ["翻唱歌手"], duration: 268.0)

    // MARK: - Choosing a result

    func testExactTitleAndArtistWins() {
        let match = NetEaseLyrics.bestMatch(in: [cover, original], title: "晴天", artist: "周杰伦", duration: 269)
        XCTAssertEqual(match, original)
    }

    func testSlashJoinedArtistsMatchTheListedOnes() {
        // NetEase publishes "A/B" for a duet; the search result lists A and B.
        let match = NetEaseLyrics.bestMatch(in: [duet], title: "千里之外", artist: "周杰伦/费玉清", duration: 254)
        XCTAssertEqual(match, duet)
    }

    func testWrongArtistIsNotACandidate() {
        XCTAssertNil(NetEaseLyrics.bestMatch(in: [cover], title: "晴天", artist: "周杰伦", duration: 269))
    }

    func testDurationTooFarOffIsNotACandidate() {
        // Same words, a different recording: every line would land late.
        let live = Song(id: 5, name: "晴天", artists: ["周杰伦"], duration: 301.0)
        XCTAssertNil(NetEaseLyrics.bestMatch(in: [live], title: "晴天", artist: "周杰伦", duration: 269))
    }

    func testUnreportedDurationDoesNotReject() {
        XCTAssertEqual(NetEaseLyrics.bestMatch(in: [original], title: "晴天", artist: "周杰伦", duration: 0), original)
        let unknownLength = Song(id: 6, name: "晴天", artists: ["周杰伦"], duration: 0)
        XCTAssertEqual(NetEaseLyrics.bestMatch(in: [unknownLength], title: "晴天", artist: "周杰伦", duration: 269), unknownLength)
    }

    func testCloserDurationBreaksATie() {
        let nearer = Song(id: 7, name: "晴天", artists: ["周杰伦"], duration: 269.4)
        let farther = Song(id: 8, name: "晴天", artists: ["周杰伦"], duration: 270.8)
        XCTAssertEqual(NetEaseLyrics.bestMatch(in: [farther, nearer], title: "晴天", artist: "周杰伦", duration: 269.5), nearer)
    }

    func testUnrequestedRemixIsNotACandidate() {
        XCTAssertNil(NetEaseLyrics.bestMatch(in: [remix], title: "晴天", artist: "周杰伦", duration: 199))
        // Asking for the remix still finds it.
        XCTAssertEqual(NetEaseLyrics.bestMatch(in: [remix], title: "晴天 (Remix)", artist: "周杰伦", duration: 199), remix)
    }

    func testMatchingIgnoresCaseAndDiacritics() {
        let song = Song(id: 9, name: "Déjà Vu", artists: ["Olivia Rodrigo"], duration: 215.0)
        XCTAssertEqual(NetEaseLyrics.bestMatch(in: [song], title: "deja vu", artist: "olivia rodrigo", duration: 215), song)
    }

    // MARK: - Reading responses

    func testSearchResponseParsesSongs() throws {
        let json = """
        {"result":{"songs":[
          {"id":186016,"name":"晴天","artists":[{"id":6452,"name":"周杰伦"}],"duration":269000},
          {"id":186001,"name":"千里之外","artists":[{"name":"周杰伦"},{"name":"费玉清"}],"duration":254533},
          {"name":"no id"}
        ],"songCount":2},"code":200}
        """
        let songs = NetEaseLyrics.parseSearchResponse(Data(json.utf8))
        XCTAssertEqual(songs, [
            Song(id: 186016, name: "晴天", artists: ["周杰伦"], duration: 269.0),
            Song(id: 186001, name: "千里之外", artists: ["周杰伦", "费玉清"], duration: 254.533),
        ])
    }

    func testSearchResponseWithoutSongsIsEmpty() {
        XCTAssertEqual(NetEaseLyrics.parseSearchResponse(Data("{\"result\":{\"songCount\":0},\"code\":200}".utf8)), [])
        XCTAssertEqual(NetEaseLyrics.parseSearchResponse(Data("not json".utf8)), [])
    }

    func testLyricResponseReturnsTheLRCAsServed() {
        let json = """
        {"lrc":{"version":12,"lyric":"[00:00.00] 作词 : 方文山\\n[00:29.65]故事的小黄花\\n"},"code":200}
        """
        XCTAssertEqual(
            NetEaseLyrics.parseLyricResponse(Data(json.utf8)),
            "[00:00.00] 作词 : 方文山\n[00:29.65]故事的小黄花"
        )
    }

    func testLyricResponseWithNoLyricsIsNil() {
        XCTAssertNil(NetEaseLyrics.parseLyricResponse(Data("{\"nolyric\":true,\"lrc\":{\"lyric\":\"[99:00.00]纯音乐，请欣赏\"}}".utf8)))
        XCTAssertNil(NetEaseLyrics.parseLyricResponse(Data("{\"uncollected\":true,\"lrc\":{\"lyric\":\"\"}}".utf8)))
        XCTAssertNil(NetEaseLyrics.parseLyricResponse(Data("{\"lrc\":{\"lyric\":\"  \\n\"}}".utf8)))
        XCTAssertNil(NetEaseLyrics.parseLyricResponse(Data("{\"code\":404}".utf8)))
    }

    // MARK: - Building requests

    func testSearchQueryEscapesStructuralCharacters() throws {
        let url = try XCTUnwrap(NetEaseLyrics.searchURL(title: "Snow + Rain & Sun", artist: "A/B"))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "s" }?.value, "Snow + Rain & Sun A B")
        XCTAssertEqual(query.first { $0.name == "type" }?.value, "1")
    }

    func testEmptyQueryBuildsNoRequest() {
        XCTAssertNil(NetEaseLyrics.searchURL(title: "  ", artist: ""))
    }
}
