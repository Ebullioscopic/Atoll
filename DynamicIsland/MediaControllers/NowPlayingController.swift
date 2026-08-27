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

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    // Stub for now to conform with ControllerProtocol
    func updatePlaybackInfo() async {}

    /// How recent a sender's timestamp has to be for the position beside it to
    /// count as a reading of now rather than a record of something earlier.
    ///
    /// Generous on purpose: it only has to separate a sample taken this moment
    /// from one a sender has been repeating since it paused, and those are
    /// minutes apart, not seconds.
    private static let currentSampleWindow: TimeInterval = 2

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }
    
    var isWorking: Bool {
        return process != nil && process?.isRunning == true
    }
    private var lastMusicItem:
        (title: String, artist: String, album: String, duration: TimeInterval, artworkData: Data?)?

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?

    // MARK: - Initialization
    init?() {
        guard
            let bundle = CFBundleCreate(
                kCFAllocatorDefault,
                NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")),
            let MRMediaRemoteSendCommandPointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSendCommand" as CFString),
            let MRMediaRemoteSetElapsedTimePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetElapsedTime" as CFString),
            let MRMediaRemoteSetShuffleModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetShuffleMode" as CFString),
            let MRMediaRemoteSetRepeatModePointer = CFBundleGetFunctionPointerForName(
                bundle, "MRMediaRemoteSetRepeatMode" as CFString)
            
        else { return nil }

        mediaRemoteBundle = bundle
        MRMediaRemoteSendCommandFunction = unsafeBitCast(
            MRMediaRemoteSendCommandPointer, to: (@convention(c) (Int, AnyObject?) -> Void).self)
        MRMediaRemoteSetElapsedTimeFunction = unsafeBitCast(
            MRMediaRemoteSetElapsedTimePointer, to: (@convention(c) (Double) -> Void).self)
        MRMediaRemoteSetShuffleModeFunction = unsafeBitCast(
            MRMediaRemoteSetShuffleModePointer, to: (@convention(c) (Int) -> Void).self)
        MRMediaRemoteSetRepeatModeFunction = unsafeBitCast(
            MRMediaRemoteSetRepeatModePointer, to: (@convention(c) (Int) -> Void).self)

        Task { await setupNowPlayingObserver() }
    }

    deinit {
        streamTask?.cancel()
        
        if let pipeHandler = self.pipeHandler {
            Task { await pipeHandler.close()
            }
        }
        
        if let process = self.process {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        self.process = nil
        self.pipeHandler = nil
    }

    // MARK: - Protocol Implementation
    func play() async {
        MRMediaRemoteSendCommandFunction(0, nil)
    }

    func pause() async {
        MRMediaRemoteSendCommandFunction(1, nil)
    }

    func togglePlay() async {
        MRMediaRemoteSendCommandFunction(2, nil)
    }

    func nextTrack() async {
        MRMediaRemoteSendCommandFunction(4, nil)
    }

    func previousTrack() async {
        MRMediaRemoteSendCommandFunction(5, nil)
    }

    func seek(to time: Double) async {
        MRMediaRemoteSetElapsedTimeFunction(time)
    }

    func isActive() -> Bool {
        return true
    }

    // MARK: - Favouriting

    /// This source fronts whatever app is playing, so favouriting has to be
    /// answered by that app rather than by the source. Under Now Playing the
    /// user has not told us which player they are using -- MediaRemote has.
    @MainActor
    var canEverFavorite: Bool {
        switch playbackState.bundleIdentifier {
        case AppleMusicFavoriting.bundleIdentifier,
             SpotifyController.bundleIdentifier,
             YouTubeMusicFavoriting.bundleIdentifier,
             TidalAccessibility.bundleIdentifier:
            return true
        default:
            return false
        }
    }

    @MainActor
    var supportsFavoriting: Bool {
        switch playbackState.bundleIdentifier {
        case AppleMusicFavoriting.bundleIdentifier:
            return AppleMusicFavoriting.isAvailable
        case SpotifyController.bundleIdentifier:
            return SpotifyFavoriting.isAvailable
        case YouTubeMusicFavoriting.bundleIdentifier:
            return YouTubeMusicFavoriting.isAvailable
        case TidalAccessibility.bundleIdentifier:
            return TidalAccessibility.isAvailable
        default:
            return false
        }
    }

    /// TIDAL reports the favourited state but will not accept a change.
    @MainActor
    var favoritingIsReadOnly: Bool {
        playbackState.bundleIdentifier == TidalAccessibility.bundleIdentifier
    }

    func isCurrentTrackFavorited() async -> Bool? {
        switch playbackState.bundleIdentifier {
        case AppleMusicFavoriting.bundleIdentifier:
            return await AppleMusicFavoriting.isCurrentTrackFavorited()
        case SpotifyController.bundleIdentifier:
            return await SpotifyFavoriting.isFavorited(
                contentIdentifier: playbackState.contentIdentifier,
                contentURL: playbackState.contentURL
            )
        case YouTubeMusicFavoriting.bundleIdentifier:
            return await YouTubeMusicFavoriting.isCurrentTrackFavorited()
        case TidalAccessibility.bundleIdentifier:
            return await TidalAccessibility.isCurrentTrackFavorited()
        default:
            return nil
        }
    }

    @discardableResult
    func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool {
        switch playbackState.bundleIdentifier {
        case AppleMusicFavoriting.bundleIdentifier:
            return await AppleMusicFavoriting.setCurrentTrackFavorited(favorited)
        case SpotifyController.bundleIdentifier:
            return await SpotifyFavoriting.setFavorited(
                favorited,
                contentIdentifier: playbackState.contentIdentifier,
                contentURL: playbackState.contentURL
            )
        case YouTubeMusicFavoriting.bundleIdentifier:
            return await YouTubeMusicFavoriting.setCurrentTrackFavorited(favorited)
        default:
            return false
        }
    }
    
    func toggleShuffle() async {
        // TIDAL never registered a shuffle command, so the Media Remote call
        // below reaches nothing: the button moved and the app carried on. Its
        // Playback menu is the one place that both reports and accepts it.
        if playbackState.bundleIdentifier == TidalAccessibility.bundleIdentifier {
            let current = await TidalAccessibility.isShuffled() ?? playbackState.isShuffled
            guard await TidalAccessibility.setShuffled(!current) else { return }
            await MainActor.run { playbackState.isShuffled = !current }
            return
        }

        // MRMediaRemoteSendCommandFunction(6, nil)
        MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
    }
    
    func toggleRepeat() async {
        // Same as shuffle, and the menu is better than a cycling button: each
        // repeat item sets its own mode, so there is nothing to overshoot.
        if playbackState.bundleIdentifier == TidalAccessibility.bundleIdentifier {
            let current = await TidalAccessibility.repeatMode() ?? playbackState.repeatMode
            let next: RepeatMode
            switch current {
            case .off: next = .all
            case .all: next = .one
            case .one: next = .off
            }
            guard await TidalAccessibility.setRepeatMode(next) else { return }
            await MainActor.run { playbackState.repeatMode = next }
            return
        }

        // MRMediaRemoteSendCommandFunction(7, nil)
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }
    
    // MARK: - Setup Methods
    private func setupNowPlayingObserver() async {
        let process = Process()
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            //let frameworkPath = Bundle.main.privateFrameworksPath?.appending("/MediaRemoteAdapter.framework")
            let frameworkPath =
                Bundle.main.resourceURL?
                    .appendingPathComponent("MediaRemoteAdapter.framework")
                    .path

        else {
            assertionFailure("Could not find mediaremote-adapter.pl script or framework path")
            return
        }
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        // --micros swaps the time keys for microsecond equivalents. The default
        // "timestamp" is an ISO-8601 string truncated to whole seconds, which
        // throws away up to a second of the playback anchor and makes every
        // position estimate drift by that much.
        process.arguments = [scriptURL.path, frameworkPath, "stream", "--micros"]
        
        let pipeHandler = JSONLinesPipeHandler()
        process.standardOutput = await pipeHandler.getPipe()

        // Capture stderr so framework/script errors are logged
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty
            else { return }
            print("NowPlayingController [stderr]: \(message)")
        }
        
        self.process = process
        self.pipeHandler = pipeHandler

        do {
            try process.run()
            streamTask = Task { [weak self] in
                await self?.processJSONStream()
            }
        } catch {
            assertionFailure("Failed to launch mediaremote-adapter.pl: \(error)")
        }
    }

    // MARK: - Async Stream Processing
    private func processJSONStream() async {
        guard let pipeHandler = self.pipeHandler else { return }
        
        await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
            await self?.handleAdapterUpdate(update)
        }
    }

    // MARK: - Update Methods
    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false

        var newPlaybackState = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)
        
        newPlaybackState.title = payload.title ?? (diff ? self.playbackState.title : "")
        newPlaybackState.artist = payload.artist ?? (diff ? self.playbackState.artist : "")
        newPlaybackState.album = payload.album ?? (diff ? self.playbackState.album : "")
        newPlaybackState.duration = payload.resolvedDuration ?? (diff ? self.playbackState.duration : 0)

        // The reported position and the instant it was sampled are a matched pair:
        // elapsedTime is the position *at* timestamp. They have to be adopted or
        // carried forward together -- pairing a fresh position with the previous
        // update's anchor makes every estimate run ahead by the age of that anchor.
        if let elapsed = payload.resolvedElapsedTime {
            newPlaybackState.currentTime = elapsed
            newPlaybackState.lastUpdated = payload.resolvedTimestamp ?? Date()
        } else if payload.clearsElapsedTime {
            // The sender named the position and set it to null, so there is
            // nothing left to extrapolate from. Carrying the old pair forward
            // here would keep advancing a position the sender has disowned.
            newPlaybackState.currentTime = 0
            newPlaybackState.lastUpdated = payload.resolvedTimestamp ?? Date()
        } else if diff {
            newPlaybackState.currentTime = self.playbackState.currentTime
            newPlaybackState.lastUpdated = self.playbackState.lastUpdated
        } else {
            newPlaybackState.currentTime = 0
            newPlaybackState.lastUpdated = payload.resolvedTimestamp ?? Date()
        }

        // Senders are not obliged to keep publishing. Spotify anchors once when
        // a track starts and then says nothing for the rest of it -- measured
        // here as an elapsed of 0 paired with a timestamp 141 seconds old, on a
        // track that had been playing for exactly that long. Extrapolating from
        // a stale anchor is fine while the music is running, because wall-clock
        // time and playback time advance together.
        //
        // They stop agreeing the moment playback stops. A pause that the sender
        // does not follow with a fresh position leaves the anchor where it was,
        // so when playback resumes the extrapolation silently counts the paused
        // time as played, and every pause pushes the estimate further ahead --
        // which is why the position could only be brought back by pausing and
        // playing until the sender happened to republish.
        //
        // So the position is re-anchored on the transition itself: frozen where
        // it had got to when playback stops, and restarted from there when it
        // resumes.
        let wasPlaying = self.playbackState.isPlaying
        let isPlayingNow = payload.playing ?? (diff ? wasPlaying : false)

        // Whether the sender sent a position is not the question -- whether it
        // sent a *current* one is. Spotify keeps republishing the exact instant
        // it paused: four reads six seconds apart returned the same 40.342 with
        // its timestamp 235, 241, 247 and 254 seconds old, still climbing. That
        // pair is true, and harmless while paused because nothing extrapolates
        // a stopped track. It becomes wrong the moment playback resumes, when
        // the anchor still points to before the pause and the whole stopped
        // interval gets counted as played.
        let now = Date()
        let hasCurrentSample: Bool = {
            guard payload.resolvedElapsedTime != nil else { return false }
            // No timestamp means it was stamped on arrival, so it is current
            // by construction.
            guard let stamp = payload.resolvedTimestamp else { return true }
            return abs(now.timeIntervalSince(stamp)) <= Self.currentSampleWindow
        }()

        if wasPlaying != isPlayingNow, !hasCurrentSample {
            // The transition is being observed now, so now is when it happened.
            // The payload's own timestamp is only better than that if it is
            // about now as well -- and the stale one is what caused this.
            let transitionInstant: Date = {
                guard let stamp = payload.resolvedTimestamp,
                      abs(now.timeIntervalSince(stamp)) <= Self.currentSampleWindow
                else { return now }
                return stamp
            }()

            if wasPlaying {
                let elapsedWhilePlaying = transitionInstant.timeIntervalSince(self.playbackState.lastUpdated)
                newPlaybackState.currentTime = max(
                    0,
                    self.playbackState.currentTime + (elapsedWhilePlaying * self.playbackState.playbackRate)
                )
            } else {
                // Resuming. The position is wherever it was left, and the
                // frozen one is what this controller worked out when the pause
                // was observed -- the payload's is the sample already known to
                // be stale, which for some senders is a repeated zero that
                // would restart the track. A seek while paused publishes a
                // fresh sample, so it never reaches this branch.
                newPlaybackState.currentTime = max(0, self.playbackState.currentTime)
            }

            newPlaybackState.lastUpdated = transitionInstant
        }

        
        if let shuffleMode = payload.shuffleMode {
            newPlaybackState.isShuffled = shuffleMode != 1
        } else if !diff {
            newPlaybackState.isShuffled = false
        } else {
            newPlaybackState.isShuffled = self.playbackState.isShuffled
        }
        if let repeatModeValue = payload.repeatMode {
            newPlaybackState.repeatMode = RepeatMode(rawValue: repeatModeValue) ?? .off
        } else if !diff {
            newPlaybackState.repeatMode = .off
        } else {
            newPlaybackState.repeatMode = self.playbackState.repeatMode
        }

        if let artworkDataString = payload.artworkData {
            newPlaybackState.artwork = Data(
                base64Encoded: artworkDataString.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } else if !diff {
            newPlaybackState.artwork = nil
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? self.playbackState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload.playing ?? (diff ? self.playbackState.isPlaying : false)
        newPlaybackState.bundleIdentifier = (
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? self.playbackState.bundleIdentifier : "")
        )
        
        self.playbackState = newPlaybackState
    }
}

