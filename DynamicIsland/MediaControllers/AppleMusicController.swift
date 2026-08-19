/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

private struct ITunesSearchResponse: Decodable {
    let results: [ITunesTrack]
}

private struct ITunesTrack: Decodable {
    let trackName: String?
    let collectionName: String?
    let artworkUrl100: String?
}

struct AppleMusicPlaybackInfo: Sendable {
    let isPlaying: Bool
    let title: String
    let artist: String
    let album: String
    let currentTime: Double
    let duration: Double
    let isShuffled: Bool
    let repeatMode: RepeatMode
    let artwork: Data?
}

class AppleMusicController: MediaControllerProtocol {
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.apple.Music",
        playbackRate: 1
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var isWorking: Bool {
        return true  // AppleMusic controller always works
    }

    /// Minimum byte count for artwork data to be considered valid. Anything
    /// smaller is likely an empty descriptor or error string, not image data.
    private static let minimumArtworkSize = 16

    private var notificationTask: Task<Void, Never>?
    private var artworkFetchTask: Task<Void, Never>?
    private var artworkRequestID: UUID?
    private var lastCatalogArtworkKey: String?
    private var cachedCatalogArtwork: Data?
    private let commandUpdateDelay: Duration
    private let commandExecutor: (String) async -> Void
    private let playbackInfoProvider: () async -> AppleMusicPlaybackInfo?
    private let catalogArtworkProvider: ((String, String, String) async -> Data?)?

    // MARK: - Initialization
    init(
        commandUpdateDelay: Duration = .milliseconds(25),
        startsObservers: Bool = true,
        commandExecutor: ((String) async -> Void)? = nil,
        playbackInfoProvider: (() async -> AppleMusicPlaybackInfo?)? = nil,
        catalogArtworkProvider: ((String, String, String) async -> Data?)? = nil
    ) {
        self.commandUpdateDelay = commandUpdateDelay
        self.commandExecutor = commandExecutor ?? Self.executeAppleMusicCommand
        self.playbackInfoProvider = playbackInfoProvider ?? Self.fetchAppleMusicPlaybackInfo
        self.catalogArtworkProvider = catalogArtworkProvider

        guard startsObservers else { return }

        setupPlaybackStateChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.apple.Music.playerInfo")
            )
            
            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    deinit {
        notificationTask?.cancel()
        artworkFetchTask?.cancel()
    }
    
    // MARK: - Protocol Implementation
    func play() async {
        await executeCommand("play")
    }
    
    func pause() async {
        await executeCommand("pause")
    }
    
    func togglePlay() async {
        await executeCommand("playpause")
    }
    
    func nextTrack() async {
        await executeAndRefresh("next track")
    }
    
    func previousTrack() async {
        await executeAndRefresh("previous track")
    }
    
    func seek(to time: Double) async {
        await executeCommand("set player position to \(time)")
        await updatePlaybackInfo()
    }
    
    func toggleShuffle() async {
        await executeCommand("set shuffle enabled to not shuffle enabled")
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func toggleRepeat() async {
        await executeCommand("""
            if song repeat is off then
                set song repeat to all
            else if song repeat is all then
                set song repeat to one
            else
                set song repeat to off
            end if
            """)
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == "com.apple.Music" }
    }
    
    func updatePlaybackInfo() async {
        guard let info = await playbackInfoProvider() else { return }
        await applyPlaybackInfo(info)
    }

