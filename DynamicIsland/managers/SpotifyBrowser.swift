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
import Foundation

@MainActor
final class SpotifyBrowser: ObservableObject {
    @Published private(set) var currentContext: SpotifyLibraryItem?
    @Published private(set) var tracks: [SpotifyTrack] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var canLoadMore = false

    private let api: SpotifyAPI
    private let pageSize = 50
    private var offset = 0
    private var loadGeneration = 0

    init(api: SpotifyAPI = SpotifyWebAPIClient()) { self.api = api }

    func open(_ item: SpotifyLibraryItem) async {
        loadGeneration += 1
        currentContext = item
        tracks = []
        offset = 0
        canLoadMore = false
        errorMessage = nil
        isLoading = false
        await loadMoreTracks()
    }

    func loadMoreTracks() async {
        guard let context = currentContext, !isLoading else { return }
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let page: SpotifyPaging<SpotifyTrack>
            switch context.kind {
            case .likedSongs:
                page = try await api.savedTracks(limit: pageSize, offset: offset)
            default:
                page = try await api.playlistTracks(playlistID: Self.playlistID(from: context.contextURI), limit: pageSize, offset: offset)
            }
            guard generation == loadGeneration else { return }
            tracks.append(contentsOf: page.items)
            offset += page.items.count
            canLoadMore = page.next != nil
            errorMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            if case SpotifyAPIError.http(403) = error {
                // Spotify blocks reading tracks of its own editorial/algorithmic playlists
                // (Discover Weekly, Daily Mix, etc.). The context is still playable.
                errorMessage = String(localized: "Spotify won’t share this playlist’s track list — tap “Play all” to play it.")
            } else {
                errorMessage = String(localized: "Couldn\u{2019}t load tracks.")
            }
            canLoadMore = false
        }
    }

    func back() {
        loadGeneration += 1
        currentContext = nil
        tracks = []
        offset = 0
        canLoadMore = false
        errorMessage = nil
        isLoading = false
    }

    private static func playlistID(from uri: String) -> String {
        uri.split(separator: ":").last.map(String.init) ?? uri
    }
}
