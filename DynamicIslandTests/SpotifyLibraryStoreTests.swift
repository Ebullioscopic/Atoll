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

private final class StoreMockAPI: SpotifyAPI {
    var playlists: [SpotifyPlaylist] = []
    var recents: [SpotifyPlayHistoryItem] = []
    var searchResp = SpotifySearchResponse(playlists: nil, albums: nil, tracks: nil)
    func currentUserPlaylists(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyPlaylist> { .init(items: playlists, next: nil, total: playlists.count) }
    func playlistTracks(playlistID: String, limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack> { .init(items: [], next: nil, total: 0) }
    func savedTracks(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack> { .init(items: [], next: nil, total: 0) }
    func recentlyPlayed(limit: Int) async throws -> [SpotifyPlayHistoryItem] { recents }
    func search(query: String, types: [SpotifySearchType], limit: Int) async throws -> SpotifySearchResponse { searchResp }
    func availableDevices() async throws -> [SpotifyDevice] { [] }
    func startPlayback(contextURI: String?, uris: [String]?, offsetURI: String?, deviceID: String?) async throws {}
    func setShuffle(_ on: Bool, deviceID: String?) async throws {}
}

@MainActor
final class SpotifyLibraryStoreTests: XCTestCase {
    func test_loadHome_populatesPlaylists() async {
        let api = StoreMockAPI()
        api.playlists = [SpotifyPlaylist(id: "p1", name: "A", uri: "spotify:playlist:p1", images: [], tracks: .init(total: 3), owner: .init(display_name: nil))]
        let store = SpotifyLibraryStore(api: api)
        await store.loadHome()
        XCTAssertEqual(store.playlists.map(\.title), ["A"])
        XCTAssertFalse(store.isLoading)
    }

    func test_search_groupsResults() async {
        let api = StoreMockAPI()
        api.searchResp = SpotifySearchResponse(
            playlists: .init(items: [SpotifyPlaylist(id: "p1", name: "Mix", uri: "spotify:playlist:p1", images: [], tracks: .init(total: 1), owner: .init(display_name: nil))], next: nil, total: 1),
            albums: nil,
            tracks: .init(items: [SpotifyTrack(id: "t1", name: "S", uri: "spotify:track:t1", artists: [.init(name: "Ar")], album: nil, duration_ms: nil)], next: nil, total: 1))
        let store = SpotifyLibraryStore(api: api)
        await store.performSearch("mix")
        XCTAssertEqual(store.searchResults.playlists.map(\.title), ["Mix"])
        XCTAssertEqual(store.searchResults.tracks.map(\.name), ["S"])
    }

    func test_clearSearch_emptiesResults() async {
        let api = StoreMockAPI()
        api.searchResp = SpotifySearchResponse(
            playlists: .init(items: [SpotifyPlaylist(id: "p1", name: "Mix", uri: "spotify:playlist:p1", images: [], tracks: .init(total: 1), owner: .init(display_name: nil))], next: nil, total: 1),
            albums: nil, tracks: nil)
        let store = SpotifyLibraryStore(api: api)
        await store.performSearch("x")
        XCTAssertFalse(store.searchResults.isEmpty, "precondition: results populated")
        store.clearSearch()
        XCTAssertTrue(store.searchResults.isEmpty)
    }

    func test_loadHome_recentlyPlayed_mapsContextTypeToKind() async {
        let api = StoreMockAPI()
        let track = SpotifyTrack(id: "t", name: "T", uri: "spotify:track:t", artists: [.init(name: "A")], album: nil, duration_ms: nil)
        api.recents = [
            SpotifyPlayHistoryItem(track: track, context: .init(uri: "spotify:album:al", type: "album")),
            SpotifyPlayHistoryItem(track: track, context: .init(uri: "spotify:playlist:pl", type: "playlist")),
        ]
        let store = SpotifyLibraryStore(api: api)
        await store.loadHome()
        let byURI = Dictionary(uniqueKeysWithValues: store.recentlyPlayed.map { ($0.contextURI, $0.kind) })
        XCTAssertEqual(byURI["spotify:album:al"], .album)
        XCTAssertEqual(byURI["spotify:playlist:pl"], .playlist)
    }
}
