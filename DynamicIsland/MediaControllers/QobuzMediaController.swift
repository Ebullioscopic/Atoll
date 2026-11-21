/*
 * Atoll (DynamicIsland), Copyright (C) 2024-2026 Atoll Contributors.
 * Licensed under GNU GPL version 3 or later; see NOTICE.
 */
import AppKit
import Combine
import Foundation

/// Qobuz owns its telemetry process and commands. Global Now Playing is never
/// consulted, published or used as a fallback by this dedicated provider.
@MainActor
final class QobuzMediaController: ObservableObject, @preconcurrency MediaControllerProtocol {
    static let bundleIdentifier = "com.qobuz.desktop"
    @Published private var playbackState = QobuzMediaController.idleState()
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { $playbackState.eraseToAnyPublisher() }
    var isWorking: Bool { process?.isRunning == true }
    var supportsSeeking: Bool { false }

    private let engineURL: URL?
    private var process: Process?
    private var transport: JSONLinesPipeHandler?
    private var streamTask: Task<Void, Never>?
    private var errorPipe: Pipe?
    private var commandInFlight = false

    init(engineURL: URL? = Bundle.main.url(forResource: "qobuz_engine", withExtension: "py"), startsObserver: Bool = true) {
        self.engineURL = engineURL
        if startsObserver {
            Task { [weak self] in await self?.startObserver() }
        }
    }

    deinit {
        streamTask?.cancel()
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        if let process, process.isRunning { process.terminate() }
        if let transport { Task { await transport.close() } }
        try? errorPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForWriting.close()
    }

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.bundleIdentifier }
    }
    func updatePlaybackInfo() async {} // The owned stream publishes every second.
    func play() async { await execute("send", "0") }
    func pause() async { await execute("send", "1") }
    func togglePlay() async { await execute("send", "2") }
    func nextTrack() async { await execute("send", "4") }
    func previousTrack() async { await execute("send", "5") }
    func seek(to time: Double) async {} // Unverified in the background; unavailable.
    func toggleShuffle() async { await execute("shuffle", playbackState.isShuffled ? "1" : "3") }
    func toggleRepeat() async {
        let mode = playbackState.repeatMode == .off ? 3 : playbackState.repeatMode.rawValue - 1
        await execute("repeat", String(mode))
    }

    private func execute(_ action: String, _ value: String) async {
        guard !commandInFlight, let engineURL else { return }
        commandInFlight = true
        defer { commandInFlight = false }
        let path = engineURL.path
        await Task.detached(priority: .userInitiated) {
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            helper.arguments = [path, action, value]
            let timeout = DispatchWorkItem { if helper.isRunning { helper.terminate() } }
            do {
                try helper.run()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
                helper.waitUntilExit()
                timeout.cancel()
                if helper.terminationStatus != 0 { print("Qobuz command failed; global media fallback is disabled") }
            } catch { print("Qobuz command failed: \(error)") }
        }.value
    }

    private func startObserver() async {
        guard process == nil, let engineURL else { return }
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        helper.arguments = [engineURL.path, "stream", "--provider-selection=Qobuz"]
        let handler = JSONLinesPipeHandler()
        helper.standardOutput = await handler.getPipe()
        let errors = Pipe()
        helper.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { handle in
            let bytes = handle.availableData
            if !bytes.isEmpty, let message = String(data: bytes, encoding: .utf8) { print("Qobuz: \(message)") }
        }
        do {
            try helper.run()
            process = helper
            transport = handler
            errorPipe = errors
            // Do not await an unbounded instance method: that would retain self
            // and prevent deinit from stopping the child when sources change.
            streamTask = Task { [weak self, handler] in
                await handler.readJSONLines(as: NowPlayingUpdate.self) { [weak self] update in
                    guard let state = Self.state(from: update) else { return }
                    self?.publish(state)
                }
            }
        } catch { print("Could not start dedicated Qobuz stream: \(error)") }
    }

    private func publish(_ state: PlaybackState) { playbackState = state }

    nonisolated static func state(from update: NowPlayingUpdate) -> PlaybackState? {
        let payload = update.payload
        let source = payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier
        guard source == "com.qobuz.desktop" else { return nil }
        var state = PlaybackState(bundleIdentifier: "com.qobuz.desktop")
        state.title = payload.title ?? ""
        state.artist = payload.artist ?? ""
        state.album = payload.album ?? ""
        state.isPlaying = payload.playing ?? false
        state.playbackRate = payload.playbackRate ?? 0
        state.duration = payload.resolvedDuration ?? 0
        state.currentTime = payload.resolvedElapsedTime ?? 0
        state.lastUpdated = payload.resolvedTimestamp ?? Date()
        state.isShuffled = payload.shuffleMode != nil && payload.shuffleMode != 1
        state.repeatMode = RepeatMode(rawValue: payload.repeatMode ?? 1) ?? .off
        state.artwork = payload.artworkData.flatMap { Data(base64Encoded: $0) }
        return state
    }

    private static func idleState() -> PlaybackState {
        var state = PlaybackState(bundleIdentifier: bundleIdentifier)
        state.title = ""; state.artist = ""; state.album = ""
        state.playbackRate = 0
        return state
    }
}
