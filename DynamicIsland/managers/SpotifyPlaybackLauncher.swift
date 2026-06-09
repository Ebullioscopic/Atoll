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
import Defaults

enum SpotifyLaunchError: Error, Equatable { case noActiveDevice }

@MainActor
protocol SpotifyDesktopControlling {
    func isRunning() -> Bool
    func play() async
    func playContext(uri: String, shuffle: Bool) async
    func playTrack(uri: String, inContext contextURI: String?) async
    func setShuffle(_ on: Bool) async
}

@MainActor
final class SpotifyPlaybackLauncher {
    private let desktop: SpotifyDesktopControlling
    private let api: SpotifyAPI
    private let inAppDeviceID: @MainActor () -> String?

    init(desktop: SpotifyDesktopControlling,
         api: SpotifyAPI,
         inAppDeviceID: @escaping @MainActor () -> String? = {
            guard Defaults[.spotifyStandalonePlayback], SpotifyPlayerManager.shared.isReady else { return nil }
            return SpotifyPlayerManager.shared.deviceID
         }) {
        self.desktop = desktop
        self.api = api
        self.inAppDeviceID = inAppDeviceID
    }

    func playContext(uri: String, shuffle: Bool) async throws {
        if let deviceID = inAppDeviceID() {
            try await api.setShuffle(shuffle, deviceID: deviceID)
            try await api.startPlayback(contextURI: uri, uris: nil, offsetURI: nil, deviceID: deviceID)
        } else if desktop.isRunning() {
            await desktop.setShuffle(shuffle)
            await desktop.playContext(uri: uri, shuffle: shuffle)
        } else {
            let deviceID = try await activeDeviceID()
            try await api.setShuffle(shuffle, deviceID: deviceID)
            try await api.startPlayback(contextURI: uri, uris: nil, offsetURI: nil, deviceID: deviceID)
        }
    }

    func playTrack(uri: String, inContext contextURI: String?, shuffle: Bool) async throws {
        if let deviceID = inAppDeviceID() {
            // Start audio first (one round-trip) so a song tap feels immediate; the
            // shuffle state for the continuing queue is set right after, best-effort.
            try await api.startPlayback(contextURI: contextURI, uris: contextURI == nil ? [uri] : nil, offsetURI: contextURI == nil ? nil : uri, deviceID: deviceID)
            try? await api.setShuffle(shuffle, deviceID: deviceID)
        } else if desktop.isRunning() {
            await desktop.setShuffle(shuffle)
            await desktop.playTrack(uri: uri, inContext: contextURI)
        } else {
            let deviceID = try await activeDeviceID()
            try await api.setShuffle(shuffle, deviceID: deviceID)
            try await api.startPlayback(contextURI: contextURI, uris: contextURI == nil ? [uri] : nil, offsetURI: contextURI == nil ? nil : uri, deviceID: deviceID)
        }
    }

    func playLikedSongs(shuffle: Bool) async throws {
        let deviceID: String
        if let d = inAppDeviceID() { deviceID = d } else { deviceID = try await activeDeviceID() }
        try await api.setShuffle(shuffle, deviceID: deviceID)
        // Starting the Liked Songs collection with shuffle on otherwise begins from a fixed
        // point, so every launch yields the same order. Seeding playback at a random saved
        // track makes the shuffled queue genuinely different each time.
        let offsetURI: String? = shuffle ? (try? await randomLikedTrackURI()) : nil
        try await api.startPlayback(contextURI: "spotify:collection:tracks", uris: nil, offsetURI: offsetURI, deviceID: deviceID)
    }

    /// A randomly chosen track URI from the user's Liked Songs, or nil if it can't be
    /// determined (empty library / API failure) — in which case playback just starts normally.
    private func randomLikedTrackURI() async throws -> String? {
        let first = try await api.savedTracks(limit: 1, offset: 0)
        guard let total = first.total, total > 1 else { return first.items.first?.uri }
        let randomOffset = Int.random(in: 0..<total)
        let page = try await api.savedTracks(limit: 1, offset: randomOffset)
        return page.items.first?.uri ?? first.items.first?.uri
    }

    /// Continue whatever was playing last rather than starting a fresh context. Prefers
    /// Atoll's in-app device (moves the existing session onto it, preserving queue +
    /// position), then the desktop app, then resuming on the active Connect device.
    func resumeLastPlayback() async throws {
        if let deviceID = inAppDeviceID() {
            try await api.transferPlayback(deviceIDs: [deviceID], play: true)
        } else if desktop.isRunning() {
            await desktop.play()
        } else {
            let deviceID = try await activeDeviceID()
            try await api.startPlayback(contextURI: nil, uris: nil, offsetURI: nil, deviceID: deviceID)
        }
    }

    private func activeDeviceID() async throws -> String {
        let devices = (try? await api.availableDevices()) ?? []
        guard let device = devices.first(where: { $0.is_active }) ?? devices.first, let id = device.id else {
            throw SpotifyLaunchError.noActiveDevice
        }
        return id
    }
}
