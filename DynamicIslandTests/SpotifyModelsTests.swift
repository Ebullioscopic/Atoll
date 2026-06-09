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

final class SpotifyModelsTests: XCTestCase {
    func test_decode_playlistsPaging() throws {
        let json = """
        {"items":[{"id":"p1","name":"Chill","uri":"spotify:playlist:p1","images":[{"url":"https://i/x.jpg","width":300,"height":300}],"tracks":{"total":42},"owner":{"display_name":"me"}}],"next":"https://api/next","total":1}
        """.data(using: .utf8)!
        let paging = try JSONDecoder().decode(SpotifyPaging<SpotifyPlaylist>.self, from: json)
        XCTAssertEqual(paging.items.count, 1)
        XCTAssertEqual(paging.items[0].name, "Chill")
        XCTAssertEqual(paging.items[0].uri, "spotify:playlist:p1")
        XCTAssertEqual(paging.items[0].tracks?.total, 42)
        XCTAssertEqual(paging.next, "https://api/next")
    }

    func test_decode_track_toleratesMissingOptionals() throws {
        let json = """
        {"id":"t1","name":"Song","uri":"spotify:track:t1","artists":[{"name":"Artist"}]}
        """.data(using: .utf8)!
        let track = try JSONDecoder().decode(SpotifyTrack.self, from: json)
        XCTAssertEqual(track.name, "Song")
        XCTAssertEqual(track.artists.first?.name, "Artist")
        XCTAssertNil(track.album)
        XCTAssertNil(track.duration_ms)
    }

    func test_decode_searchResponse() throws {
        let json = """
        {"playlists":{"items":[{"id":"p1","name":"Mix","uri":"spotify:playlist:p1","images":[],"tracks":{"total":1},"owner":{"display_name":null}}],"next":null,"total":1},"tracks":{"items":[{"id":"t1","name":"S","uri":"spotify:track:t1","artists":[{"name":"A"}]}],"next":null,"total":1}}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(SpotifySearchResponse.self, from: json)
        XCTAssertEqual(r.playlists?.items.first?.name, "Mix")
        XCTAssertEqual(r.tracks?.items.first?.uri, "spotify:track:t1")
        XCTAssertNil(r.albums)
    }

    func test_libraryItem_fromPlaylist() {
        let p = SpotifyPlaylist(id: "p1", name: "Chill", uri: "spotify:playlist:p1", images: [], tracks: .init(total: 5), owner: .init(display_name: "me"))
        let item = SpotifyLibraryItem(playlist: p)
        XCTAssertEqual(item.id, "spotify:playlist:p1")
        XCTAssertEqual(item.contextURI, "spotify:playlist:p1")
        XCTAssertEqual(item.kind, .playlist)
        XCTAssertEqual(item.subtitle, "5 tracks")
    }

    func test_decode_playlist_nullImages_doesNotThrow() throws {
        let json = """
        {"id":"p1","name":"N","uri":"spotify:playlist:p1","images":null,"tracks":{"total":0},"owner":{"display_name":null}}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(SpotifyPlaylist.self, from: json)
        XCTAssertNil(p.images)
    }

    func test_decode_playlist_missingTracksAndOwner_doesNotThrow() throws {
        // Real /me/playlists payload shape that previously failed: no `tracks`, images null.
        let json = """
        {"id":"01WzDKQXzp47Bb25T4YVuk","name":"Pending","uri":"spotify:playlist:01WzDKQXzp47Bb25T4YVuk","images":null}
        """.data(using: .utf8)!
        let p = try JSONDecoder().decode(SpotifyPlaylist.self, from: json)
        XCTAssertNil(p.tracks)
        XCTAssertNil(p.owner)
        XCTAssertEqual(SpotifyLibraryItem(playlist: p).subtitle, "0 tracks")
    }
}
