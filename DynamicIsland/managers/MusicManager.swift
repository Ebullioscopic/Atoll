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
import Defaults
import Foundation
import SwiftUI

// MARK: - Lyric Data Structures
struct LyricLine: Identifiable, Codable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String

    init(timestamp: TimeInterval, text: String) {
        self.timestamp = timestamp
        self.text = text
    }
}

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

class MusicManager: ObservableObject {
    enum SkipDirection: Equatable {
        case backward
        case forward
    }

    struct SkipGesturePulse: Equatable {
        let token: Int
        let direction: SkipDirection
        let behavior: MusicSkipBehavior
    }

    static let skipGestureSeekInterval: TimeInterval = 10

    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    @MainActor private var pendingOptimisticPlayState: Bool?

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Pear Desktop auto-detection
    private static let appleMusicBundleID = "com.apple.Music"
    private static let spotifyBundleID = "com.spotify.client"
    private static let pearDesktopBundleID = YouTubeMusicConfiguration.default.bundleIdentifier
    private var isPearDesktopAutoSwitched: Bool = false
    private var isSmartAutoSwitched: Bool = false

    // Multi-source tracking (All Music mode)
    private var knownSources: [String: MediaSource] = [:]
    private var multiSourceCleanupTask: Task<Void, Never>?
    private var backgroundNowPlayingController: NowPlayingController?
    private var backgroundNPCancellables = Set<AnyCancellable>()
    @Published var secondarySources: [MediaSource] = []
    @Published var isMultiSourceListExpanded: Bool = false

    /// When a non-native source (e.g. Safari) is promoted, this holds its bundle ID
    /// so that main playback controls are routed to it via `controlSource`.
    private(set) var promotedSourceBundleID: String?

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true

    /// Whether there is an active music session with real metadata.
    /// Returns `false` only when the metadata is still placeholder/fallback defaults
    /// (i.e. nothing has been played since app launch, or the controller returned
    /// unknown/not-playing placeholders). Paused music with real metadata is still
    /// considered an active session.
    private static let placeholderTitles: Set<String> = [
        "i'm handsome", "i’m handsome", "unknown", "not playing"
    ]
    private static let placeholderArtists: Set<String> = [
        "me", "unknown"
    ]

    private func isPlaceholder(title: String, artist: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let a = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Self.placeholderTitles.contains(t) || Self.placeholderArtists.contains(a)
    }

    var hasActiveSession: Bool {
        if isPlaying { return true }
        let trimmedTitle = songTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasRealTitle = !trimmedTitle.isEmpty && !Self.placeholderTitles.contains(trimmedTitle)
        let hasRealArtist = !trimmedArtist.isEmpty && !Self.placeholderArtists.contains(trimmedArtist)
        return hasRealTitle || hasRealArtist
    }

    @Published var animations: DynamicIslandAnimations = .init()
    @Published var avgColor: NSColor = .white
    @Published var bundleIdentifier: String? = nil
    @Published var songDuration: TimeInterval = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var timestampDate: Date = .init()
    @Published var playbackRate: Double = 1
    @Published var isShuffled: Bool = false
    @Published var repeatMode: RepeatMode = .off
    @Published var isLiveStream: Bool = false
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Published var usingAppIconForArtwork: Bool = false
    @Published private(set) var skipGesturePulse: SkipGesturePulse?

    // MARK: - Lyrics Properties
    @Published var currentLyrics: String = ""
    @Published var syncedLyrics: [LyricLine] = []
    @Published var showLyrics: Bool = false
    @Published var currentLyricIndex: Int = -1

    // Task used to periodically sync displayed lyric with playback position
    private var lyricSyncTask: Task<Void, Never>?

    private(set) var artworkData: Data? = nil

    private var liveStreamUnknownDurationCount: Int = 0
    private var liveStreamEdgeObservationCount: Int = 0
    private var liveStreamCompletionObservationCount: Int = 0
    private var liveStreamCompletionReleaseCount: Int = 0

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil

    @Published var flipAngle: Double = 0
    @Published var lastFlipDirection: SkipDirection = .forward
    private let flipAnimationDuration: TimeInterval = 0.45
    private var flipCooldownActive: Bool = false

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?
    private var skipGestureToken: Int = 0

