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

@MainActor
private final class MockDesktop: SpotifyDesktopControlling {
    var running = true
    var playedContext: (uri: String, shuffle: Bool)?
    var playedTrack: (uri: String, context: String?)?
    var shuffleSet: Bool?
    func isRunning() -> Bool { running }
    func playContext(uri: String, shuffle: Bool) async { playedContext = (uri, shuffle) }
    func playTrack(uri: String, inContext contextURI: String?) async { playedTrack = (uri, contextURI) }
    func setShuffle(_ on: Bool) async { shuffleSet = on }
}

private final class MockAPI: SpotifyAPI {
    var devices: [SpotifyDevice] = []
    var started: (context: String?, uris: [String]?, offset: String?, device: String?)?
    var shuffleSet: Bool?
    func currentUserPlaylists(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyPlaylist> { .init(items: [], next: nil, total: 0) }
    func playlistTracks(playlistID: String, limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack> { .init(items: [], next: nil, total: 0) }
    func savedTracks(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack> { .init(items: [], next: nil, total: 0) }
    func recentlyPlayed(limit: Int) async throws -> [SpotifyPlayHistoryItem] { [] }
    func search(query: String, types: [SpotifySearchType], limit: Int) async throws -> SpotifySearchResponse { .init(playlists: nil, albums: nil, tracks: nil) }
    func availableDevices() async throws -> [SpotifyDevice] { devices }
    func startPlayback(contextURI: String?, uris: [String]?, offsetURI: String?, deviceID: String?) async throws { started = (contextURI, uris, offsetURI, deviceID) }
    func setShuffle(_ on: Bool, deviceID: String?) async throws { shuffleSet = on }
}

@MainActor
final class SpotifyPlaybackLauncherTests: XCTestCase {
    func test_desktopRunning_usesAppleScript_notWebAPI() async throws {
        let desktop = MockDesktop(); desktop.running = true
        let api = MockAPI()
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api)
        try await launcher.playContext(uri: "spotify:playlist:p1", shuffle: true)
        XCTAssertEqual(desktop.playedContext?.uri, "spotify:playlist:p1")
        XCTAssertEqual(desktop.playedContext?.shuffle, true)
        XCTAssertNil(api.started, "web API should not be used when desktop is running")
    }

    func test_desktopNotRunning_withActiveDevice_usesWebAPI() async throws {
        let desktop = MockDesktop(); desktop.running = false
        let api = MockAPI(); api.devices = [SpotifyDevice(id: "d1", name: "Phone", is_active: true)]
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api)
        try await launcher.playContext(uri: "spotify:playlist:p1", shuffle: false)
        XCTAssertEqual(api.started?.context, "spotify:playlist:p1")
        XCTAssertEqual(api.started?.device, "d1")
        XCTAssertNil(desktop.playedContext)
    }

    func test_desktopNotRunning_noDevice_throws() async {
        let desktop = MockDesktop(); desktop.running = false
        let api = MockAPI(); api.devices = []
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api)
        do { try await launcher.playContext(uri: "spotify:playlist:p1", shuffle: false); XCTFail("expected throw") }
        catch let e as SpotifyLaunchError { XCTAssertEqual(e, .noActiveDevice) }
        catch { XCTFail("wrong error: \(error)") }
    }

    func test_likedSongs_usesCollectionContext() async throws {
        let desktop = MockDesktop(); desktop.running = false
        let api = MockAPI(); api.devices = [SpotifyDevice(id: "d1", name: "PC", is_active: true)]
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api)
        try await launcher.playLikedSongs(shuffle: true)
        XCTAssertEqual(api.started?.context, "spotify:collection:tracks")
    }
}