struct NowPlayingUpdate: Codable {
    let payload: NowPlayingPayload
    let diff: Bool?
}

struct NowPlayingPayload: Codable {
    let title: String?
    let artist: String?
    let album: String?
    let duration: Double?
    let elapsedTime: Double?
    /// Microsecond variants, emitted in place of the keys above when the adapter
    /// runs with --micros. Preferred because the plain "timestamp" is truncated
    /// to whole seconds.
    let durationMicros: Double?
    let elapsedTimeMicros: Double?
    let timestampEpochMicros: Double?
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?

    /// Whether the update names a position field and sets it to null.
    ///
    /// A diff omits what has not changed, so an absent position means "carry the
    /// last one forward". A position that is present but null is the sender
    /// saying it no longer has one. Optional decoding renders both as nil, so
    /// the distinction has to be captured while the container is still in hand
    /// -- otherwise a cleared position is mistaken for an unchanged one and the
    /// old position keeps being extrapolated from.
    let clearsElapsedTime: Bool

    private enum CodingKeys: String, CodingKey {
        case title, artist, album, duration, elapsedTime
        case durationMicros, elapsedTimeMicros, timestampEpochMicros
        case shuffleMode, repeatMode, artworkData, timestamp
        case playbackRate, playing
        case parentApplicationBundleIdentifier, bundleIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        title = try container.decodeIfPresent(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        album = try container.decodeIfPresent(String.self, forKey: .album)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        elapsedTime = try container.decodeIfPresent(Double.self, forKey: .elapsedTime)
        durationMicros = try container.decodeIfPresent(Double.self, forKey: .durationMicros)
        elapsedTimeMicros = try container.decodeIfPresent(Double.self, forKey: .elapsedTimeMicros)
        timestampEpochMicros = try container.decodeIfPresent(Double.self, forKey: .timestampEpochMicros)
        shuffleMode = try container.decodeIfPresent(Int.self, forKey: .shuffleMode)
        repeatMode = try container.decodeIfPresent(Int.self, forKey: .repeatMode)
        artworkData = try container.decodeIfPresent(String.self, forKey: .artworkData)
        timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate)
        playing = try container.decodeIfPresent(Bool.self, forKey: .playing)
        parentApplicationBundleIdentifier = try container.decodeIfPresent(
            String.self, forKey: .parentApplicationBundleIdentifier
        )
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)