    @MainActor
    private func applyPlaybackInfo(_ info: AppleMusicPlaybackInfo) {
        var updatedState = playbackState

        updatedState.isPlaying = info.isPlaying
        updatedState.title = info.title
        updatedState.artist = info.artist
        updatedState.album = info.album
        updatedState.currentTime = info.currentTime
        updatedState.duration = info.duration
        updatedState.isShuffled = info.isShuffled
        updatedState.repeatMode = info.repeatMode
        updatedState.artwork = info.artwork
        updatedState.lastUpdated = Date()

        artworkFetchTask?.cancel()
        artworkFetchTask = nil
        artworkRequestID = nil

        // Publish the new track immediately. Streamed Apple Music tracks often
        // have no embedded artwork, and the catalog fallback can take seconds.
        // Waiting for it here leaves the previous track's poster on screen.
        playbackState = updatedState

        guard info.artwork == nil else { return }

        let requestID = UUID()
        artworkRequestID = requestID
        artworkFetchTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let artwork: Data?
            if let catalogArtworkProvider = self.catalogArtworkProvider {
                artwork = await catalogArtworkProvider(info.title, info.artist, info.album)
            } else {
                artwork = await self.fetchArtworkFromCatalog(
                    title: info.title,
                    artist: info.artist,
                    album: info.album
                )
            }

            guard !Task.isCancelled else { return }
            self.completeArtworkRequest(artwork, requestID: requestID)
        }
    }

    @MainActor
    private func completeArtworkRequest(_ artwork: Data?, requestID: UUID) {
        guard artworkRequestID == requestID else { return }
        defer {
            artworkRequestID = nil
            artworkFetchTask = nil
        }
        guard let artwork else { return }

        var artworkState = playbackState
        artworkState.artwork = artwork
        playbackState = artworkState
    }

    // MARK: - Private Methods

    @MainActor
    private func fetchArtworkFromCatalog(title: String, artist: String, album: String) async -> Data? {
        let key = "\(title)|\(artist)|\(album)"

        if key == lastCatalogArtworkKey, let cached = cachedCatalogArtwork {
            return cached
        }

        // Search with title + artist only; including album in the query can
        // confuse the free-text search when names overlap. We validate the
        // album from the structured response fields instead.
        let query = "\(title) \(artist)"
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=10")
        else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard !response.results.isEmpty else { return nil }

            let normalizedAlbum = album.lowercased()
            let normalizedTitle = title.lowercased()

            let match = response.results.first(where: {
                $0.trackName?.lowercased() == normalizedTitle &&
                $0.collectionName?.lowercased() == normalizedAlbum
            }) ?? response.results.first(where: {
                $0.collectionName?.lowercased() == normalizedAlbum
            }) ?? response.results.first(where: {
                $0.trackName?.lowercased() == normalizedTitle
            }) ?? response.results.first

            guard let artworkURLString = match?.artworkUrl100 else { return nil }

            let highResURL = artworkURLString.replacingOccurrences(of: "100x100", with: "600x600")
            guard let imageURL = URL(string: highResURL) else { return nil }

            let (imageData, _) = try await URLSession.shared.data(from: imageURL)
            lastCatalogArtworkKey = key
            cachedCatalogArtwork = imageData
            return imageData
        } catch {
            return nil
        }
    }

    private func executeCommand(_ command: String) async {
        await commandExecutor(command)
    }

    private static func executeAppleMusicCommand(_ command: String) async {
        let script = "tell application \"Music\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }

    private func executeAndRefresh(_ command: String) async {
        await executeCommand(command)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    private static func fetchAppleMusicPlaybackInfo() async -> AppleMusicPlaybackInfo? {
        guard let descriptor = try? await fetchPlaybackInfoDescriptor() else { return nil }
        guard descriptor.numberOfItems >= 9 else { return nil }

        let repeatModeValue = descriptor.atIndex(8)?.int32Value ?? 0
        let artworkData = descriptor.atIndex(9)?.data as Data?
        let validArtwork = artworkData.flatMap {
            $0.count > minimumArtworkSize ? $0 : nil
        }

        return AppleMusicPlaybackInfo(
            isPlaying: descriptor.atIndex(1)?.booleanValue ?? false,
            title: descriptor.atIndex(2)?.stringValue ?? "Unknown",
            artist: descriptor.atIndex(3)?.stringValue ?? "Unknown",
            album: descriptor.atIndex(4)?.stringValue ?? "Unknown",
            currentTime: descriptor.atIndex(5)?.doubleValue ?? 0,
            duration: descriptor.atIndex(6)?.doubleValue ?? 0,
            isShuffled: descriptor.atIndex(7)?.booleanValue ?? false,
            repeatMode: RepeatMode(rawValue: Int(repeatModeValue)) ?? .off,
            artwork: validArtwork
        )
    }

    private static func fetchPlaybackInfoDescriptor() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Music"
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffle enabled
                set repeatState to song repeat
                if repeatState is off then
                    set repeatValue to 1
                else if repeatState is one then
                    set repeatValue to 2
                else if repeatState is all then
                    set repeatValue to 3
                end if

                set artData to ""
                try
                    set artData to raw data of artwork 1 of current track
                end try

                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatValue, artData}
            on error
                return {false, "Not Playing", "Unknown", "Unknown", 0, 0, false, 0, ""}
            end try
        end tell
        """
        return try await AppleScriptHelper.execute(script)
    }
}
