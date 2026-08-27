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

/// Media Remote stream filtered to one application. When another app owns Now
/// Playing, state idles so stale metadata from the selected player is not shown.
class FilteredNowPlayingController: ObservableObject, MediaControllerProtocol {

    func updatePlaybackInfo() async {}

    @Published private(set) var playbackState: PlaybackState

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var isWorking: Bool {
        process != nil && process?.isRunning == true
    }

    private let mediaRemoteBundle: CFBundle
    private let MRMediaRemoteSendCommandFunction: @convention(c) (Int, AnyObject?) -> Void
    private let MRMediaRemoteSetElapsedTimeFunction: @convention(c) (Double) -> Void
    private let MRMediaRemoteSetShuffleModeFunction: @convention(c) (Int) -> Void
    private let MRMediaRemoteSetRepeatModeFunction: @convention(c) (Int) -> Void

    private var process: Process?
    private var pipeHandler: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private let targetBundleIdentifier: String
    private let controllerName: String

    /// True only after a stream line explicitly identified the selected app as the now playing source.
    private var targetSessionActive = false

    init?(bundleIdentifier: String, controllerName: String) {
        self.targetBundleIdentifier = bundleIdentifier
        self.controllerName = controllerName
        self.playbackState = Self.makeIdlePlaybackState(bundleIdentifier: bundleIdentifier)

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

        self.mediaRemoteBundle = bundle
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
            Task { await pipeHandler.close() }
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
        await MainActor.run {
            MRMediaRemoteSetElapsedTimeFunction(time)
        }
    }

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == targetBundleIdentifier }
    }

    // MARK: - Favouriting

    // Declared here rather than left to the protocol's defaults so subclasses
    // can override them: the conformance is on this class, so a witness picked
    // from an extension would be the one used no matter what a subclass says.

    @MainActor
    var canEverFavorite: Bool { false }

    @MainActor
    var supportsFavoriting: Bool { false }

    @MainActor
    var favoritingIsReadOnly: Bool { false }

    func isCurrentTrackFavorited() async -> Bool? { nil }

    @discardableResult
    func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool { false }

    func toggleShuffle() async {
        MRMediaRemoteSetShuffleModeFunction(playbackState.isShuffled ? 1 : 3)
        playbackState.isShuffled.toggle()
    }

    /// Openings for a subclass whose app reports shuffle and repeat somewhere
    /// other than the Media Remote stream. `playbackState` is settable only in
    /// this file, so a subclass cannot reach it directly.

    func applyShuffleState(_ isShuffled: Bool) {
        guard playbackState.isShuffled != isShuffled else { return }
        playbackState.isShuffled = isShuffled
    }

    func applyRepeatMode(_ mode: RepeatMode) {
        guard playbackState.repeatMode != mode else { return }
        playbackState.repeatMode = mode
    }

    func toggleRepeat() async {
        let newRepeatMode = (playbackState.repeatMode == .off) ? 3 : (playbackState.repeatMode.rawValue - 1)
        playbackState.repeatMode = RepeatMode(rawValue: newRepeatMode) ?? .off
        MRMediaRemoteSetRepeatModeFunction(newRepeatMode)
    }

    private func setupNowPlayingObserver() async {
        let process = Process()
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
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

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        let logName = controllerName
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty
            else { return }
            print("\(logName) [stderr]: \(message)")
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

    private func processJSONStream() async {
        guard let pipeHandler = self.pipeHandler else { return }

        await pipeHandler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
            await self?.handleAdapterUpdate(update)
        }
    }

    private static func makeIdlePlaybackState(bundleIdentifier: String) -> PlaybackState {
        var state = PlaybackState(bundleIdentifier: bundleIdentifier)
        state.title = "Unknown"
        state.artist = "Unknown"
        state.album = ""
        state.isPlaying = false
        state.artwork = nil
        state.duration = 0
        state.currentTime = 0
        state.isShuffled = false
        state.repeatMode = .off
        state.lastUpdated = Date()
        return state
    }

    private func applyIdleBecauseDifferentSource() {
        targetSessionActive = false
        playbackState = Self.makeIdlePlaybackState(bundleIdentifier: targetBundleIdentifier)
    }

    private func handleAdapterUpdate(_ update: NowPlayingUpdate) async {
        let payload = update.payload
        let diff = update.diff ?? false

        let explicitParent = payload.parentApplicationBundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitBundle = payload.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitSource: String? = {
            if let p = explicitParent, !p.isEmpty { return p }
            if let b = explicitBundle, !b.isEmpty { return b }
            return nil
        }()

        if let source = explicitSource {
            if source != targetBundleIdentifier {
                applyIdleBecauseDifferentSource()
                return
            }
            targetSessionActive = true
        } else if !diff {
            applyIdleBecauseDifferentSource()
            return
        } else if !targetSessionActive {
            return
        }

        var newPlaybackState = PlaybackState(bundleIdentifier: targetBundleIdentifier)

        newPlaybackState.title = payload.title ?? (diff ? self.playbackState.title : "")
        newPlaybackState.artist = payload.artist ?? (diff ? self.playbackState.artist : "")
        newPlaybackState.album = payload.album ?? (diff ? self.playbackState.album : "")
        newPlaybackState.duration = payload.duration ?? (diff ? self.playbackState.duration : 0)
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
           let date = ISO8601DateFormatter().date(from: dateString) {
            newPlaybackState.lastUpdated = date
        } else if !diff {
            newPlaybackState.lastUpdated = Date()
        } else {
            newPlaybackState.lastUpdated = self.playbackState.lastUpdated
        }

        newPlaybackState.playbackRate = payload.playbackRate ?? (diff ? self.playbackState.playbackRate : 1.0)
        newPlaybackState.isPlaying = payload.playing ?? (diff ? self.playbackState.isPlaying : false)
        newPlaybackState.bundleIdentifier = targetBundleIdentifier

        self.playbackState = newPlaybackState
    }
}

final class AmazonMusicController: FilteredNowPlayingController {
    static let bundleIdentifier = "com.amazon.music"

    init?() {
        super.init(
            bundleIdentifier: Self.bundleIdentifier,
            controllerName: "AmazonMusicController"
        )
    }
}

final class CiderController: FilteredNowPlayingController {
    static let bundleIdentifier = "sh.cider.genten.mac"

    init?() {
        super.init(
            bundleIdentifier: Self.bundleIdentifier,
            controllerName: "CiderController"
        )
    }
}