        func isExplicitlyNull(_ key: CodingKeys) throws -> Bool {
            try container.contains(key) && container.decodeNil(forKey: key)
        }

        clearsElapsedTime = try isExplicitlyNull(.elapsedTime)
            || isExplicitlyNull(.elapsedTimeMicros)
    }
}

extension NowPlayingPayload {
    private static let isoFormatter = ISO8601DateFormatter()

    var resolvedDuration: Double? {
        if let durationMicros { return durationMicros / 1_000_000 }
        return duration
    }

    var resolvedElapsedTime: Double? {
        if let elapsedTimeMicros { return elapsedTimeMicros / 1_000_000 }
        return elapsedTime
    }

    /// The instant ``resolvedElapsedTime`` was sampled.
    ///
    /// Prefers the microsecond epoch value. The ISO-8601 string is only a
    /// fallback for adapters that do not honour --micros: it is formatted as
    /// `yyyy-MM-dd'T'HH:mm:ss'Z'`, so it silently drops the sub-second part of
    /// the anchor and biases the position estimate forward by up to a second.
    var resolvedTimestamp: Date? {
        if let timestampEpochMicros {
            return Date(timeIntervalSince1970: timestampEpochMicros / 1_000_000)
        }
        guard let timestamp else { return nil }
        return Self.isoFormatter.date(from: timestamp)
    }
}