    // MARK: - Initialization
    init() {
        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.isPearDesktopAutoSwitched = false
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        // Observe Pear Desktop launch/terminate for auto-detection
        setupPearDesktopAutoDetection()

        // Initialize deprecation check asynchronously
        Task { @MainActor in
            do {
                self.isNowPlayingDeprecated = try await self.mediaChecker.checkDeprecationStatus()
                print("Deprecation check completed: \(self.isNowPlayingDeprecated)")
            } catch {
                print("Failed to check deprecation status: \(error). Defaulting to false.")
                self.isNowPlayingDeprecated = false
            }
            
            // Check if Pear Desktop is already running at startup
            let pearDesktopRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == Self.pearDesktopBundleID
            }
            
            if pearDesktopRunning {
                print("[MusicManager] Pear Desktop detected at startup, auto-switching to YouTubeMusicController")
                self.isPearDesktopAutoSwitched = true
                if let controller = self.createController(for: .youtubeMusic) {
                    self.setActiveController(controller)
                }
            } else {
                // Initialize the active controller after deprecation check
                self.setActiveControllerBasedOnPreference()
            }
        }
    }

    // MARK: - Pear Desktop Auto-Detection
    private func setupPearDesktopAutoDetection() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notification in
                guard let self = self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.pearDesktopBundleID else { return }

                print("[MusicManager] Pear Desktop launched, auto-switching to YouTubeMusicController")
                self.isPearDesktopAutoSwitched = true
                if let controller = self.createController(for: .youtubeMusic) {
                    self.setActiveController(controller)
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] notification in
                guard let self = self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.pearDesktopBundleID else { return }

                print("[MusicManager] Pear Desktop terminated, reverting to preferred controller")
                if self.isPearDesktopAutoSwitched {
                    self.isPearDesktopAutoSwitched = false
                    self.setActiveControllerBasedOnPreference()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        destroy()
    }
    
    public func destroy() {
        debounceIdleTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        transitionWorkItem?.cancel()
        stopMultiSourceDetection()

        // Release active controller
        activeController = nil
    }

    // MARK: - Setup Methods
    private func createController(for type: MediaControllerType) -> (any MediaControllerProtocol)? {
        // Cleanup previous controller
        if activeController != nil {
            controllerCancellables.removeAll()
            activeController = nil
        }

        let newController: (any MediaControllerProtocol)?

        switch type {
        case .nowPlaying, .all:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                newController = AppleMusicController()
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        }

        // Set up state observation for the new controller
        if let controller = newController {
            controller.playbackStatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self,
                          self.activeController === controller else { return }
                    self.updateFromPlaybackState(state)
                }
                .store(in: &controllerCancellables)
        }

        return newController
    }

    private func setActiveControllerBasedOnPreference() {
        let preferredType = Defaults[.mediaController]
        print("Preferred Media Controller: \(preferredType)")
        promotedSourceBundleID = nil

        // If NowPlaying is deprecated but that's the preference, use Apple Music instead
        let controllerType = (self.isNowPlayingDeprecated && preferredType == .nowPlaying)
            ? .appleMusic
            : preferredType

        if let controller = createController(for: controllerType) {
            setActiveController(controller)
        } else if controllerType != .appleMusic, let fallbackController = createController(for: .appleMusic) {
            // Fallback to Apple Music if preferred controller couldn't be created
            setActiveController(fallbackController)
        }

        // Start/stop multi-source detection based on mode
        if preferredType == .all {
            startMultiSourceDetection()
        } else {
            stopMultiSourceDetection()
        }
    }

    private func setActiveController(_ controller: any MediaControllerProtocol) {
        // Set new active controller
        activeController = controller

        // Get current state from active controller
        forceUpdate()
    }

    @MainActor
    private func applyPlayState(_ state: Bool, animation: Animation?) {
        if let animation {
            var transaction = Transaction()
            transaction.animation = animation
            withTransaction(transaction) {
                self.isPlaying = state
            }
        } else {
            self.isPlaying = state
        }

        self.updateIdleState(state: state)
    }

    // MARK: - Update Methods
    @MainActor
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        let eventIsPlaying = state.isPlaying
        let expectedState = pendingOptimisticPlayState
        pendingOptimisticPlayState = nil

        if eventIsPlaying != self.isPlaying {
            let animation: Animation? = (expectedState == eventIsPlaying) ? .smooth(duration: 0.18) : .smooth
            applyPlayState(eventIsPlaying, animation: animation)

            if eventIsPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                self.updateSneakPeek()
            }
        } else {
            self.updateIdleState(state: eventIsPlaying)
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData
        let hasContentChange = titleChanged || artistChanged || albumChanged || artworkChanged || bundleChanged

        // Handle artwork and visual transitions for changed content
        let shouldAutoPeekOnTrackChange = Defaults[.showSneakPeekOnTrackChange]

        if hasContentChange {
            self.triggerFlipAnimation()

            if artworkChanged, let artwork = state.artwork {
                self.updateArtwork(artwork)
            } else if state.artwork == nil {
                // Try to use app icon if no artwork but track changed
                if let appIconImage = AppIconAsNSImage(for: state.bundleIdentifier) {
                    self.usingAppIconForArtwork = true
                    self.updateAlbumArt(newAlbumArt: appIconImage)
                }
            }
            self.artworkData = state.artwork

            // Update last artwork change values
            self.lastArtworkTitle = state.title
            self.lastArtworkArtist = state.artist
            self.lastArtworkAlbum = state.album
            self.lastArtworkBundleIdentifier = state.bundleIdentifier

            // Fetch lyrics for new track whenever content changes
            self.fetchLyrics()

            // Only update sneak peek if there's actual content and something changed
            if shouldAutoPeekOnTrackChange && !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }
        }

        // Smart switching logic for "All Music" mode
        if Defaults[.mediaController] == .all {
            self.switchSmartControllerIfNeeded(for: state.bundleIdentifier, isPlaying: state.isPlaying)
            // Track this source for the multi-source list
            self.trackSource(from: state)

            // If a non-native source is promoted and this update is from a different app,
            // skip UI updates to preserve the promoted source's metadata
            if let promoted = promotedSourceBundleID,
               state.bundleIdentifier != promoted {
                return
            }
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode

        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

        if timeChanged {
            self.elapsedTime = state.currentTime
            // Update current lyric based on elapsed time
            self.updateCurrentLyric(for: state.currentTime)
        }

        if durationChanged {
            self.songDuration = state.duration
        }

        if playbackRateChanged {
            self.playbackRate = state.playbackRate
        }
        
        if shuffleChanged {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
        }

        if repeatModeChanged {
            self.repeatMode = state.repeatMode
        }
        
        updateLiveStreamState(with: state)
        self.timestampDate = state.lastUpdated

        // Manage lyric sync task based on playback/lyrics availability
        if Defaults[.enableLyrics] && !self.syncedLyrics.isEmpty {
            // Ensure syncing runs while lyrics are enabled
            startLyricSync()
        } else {
            stopLyricSync()
        }
    }

    private func triggerFlipAnimation() {
        // Debounce: rapid metadata updates (title, artwork, bundle arriving
        // separately for one track change) should only produce a single flip.
        guard !flipCooldownActive else { return }
        flipCooldownActive = true

        // Direction: positive rotation = next (page turn forward),
        //            negative rotation = previous (page turn backward).
        let delta: Double = lastFlipDirection == .forward ? 180 : -180
        withAnimation(.easeInOut(duration: flipAnimationDuration)) {
            flipAngle += delta
        }

        // Reset cooldown after the animation completes so the next
        // genuine track change can flip again.
        DispatchQueue.main.asyncAfter(deadline: .now() + flipAnimationDuration + 0.15) { [weak self] in
            self?.flipCooldownActive = false
        }
    }

    private func updateLiveStreamState(with state: PlaybackState) {
        let duration = state.duration
        let current = max(state.currentTime, elapsedTime)
        let hasKnownDuration = duration.isFinite && duration > 0
        let isPlaying = state.isPlaying

        if hasKnownDuration {
            liveStreamUnknownDurationCount = 0

            let remaining = duration - current
            let clampedDuration = max(duration, 0)
            let clampedCurrent = clampedDuration > 0
                ? max(0, min(current, clampedDuration))
                : max(0, current)
            let progress = clampedDuration > 0 ? clampedCurrent / clampedDuration : 0
            let sliderAppearsComplete = isPlaying && clampedDuration > 0 && progress >= 0.999
            let nearDurationEdge = isPlaying && remaining.isFinite && remaining <= 1.0 && clampedCurrent >= 10

            if sliderAppearsComplete {
                liveStreamCompletionObservationCount = min(liveStreamCompletionObservationCount + 1, 8)
                liveStreamCompletionReleaseCount = 0
            } else {
                liveStreamCompletionReleaseCount = min(liveStreamCompletionReleaseCount + 1, 8)
                if liveStreamCompletionObservationCount > 0 {
                    liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
                }
            }

            if nearDurationEdge || sliderAppearsComplete {
                liveStreamEdgeObservationCount = min(liveStreamEdgeObservationCount + 1, 12)
            } else if liveStreamEdgeObservationCount > 0 {
                liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            }

            if !isLiveStream {
                if liveStreamCompletionObservationCount >= 3 || liveStreamEdgeObservationCount >= 5 {
                    isLiveStream = true
                }
            } else {
                let shouldClearForKnownDuration =
                    (duration > 10 && remaining > 5)
                    || (liveStreamCompletionObservationCount == 0
                        && liveStreamEdgeObservationCount == 0
                        && liveStreamCompletionReleaseCount >= 4)

                if shouldClearForKnownDuration {
                    isLiveStream = false
                }
            }
        } else if isPlaying {
            liveStreamEdgeObservationCount = max(liveStreamEdgeObservationCount - 1, 0)
            liveStreamCompletionObservationCount = max(liveStreamCompletionObservationCount - 1, 0)
            liveStreamCompletionReleaseCount = 0

            liveStreamUnknownDurationCount = min(liveStreamUnknownDurationCount + 1, 8)
            if liveStreamUnknownDurationCount >= 3 && !isLiveStream {
                isLiveStream = true
            }
        } else {
            liveStreamUnknownDurationCount = 0
            liveStreamEdgeObservationCount = 0
            liveStreamCompletionObservationCount = 0
            liveStreamCompletionReleaseCount = 0
        }
    }

    private func updateArtwork(_ artworkData: Data) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            if let artworkImage = NSImage(data: artworkData) {
                DispatchQueue.main.async { [weak self] in
                    self?.usingAppIconForArtwork = false
                    self?.updateAlbumArt(newAlbumArt: artworkImage)
                }
            }
        }
    }

    private func updateIdleState(state: Bool) {
        if state {
            isPlayerIdle = false
            debounceIdleTask?.cancel()
        } else {
            debounceIdleTask?.cancel()
            debounceIdleTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(for: .seconds(Defaults[.waitInterval]))
                withAnimation {
                    self.isPlayerIdle = !self.isPlaying
                }
            }
        }
    }

    private var workItem: DispatchWorkItem?

    func updateAlbumArt(newAlbumArt: NSImage) {
        workItem?.cancel()
        workItem = DispatchWorkItem { [weak self] in
            withAnimation(.smooth) {
                self?.albumArt = newAlbumArt
                if Defaults[.coloredSpectrogram] {
                    self?.calculateAverageColor()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem!)
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.averageColor { [weak self] color in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = color ?? .white
                }
            }
        }
    }

    private func updateSneakPeek() {
        let standardControlsEnabled = Defaults[.showStandardMediaControls]
        let minimalisticEnabled = Defaults[.enableMinimalisticUI]

        guard standardControlsEnabled || minimalisticEnabled else { return }

        if isPlaying && Defaults[.enableSneakPeek] {
            if Defaults[.sneakPeekStyles] == .standard {
                coordinator.toggleSneakPeek(status: true, type: .music)
            } else {
                coordinator.toggleExpandingView(status: true, type: .music)
            }
        }
    }

    private func switchSmartControllerIfNeeded(for bundleID: String?, isPlaying: Bool) {
        let currentType = Defaults[.mediaController]
        guard currentType == .all else { return }

        // Don't auto-switch when a non-native source has been manually promoted
        if promotedSourceBundleID != nil { return }
        
        // Determine the current active controller type
        let activeType: MediaControllerType
        if let _ = activeController as? AppleMusicController {
            activeType = .appleMusic
        } else if let _ = activeController as? SpotifyController {
            activeType = .spotify
        } else if let _ = activeController as? YouTubeMusicController {
            activeType = .youtubeMusic
        } else {
            activeType = .nowPlaying
        }

        // Determine the target controller type based on bundleID and playback status
        var targetType: MediaControllerType = .nowPlaying
        
        if let bundleID = bundleID {
            if bundleID == Self.appleMusicBundleID {
                targetType = .appleMusic
            } else if bundleID == Self.spotifyBundleID {
                targetType = .spotify
            } else if bundleID == Self.pearDesktopBundleID {
                targetType = .youtubeMusic
            }
        }
        
        // If we are on a dedicated controller but it's not playing and not the current bundle,
        // we should probably switch back to NowPlaying to see what else might be playing.
        if activeType != .nowPlaying && !isPlaying && targetType == .nowPlaying {
            // Revert to nowPlaying to scan for other sources
             print("[MusicManager] Smart switching back to nowPlaying (dedicated controller inactive)")
             if let controller = createController(for: .nowPlaying) {
                 setActiveController(controller)
                 isSmartAutoSwitched = false
             }
             return
        }

        if targetType != activeType && isPlaying {
            print("[MusicManager] Smart switching from \(activeType) to \(targetType) based on bundle: \(bundleID ?? "none")")
            if let controller = createController(for: targetType) {
                setActiveController(controller)
                isSmartAutoSwitched = (targetType != .nowPlaying)
            }
        }
    }

    // MARK: - Multi-Source Tracking (All Music mode)

    /// Track a playback state update as a known media source.
    private func trackSource(from state: PlaybackState) {
        let bundleID = state.bundleIdentifier
        guard !bundleID.isEmpty else { return }

        let source = MediaSource(
            id: bundleID,
            bundleIdentifier: bundleID,
            title: state.title,
            artist: state.artist,
            artworkData: state.artwork,
            isPlaying: state.isPlaying,
            lastUpdated: Date()
        )
        knownSources[bundleID] = source
        rebuildSecondarySources()
    }

    /// Called from the background NowPlaying listener to detect other media sources.
    private func trackBackgroundSource(from state: PlaybackState) {
        let bundleID = state.bundleIdentifier
        guard !bundleID.isEmpty else { return }

        // Filter out ghost sources (e.g. Apple Music placeholder)
        if bundleID == "com.apple.Music" {
            // If it's a placeholder, and it's not the primary, skip it.
            if isPlaceholder(title: state.title, artist: state.artist) && bundleID != self.bundleIdentifier {
                return
            }
        }

        // Don't overwrite the primary source with stale NP data
        if bundleID == self.bundleIdentifier {
            // Update isPlaying status only
            if var existing = knownSources[bundleID] {
                existing.isPlaying = state.isPlaying
                existing.lastUpdated = Date()
                knownSources[bundleID] = existing
            }
        } else {
            let source = MediaSource(
                id: bundleID,
                bundleIdentifier: bundleID,
                title: state.title,
                artist: state.artist,
                artworkData: state.artwork,
                isPlaying: state.isPlaying,
                lastUpdated: Date()
            )
            knownSources[bundleID] = source
        }
        rebuildSecondarySources()
    }

    /// Rebuild the published secondarySources array from knownSources,
    /// excluding the current primary source.
    private func rebuildSecondarySources() {
        // Use the absolute latest data from the primary player
        let pTitle = self.songTitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pArtist = self.artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pBundle = self.bundleIdentifier ?? ""
        
        // Fuzzy matching helper
        func isMatch(title: String, artist: String, bundle: String) -> Bool {
            if bundle == pBundle && !bundle.isEmpty { return true }
            
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let a = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            
            // If titles match exactly and it's not empty, it's likely a duplicate (e.g. Safari)
            if !t.isEmpty && t == pTitle && (a == pArtist || a.isEmpty || pArtist.isEmpty) {
                return true
            }
            return false
        }
        
        let sources = knownSources.values
            .filter { source in
                // 1. Check if it matches the primary player
                if isMatch(title: source.title, artist: source.artist, bundle: source.bundleIdentifier) {
                    return false
                }
                
                // 2. Final ghost check (placeholder removal)
                if source.bundleIdentifier == "com.apple.Music" && isPlaceholder(title: source.title, artist: source.artist) {
                    return false
                }
                
                return true
            }
            .sorted { $0.lastUpdated > $1.lastUpdated }
        
        DispatchQueue.main.async {
            self.secondarySources = sources
        }
    }

    /// Start the background NowPlaying listener for multi-source detection.
    func startMultiSourceDetection() {
        guard backgroundNowPlayingController == nil else { return }
        guard let bgController = NowPlayingController() else {
            print("[MusicManager] Could not create background NowPlayingController for multi-source detection")
            return
        }
        backgroundNowPlayingController = bgController

        bgController.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.trackBackgroundSource(from: state)
            }
            .store(in: &backgroundNPCancellables)

        // Periodic cleanup: remove sources not updated in 30s
        multiSourceCleanupTask?.cancel()
        multiSourceCleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                guard let self = self else { return }
                let cutoff = Date().addingTimeInterval(-30)
                var changed = false
                for (key, source) in self.knownSources {
                    if source.lastUpdated < cutoff && !source.isPlaying {
                        self.knownSources.removeValue(forKey: key)
                        changed = true
                    }
                }
                if changed {
                    self.rebuildSecondarySources()
                }
            }
        }

        print("[MusicManager] Multi-source detection started")
    }

    /// Stop the background NowPlaying listener.
    func stopMultiSourceDetection() {
        multiSourceCleanupTask?.cancel()
        multiSourceCleanupTask = nil
        backgroundNPCancellables.removeAll()
        backgroundNowPlayingController = nil
        knownSources.removeAll()
        secondarySources = []
        isMultiSourceListExpanded = false
        print("[MusicManager] Multi-source detection stopped")
    }

    /// Whether a bundle ID has a dedicated native controller.
    private func hasNativeController(for bundleID: String) -> Bool {
        return bundleID == Self.appleMusicBundleID
            || bundleID == Self.spotifyBundleID
            || bundleID == Self.pearDesktopBundleID
    }

    /// Promote a secondary source to be the primary player.
    func promoteSource(_ source: MediaSource) {
        let bundleID = source.bundleIdentifier
        guard bundleID != self.bundleIdentifier else { return }
        print("[MusicManager] Promoting source: \(bundleID)")

        // Haptic feedback on source switch
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

        // 1. Save current primary as a known source so it appears in the secondary list
        if let oldBundle = self.bundleIdentifier, !oldBundle.isEmpty {
            if var existing = knownSources[oldBundle] {
                // Update the existing entry with latest UI metadata
                existing.title = self.songTitle
                existing.artist = self.artistName
                existing.artworkData = self.artworkData
                existing.isPlaying = self.isPlaying
                existing.lastUpdated = Date()
                knownSources[oldBundle] = existing
            } else {
                knownSources[oldBundle] = MediaSource(
                    id: oldBundle,
                    bundleIdentifier: oldBundle,
                    title: self.songTitle,
                    artist: self.artistName,
                    artworkData: self.artworkData,
                    isPlaying: self.isPlaying,
                    lastUpdated: Date()
                )
            }
        }

        // 2. Immediately update displayed metadata from the promoted source.
        //    This must happen synchronously BEFORE rebuildSecondarySources so the
        //    primary bundleIdentifier is correct when filtering.
        self.bundleIdentifier = bundleID
        self.songTitle = source.title.isEmpty ? "Unknown" : source.title
        self.artistName = source.artist.isEmpty ? "Unknown" : source.artist
        self.isPlaying = source.isPlaying
        self.isPlayerIdle = false

        // Cancel any pending debounced artwork from the previous source
        workItem?.cancel()
        if let artData = source.artworkData, let nsImage = NSImage(data: artData) {
            self.albumArt = nsImage
            self.artworkData = artData
            self.usingAppIconForArtwork = false
            if Defaults[.coloredSpectrogram] {
                self.calculateAverageColor()
            }
        } else if let appIcon = AppIconAsNSImage(for: bundleID) {
            self.albumArt = appIcon
            self.artworkData = nil
            self.usingAppIconForArtwork = true
        }

        // Update artwork tracking to prevent false "content changed" triggers
        self.lastArtworkTitle = self.songTitle
        self.lastArtworkArtist = self.artistName
        self.lastArtworkAlbum = self.album
        self.lastArtworkBundleIdentifier = bundleID

        // 3. Switch controller or set promoted source routing
        if hasNativeController(for: bundleID) {
            promotedSourceBundleID = nil

            var targetType: MediaControllerType = .nowPlaying
            if bundleID == Self.appleMusicBundleID {
                targetType = .appleMusic
            } else if bundleID == Self.spotifyBundleID {
                targetType = .spotify
            } else if bundleID == Self.pearDesktopBundleID {
                targetType = .youtubeMusic
            }

            if let controller = createController(for: targetType) {
                setActiveController(controller)
                isSmartAutoSwitched = true
            }
        } else {
            // Non-native source: route commands through controlSource
            promotedSourceBundleID = bundleID
        }

        // 4. Rebuild secondary sources with the updated primary
        rebuildSecondarySources()
    }

    /// Toggle expand/collapse of the multi-source list.
    func toggleMultiSourceList() {
        withAnimation(.smooth(duration: 0.25)) {
            isMultiSourceListExpanded.toggle()
        }
    }

    enum MediaControlAction {
        case play, pause, togglePlay, next, previous
        
        var rawCommand: Int {
            switch self {
            case .play: return 0
            case .pause: return 1
            case .togglePlay: return 2
            case .next: return 4
            case .previous: return 5
            }
        }
    }

    /// Control a specific media source without promoting it to the primary slot.
    private static let safariBundleID = "com.apple.Safari"

    func controlSource(_ source: MediaSource, action: MediaControlAction) {
        let bundleID = source.bundleIdentifier
        print("[MusicManager] Controlling source \(bundleID) with action \(action)")

        // Ensure background NowPlaying controller is initialized for multi-source commands
        if backgroundNowPlayingController == nil {
            startMultiSourceDetection()
        }

        // Use AppleScript for reliable targeted control of supported apps
        if bundleID == Self.appleMusicBundleID || bundleID == Self.spotifyBundleID {
            let appName = bundleID == Self.appleMusicBundleID ? "Music" : "Spotify"
            let scriptVerb: String
            switch action {
            case .play: scriptVerb = "play"
            case .pause: scriptVerb = "pause"
            case .togglePlay: scriptVerb = "playpause"
            case .next: scriptVerb = "next track"
            case .previous: scriptVerb = "previous track"
            }

            let script = "tell application \"\(appName)\" to \(scriptVerb)"
            Task {
                do {
                    try await AppleScriptHelper.executeVoid(script)
                    print("[MusicManager] Successfully controlled \(bundleID) via AppleScript")
                } catch {
                    print("[MusicManager] AppleScript failed for \(bundleID): \(error)")
                }
            }
        } else if bundleID == Self.safariBundleID {
            // Safari: use JavaScript via AppleScript to control the media element
            let jsAction: String
            switch action {
            case .play:
                jsAction = "var v = document.querySelector('video') || document.querySelector('audio'); if(v) v.play();"
            case .pause:
                jsAction = "var v = document.querySelector('video') || document.querySelector('audio'); if(v) v.pause();"
            case .togglePlay:
                jsAction = "var v = document.querySelector('video') || document.querySelector('audio'); if(v) { if(v.paused) v.play(); else v.pause(); }"
            case .next:
                jsAction = "var v = document.querySelector('video') || document.querySelector('audio'); if(v) v.currentTime = Math.min(v.currentTime + 10, v.duration);"
            case .previous:
                jsAction = "var v = document.querySelector('video') || document.querySelector('audio'); if(v) v.currentTime = Math.max(v.currentTime - 10, 0);"
            }

            let script = """
            tell application "Safari"
                do JavaScript "\(jsAction)" in current tab of front window
            end tell
            """
            Task {
                do {
                    try await AppleScriptHelper.executeVoid(script)
                    print("[MusicManager] Successfully controlled Safari via JavaScript")
                } catch {
                    print("[MusicManager] Safari JavaScript failed: \(error). Trying MediaRemote.")
                    self.sendMediaRemoteCommandByPID(bundleID: bundleID, command: action.rawCommand)
                }
            }
        } else {
            // Other apps: try MediaRemote with PID-based targeting
            sendMediaRemoteCommandByPID(bundleID: bundleID, command: action.rawCommand)
        }
        
        // Optimistically update the isPlaying state in our tracking
        if action == .play || action == .pause || action == .togglePlay {
            if var existing = knownSources[bundleID] {
                if action == .play { existing.isPlaying = true }
                else if action == .pause { existing.isPlaying = false }
                else { existing.isPlaying.toggle() }
                
                knownSources[bundleID] = existing
                rebuildSecondarySources()
            }
        }
    }

    /// Send a MediaRemote command targeted by PID lookup from bundle identifier.
    private func sendMediaRemoteCommandByPID(bundleID: String, command: Int) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            print("[MusicManager] Could not find running app for \(bundleID)")
            // Last resort: untargeted command
            backgroundNowPlayingController?.sendCommand(command, bundleID: bundleID)
            return
        }

        let pid = app.processIdentifier
        print("[MusicManager] Sending MediaRemote command \(command) to PID \(pid) (\(bundleID))")

        // Use kMRMediaRemoteOptionSendCommandPID for PID-based targeting
        let options: NSDictionary = [
            "kMRMediaRemoteOptionSendCommandPID": pid as NSNumber
        ]

        // Access the send function through the background controller
        backgroundNowPlayingController?.sendCommand(command, options: options)
    }

    // MARK: - All Music mode targeted routing

    /// In "All Music" mode, routes playback commands to the primary source using
    /// app-specific targeting (AppleScript / PID) instead of untargeted MediaRemote.
    /// This ensures only the intended source is affected.
    /// Returns `true` if the command was handled.
    private func routeInAllMusicMode(action: MediaControlAction) -> Bool {
        guard Defaults[.mediaController] == .all else { return false }
        guard let bundleID = self.bundleIdentifier, !bundleID.isEmpty else { return false }

        // Use tracked source data if available, otherwise build from current UI state
        let source = knownSources[bundleID] ?? MediaSource(
            id: bundleID,
            bundleIdentifier: bundleID,
            title: self.songTitle,
            artist: self.artistName,
            artworkData: self.artworkData,
            isPlaying: self.isPlaying,
            lastUpdated: Date()
        )

        controlSource(source, action: action)

        // Optimistically update UI play state
        if action == .togglePlay {
            self.isPlaying.toggle()
            self.updateIdleState(state: self.isPlaying)
        } else if action == .play {
            self.isPlaying = true
            self.updateIdleState(state: true)
        } else if action == .pause {
            self.isPlaying = false
            self.updateIdleState(state: false)
        }
        return true
    }

    // MARK: - Public Methods for controlling playback
    func playPause() {
        if routeInAllMusicMode(action: .togglePlay) { return }
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        if routeInAllMusicMode(action: .play) { return }
        Task {
            await activeController?.play()
        }
    }

    func pause() {
        if routeInAllMusicMode(action: .pause) { return }
        Task {
            await activeController?.pause()
        }
    }

    func toggleShuffle() {
        Task {
            await activeController?.toggleShuffle()
        }
    }

    func toggleRepeat() {
        Task {
            await activeController?.toggleRepeat()
        }
    }

    func togglePlay() {
        if routeInAllMusicMode(action: .togglePlay) { return }
        guard let controller = activeController else { return }
        let targetState = !isPlaying

        Task {
            await MainActor.run {
                pendingOptimisticPlayState = targetState
                applyPlayState(targetState, animation: .smooth(duration: 0.18))
            }

            if targetState {
                await controller.play()
            } else {
                await controller.pause()
            }
        }
    }

    func nextTrack() {
        if routeInAllMusicMode(action: .next) { return }
        Task {
            await activeController?.nextTrack()
        }
    }

    func previousTrack() {
        if routeInAllMusicMode(action: .previous) { return }
        Task {
            await activeController?.previousTrack()
        }
    }

    func seek(to position: TimeInterval) {
        Task {
            await activeController?.seek(to: position)
        }
    }

    func seek(by offset: TimeInterval) {
        guard !isLiveStream else { return }
        let duration = songDuration
        guard duration > 0 else { return }

        let current = estimatedPlaybackPosition()
        let magnitude = abs(offset)

        if offset < 0, current <= magnitude {
            previousTrack()
            return
        }

        if offset > 0, (duration - current) <= magnitude {
            nextTrack()
            return
        }

        let target = min(max(0, current + offset), duration)
        seek(to: target)
    }

    @MainActor
    func handleSkipGesture(direction: SkipDirection) {
        guard Defaults[.enableHorizontalMusicGestures] else { return }
        guard !isPlayerIdle || bundleIdentifier != nil else { return }

        let behavior = Defaults[.musicGestureBehavior]

        switch behavior {
        case .track:
            if direction == .forward {
                lastFlipDirection = .forward
                nextTrack()
            } else {
                lastFlipDirection = .backward
                previousTrack()
            }
        case .tenSecond:
            let interval = Self.skipGestureSeekInterval
            let offset = direction == .forward ? interval : -interval
            seek(by: offset)
        }

        skipGestureToken = skipGestureToken &+ 1
        skipGesturePulse = SkipGesturePulse(
            token: skipGestureToken,
            direction: direction,
            behavior: behavior
        )
    }

    func openMusicApp() {
        guard let bundleID = bundleIdentifier else {
            print("Error: appBundleIdentifier is nil")
            return
        }

        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
            let configuration = NSWorkspace.OpenConfiguration()
            workspace.openApplication(at: appURL, configuration: configuration) { (app, error) in
                if let error = error {
                    print("Failed to launch app with bundle ID: \(bundleID), error: \(error)")
                } else {
                    print("Launched app with bundle ID: \(bundleID)")
                }
            }
        } else {
            print("Failed to find app with bundle ID: \(bundleID)")
        }
    }

    func forceUpdate() {
        // Request immediate update from the active controller
        Task { [weak self] in
            if self?.activeController?.isActive() == true {
                if let youtubeController = self?.activeController as? YouTubeMusicController {
                    await youtubeController.pollPlaybackState()
                } else {
                    await self?.activeController?.updatePlaybackInfo()
                }
            }
        }
    }

    // MARK: - Lyrics Methods
    func fetchLyrics() {
        guard Defaults[.enableLyrics] else { return }
        // If the lyrics panel is visible already, provide immediate feedback
        if showLyrics {
            Task { @MainActor in
                self.currentLyrics = "Loading lyrics..."
                self.syncedLyrics = []
                self.currentLyricIndex = -1
            }
        }

        Task {
            do {
                let lyrics = try await fetchLyricsFromAPI(artist: artistName, title: songTitle)
                await MainActor.run {
                    self.syncedLyrics = lyrics
                    self.currentLyricIndex = -1
                    if !lyrics.isEmpty {
                        self.currentLyrics = lyrics[0].text
                    } else {
                        self.currentLyrics = ""
                    }

                    // If lyrics are enabled, start syncing them to playback position
                    if Defaults[.enableLyrics] && !self.syncedLyrics.isEmpty {
                        self.startLyricSync()
                    } else if self.syncedLyrics.isEmpty {
                        self.stopLyricSync()
                    }
                }
            } catch {
                print("Failed to fetch lyrics: \(error)")
                await MainActor.run {
                    self.syncedLyrics = []
                    self.currentLyrics = ""
                    self.currentLyricIndex = -1
                    self.stopLyricSync()
                }
            }
        }
    }

    private func fetchLyricsFromAPI(artist: String, title: String) async throws -> [LyricLine] {
        guard !artist.isEmpty, !title.isEmpty else { return [] }

        // Normalize input and percent-encode
        let cleanArtist = artist.folding(options: .diacriticInsensitive, locale: .current)
        let cleanTitle = title.folding(options: .diacriticInsensitive, locale: .current)
        guard let encodedArtist = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedTitle = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }

        // Use LRCLIB search endpoint which returns an array JSON with `plainLyrics` and/or `syncedLyrics`.
        let urlString = "https://lrclib.net/api/search?track_name=\(encodedTitle)&artist_name=\(encodedArtist)"
        guard let url = URL(string: urlString) else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
            // Try parse as array JSON (preferred)
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = jsonArray.first {
                let plain = (first["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let synced = (first["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if !synced.isEmpty {
                    return parseLRC(synced)
                } else if !plain.isEmpty {
                    return [LyricLine(timestamp: 0, text: plain)]
                } else {
                    return []
                }
            } else {
                // Fallback: try to decode as UTF8 and handle as LRC or plain text
                if let lrcString = String(data: data, encoding: .utf8) {
                    let trimmed = lrcString.trimmingCharacters(in: .whitespacesAndNewlines)

                    if trimmed.isEmpty  {
                        return []
                    }

                    // If it contains a syncedLyrics key in an object, try that
                    if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                        if let dict = json as? [String: Any],
                            let synced = dict["syncedLyrics"] as? String
                        {
                            return parseLRC(synced)
                        }
                        if let array = json as? [Any], array.isEmpty {
                            return []
                        }
                    }

                    // Otherwise treat as plain lyrics blob
                    return [LyricLine(timestamp: 0, text: trimmed)]
                }
                return []
            }
        } else {
            return []
        }
    }

    private func parseLRC(_ lrc: String) -> [LyricLine] {
        let lines = lrc.components(separatedBy: .newlines)
        var lyrics: [LyricLine] = []

        // Accept patterns like [m:ss], [mm:ss], [mm:ss.xx] where centiseconds are optional
        let pattern = "\\[(\\d{1,2}):(\\d{2})(?:\\.(\\d{1,2}))?\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        for line in lines {
            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            if let match = regex.firstMatch(in: line, options: [], range: fullRange) {
                let minRange = match.range(at: 1)
                let secRange = match.range(at: 2)
                let centiRange = match.range(at: 3)

                let minStr = minRange.location != NSNotFound ? nsLine.substring(with: minRange) : "0"
                let secStr = secRange.location != NSNotFound ? nsLine.substring(with: secRange) : "0"
                let centiStr = (centiRange.location != NSNotFound) ? nsLine.substring(with: centiRange) : "0"

                let minutes = Double(minStr) ?? 0
                let seconds = Double(secStr) ?? 0
                let centis = Double(centiStr) ?? 0
                let timestamp = minutes * 60 + seconds + centis / 100.0

                let textStart = match.range.location + match.range.length
                if textStart <= nsLine.length {
                    let text = nsLine.substring(from: textStart).trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        lyrics.append(LyricLine(timestamp: timestamp, text: text))
                    }
                }
            }
        }

        return lyrics.sorted(by: { $0.timestamp < $1.timestamp })
    }

    func updateCurrentLyric(for elapsedTime: TimeInterval) {
        guard !syncedLyrics.isEmpty else { return }

        // Find the current lyric based on elapsed time
        var newIndex = -1
        for (index, lyric) in syncedLyrics.enumerated() {
            if elapsedTime >= lyric.timestamp {
                newIndex = index
            } else {
                break
            }
        }

        if newIndex != currentLyricIndex {
            currentLyricIndex = newIndex
            if newIndex >= 0 && newIndex < syncedLyrics.count {
                currentLyrics = syncedLyrics[newIndex].text
            }
        }
    }

    // Start a background task that periodically updates the displayed lyric
    private func startLyricSync() {
        // If already running, keep it
        if lyricSyncTask != nil { return }

        lyricSyncTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Compute estimated playback position and update lyric
                let position = self.estimatedPlaybackPosition()
                await MainActor.run {
                    self.updateCurrentLyric(for: position)
                }

                // Sleep ~300ms between updates
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    private func stopLyricSync() {
        lyricSyncTask?.cancel()
        lyricSyncTask = nil
    }

    func toggleLyrics() {
        // Toggle the UI state first so the views can react immediately.
        showLyrics.toggle()

        // If lyrics are requested to be shown but we don't have any yet,
        // show a loading placeholder and start fetching asynchronously.
        if showLyrics && syncedLyrics.isEmpty {
            // Provide immediate feedback so the UI can show a loading state.
            currentLyrics = "Loading lyrics..."

            Task {
                await fetchLyrics()

                // If fetch completed but no lyrics were found, show a friendly message.
                await MainActor.run {
                    if self.syncedLyrics.isEmpty && self.currentLyrics.isEmpty {
                        self.currentLyrics = "No lyrics found"
                    }
                }
            }
        }
    }
}

