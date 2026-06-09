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
    var resumed = false
    var playedContext: (uri: String, shuffle: Bool)?
    var playedTrack: (uri: String, context: String?)?
    var shuffleSet: Bool?
    func isRunning() -> Bool { running }
    func play() async { resumed = true }
    func playContext(uri: String, shuffle: Bool) async { playedContext = (uri, shuffle) }
    func playTrack(uri: String, inContext contextURI: String?) async { playedTrack = (uri, contextURI) }
    func setShuffle(_ on: Bool) async { shuffleSet = on }
}

private final class MockAPI: SpotifyAPI {
    var devices: [SpotifyDevice] = []
    var started: (context: String?, uris: [String]?, offset: String?, device: String?)?
    var shuffleSet: Bool?
    var transferred: (devices: [String], play: Bool)?
    /// When set, `savedTracks` reports this many liked tracks and returns a stub track,
    /// so the random-offset seeding path in `playLikedSongs` has something to pick.
    var savedTotal: Int?
    var savedURI = "spotify:track:LIKED"
    func currentUserPlaylists(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyPlaylist> { .init(items: [], next: nil, total: 0) }
    func playlistTracks(playlistID: String, limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack> { .init(items: [], next: nil, total: 0) }
    func savedTracks(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack> {
        guard let total = savedTotal else { return .init(items: [], next: nil, total: 0) }
        let track = SpotifyTrack(id: "LIKED", name: "Liked", uri: savedURI, artists: [.init(name: "A")], album: nil, duration_ms: nil)
        return .init(items: [track], next: nil, total: total)
    }
    func recentlyPlayed(limit: Int) async throws -> [SpotifyPlayHistoryItem] { [] }
    func search(query: String, types: [SpotifySearchType], limit: Int) async throws -> SpotifySearchResponse { .init(playlists: nil, albums: nil, tracks: nil) }
    func availableDevices() async throws -> [SpotifyDevice] { devices }
    func startPlayback(contextURI: String?, uris: [String]?, offsetURI: String?, deviceID: String?) async throws { started = (contextURI, uris, offsetURI, deviceID) }
    func setShuffle(_ on: Bool, deviceID: String?) async throws { shuffleSet = on }
    func transferPlayback(deviceIDs: [String], play: Bool) async throws { transferred = (deviceIDs, play) }
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

    func test_playTrack_remote_appliesShuffle_andContextOffset() async throws {
        let desktop = MockDesktop(); desktop.running = false
        let api = MockAPI(); api.devices = [SpotifyDevice(id: "d1", name: "P", is_active: true)]
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api)
        try await launcher.playTrack(uri: "spotify:track:t1", inContext: "spotify:playlist:p1", shuffle: true)
        XCTAssertEqual(api.shuffleSet, true)
        XCTAssertEqual(api.started?.context, "spotify:playlist:p1")
        XCTAssertEqual(api.started?.offset, "spotify:track:t1")
    }

    func test_inAppDevice_preferred_overDesktop() async throws {
        let desktop = MockDesktop(); desktop.running = true   // desktop IS running...
        let api = MockAPI()
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api, inAppDeviceID: { "atoll-dev" })
        try await launcher.playContext(uri: "spotify:playlist:p1", shuffle: true)
        // ...but the in-app device wins: Web API targets it, AppleScript NOT used.
        XCTAssertEqual(api.started?.context, "spotify:playlist:p1")
        XCTAssertEqual(api.started?.device, "atoll-dev")
        XCTAssertEqual(api.shuffleSet, true)
        XCTAssertNil(desktop.playedContext)
    }

    func test_inAppDevice_nil_fallsBackToDesktop() async throws {
        let desktop = MockDesktop(); desktop.running = true
        let api = MockAPI()
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api, inAppDeviceID: { nil })
        try await launcher.playContext(uri: "spotify:playlist:p1", shuffle: false)
        XCTAssertEqual(desktop.playedContext?.uri, "spotify:playlist:p1")
        XCTAssertNil(api.started)
    }

    func test_inAppDevice_preferred_forLikedSongs() async throws {
        let desktop = MockDesktop(); desktop.running = true
        let api = MockAPI()
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api, inAppDeviceID: { "atoll-dev" })
        try await launcher.playLikedSongs(shuffle: false)
        XCTAssertEqual(api.started?.context, "spotify:collection:tracks")
        XCTAssertEqual(api.started?.device, "atoll-dev")
    }

    func test_likedSongs_shuffle_seedsRandomOffsetURI() async throws {
        let desktop = MockDesktop(); desktop.running = false
        let api = MockAPI()
        api.devices = [SpotifyDevice(id: "d1", name: "PC", is_active: true)]
        api.savedTotal = 200                       // a real library so a random offset is chosen
        api.savedURI = "spotify:track:RANDOM"
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api)
        try await launcher.playLikedSongs(shuffle: true)
        XCTAssertEqual(api.started?.context, "spotify:collection:tracks")
        XCTAssertEqual(api.started?.offset, "spotify:track:RANDOM",
                       "shuffled Liked Songs should start at a randomly seeded track, not a fixed point")
        XCTAssertEqual(api.shuffleSet, true)
    }

    func test_likedSongs_noShuffle_doesNotSeedOffset() async throws {
        let desktop = MockDesktop(); desktop.running = false
        let api = MockAPI()
        api.devices = [SpotifyDevice(id: "d1", name: "PC", is_active: true)]
        api.savedTotal = 200
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api)
        try await launcher.playLikedSongs(shuffle: false)
        XCTAssertNil(api.started?.offset, "an unshuffled start should keep the natural order")
    }

    func test_resume_prefersInAppDevice_andTransfers() async throws {
        let desktop = MockDesktop(); desktop.running = true   // desktop running, but in-app wins
        let api = MockAPI()
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api, inAppDeviceID: { "atoll-dev" })
        try await launcher.resumeLastPlayback()
        XCTAssertEqual(api.transferred?.devices, ["atoll-dev"])
        XCTAssertEqual(api.transferred?.play, true)
        XCTAssertFalse(desktop.resumed)
        XCTAssertNil(api.started)
    }

    func test_resume_noInApp_desktopRunning_resumesDesktop() async throws {
        let desktop = MockDesktop(); desktop.running = true
        let api = MockAPI()
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api, inAppDeviceID: { nil })
        try await launcher.resumeLastPlayback()
        XCTAssertTrue(desktop.resumed)
        XCTAssertNil(api.transferred)
    }

    func test_resume_noInApp_noDesktop_resumesActiveDevice() async throws {
        let desktop = MockDesktop(); desktop.running = false
        let api = MockAPI()
        api.devices = [SpotifyDevice(id: "d1", name: "Phone", is_active: true)]
        let launcher = SpotifyPlaybackLauncher(desktop: desktop, api: api, inAppDeviceID: { nil })
        try await launcher.resumeLastPlayback()
        // A context-less start on the active device resumes the existing queue + position.
        XCTAssertEqual(api.started?.device, "d1")
        XCTAssertNil(api.started?.context)
        XCTAssertNil(api.started?.uris)
    }
}