actor JSONLinesPipeHandler {
    private let pipe: Pipe
    private let fileHandle: FileHandle
    private var buffer = ""
    
    init() {
        self.pipe = Pipe()
        self.fileHandle = pipe.fileHandleForReading
    }
    
    func getPipe() -> Pipe {
        return pipe
    }
    
    func readJSONLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async {
        do {
            try await self.processLines(as: type) { decodedObject in
                await onLine(decodedObject)
            }
        } catch {
            print("Error processing JSON stream: \(error)")
        }
    }
    
    private func processLines<T: Decodable>(as type: T.Type, onLine: @escaping (T) async -> Void) async throws {
        while true {
            let data = try await readData()
            guard !data.isEmpty else { break }
            
            if let chunk = String(data: data, encoding: .utf8) {
                buffer.append(chunk)
                
                while let range = buffer.range(of: "\n") {
                    let line = String(buffer[..<range.lowerBound])
                    buffer = String(buffer[range.upperBound...])
                    
                    if !line.isEmpty {
                        await processJSONLine(line, as: type, onLine: onLine)
                    }
                }
            }
        }
    }
    
    private func processJSONLine<T: Decodable>(_ line: String, as type: T.Type, onLine: @escaping (T) async -> Void) async {
        guard let data = line.data(using: .utf8) else {
            return
        }
        do {
            let decodedObject = try JSONDecoder().decode(T.self, from: data)
            await onLine(decodedObject)
        } catch {
            // Ignore lines that can't be decoded
        }
    }
    
    private func readData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                handle.readabilityHandler = nil
                continuation.resume(returning: data)
            }
        }
    }
    
    func close() async {
        do {
            fileHandle.readabilityHandler = nil
            try fileHandle.close()
            try pipe.fileHandleForWriting.close()
        } catch {
            print("Error closing pipe handler: \(error)")
        }
    }
}
