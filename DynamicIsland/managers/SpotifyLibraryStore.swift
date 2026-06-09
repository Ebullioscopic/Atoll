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

import Combine
import Defaults
import Foundation

@MainActor
final class SpotifyLibraryStore: ObservableObject {
    static let shared = SpotifyLibraryStore()

    @Published private(set) var playlists: [SpotifyLibraryItem] = []
    @Published private(set) var recentlyPlayed: [SpotifyLibraryItem] = []
    @Published private(set) var searchResults = SpotifyGroupedResults()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let likedSongs = SpotifyLibraryItem.likedSongs

    private let api: SpotifyAPI
    private var searchTask: Task<Void, Never>?

    init(api: SpotifyAPI = SpotifyWebAPIClient()) {
        self.api = api
    }

    func loadHome() async {
        guard !isLoading else { return }   // avoid concurrent re-fires hammering the API
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let recentLimit = Defaults[.spotifyRecentLimit]
            async let pl = api.currentUserPlaylists(limit: 50, offset: 0)
            async let rp = api.recentlyPlayed(limit: recentLimit)
            let (playlistsPage, recents) = try await (pl, rp)
            playlists = playlistsPage.items.map { SpotifyLibraryItem(playlist: $0) }
            recentlyPlayed = Self.mapRecents(recents)
        } catch SpotifyAPIError.http(429) {
            errorMessage = String(localized: "Spotify is rate-limiting — wait a minute, then reopen the tab.")
            NSLog("[SpotifyAPI] loadHome: 429 rate limited")
        } catch {
            // Diagnostic: surface the concrete error (e.g. http(403) / decoding / notAuthenticated).
            errorMessage = "Couldn't load library: \(error)"
            NSLog("[SpotifyAPI] loadHome failed: %@", String(describing: error))
        }
    }

    /// Debounced search entry point for the view.
    func search(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { clearSearch(); return }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.performSearch(trimmed)
        }
    }

    /// Synchronous search core (also called directly by tests).
    func performSearch(_ query: String) async {
        do {
            let r = try await api.search(query: query, types: [.playlist, .album, .track], limit: 20)
            guard !Task.isCancelled else { return }
            var grouped = SpotifyGroupedResults()
            grouped.playlists = (r.playlists?.items ?? []).map { SpotifyLibraryItem(playlist: $0) }
            grouped.albums = (r.albums?.items ?? []).map { SpotifyLibraryItem(album: $0) }
            grouped.tracks = r.tracks?.items ?? []
            searchResults = grouped
            errorMessage = nil
        } catch SpotifyAPIError.http(400), SpotifyAPIError.http(403) {
            // Spotify blocks /search (catalog) for developer apps without Extended Quota
            // Mode (Nov 2024). The 400 "Invalid limit" / 403 is the platform refusing access.
            errorMessage = String(localized: "Spotify doesn’t allow search on personal API apps.")
        } catch {
            errorMessage = String(localized: "Search failed.")
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchResults = SpotifyGroupedResults()
        errorMessage = nil
    }

    private static func mapRecents(_ items: [SpotifyPlayHistoryItem]) -> [SpotifyLibraryItem] {
        var seen = Set<String>()
        var result: [SpotifyLibraryItem] = []
        for item in items {
            let contextURI = item.context?.uri ?? item.track.uri
            guard !seen.contains(contextURI) else { continue }
            seen.insert(contextURI)
            let kind: SpotifyLibraryKind
            switch item.context?.type {
            case "playlist": kind = .playlist          // drillable via playlistTracks
            case "collection": kind = .likedSongs       // drillable via savedTracks
            case .some: kind = .album                    // album / artist → play-on-tap (no track-list endpoint)
            case nil: kind = .track                      // played outside any context → a single track
            }
            result.append(SpotifyLibraryItem(
                id: contextURI,
                title: item.track.name,
                subtitle: item.track.artists.map(\.name).joined(separator: ", "),
                imageURL: item.track.album?.images?.first.flatMap { URL(string: $0.url) },
                contextURI: contextURI,
                kind: kind))
        }
        return result
    }
}
