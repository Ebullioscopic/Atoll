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

import Foundation

// MARK: - API models (decode only the fields we use)

struct SpotifyImage: Codable, Equatable {
    let url: String
    let width: Int?
    let height: Int?
}

struct SpotifyArtistRef: Codable, Equatable {
    let name: String
}

struct SpotifyAlbumRef: Codable, Equatable {
    let images: [SpotifyImage]?
}

struct SpotifyPlaylist: Codable, Equatable, Identifiable {
    struct CountRef: Codable, Equatable { let total: Int }
    struct OwnerRef: Codable, Equatable { let display_name: String? }
    let id: String
    let name: String
    let uri: String
    let images: [SpotifyImage]?
    // Spotify omits `tracks` / `owner` on some playlist objects (e.g. certain
    // library entries) — optional so one such playlist doesn't fail the whole list.
    let tracks: CountRef?
    let owner: OwnerRef?
}

struct SpotifyTrack: Codable, Equatable, Identifiable {
    let id: String?
    let name: String
    let uri: String
    let artists: [SpotifyArtistRef]
    let album: SpotifyAlbumRef?
    let duration_ms: Int?
}

struct SpotifyAlbum: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let uri: String
    let images: [SpotifyImage]?
    let artists: [SpotifyArtistRef]
}

struct SpotifyDevice: Codable, Equatable, Identifiable {
    let id: String?
    let name: String
    let is_active: Bool
}

struct SpotifyPaging<T: Codable & Equatable>: Codable, Equatable {
    let items: [T]
    let next: String?
    let total: Int?
}

struct SpotifyPlayHistoryItem: Codable, Equatable {
    struct ContextRef: Codable, Equatable { let uri: String; let type: String }
    let track: SpotifyTrack
    let context: ContextRef?
}

struct SpotifySearchResponse: Codable, Equatable {
    let playlists: SpotifyPaging<SpotifyPlaylist>?
    let albums: SpotifyPaging<SpotifyAlbum>?
    let tracks: SpotifyPaging<SpotifyTrack>?
}

enum SpotifySearchType: String { case playlist, album, track }

// MARK: - View models

enum SpotifyLibraryKind: Equatable { case playlist, album, likedSongs, track }

struct SpotifyLibraryItem: Identifiable, Equatable {
    let id: String          // uri — stable identity
    let title: String
    let subtitle: String
    let imageURL: URL?
    let contextURI: String  // what to play
    let kind: SpotifyLibraryKind

    init(id: String, title: String, subtitle: String, imageURL: URL?, contextURI: String, kind: SpotifyLibraryKind) {
        self.id = id; self.title = title; self.subtitle = subtitle
        self.imageURL = imageURL; self.contextURI = contextURI; self.kind = kind
    }

    init(playlist p: SpotifyPlaylist) {
        self.init(id: p.uri, title: p.name,
                  subtitle: "\(p.tracks?.total ?? 0) tracks",
                  imageURL: p.images?.first.flatMap { URL(string: $0.url) },
                  contextURI: p.uri, kind: .playlist)
    }

    init(album a: SpotifyAlbum) {
        self.init(id: a.uri, title: a.name,
                  subtitle: a.artists.map(\.name).joined(separator: ", "),
                  imageURL: a.images?.first.flatMap { URL(string: $0.url) },
                  contextURI: a.uri, kind: .album)
    }

    static let likedSongs = SpotifyLibraryItem(
        id: "spotify:collection:tracks", title: "Liked Songs", subtitle: "Saved tracks",
        imageURL: nil, contextURI: "spotify:collection:tracks", kind: .likedSongs)
}

struct SpotifyGroupedResults: Equatable {
    var playlists: [SpotifyLibraryItem] = []
    var albums: [SpotifyLibraryItem] = []
    var tracks: [SpotifyTrack] = []
    var isEmpty: Bool { playlists.isEmpty && albums.isEmpty && tracks.isEmpty }
}

// MARK: - API protocol (so stores/launcher can be tested with a mock)

protocol SpotifyAPI {
    func currentUserPlaylists(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyPlaylist>
    func playlistTracks(playlistID: String, limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack>
    func savedTracks(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack>
    func recentlyPlayed(limit: Int) async throws -> [SpotifyPlayHistoryItem]
    func search(query: String, types: [SpotifySearchType], limit: Int) async throws -> SpotifySearchResponse
    func availableDevices() async throws -> [SpotifyDevice]
    func startPlayback(contextURI: String?, uris: [String]?, offsetURI: String?, deviceID: String?) async throws
    func setShuffle(_ on: Bool, deviceID: String?) async throws
    /// Whether each of `ids` is in the user's Liked Songs. Parallel to the input order.
    func savedTracksContains(ids: [String]) async throws -> [Bool]
    /// Add tracks to Liked Songs. Requires the `user-library-modify` scope.
    func saveTracks(ids: [String]) async throws
    /// Remove tracks from Liked Songs. Requires the `user-library-modify` scope.
    func removeSavedTracks(ids: [String]) async throws
    /// Move the active playback session onto `deviceIDs`, optionally resuming it.
    func transferPlayback(deviceIDs: [String], play: Bool) async throws
}

// Default no-op/empty implementations so lightweight mocks that don't exercise the
// library/transfer surface keep conforming without boilerplate. The real
// `SpotifyWebAPIClient` overrides each of these.
extension SpotifyAPI {
    func savedTracksContains(ids: [String]) async throws -> [Bool] { ids.map { _ in false } }
    func saveTracks(ids: [String]) async throws {}
    func removeSavedTracks(ids: [String]) async throws {}
    func transferPlayback(deviceIDs: [String], play: Bool) async throws {}
}
