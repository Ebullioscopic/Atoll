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

import Combine
import Foundation
import SwiftUI

class SpotifyController: MediaControllerProtocol, SpotifyDesktopControlling {
    static let bundleIdentifier = "com.spotify.client"
    static let sharedForLaunch = SpotifyController()

    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: SpotifyController.bundleIdentifier
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var isWorking: Bool {
        true
    }

    private var notificationTask: Task<Void, Never>?
    private var sessionChangeCancellable: AnyCancellable?

    // Constant for time between command and update
    private let commandUpdateDelay: Duration = .milliseconds(25)

    private var lastArtworkURL: String?
    private var artworkFetchTask: Task<Void, Never>?
    private var canvasFetchTask: Task<Void, Never>?
    private var currentCanvasTrackURI: String?
    private var lastCanvasRequestTrackURI: String?
    private var lastCanvasRequestDate: Date = .distantPast
    private let canvasResolver = SpotifyCanvasResolver()

    init() {
        setupPlaybackStateChangeObserver()
        setupSessionChangeObserver()
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }

    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.spotify.client.PlaybackStateChanged")
            )

            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }

    private func setupSessionChangeObserver() {
        sessionChangeCancellable = NotificationCenter.default.publisher(for: .spotifyCanvasSessionDidChange)
            .sink { [weak self] _ in
                self?.lastCanvasRequestTrackURI = nil
                self?.lastCanvasRequestDate = .distantPast
                if let self {
                    var updatedState = self.playbackState
                    updatedState.liveArtworkURL = nil
                    self.playbackState = updatedState
                }
                Task {
                    await self?.updatePlaybackInfo()
                }
            }
    }

    deinit {
        notificationTask?.cancel()
        artworkFetchTask?.cancel()
        canvasFetchTask?.cancel()
        sessionChangeCancellable?.cancel()
    }

    // MARK: - Protocol Implementation
    func play() async { await executeCommand("play") }
    func pause() async { await executeCommand("pause") }
    func togglePlay() async { await executeCommand("playpause") }
    func nextTrack() async { await executeCommand("next track") }

    func previousTrack() async {
        await executeAndRefresh("previous track")
    }

    func seek(to time: Double) async {
        await executeAndRefresh("set player position to \(time)")
    }

    func toggleShuffle() async {
        await executeAndRefresh("set shuffling to not shuffling")
    }

    func toggleRepeat() async {
        await executeAndRefresh("set repeating to not repeating")
    }

    // MARK: - Launch API (used by SpotifyPlaybackLauncher)

    func playContext(uri: String, shuffle: Bool) async {
        await executeCommand("set shuffling to \(shuffle)")
        await executeCommand("play track \"\(uri)\"")
    }

    func playTrack(uri: String, inContext contextURI: String?) async {
        if let contextURI {
            await executeCommand("play track \"\(uri)\" in context \"\(contextURI)\"")
        } else {
            await executeCommand("play track \"\(uri)\"")
        }
    }

    func setShuffle(_ on: Bool) async {
        await executeCommand("set shuffling to \(on)")
    }

    func isRunning() -> Bool { isActive() }

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == playbackState.bundleIdentifier }
    }

    func updatePlaybackInfo() async {
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard descriptor.numberOfItems >= 11 else { return }

        let isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        let currentTrack = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        let currentTrackArtist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        let currentTrackAlbum = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        let currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = (descriptor.atIndex(6)?.doubleValue ?? 0) / 1000
        let isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let isRepeating = descriptor.atIndex(8)?.booleanValue ?? false
        let artworkURL = descriptor.atIndex(9)?.stringValue ?? ""
        let trackIdentifier = descriptor.atIndex(10)?.stringValue ?? ""
        let spotifyURLString = descriptor.atIndex(11)?.stringValue ?? ""
        let trackURI = Self.canonicalTrackURI(from: trackIdentifier, spotifyURLString: spotifyURLString)

        var state = PlaybackState(
            bundleIdentifier: Self.bundleIdentifier,
            isPlaying: isPlaying,
            title: currentTrack,
            artist: currentTrackArtist,
            album: currentTrackAlbum,
            currentTime: currentTime,
            duration: duration,
            playbackRate: 1,
            isShuffled: isShuffled,
            repeatMode: isRepeating ? .all : .off,
            lastUpdated: Date()
        )
        state.contentIdentifier = trackIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : trackIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        state.contentURL = spotifyURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : spotifyURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        if artworkURL == lastArtworkURL, let existingArtwork = self.playbackState.artwork {
            state.artwork = existingArtwork
        }

        let isSameCanvasTrack = trackURI == currentCanvasTrackURI

        if isSameCanvasTrack {
            state.liveArtworkURL = playbackState.liveArtworkURL
        } else {
            state.liveArtworkURL = nil
            currentCanvasTrackURI = trackURI.isEmpty ? nil : trackURI
            canvasFetchTask?.cancel()
            canvasFetchTask = nil
        }

        playbackState = state

        if !trackURI.isEmpty {
            scheduleCanvasFetchIfNeeded(for: trackURI)
        }

        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            guard artworkURL != lastArtworkURL || state.artwork == nil else { return }
            artworkFetchTask?.cancel()

            let currentState = state
            let expectedTrackURI = trackURI

            artworkFetchTask = Task {
                do {
                    let data = try await ImageService.shared.fetchImageData(from: url)

                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        guard expectedTrackURI.isEmpty || self.currentCanvasTrackURI == expectedTrackURI else {
                            self.artworkFetchTask = nil
                            return
                        }
                        var updatedState = currentState
                        updatedState.artwork = data
                        updatedState.liveArtworkURL = self.playbackState.liveArtworkURL
                        self.playbackState = updatedState
                        self.lastArtworkURL = artworkURL
                        self.artworkFetchTask = nil
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.artworkFetchTask = nil
                    }
                }
            }
        }
    }

    private func scheduleCanvasFetchIfNeeded(for trackURI: String) {
        guard !trackURI.isEmpty else { return }
        guard playbackState.liveArtworkURL == nil else { return }
        guard canvasFetchTask == nil else { return }

        if lastCanvasRequestTrackURI == trackURI,
           Date().timeIntervalSince(lastCanvasRequestDate) < 5
        {
            return
        }

        lastCanvasRequestTrackURI = trackURI
        lastCanvasRequestDate = Date()

        canvasFetchTask = Task { [weak self] in
            guard let self else { return }

            let canvasURL = await self.canvasResolver.canvasURL(for: trackURI)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard self.currentCanvasTrackURI == trackURI else {
                    self.canvasFetchTask = nil
                    return
                }

                var updatedState = self.playbackState
                updatedState.liveArtworkURL = canvasURL
                self.playbackState = updatedState
                self.canvasFetchTask = nil
            }
        }
    }
    private func executeCommand(_ command: String) async {
        let script = "tell application \"Spotify\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }

    private func executeAndRefresh(_ command: String) async {
        await executeCommand(command)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }

    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Spotify"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffling
                set repeatState to repeating
                set artworkURL to artwork url of current track
                set trackID to id of current track
                set spotifyURL to spotify url of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatState, artworkURL, trackID, spotifyURL}
            on error
                return {false, "Unknown", "Unknown", "Unknown", 0, 0, false, false, "", "", ""}
            end try
        end tell
        """

        return try await AppleScriptHelper.execute(script)
    }

    private static func canonicalTrackURI(from trackIdentifier: String, spotifyURLString: String) -> String {
        let trimmedIdentifier = trackIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedIdentifier.hasPrefix("spotify:track:") {
            return trimmedIdentifier
        }

        if isLikelySpotifyTrackID(trimmedIdentifier) {
            return "spotify:track:\(trimmedIdentifier)"
        }

        if let trackID = extractTrackID(from: spotifyURLString) {
            return "spotify:track:\(trackID)"
        }

        return ""
    }

    private static func extractTrackID(from spotifyURLString: String) -> String? {
        guard let url = URL(string: spotifyURLString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let pathComponents = components.path.split(separator: "/")
        guard let trackIndex = pathComponents.firstIndex(of: "track"),
              trackIndex + 1 < pathComponents.count
        else { return nil }

        let identifier = String(pathComponents[trackIndex + 1])
        return isLikelySpotifyTrackID(identifier) ? identifier : nil
    }

    private static func isLikelySpotifyTrackID(_ value: String) -> Bool {
        value.count == 22 && value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
        }
    }
}

private actor SpotifyCanvasResolver {
    private struct CacheEntry {
        let url: URL?
        let expiresAt: Date
    }

    private var cache: [String: CacheEntry] = [:]

    func canvasURL(for trackURI: String) async -> URL? {
        let now = Date()
        if let entry = cache[trackURI], entry.expiresAt > now {
            return entry.url
        }

        let resolvedURL = await fetchCanvasURL(for: trackURI, retryOnUnauthorized: true)
        let cacheLifetime: TimeInterval = resolvedURL == nil ? 300 : 3600
        cache[trackURI] = CacheEntry(url: resolvedURL, expiresAt: now.addingTimeInterval(cacheLifetime))
        return resolvedURL
    }

    private func fetchCanvasURL(for trackURI: String, retryOnUnauthorized: Bool) async -> URL? {
        guard let accessToken = await SpotifyAuthManager.shared.validAccessToken() else {
            return nil
        }

        var request = URLRequest(url: URL(string: "https://spclient.wg.spotify.com/canvaz-cache/v0/canvases")!)
        request.httpMethod = "POST"
        request.httpBody = SpotifyCanvasProtobuf.makeCanvasRequest(trackURI: trackURI)
        request.setValue("application/protobuf", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue("Spotify/9.0.34.593 iOS/18.4 (iPhone15,3)", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }

            if httpResponse.statusCode == 401, retryOnUnauthorized {
                await SpotifyAuthManager.shared.invalidateAccessToken()
                return await fetchCanvasURL(for: trackURI, retryOnUnauthorized: false)
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            return SpotifyCanvasProtobuf.parseCanvasURL(from: data, matching: trackURI)
        } catch {
            return nil
        }
    }
}

private enum SpotifyCanvasProtobuf {
    static func makeCanvasRequest(trackURI: String) -> Data {
        let uriData = Data(trackURI.utf8)

        var trackMessage = Data()
        trackMessage.append(protobufKey(fieldNumber: 1, wireType: 2))
        trackMessage.append(varint(for: uriData.count))
        trackMessage.append(uriData)

        var request = Data()
        request.append(protobufKey(fieldNumber: 1, wireType: 2))
        request.append(varint(for: trackMessage.count))
        request.append(trackMessage)
        return request
    }

    static func parseCanvasURL(from data: Data, matching trackURI: String) -> URL? {
        do {
            var reader = ProtobufReader(data: data)
            var matchingURLs: [URL] = []

            while !reader.isAtEnd {
                let key = try reader.readVarint()
                let fieldNumber = Int(key >> 3)
                let wireType = Int(key & 0x7)

                switch (fieldNumber, wireType) {
                case (1, 2):
                    let canvasData = try reader.readLengthDelimited()
                    if let record = try parseCanvasRecord(from: canvasData),
                       record.trackURI == trackURI,
                       let canvasURL = record.canvasURL
                    {
                        matchingURLs.append(canvasURL)
                    }
                default:
                    try reader.skipField(wireType: wireType)
                }
            }

            return matchingURLs.first { $0.absoluteString.lowercased().hasSuffix(".mp4") } ?? matchingURLs.first
        } catch {
            return nil
        }
    }

    private static func parseCanvasRecord(from data: Data) throws -> SpotifyCanvasRecord? {
        var reader = ProtobufReader(data: data)
        var trackURI = ""
        var canvasURL: URL?

        while !reader.isAtEnd {
            let key = try reader.readVarint()
            let fieldNumber = Int(key >> 3)
            let wireType = Int(key & 0x7)

            switch (fieldNumber, wireType) {
            case (2, 2):
                let urlString = try reader.readString()
                canvasURL = URL(string: urlString)
            case (5, 2):
                trackURI = try reader.readString()
            default:
                try reader.skipField(wireType: wireType)
            }
        }

        guard !trackURI.isEmpty else { return nil }
        return SpotifyCanvasRecord(trackURI: trackURI, canvasURL: canvasURL)
    }

    private static func protobufKey(fieldNumber: Int, wireType: Int) -> Data {
        var key = Data()
        key.append(varint(for: (fieldNumber << 3) | wireType))
        return key
    }

    private static func varint(for value: Int) -> Data {
        var remaining = UInt64(value)
        var buffer = Data()

        repeat {
            var nextByte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 {
                nextByte |= 0x80
            }
            buffer.append(nextByte)
        } while remaining != 0

        return buffer
    }
}

private struct SpotifyCanvasRecord {
    let trackURI: String
    let canvasURL: URL?
}

private struct ProtobufReader {
    enum ReaderError: Error {
        case malformedVarint
        case unexpectedEnd
        case unsupportedWireType
    }

    private let data: Data
    private var index: Data.Index

    init(data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    var isAtEnd: Bool {
        index >= data.endIndex
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while shift < 64 {
            guard index < data.endIndex else {
                throw ReaderError.unexpectedEnd
            }

            let byte = data[index]
            index = data.index(after: index)

            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }

            shift += 7
        }

        throw ReaderError.malformedVarint
    }

    mutating func readLengthDelimited() throws -> Data {
        let length = Int(try readVarint())
        guard length >= 0 else {
            throw ReaderError.unexpectedEnd
        }

        let endIndex = data.index(index, offsetBy: length, limitedBy: data.endIndex)
        guard let endIndex else {
            throw ReaderError.unexpectedEnd
        }

        let slice = data[index..<endIndex]
        index = endIndex
        return Data(slice)
    }

    mutating func readString() throws -> String {
        let bytes = try readLengthDelimited()
        return String(decoding: bytes, as: UTF8.self)
    }

    mutating func skipField(wireType: Int) throws {
        switch wireType {
        case 0:
            _ = try readVarint()
        case 1:
            try advance(by: 8)
        case 2:
            _ = try readLengthDelimited()
        case 5:
            try advance(by: 4)
        default:
            throw ReaderError.unsupportedWireType
        }
    }

    private mutating func advance(by count: Int) throws {
        let endIndex = data.index(index, offsetBy: count, limitedBy: data.endIndex)
        guard let endIndex else {
            throw ReaderError.unexpectedEnd
        }
        index = endIndex
    }
}
