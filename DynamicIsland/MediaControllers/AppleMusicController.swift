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

func makeAppleMusicCatalogSearchURL(query: String) -> URL? {
    guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "itunes.apple.com"
    components.path = "/search"
    components.queryItems = [
        URLQueryItem(name: "term", value: query),
        URLQueryItem(name: "media", value: "music"),
        URLQueryItem(name: "entity", value: "song"),
        URLQueryItem(name: "limit", value: "10")
    ]
    return components.url
}

private actor AppleMusicCatalogArtworkResolver {
    // Intentionally cache only the most recent artwork to bound memory usage.
    // Consecutive refreshes commonly request the same track, while a larger
    // cache would retain decoded image data for tracks that may not recur.
    private var lastArtworkKey: String?
    private var cachedArtwork: Data?

    func fetch(title: String, artist: String, album: String) async -> Data? {
        let key = "\(title)|\(artist)|\(album)"

        if key == lastArtworkKey, let cachedArtwork {
            return cachedArtwork
        }

        // Search with title + artist only; including album in the query can
        // confuse the free-text search when names overlap. We validate the
        // album from the structured response fields instead.
        let query = "\(title) \(artist)"
        guard let url = makeAppleMusicCatalogSearchURL(query: query) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard !response.results.isEmpty else { return nil }

            let normalizedAlbum = album.lowercased()
            let normalizedTitle = title.lowercased()
            let match = response.results.first(where: {
                $0.trackName?.lowercased() == normalizedTitle
                    && $0.collectionName?.lowercased() == normalizedAlbum
            }) ?? response.results.first(where: {
                $0.collectionName?.lowercased() == normalizedAlbum
            }) ?? response.results.first(where: {
                $0.trackName?.lowercased() == normalizedTitle
            }) ?? response.results.first

            guard let artworkURLString = match?.artworkUrl100 else { return nil }
            let highResURL = artworkURLString.replacingOccurrences(of: "100x100", with: "600x600")
            guard let imageURL = URL(string: highResURL) else { return nil }

            let (imageData, _) = try await URLSession.shared.data(from: imageURL)
            lastArtworkKey = key
            cachedArtwork = imageData
            return imageData
        } catch {
            return nil
        }
    }
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
    private var playbackInfoRequestGeneration = 0
    private var artworkFetchTask: Task<Void, Never>?
    private var artworkRequestID: UUID?
    private let catalogArtworkResolver = AppleMusicCatalogArtworkResolver()
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
        let generation = await beginPlaybackInfoRequest()
        guard let info = await playbackInfoProvider() else { return }
        await applyPlaybackInfo(info, generation: generation)
    }

    @MainActor
    private func beginPlaybackInfoRequest() -> Int {
        playbackInfoRequestGeneration += 1
        return playbackInfoRequestGeneration
    }

    @MainActor
    private func applyPlaybackInfo(_ info: AppleMusicPlaybackInfo, generation: Int) {
        guard generation == playbackInfoRequestGeneration else { return }
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
        let artworkProvider = catalogArtworkProvider
        let artworkResolver = catalogArtworkResolver
        let title = info.title
        let artist = info.artist
        let album = info.album
        artworkRequestID = requestID
        artworkFetchTask = Task { @MainActor [weak self] in
            let artwork: Data?
            if let artworkProvider {
                artwork = await artworkProvider(title, artist, album)
            } else {
                artwork = await artworkResolver.fetch(
                    title: title,
                    artist: artist,
                    album: album
                )
            }

            guard !Task.isCancelled else { return }
            self?.completeArtworkRequest(artwork, requestID: requestID)
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

    private func executeCommand(_ command: String) async {
        await commandExecutor(command)
    }

    // MARK: - Favouriting

    @MainActor
    var canEverFavorite: Bool { true }

    @MainActor
    var supportsFavoriting: Bool { AppleMusicFavoriting.isAvailable }

    func isCurrentTrackFavorited() async -> Bool? {
        await AppleMusicFavoriting.isCurrentTrackFavorited()
    }

    @discardableResult
    func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool {
        await AppleMusicFavoriting.setCurrentTrackFavorited(favorited)
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


/// Favouriting the track Music.app is playing.
///
/// Music.app is scriptable and favouriting is a plain read/write property on
/// `current track` -- no MusicKit, no developer token, and no Apple Music
/// subscription, which is what had this feature stuck. Anything in the library
/// can be favourited whether or not the user subscribes to anything.
///
/// Lives apart from ``AppleMusicController`` because the Now Playing source
/// needs it too: that controller fronts whatever app is playing, and when that
/// app is Music.app the same script is the answer.
enum AppleMusicFavoriting {
    static let bundleIdentifier = "com.apple.Music"

    /// Only ever true while Music.app is already running.
    ///
    /// Scripting an app that is not running launches it, and a heart appearing
    /// in the notch is not a reason to open Music.
    @MainActor
    static var isAvailable: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    static func isCurrentTrackFavorited() async -> Bool? {
        guard await isAvailable else { return nil }
        for property in propertyNames {
            guard let descriptor = try? await AppleScriptHelper.execute(
                "tell application \"Music\" to return \(property) of current track"
            ) else { continue }
            return descriptor.booleanValue
        }
        return nil
    }

    @discardableResult
    static func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool {
        guard await isAvailable else { return false }
        for property in propertyNames {
            do {
                try await AppleScriptHelper.executeVoid(
                    "tell application \"Music\" to set \(property) of current track to \(favorited)"
                )
                return true
            } catch {
                continue
            }
        }
        return false
    }

    /// `favorited` and `loved` are the same property under the same AppleEvent
    /// code (`pLov`); Music.app renamed it when Love became Favorite. A script
    /// is compiled against the name, though, so the one the running version
    /// does not know fails to compile -- and Atoll still supports macOS 14,
    /// where it is `loved`. Try the current name first and fall back, rather
    /// than branching on an OS version that only approximates which Music.app
    /// is installed.
    private static let propertyNames = ["favorited", "loved"]
}
