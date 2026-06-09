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

/// Tracks whether the currently playing Spotify track is in the user's Liked Songs and
/// toggles that state. Works for both the desktop Spotify app and Atoll's in-app web
/// player, since both surface the track as a `spotify:track:…` identifier via
/// `MusicManager.contentIdentifier`. For any non-Spotify source it reports `canLike = false`
/// so the Like control can dim itself.
@MainActor
final class SpotifyLikeController: ObservableObject {
    static let shared = SpotifyLikeController()

    /// Whether the current track is saved in Liked Songs.
    @Published private(set) var isLiked = false
    /// Whether the Like control should be interactive (a Spotify track + authenticated).
    @Published private(set) var canLike = false

    private let api: SpotifyAPI
    private let music: MusicManager
    private let auth: SpotifyOAuthManager
    private var cancellables = Set<AnyCancellable>()
    private var currentTrackID: String?
    private var refreshTask: Task<Void, Never>?

    init(api: SpotifyAPI = SpotifyWebAPIClient(),
         music: MusicManager = .shared,
         auth: SpotifyOAuthManager = .shared) {
        self.api = api
        self.music = music
        self.auth = auth

        music.$contentIdentifier
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] id in self?.handleTrackChange(id) }
            .store(in: &cancellables)

        auth.$isAuthenticated
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleTrackChange(self?.music.contentIdentifier) }
            .store(in: &cancellables)

        handleTrackChange(music.contentIdentifier)
    }

    /// Extract a bare base-62 Spotify track ID from a `spotify:track:…` URI or an
    /// open.spotify.com/track URL. Returns nil for anything that isn't unambiguously a
    /// Spotify track (so Apple Music / YouTube identifiers never enable the control).
    static func trackID(from identifier: String?) -> String? {
        guard let raw = identifier?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let candidate: String?
        if raw.hasPrefix("spotify:track:") {
            candidate = String(raw.dropFirst("spotify:track:".count))
        } else if let url = URL(string: raw), url.host?.contains("spotify.com") == true {
            let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if let i = parts.firstIndex(of: "track"), i + 1 < parts.count {
                candidate = parts[i + 1]
            } else {
                candidate = nil
            }
        } else {
            candidate = nil
        }
        guard let id = candidate,
              id.range(of: "^[A-Za-z0-9]{22}$", options: .regularExpression) != nil
        else { return nil }
        return id
    }

    private func handleTrackChange(_ identifier: String?) {
        let id = Self.trackID(from: identifier)
        currentTrackID = id

        // Interactivity needs the modify scope; reading the saved state only needs the read
        // scope, so the heart can still reflect liked/not-liked even when toggling is blocked
        // (e.g. a session authorized before `user-library-modify` was added).
        let available = id != nil && auth.isAuthenticated && auth.canModifyLibrary
        if canLike != available { canLike = available }

        guard let id, auth.isAuthenticated else {
            if isLiked { isLiked = false }
            return
        }

        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            let liked = (try? await self.api.savedTracksContains(ids: [id]))?.first ?? false
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.currentTrackID == id else { return }
                self.isLiked = liked
            }
        }
    }

    /// Add or remove the current track from Liked Songs, updating the UI optimistically and
    /// reverting if the network call fails.
    func toggle() {
        guard let id = currentTrackID, auth.isAuthenticated, auth.canModifyLibrary else { return }
        let wasLiked = isLiked
        isLiked = !wasLiked

        Task { [weak self] in
            guard let self else { return }
            do {
                if wasLiked {
                    try await self.api.removeSavedTracks(ids: [id])
                } else {
                    try await self.api.saveTracks(ids: [id])
                }
            } catch {
                await MainActor.run {
                    guard self.currentTrackID == id else { return }
                    self.isLiked = wasLiked
                }
            }
        }
    }
}
