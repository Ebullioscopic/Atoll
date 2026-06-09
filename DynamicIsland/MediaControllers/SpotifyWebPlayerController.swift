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

import AppKit
import Combine
import Foundation

/// Bridges the in-app Spotify Web Playback SDK player (`SpotifyPlayerManager`) into the
/// notch's media-controller system, so the dynamic island shows the track and its
/// transport controls drive the web player. Used while Atoll is the active Spotify device.
@MainActor
final class SpotifyWebPlayerController: ObservableObject, MediaControllerProtocol {
    private let manager = SpotifyPlayerManager.shared
    private let subject: CurrentValueSubject<PlaybackState, Never>
    private var cancellables = Set<AnyCancellable>()
    private var artworkCache: (url: String, data: Data)?

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { subject.eraseToAnyPublisher() }
    var isWorking: Bool { manager.isReady }

    init() {
        subject = CurrentValueSubject(PlaybackState(bundleIdentifier: Self.bundleID))
        manager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.rebuild() }
            .store(in: &cancellables)
        rebuild()
    }

    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.atoll.webplayer"

    private func rebuild() {
        var state = PlaybackState(bundleIdentifier: Self.bundleID)
        state.isPlaying = manager.isReady && !manager.isPaused
        state.title = manager.currentTrack ?? ""
        state.artist = manager.currentArtist ?? ""
        // Carry the Spotify track URI so the media layer (e.g. the Like control) can act on
        // the in-app player's current track, matching the desktop controller's convention.
        state.contentIdentifier = manager.currentTrackURI
        state.duration = manager.currentDuration
        state.currentTime = manager.currentPosition
        state.playbackRate = manager.isPaused ? 0 : 1
        state.lastUpdated = manager.lastStateDate
        if let urlString = manager.artworkURL, let url = URL(string: urlString) {
            state.liveArtworkURL = nil
            if let cache = artworkCache, cache.url == urlString { state.artwork = cache.data }
        }
        subject.send(state)
    
        // Fetch artwork once per track for the (non-live) artwork slot.
        if let urlString = manager.artworkURL, artworkCache?.url != urlString, let url = URL(string: urlString) {
            Task { [weak self] in
                guard let data = try? await URLSession.shared.data(from: url).0 else { return }
                await MainActor.run {
                    guard let self, self.manager.artworkURL == urlString else { return }
                    self.artworkCache = (urlString, data)
                    self.rebuild()
                }
            }
        }
    }

    // MARK: - MediaControllerProtocol
    func play() async { manager.resume() }
    func pause() async { manager.pause() }
    func togglePlay() async { manager.togglePlay() }
    func nextTrack() async { manager.nextTrack() }
    func previousTrack() async { manager.previousTrack() }
    func seek(to time: Double) async { manager.seek(toMilliseconds: time * 1000) }
    func toggleShuffle() async {}   // shuffle/repeat aren't exposed by the Web Playback SDK player
    func toggleRepeat() async {}
    func isActive() -> Bool { manager.isReady && !(manager.currentTrack ?? "").isEmpty }
    func updatePlaybackInfo() async { rebuild() }
}