// MARK: - Media Branding

extension MusicManager {
    var brandAccentColor: Color {
        Self.brandAccentColor(for: Defaults[.mediaController], bundleIdentifier: bundleIdentifier)
    }

    private static func brandAccentColor(for controller: MediaControllerType, bundleIdentifier: String?) -> Color {
        switch controller {
        case .appleMusic:
            return appleMusicPink
        case .spotify:
            return spotifyGreen
        case .nowPlaying, .all:
            if let bundleIdentifier,
               let bundleColor = brandAccentColor(forBundleIdentifier: bundleIdentifier) {
                return bundleColor
            }
            fallthrough
        case .youtubeMusic:
            return .accentColor
        }
    }

    private static func brandAccentColor(forBundleIdentifier bundleIdentifier: String) -> Color? {
        switch bundleIdentifier {
        case "com.apple.Music":
            return appleMusicPink
        case "com.spotify.client":
            return spotifyGreen
        default:
            return nil
        }
    }

    private static let appleMusicPink = Color(red: 0.999, green: 0.171, blue: 0.331)
    private static let spotifyGreen = Color(red: 0.0, green: 0.857, blue: 0.302)
}

// MARK: - Album Art Flip Helper

private struct AlbumArtFlipModifier: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: 0.5
            )
            // Counter-rotate the content so the image never appears mirrored.
            // At odd multiples of 180° the 3D rotation mirrors along X;
            // applying an opposite scaleEffect cancels that out.
            .scaleEffect(x: cosineSign(for: angle), y: 1)
    }

    /// Returns +1 when the front face is showing, −1 when the back face is showing.
    private func cosineSign(for degrees: Double) -> CGFloat {
        let cos = Darwin.cos(degrees * .pi / 180)
        // Use a small tolerance to avoid flickering exactly at 90°/270°.
        if cos > 0.001 { return 1 }
        if cos < -0.001 { return -1 }
        // At the exact edge, prefer the side we're animating toward.
        return degrees.truncatingRemainder(dividingBy: 360) >= 0 ? -1 : 1
    }
}

extension View {
    func albumArtFlip(angle: Double) -> some View {
        modifier(AlbumArtFlipModifier(angle: angle))
    }
}
