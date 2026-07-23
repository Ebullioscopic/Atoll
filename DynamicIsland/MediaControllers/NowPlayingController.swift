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

    /// Reused across every stream update to avoid re-allocating a formatter
    /// on each (1+/second) now playing payload.
    private static let iso8601Formatter = ISO8601DateFormatter()

    // MARK: - Media Remote Functions
    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?

    // MARK: - Lazy-start gating
    /// Optional MediaRemote functions used to detect whether a now-playing
    /// session exists without keeping the perl `stream` subprocess alive.
    /// When available we only launch the subprocess while a now-playing app is
    /// present, and tear it down after a long idle period. When unavailable we
    /// fall back to the original eager-start behaviour so nothing regresses.
    private let MRMediaRemoteRegisterForNowPlayingNotificationsFunction:
        (@convention(c) (DispatchQueue) -> Void)?
    private let MRMediaRemoteUnregisterForNowPlayingNotificationsFunction:
        (@convention(c) () -> Void)?
    private let MRMediaRemoteGetNowPlayingApplicationPIDFunction:
        (@convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void)?

    private var nowPlayingObservers: [NSObjectProtocol] = []
    private var idleStopTask: Task<Void, Never>?
    /// How long a now-playing session may be absent before the subprocess is
    /// torn down. Kept generous so paused/idle sessions keep working.
    private static let idleStopDelay: Duration = .seconds(180)

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

        // Optional presence-detection functions (may be absent on some macOS builds).
        if let ptr = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) {
            MRMediaRemoteRegisterForNowPlayingNotificationsFunction = unsafeBitCast(
                ptr, to: (@convention(c) (DispatchQueue) -> Void).self)
        } else {
            MRMediaRemoteRegisterForNowPlayingNotificationsFunction = nil
        }
        if let ptr = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteUnregisterForNowPlayingNotifications" as CFString) {
            MRMediaRemoteUnregisterForNowPlayingNotificationsFunction = unsafeBitCast(
                ptr, to: (@convention(c) () -> Void).self)
        } else {
            MRMediaRemoteUnregisterForNowPlayingNotificationsFunction = nil
        }
        if let ptr = CFBundleGetFunctionPointerForName(
            bundle, "MRMediaRemoteGetNowPlayingApplicationPID" as CFString) {
            MRMediaRemoteGetNowPlayingApplicationPIDFunction = unsafeBitCast(
                ptr,
                to: (@convention(c) (DispatchQueue, @escaping @convention(block) (Int32) -> Void) -> Void).self)
        } else {
            MRMediaRemoteGetNowPlayingApplicationPIDFunction = nil
        }

        let canGate = MRMediaRemoteRegisterForNowPlayingNotificationsFunction != nil
            && MRMediaRemoteGetNowPlayingApplicationPIDFunction != nil

        if canGate {
            // Lazy: only spin up the perl subprocess once a now-playing app exists.
            Task { @MainActor [weak self] in self?.beginLazyObservation() }
        } else {
            // Fallback: preserve original eager-start behaviour.
            Task { @MainActor [weak self] in await self?.startStreamingIfNeeded() }
        }
    }

    deinit {
        MRMediaRemoteUnregisterForNowPlayingNotificationsFunction?()
        for observer in nowPlayingObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        idleStopTask?.cancel()
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

    // MARK: - Lazy Observation
    /// Registers for MediaRemote now-playing notifications (lightweight, no
    /// subprocess) and starts/stops the perl stream based on session presence.
    @MainActor
    private func beginLazyObservation() {
        MRMediaRemoteRegisterForNowPlayingNotificationsFunction?(DispatchQueue.main)

        let center = NotificationCenter.default
        let names = [
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        ]
        for name in names {
            let token = center.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                self?.evaluateNowPlayingPresence()
            }
            nowPlayingObservers.append(token)
        }

        // Initial check: start immediately if a session already exists at launch.
        evaluateNowPlayingPresence()
    }

    /// Queries whether a now-playing app is present and starts or schedules a
    /// teardown of the perl stream accordingly.
    @MainActor
    private func evaluateNowPlayingPresence() {
        guard let getPID = MRMediaRemoteGetNowPlayingApplicationPIDFunction else {
            Task { @MainActor [weak self] in await self?.startStreamingIfNeeded() }
            return
        }
        getPID(DispatchQueue.main) { [weak self] pid in
            // Callback is delivered on the main queue.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if pid != 0 {
                    self.idleStopTask?.cancel()
                    self.idleStopTask = nil
                    await self.startStreamingIfNeeded()
                } else {
                    self.scheduleIdleStop()
                }
            }
        }
    }

    /// Tears down the subprocess after a grace period if no session reappears.
    @MainActor
    private func scheduleIdleStop() {
        guard process != nil else { return }      // nothing running
        guard idleStopTask == nil else { return }  // already scheduled
        idleStopTask = Task { [weak self] in
            try? await Task.sleep(for: NowPlayingController.idleStopDelay)
            guard let self, !Task.isCancelled else { return }
            self.stopStreaming()
            self.idleStopTask = nil
        }
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
    
    func toggleShuffle() async {
        // MRMediaRemoteSendCommandFunction(6, nil)
        await MainActor.run {
            MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 1 : 3)
            playbackState.isShuffled.toggle()
        }
    }

    func toggleRepeat() async {
        // MRMediaRemoteSendCommandFunction(7, nil)
        await MainActor.run {
            let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
            playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
            MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
        }
    }
    
    // MARK: - Setup Methods
    /// Idempotently launches the perl `stream` subprocess. Safe to call
    /// repeatedly — a no-op while a process is already running.
    @MainActor
    private func startStreamingIfNeeded() async {
        guard process == nil else { return }

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
        process.arguments = [scriptURL.path, frameworkPath, "stream"]

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
            // Reset so a later demand can retry cleanly.
            self.process = nil
            self.pipeHandler = nil
            assertionFailure("Failed to launch mediaremote-adapter.pl: \(error)")
        }
    }

    /// Idempotently tears down the perl `stream` subprocess. Safe to call
    /// repeatedly — a no-op when nothing is running.
    @MainActor
    private func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil

        if let pipeHandler = self.pipeHandler {
            Task { await pipeHandler.close() }
        }

        if let process = self.process, process.isRunning {
            process.terminate()
        }

        self.process = nil
        self.pipeHandler = nil
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
        newPlaybackState.duration = payload.duration ?? (diff ? self.playbackState.duration : 0)
        
        // Match boring.notch behavior: if elapsedTime is provided use it,
        // if this update is a diff keep the previous currentTime, otherwise default to 0.
        newPlaybackState.currentTime = payload.elapsedTime ?? (diff ? self.playbackState.currentTime : 0)

        
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

        if let dateString = payload.timestamp,
           let date = Self.iso8601Formatter.date(from: dateString) {
            newPlaybackState.lastUpdated = date
        } else if !diff {
            newPlaybackState.lastUpdated = Date()
        } else {
            newPlaybackState.lastUpdated = self.playbackState.lastUpdated
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? self.playbackState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload.playing ?? (diff ? self.playbackState.isPlaying : false)
        newPlaybackState.bundleIdentifier = (
            payload.parentApplicationBundleIdentifier ??
            payload.bundleIdentifier ??
            (diff ? self.playbackState.bundleIdentifier : "")
        )

        await MainActor.run { [weak self] in
            self?.playbackState = newPlaybackState
        }
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
    let shuffleMode: Int?
    let repeatMode: Int?
    let artworkData: String?
    let timestamp: String?
    let playbackRate: Double?
    let playing: Bool?
    let parentApplicationBundleIdentifier: String?
    let bundleIdentifier: String?
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
