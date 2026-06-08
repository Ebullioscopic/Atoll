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

enum SpotifyLaunchError: Error, Equatable { case noActiveDevice }

@MainActor
protocol SpotifyDesktopControlling {
    func isRunning() -> Bool
    func playContext(uri: String, shuffle: Bool) async
    func playTrack(uri: String, inContext contextURI: String?) async
    func setShuffle(_ on: Bool) async
}

@MainActor
final class SpotifyPlaybackLauncher {
    private let desktop: SpotifyDesktopControlling
    private let api: SpotifyAPI

    init(desktop: SpotifyDesktopControlling, api: SpotifyAPI) {
        self.desktop = desktop
        self.api = api
    }

    func playContext(uri: String, shuffle: Bool) async throws {
        if desktop.isRunning() {
            await desktop.setShuffle(shuffle)
            await desktop.playContext(uri: uri, shuffle: shuffle)
        } else {
            let deviceID = try await activeDeviceID()
            try await api.setShuffle(shuffle, deviceID: deviceID)
            try await api.startPlayback(contextURI: uri, uris: nil, offsetURI: nil, deviceID: deviceID)
        }
    }

    func playTrack(uri: String, inContext contextURI: String?, shuffle: Bool) async throws {
        if desktop.isRunning() {
            await desktop.setShuffle(shuffle)
            await desktop.playTrack(uri: uri, inContext: contextURI)
        } else {
            let deviceID = try await activeDeviceID()
            try await api.setShuffle(shuffle, deviceID: deviceID)
            try await api.startPlayback(contextURI: contextURI, uris: contextURI == nil ? [uri] : nil, offsetURI: contextURI == nil ? nil : uri, deviceID: deviceID)
        }
    }

    func playLikedSongs(shuffle: Bool) async throws {
        // Liked Songs has no reliable AppleScript URI; always drive via Web API context.
        let deviceID = try await activeDeviceID()
        try await api.setShuffle(shuffle, deviceID: deviceID)
        try await api.startPlayback(contextURI: "spotify:collection:tracks", uris: nil, offsetURI: nil, deviceID: deviceID)
    }

    private func activeDeviceID() async throws -> String {
        let devices = (try? await api.availableDevices()) ?? []
        guard let device = devices.first(where: { $0.is_active }) ?? devices.first, let id = device.id else {
            throw SpotifyLaunchError.noActiveDevice
        }
        return id
    }
}
