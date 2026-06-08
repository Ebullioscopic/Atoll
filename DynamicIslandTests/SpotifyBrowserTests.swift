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

private final class BrowserMockAPI: SpotifyAPI {
    var pages: [SpotifyPaging<SpotifyTrack>] = []
    private var idx = 0
    func currentUserPlaylists(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyPlaylist> { .init(items: [], next: nil, total: 0) }
    func playlistTracks(playlistID: String, limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack> { defer { idx += 1 }; return pages[min(idx, pages.count - 1)] }
    func savedTracks(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack> { .init(items: [], next: nil, total: 0) }
    func recentlyPlayed(limit: Int) async throws -> [SpotifyPlayHistoryItem] { [] }
    func search(query: String, types: [SpotifySearchType], limit: Int) async throws -> SpotifySearchResponse { .init(playlists: nil, albums: nil, tracks: nil) }
    func availableDevices() async throws -> [SpotifyDevice] { [] }
    func startPlayback(contextURI: String?, uris: [String]?, offsetURI: String?, deviceID: String?) async throws {}
    func setShuffle(_ on: Bool, deviceID: String?) async throws {}
}

@MainActor
final class SpotifyBrowserTests: XCTestCase {
    private func track(_ id: String) -> SpotifyTrack { .init(id: id, name: id, uri: "spotify:track:\(id)", artists: [.init(name: "A")], album: nil, duration_ms: nil) }
    private func playlistItem() -> SpotifyLibraryItem {
        SpotifyLibraryItem(playlist: .init(id: "p1", name: "P", uri: "spotify:playlist:p1", images: [], tracks: .init(total: 4), owner: .init(display_name: nil)))
    }

    func test_open_loadsFirstPage() async {
        let api = BrowserMockAPI()
        api.pages = [.init(items: [track("a"), track("b")], next: "more", total: 4)]
        let browser = SpotifyBrowser(api: api)
        await browser.open(playlistItem())
        XCTAssertEqual(browser.tracks.map(\.name), ["a", "b"])
        XCTAssertTrue(browser.canLoadMore)
        XCTAssertNotNil(browser.currentContext)
    }

    func test_loadMore_appends_andStopsWhenNextNil() async {
        let api = BrowserMockAPI()
        api.pages = [.init(items: [track("a")], next: "more", total: 2), .init(items: [track("b")], next: nil, total: 2)]
        let browser = SpotifyBrowser(api: api)
        await browser.open(playlistItem())
        await browser.loadMoreTracks()
        XCTAssertEqual(browser.tracks.map(\.name), ["a", "b"])
        XCTAssertFalse(browser.canLoadMore)
    }

    func test_back_clearsContext() async {
        let api = BrowserMockAPI()
        api.pages = [.init(items: [track("a")], next: nil, total: 1)]
        let browser = SpotifyBrowser(api: api)
        await browser.open(playlistItem())
        browser.back()
        XCTAssertNil(browser.currentContext)
        XCTAssertTrue(browser.tracks.isEmpty)
    }

    func test_open_secondContext_replacesTracks() async {
        let api = BrowserMockAPI()
        api.pages = [.init(items: [track("a")], next: nil, total: 1), .init(items: [track("b")], next: nil, total: 1)]
        let browser = SpotifyBrowser(api: api)
        await browser.open(playlistItem())
        await browser.open(playlistItem())
        XCTAssertEqual(browser.tracks.map(\.name), ["b"])
    }
}
