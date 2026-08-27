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

// swiftlint:disable file_length

// MARK: - Lyric Data Structures
struct LyricLine: Identifiable, Codable, Equatable {
    let id = UUID()
    let timestamp: TimeInterval
    let text: String

    init(timestamp: TimeInterval, text: String) {
        self.timestamp = timestamp
        self.text = text
    }

    // Compares content only; `id` is regenerated per instance, so identical
    // lyrics parsed twice would otherwise never compare equal
    static func == (lhs: LyricLine, rhs: LyricLine) -> Bool {
        lhs.timestamp == rhs.timestamp && lhs.text == rhs.text
    }
}

private struct LyricsLookupKey: Hashable {
    let title: String
    let artist: String
    let album: String

    /// Whether this is worth searching for.
    ///
    /// Empty fields are the obvious case. The subtler one is metadata that is
    /// filled in but identifies nothing -- an untagged rip playing as "Track 7"
    /// by "Unknown Artist" matches lrclib's twenty *other* untagged rips
    /// exactly, and one of them wins. Not searching is the right answer there.
    var isValid: Bool {
        !LyricsMetadata.namesNoParticularTrack(title: title, artist: artist)
    }
}

let defaultImage: NSImage = .init(
    systemSymbolName: "heart.fill",
    accessibilityDescription: "Album Art"
)!

struct OptimisticPlaybackTransition {
    private(set) var expectedState: Bool? = nil

    mutating func begin(expecting state: Bool) {
        expectedState = state
    }

    mutating func shouldApply(eventIsPlaying: Bool) -> Bool {
        guard let expectedState else { return true }
        guard eventIsPlaying == expectedState else { return false }

        self.expectedState = nil
        return true
    }

    mutating func cancel(ifExpecting state: Bool) -> Bool {
        guard expectedState == state else { return false }
        expectedState = nil
        return true
    }
}

private struct ManualTrackArtworkHandoff {
    private static let manualTrackArtworkTransitionDuration: TimeInterval = 0.225
    private var deadline: Date? = nil
    private var generation = 0

    mutating func begin(at date: Date = Date()) {
        generation &+= 1
        deadline = date.addingTimeInterval(Self.manualTrackArtworkTransitionDuration)
    }

    mutating func pendingSchedule(at date: Date = Date()) -> (generation: Int, delay: TimeInterval)? {
        guard let deadline else { return nil }
        let remainingDelay = deadline.timeIntervalSince(date)
        guard remainingDelay > 0 else {
            self.deadline = nil
            return nil
        }
        return (generation, remainingDelay)
    }

    mutating func complete(generation: Int) -> Bool {
        guard self.generation == generation else { return false }
        deadline = nil
        return true
    }
}

private struct ITunesExplicitnessSearchResponse: Decodable {
    let results: [ITunesExplicitnessTrack]
}

private struct ITunesExplicitnessTrack: Decodable {
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let trackExplicitness: String?
}

private actor MusicExplicitnessResolver {
    struct LookupKey: Hashable, Sendable {
        let title: String
        let artist: String
        let album: String

        init(title: String, artist: String, album: String) {
            self.title = MusicExplicitnessResolver.normalize(title)
            self.artist = MusicExplicitnessResolver.normalize(artist)
            self.album = MusicExplicitnessResolver.normalize(album)
        }

        var canResolve: Bool {
            !title.isEmpty && !artist.isEmpty
        }
    }

    static let shared = MusicExplicitnessResolver()

    private let session = URLSession(configuration: .ephemeral)
    private static let cacheLimit = 300
    private var cache: [LookupKey: Bool] = [:]
    private var cacheOrder: [LookupKey] = []
    private var inFlightTasks: [LookupKey: Task<Bool, Never>] = [:]

    private func store(_ value: Bool, for key: LookupKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            while cacheOrder.count > Self.cacheLimit {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[key] = value
    }

    func resolve(title: String, artist: String, album: String) async -> Bool {
        let key = LookupKey(title: title, artist: artist, album: album)
        guard key.canResolve else { return false }

        if let cached = cache[key] {
            return cached
        }

        if let inFlightTask = inFlightTasks[key] {
            return await inFlightTask.value
        }

        let task = Task<Bool, Never> { [session] in
            await Self.fetchExplicitness(for: key, using: session)
        }

        inFlightTasks[key] = task
        let result = await task.value
        store(result, for: key)
        inFlightTasks[key] = nil
        return result
    }

    private static func fetchExplicitness(for key: LookupKey, using session: URLSession) async -> Bool {
        let query = "\(key.title) \(key.artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(
                string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=15")
        else {
            return false
        }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode(ITunesExplicitnessSearchResponse.self, from: data)

            let bestMatch = response.results
                .map { track in (track, matchScore(for: track, key: key)) }
                .max { lhs, rhs in lhs.1 < rhs.1 }

            guard let bestMatch,
                  bestMatch.1 >= 8
            else {
                return false
            }

            return bestMatch.0.trackExplicitness?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                == "explicit"
        } catch {
            return false
        }
    }

    private static func matchScore(for track: ITunesExplicitnessTrack, key: LookupKey) -> Int {
        let trackTitle = canonicalTitle(track.trackName ?? "")
        guard !trackTitle.isEmpty else { return Int.min }

        let keyTitle = canonicalTitle(key.title)
        let trackArtist = normalize(track.artistName ?? "")
        let trackAlbum = normalize(track.collectionName ?? "")

        var score = 0

        if trackTitle == keyTitle {
            score += 6
        } else if trackTitle.contains(keyTitle) || keyTitle.contains(trackTitle) {
            score += 4
        } else {
            return Int.min
        }

        if !key.artist.isEmpty {
            if trackArtist == key.artist {
                score += 4
            } else if trackArtist.contains(key.artist) || key.artist.contains(trackArtist) {
                score += 2
            }
        }

        if !key.album.isEmpty {
            if trackAlbum == key.album {
                score += 2
            } else if !trackAlbum.isEmpty && (trackAlbum.contains(key.album) || key.album.contains(trackAlbum)) {
                score += 1
            }
        }

        return score
    }

    private static func canonicalTitle(_ value: String) -> String {
        var title = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        title = title.replacingOccurrences(
            of: #"\([^)]*\)|\[[^\]]*\]"#,
            with: " ",
            options: .regularExpression
        )
        title = title.replacingOccurrences(
            of: #"\s-\s(?:\d{4}\s)?(?:remaster(?:ed)?|live|edit|mix|version|mono|stereo).*$"#,
            with: " ",
            options: .regularExpression
        )
        return normalize(title)
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let stripped = folded.replacingOccurrences(
            of: #"[^a-z0-9]+"#,
            with: " ",
            options: .regularExpression
        )
        return stripped
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private actor SpotifyExplicitnessResolver {
    struct LookupKey: Hashable, Sendable {
        let trackID: String

        init?(contentIdentifier: String?, contentURL: String?) {
            guard let trackID = SpotifyExplicitnessResolver.extractTrackID(from: contentIdentifier)
                ?? SpotifyExplicitnessResolver.extractTrackID(from: contentURL)
            else {
                return nil
            }

            self.trackID = trackID
        }
    }

    static let shared = SpotifyExplicitnessResolver()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0",
            "Accept-Language": "en-US,en;q=0.9"
        ]
        return URLSession(configuration: configuration)
    }()

    private static let cacheLimit = 300
    private var cache: [LookupKey: Bool] = [:]
    private var cacheOrder: [LookupKey] = []
    private var inFlightTasks: [LookupKey: Task<Bool?, Never>] = [:]

    private func store(_ value: Bool, for key: LookupKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            while cacheOrder.count > Self.cacheLimit {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        }
        cache[key] = value
    }

    func resolve(key: LookupKey) async -> Bool? {
        if let cached = cache[key] {
            return cached
        }

        if let inFlightTask = inFlightTasks[key] {
            return await inFlightTask.value
        }

        let task = Task<Bool?, Never> { [session] in
            await Self.fetchExplicitness(for: key, using: session)
        }

        inFlightTasks[key] = task
        let result = await task.value
        if let result {
            store(result, for: key)
        }
        inFlightTasks[key] = nil
        return result
    }

    private static func fetchExplicitness(for key: LookupKey, using session: URLSession) async -> Bool? {
        guard let url = URL(string: "https://open.spotify.com/embed/track/\(key.trackID)") else {
            return nil
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let html = String(data: data, encoding: .utf8)
            else {
                return nil
            }

            if let isExplicit = parseIsExplicitDirectly(from: html) {
                return isExplicit
            }

            if let nextDataJSON = extractNextDataJSON(from: html),
               let isExplicit = parseIsExplicit(from: nextDataJSON) {
                return isExplicit
            }

            return nil
        } catch {
            return nil
        }
    }

    private static func extractNextDataJSON(from html: String) -> String? {
        let pattern = #"<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let jsonRange = Range(match.range(at: 1), in: html)
        else {
            return nil
        }

        return String(html[jsonRange])
    }

    private static func parseIsExplicitDirectly(from html: String) -> Bool? {
        if let value = captureFirstMatch(
            in: html,
            pattern: #""isExplicit"\s*:\s*(true|false)"#
        ) {
            return value == "true"
        }

        if let label = captureFirstMatch(
            in: html,
            pattern: #""label"\s*:\s*"([A-Z_]+)""#
        ) {
            switch label {
            case "EXPLICIT":
                return true
            case "NON_EXPLICIT":
                return false
            default:
                break
            }
        }

        return nil
    }

    private static func captureFirstMatch(in source: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        guard let match = regex.firstMatch(in: source, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: source)
        else {
            return nil
        }

        return String(source[valueRange]).lowercased()
    }

    private static func parseIsExplicit(from nextDataJSON: String) -> Bool? {
        guard let data = nextDataJSON.data(using: .utf8),
              let rootObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let props = rootObject["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let state = pageProps["state"] as? [String: Any],
              let dataObject = state["data"] as? [String: Any],
              let entity = dataObject["entity"] as? [String: Any]
        else {
            return nil
        }

        if let isExplicit = entity["isExplicit"] as? Bool {
            return isExplicit
        }

        if let contentRating = entity["contentRating"] as? [String: Any],
           let label = contentRating["label"] as? String {
            return label.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "EXPLICIT"
        }

        return nil
    }

    private static func extractTrackID(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("spotify:track:") {
            return validatedTrackID(String(trimmed.split(separator: ":").last ?? ""))
        }

        if let url = URL(string: trimmed) {
            let pathComponents = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if let trackIndex = pathComponents.firstIndex(of: "track"),
               trackIndex + 1 < pathComponents.count {
                return validatedTrackID(pathComponents[trackIndex + 1])
            }
        }

        return validatedTrackID(trimmed)
    }

    private static func validatedTrackID<S: StringProtocol>(_ candidate: S) -> String? {
        let value = String(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[A-Za-z0-9]{22}$"#, options: .regularExpression) != nil else {
            return nil
        }

        return value
    }
}

// swiftlint:disable:next type_body_length
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
    private static let optimisticPlaybackRecoveryTimeout: Duration = .seconds(2)

    // MARK: - Properties
    static let shared = MusicManager()
    private var cancellables = Set<AnyCancellable>()
    private var controllerCancellables = Set<AnyCancellable>()
    private var debounceIdleTask: Task<Void, Never>?
    private var optimisticPlayStateTimeoutTask: Task<Void, Never>?
    @MainActor private var optimisticPlaybackTransition = OptimisticPlaybackTransition()

    // Helper to check if macOS has removed support for NowPlayingController
    public private(set) var isNowPlayingDeprecated: Bool = false
    private let mediaChecker = MediaChecker()

    // Active controller
    private var activeController: (any MediaControllerProtocol)?

    // Pear Desktop auto-detection
    private static let pearDesktopBundleID = YouTubeMusicConfiguration.default.bundleIdentifier
    private var isPearDesktopAutoSwitched: Bool = false

    // Published properties for UI
    @Published var songTitle: String = "I'm Handsome"
    @Published var artistName: String = "Me"
    @Published var albumArt: NSImage = defaultImage
    @Published var isPlaying = false
    @Published var album: String = "Self Love"
    @Published var isPlayerIdle: Bool = true
    @Published var isCurrentTrackExplicit: Bool = false

    /// Whether there is an active music session with real metadata.
    /// Returns `false` only when the metadata is still placeholder/fallback defaults
    /// (i.e. nothing has been played since app launch, or the controller returned
    /// unknown/not-playing placeholders). Paused music with real metadata is still
    /// considered an active session.
    private static let placeholderTitles: Set<String> = [
        "i'm handsome", "unknown", "not playing"
    ]
    private static let placeholderArtists: Set<String> = [
        "me", "unknown"
    ]

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
    @Published var secondaryColor: NSColor = .gray
    @Published var bundleIdentifier: String? = nil

    var isAppleMusicActive: Bool { bundleIdentifier == "com.apple.Music" }
    var isSpotifyActive: Bool { bundleIdentifier == SpotifyController.bundleIdentifier }
    /// Whether favouriting applies to the playing source at all. Decides
    /// whether the control is offered in settings and kept in the layout, so
    /// it must not change with playback or connection state.
    @MainActor
    var activeSourceCanEverFavorite: Bool { activeController?.canEverFavorite ?? false }

    /// Whether favouriting would work right now -- the app is playing, the
    /// account is connected. Decides only whether the control is enabled.
    @MainActor
    var activeSourceSupportsFavoriting: Bool { activeController?.supportsFavoriting ?? false }

    /// True when the playing source will show the favourited state but not
    /// change it. The heart stays lit and stops taking clicks.
    var activeSourceFavoritingIsReadOnly: Bool { activeController?.favoritingIsReadOnly ?? false }
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
    private var lyricsFetchTask: Task<Void, Never>?
    private var lyricsFetchKey: LyricsLookupKey?
    // Identity of the fetch that is allowed to write lyrics state. A cancelled
    // task can still reach its completion handler, and the key alone does not
    // tell it apart from a newer fetch for the same track.
    private var lyricsFetchID: UUID?
    private var activeLyricsKey: LyricsLookupKey?
    private var lyricsCache: [LyricsLookupKey: [LyricLine]] = [:]
    // Bounded, insertion-order eviction so the cache cannot grow unboundedly.
    private static let lyricsCacheLimit = 80
    private var lyricsCacheOrder: [LyricsLookupKey] = []
    private var explicitLookupTask: Task<Void, Never>?
    private var explicitLookupKey: String?

    // MARK: - Favourite current track
    /// nil = unknown (the source cannot favourite, is not connected, or the
    /// lookup is still running) — the control renders disabled.
    @Published private(set) var isCurrentTrackLiked: Bool? = nil
    /// Whether the playing source can favourite at all, so a view can hide the
    /// control outright rather than show one that will never do anything.
    @Published private(set) var canFavoriteCurrentTrack: Bool = false

    private static let tidalModeRefreshInterval: TimeInterval = 2
    private var lastTidalModeRefresh = Date.distantPast
    private var tidalModeTask: Task<Void, Never>?
    /// Identifies the track a lookup belongs to, so a result arriving after the
    /// track changed is discarded.
    private var likedLookupTrackID: String?
    private var likedLookupTask: Task<Void, Never>?
    private var likeToggleTask: Task<Void, Never>?

    /// Inserts lyrics with insertion-order eviction to keep the cache bounded.
    private func storeLyricsInCache(_ lyrics: [LyricLine], for key: LyricsLookupKey) {
        if lyricsCache[key] == nil {
            lyricsCacheOrder.append(key)
            while lyricsCacheOrder.count > Self.lyricsCacheLimit {
                let evicted = lyricsCacheOrder.removeFirst()
                lyricsCache.removeValue(forKey: evicted)
            }
        }
        lyricsCache[key] = lyrics
    }

    private(set) var artworkData: Data? = nil
    private var manualTrackArtworkHandoff = ManualTrackArtworkHandoff()
    private var artworkHandoffTask: Task<Void, Never>?
    private var pendingHandoffArtwork: NSImage?

    @Published var videoArtworkURL: URL? = nil

    private var liveStreamUnknownDurationCount: Int = 0
    private var liveStreamEdgeObservationCount: Int = 0
    private var liveStreamCompletionObservationCount: Int = 0
    private var liveStreamCompletionReleaseCount: Int = 0

    // Store last values at the time artwork was changed
    private var lastArtworkTitle: String = "I'm Handsome"
    private var lastArtworkArtist: String = "Me"
    private var lastArtworkAlbum: String = "Self Love"
    private var lastArtworkBundleIdentifier: String? = nil
    private var lastArtworkContentIdentifier: String? = nil
    private var lastArtworkContentURL: String? = nil

    @Published var flipAngle: Double = 0
    @Published var lastFlipDirection: SkipDirection = .forward
    private let flipAnimationDuration: TimeInterval = 0.45
    private var flipCooldownActive: Bool = false

    @Published var isTransitioning: Bool = false
    private var transitionWorkItem: DispatchWorkItem?
    private var skipGestureToken: Int = 0

    // MARK: - Initialization
    init(startsControllerSetup: Bool = true) {
        guard startsControllerSetup else { return }

        // Listen for changes to the default controller preference
        NotificationCenter.default.publisher(for: Notification.Name.mediaControllerChanged)
            .sink { [weak self] _ in
                self?.isPearDesktopAutoSwitched = false
                self?.setActiveControllerBasedOnPreference()
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableLyrics)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.handleLyricsPreferenceChange(isEnabled: change.newValue)
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
        optimisticPlayStateTimeoutTask?.cancel()
        lyricsFetchTask?.cancel()
        lyricSyncTask?.cancel()
        explicitLookupTask?.cancel()
        cancellables.removeAll()
        controllerCancellables.removeAll()
        transitionWorkItem?.cancel()
        artworkHandoffTask?.cancel()
        pendingHandoffArtwork = nil

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
        case .nowPlaying:
            // Only create NowPlayingController if not deprecated on this macOS version
            if !self.isNowPlayingDeprecated {
                newController = NowPlayingController()
            } else {
                return nil
            }
        case .appleMusic:
            newController = AppleMusicController()
        case .spotify:
            newController = SpotifyController()
        case .youtubeMusic:
            newController = YouTubeMusicController()
        case .amazonMusic:
            newController = AmazonMusicController()
        case .tidal:
            newController = TidalController()
        case .cider:
            newController = CiderController()
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
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func updateFromPlaybackState(_ state: PlaybackState) {
        // Check for playback state changes (playing/paused)
        let eventIsPlaying = state.isPlaying
        let expectedState = optimisticPlaybackTransition.expectedState
        let shouldApplyPlaybackEvent = optimisticPlaybackTransition.shouldApply(
            eventIsPlaying: eventIsPlaying
        )

        if shouldApplyPlaybackEvent {
            if expectedState != nil {
                optimisticPlayStateTimeoutTask?.cancel()
                optimisticPlayStateTimeoutTask = nil
            }

            if eventIsPlaying != self.isPlaying {
                let animation: Animation? = (expectedState == eventIsPlaying)
                    ? .smooth(duration: 0.18)
                    : .smooth
                applyPlayState(eventIsPlaying, animation: animation)

                if eventIsPlaying && !state.title.isEmpty && !state.artist.isEmpty {
                    self.updateSneakPeek()
                }
            } else {
                self.updateIdleState(state: eventIsPlaying)
            }
        }

        // Check for changes in track metadata using last artwork change values
        let titleChanged = state.title != self.lastArtworkTitle
        let artistChanged = state.artist != self.lastArtworkArtist
        let albumChanged = state.album != self.lastArtworkAlbum
        let bundleChanged = state.bundleIdentifier != self.lastArtworkBundleIdentifier
        let contentIdentifierChanged = state.contentIdentifier != self.lastArtworkContentIdentifier
        let contentURLChanged = state.contentURL != self.lastArtworkContentURL

        // Check for artwork changes
        let artworkChanged = state.artwork != nil && state.artwork != self.artworkData

        let hasContentChange =
            titleChanged
            || artistChanged
            || albumChanged
            || artworkChanged
            || bundleChanged
            || contentIdentifierChanged
            || contentURLChanged
        let liveArtworkChanged = state.liveArtworkURL != self.videoArtworkURL

        if liveArtworkChanged {
            self.videoArtworkURL = state.liveArtworkURL
        }

        if state.title != self.songTitle {
            self.songTitle = state.title
        }

        if state.artist != self.artistName {
            self.artistName = state.artist
        }

        if state.album != self.album {
            self.album = state.album
        }

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
            self.lastArtworkContentIdentifier = state.contentIdentifier
            self.lastArtworkContentURL = state.contentURL

            self.prepareLyricsForCurrentTrack()
            if let liveArtworkURL = state.liveArtworkURL {
                self.videoArtworkURL = liveArtworkURL
            } else {
                self.fetchVideoArtwork()
            }

            self.refreshExplicitFlag(for: state)


            // Only update sneak peek if there's actual content and something changed
            if shouldAutoPeekOnTrackChange && !state.title.isEmpty && !state.artist.isEmpty && state.isPlaying {
                self.updateSneakPeek()
            }
        } else if state.isExplicit != nil {
            self.refreshExplicitFlag(for: state)
        }

        let timeChanged = state.currentTime != self.elapsedTime
        let durationChanged = state.duration != self.songDuration
        let playbackRateChanged = state.playbackRate != self.playbackRate
        let shuffleChanged = state.isShuffled != self.isShuffled
        let repeatModeChanged = state.repeatMode != self.repeatMode

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
        
        // TIDAL reports neither on the media stream, so what arrives here is
        // the default rather than the truth. Its own menu is the authority.
        let sourceOwnsPlaybackModes = state.bundleIdentifier == TidalAccessibility.bundleIdentifier

        if shuffleChanged && !sourceOwnsPlaybackModes {
            self.isShuffled = state.isShuffled
        }

        if state.bundleIdentifier != self.bundleIdentifier {
            self.bundleIdentifier = state.bundleIdentifier
        }

        if repeatModeChanged && !sourceOwnsPlaybackModes {
            self.repeatMode = state.repeatMode
        }
        
        updateLiveStreamState(with: state)
        self.refreshLikedFlag(for: state)
        self.refreshTidalPlaybackModes(for: state)

        // Guarded like every other assignment in this method, and for the same
        // reason. This is a published property that several views read, so an
        // unconditional assign republishes MusicManager on every delivery from
        // the media stream and invalidates all of them.
        //
        // It is not a clock, it is the playback anchor: it moves when the
        // player re-anchors, which Spotify does roughly once a track. While
        // paused it re-sends the same instant indefinitely -- four samples six
        // seconds apart during this work carried a byte-identical timestamp.
        // Nearly every one of those assignments was writing a value that had
        // not changed.
        if state.lastUpdated != self.timestampDate {
            self.timestampDate = state.lastUpdated
        }

        // Manage lyric sync task based on playback/lyrics availability
        if Defaults[.enableLyrics] && !self.syncedLyrics.isEmpty {
            // Ensure syncing runs while lyrics are enabled
            startLyricSync()
        } else {
            stopLyricSync()
        }
    }

    /// TIDAL is the one source whose shuffle and repeat never arrive on the
    /// media stream -- it registers no command for either, so Media Remote has
    /// nothing to report. The state has to be asked for instead, and asking
    /// means reading TIDAL's menu, so it is paced rather than done on every
    /// delivery.
    @MainActor
    private func refreshTidalPlaybackModes(for state: PlaybackState) {
        guard state.bundleIdentifier == TidalAccessibility.bundleIdentifier,
              TidalAccessibility.isAvailable else { return }

        let now = Date()
        guard now.timeIntervalSince(lastTidalModeRefresh) >= Self.tidalModeRefreshInterval else {
            return
        }
        lastTidalModeRefresh = now

        tidalModeTask?.cancel()
        tidalModeTask = Task { [weak self] in
            let shuffled = await TidalAccessibility.isShuffled()
            let mode = await TidalAccessibility.repeatMode()
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                if let shuffled, self.isShuffled != shuffled { self.isShuffled = shuffled }
                if let mode, self.repeatMode != mode { self.repeatMode = mode }
            }
        }
    }

    @MainActor
    private func refreshLikedFlag(for state: PlaybackState) {
        // Favouriting is the playing source's own business: Music.app has a
        // scriptable property, Spotify has the account the user connected.
        // Ask whichever is playing rather than naming one of them here.
        guard let controller = activeController, controller.supportsFavoriting else {
            clearLikedState()
            return
        }

        // Any change of track invalidates the answer. There is no id that means
        // the same thing across every source, so the track's own identity is
        // what a lookup is keyed on.
        let trackKey = Self.favoriteTrackKey(for: state)
        guard !trackKey.isEmpty else {
            clearLikedState()
            return
        }

        if !canFavoriteCurrentTrack { canFavoriteCurrentTrack = true }
        guard likedLookupTrackID != trackKey else { return }

        likedLookupTask?.cancel()
        likeToggleTask?.cancel()
        likedLookupTrackID = trackKey
        isCurrentTrackLiked = nil

        likedLookupTask = Task { [weak self] in
            let favorited = await controller.isCurrentTrackFavorited()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.likedLookupTrackID == trackKey else { return }
                self.isCurrentTrackLiked = favorited
            }
        }
    }

    @MainActor
    private func clearLikedState() {
        likedLookupTask?.cancel()
        likedLookupTask = nil
        likedLookupTrackID = nil
        if canFavoriteCurrentTrack { canFavoriteCurrentTrack = false }
        if isCurrentTrackLiked != nil { isCurrentTrackLiked = nil }
    }

    /// Identity of the playing track, for deciding when a lookup is stale.
    ///
    /// Prefers whatever stable identifier the source gives; falls back to the
    /// metadata, which is all a scripted app like Music.app offers.
    private static func favoriteTrackKey(for state: PlaybackState) -> String {
        if let identifier = state.contentIdentifier, !identifier.isEmpty { return identifier }
        if let url = state.contentURL, !url.isEmpty { return url }
        let parts = [state.title, state.artist, state.album].filter { !$0.isEmpty }
        return parts.isEmpty ? "" : parts.joined(separator: "\u{1F}")
    }

    @MainActor
    func toggleLike() {
        guard let controller = activeController,
              controller.supportsFavoriting,
              !controller.favoritingIsReadOnly,
              let trackKey = likedLookupTrackID,
              let currentValue = isCurrentTrackLiked else { return }

        // Shown as done straight away, then put back if the source refuses:
        // scripting a running app and a network round trip are both slow
        // enough that waiting would feel like the click missed.
        let targetValue = !currentValue
        isCurrentTrackLiked = targetValue

        likeToggleTask?.cancel()
        likeToggleTask = Task { [weak self] in
            let success = await controller.setCurrentTrackFavorited(targetValue)
            guard !Task.isCancelled, !success else { return }
            await MainActor.run {
                guard let self, self.likedLookupTrackID == trackKey else { return }
                self.isCurrentTrackLiked = currentValue
            }
        }
    }

    @MainActor
    private func refreshExplicitFlag(for state: PlaybackState) {
        if let explicitValue = state.isExplicit {
            explicitLookupTask?.cancel()
            explicitLookupTask = nil
            explicitLookupKey = nil

            if isCurrentTrackExplicit != explicitValue {
                isCurrentTrackExplicit = explicitValue
            }
            return
        }

        if state.bundleIdentifier == SpotifyController.bundleIdentifier,
           let spotifyLookupKey = SpotifyExplicitnessResolver.LookupKey(
               contentIdentifier: state.contentIdentifier,
               contentURL: state.contentURL
           ) {
            let lookupIdentifier = "spotify|\(spotifyLookupKey.trackID)"
            let fallbackTitle = state.title
            let fallbackArtist = state.artist
            let fallbackAlbum = state.album
            guard explicitLookupKey != lookupIdentifier else { return }

            explicitLookupTask?.cancel()
            explicitLookupKey = lookupIdentifier

            if isCurrentTrackExplicit {
                isCurrentTrackExplicit = false
            }

            explicitLookupTask = Task { [weak self] in
                let isExplicit = await SpotifyExplicitnessResolver.shared.resolve(key: spotifyLookupKey)

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard let self,
                          self.explicitLookupKey == lookupIdentifier
                    else {
                        return
                    }

                    self.explicitLookupTask = nil

                    if let isExplicit {
                        self.isCurrentTrackExplicit = isExplicit
                    } else {
                        self.explicitLookupKey = nil
                        self.refreshGenericExplicitFlag(
                            title: fallbackTitle,
                            artist: fallbackArtist,
                            album: fallbackAlbum
                        )
                    }
                }
            }
            return
        }

        refreshGenericExplicitFlag(title: state.title, artist: state.artist, album: state.album)
    }

    @MainActor
    private func refreshGenericExplicitFlag(title: String, artist: String, album: String) {
        let lookupKey = MusicExplicitnessResolver.LookupKey(
            title: title,
            artist: artist,
            album: album
        )
        let lookupIdentifier = "generic|\(lookupKey.title)|\(lookupKey.artist)|\(lookupKey.album)"

        guard lookupKey.canResolve,
              !Self.placeholderTitles.contains(lookupKey.title),
              !Self.placeholderArtists.contains(lookupKey.artist)
        else {
            explicitLookupTask?.cancel()
            explicitLookupTask = nil
            explicitLookupKey = nil
            if isCurrentTrackExplicit {
                isCurrentTrackExplicit = false
            }
            return
        }

        guard explicitLookupKey != lookupIdentifier else { return }

        explicitLookupTask?.cancel()
        explicitLookupKey = lookupIdentifier

        if isCurrentTrackExplicit {
            isCurrentTrackExplicit = false
        }

        explicitLookupTask = Task { [weak self] in
            let isExplicit = await MusicExplicitnessResolver.shared.resolve(
                title: title,
                artist: artist,
                album: album
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      self.explicitLookupKey == lookupIdentifier
                else {
                    return
                }

                self.isCurrentTrackExplicit = isExplicit
                self.explicitLookupTask = nil
            }
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

    @MainActor
    func beginManualTrackArtworkHandoff() {
        artworkHandoffTask?.cancel()
        artworkHandoffTask = nil
        manualTrackArtworkHandoff.begin()
        schedulePendingArtworkHandoff()
    }

    @MainActor
    func updateAlbumArt(newAlbumArt: NSImage) {
        pendingHandoffArtwork = newAlbumArt
        schedulePendingArtworkHandoff()
    }

    @MainActor
    private func schedulePendingArtworkHandoff() {
        artworkHandoffTask?.cancel()
        artworkHandoffTask = nil

        guard let artwork = pendingHandoffArtwork else { return }
        guard let pending = manualTrackArtworkHandoff.pendingSchedule() else {
            pendingHandoffArtwork = nil
            applyAlbumArt(artwork)
            return
        }

        artworkHandoffTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(pending.delay))
            } catch {
                return
            }

            guard let self,
                  !Task.isCancelled,
                  self.manualTrackArtworkHandoff.complete(generation: pending.generation)
            else { return }

            self.artworkHandoffTask = nil
            self.pendingHandoffArtwork = nil
            self.applyAlbumArt(artwork)
        }
    }

    @MainActor
    private func applyAlbumArt(_ newAlbumArt: NSImage) {
        withAnimation(.smooth) {
            albumArt = newAlbumArt
            if Defaults[.coloredSpectrogram] {
                calculateAverageColor()
            }
        }
    }

    // MARK: - Playback Position Estimation
    public func estimatedPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        guard isPlaying else { return min(elapsedTime, songDuration) }

        let timeDifference = date.timeIntervalSince(timestampDate)
        let estimated = elapsedTime + (timeDifference * playbackRate)
        return min(max(0, estimated), songDuration)
    }

    func calculateAverageColor() {
        albumArt.prominentOpposingColors { [weak self] primary, secondary in
            DispatchQueue.main.async {
                withAnimation(.smooth) {
                    self?.avgColor = primary
                    self?.secondaryColor = secondary
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

    // MARK: - Public Methods for controlling playback
    func playPause() {
        Task {
            await activeController?.togglePlay()
        }
    }

    func play() {
        Task {
            await activeController?.play()
        }
    }

    func pause() {
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
        guard let controller = activeController else { return }
        let targetState = !isPlaying

        Task {
            await MainActor.run {
                optimisticPlaybackTransition.begin(expecting: targetState)
                applyPlayState(targetState, animation: .smooth(duration: 0.18))
                scheduleOptimisticPlayStateRecovery(
                    expecting: targetState,
                    controller: controller
                )
            }

            if targetState {
                await controller.play()
            } else {
                await controller.pause()
            }
        }
    }

    @MainActor
    private func scheduleOptimisticPlayStateRecovery(
        expecting targetState: Bool,
        controller: any MediaControllerProtocol
    ) {
        optimisticPlayStateTimeoutTask?.cancel()
        optimisticPlayStateTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.optimisticPlaybackRecoveryTimeout)
            guard !Task.isCancelled, let self else { return }

            let shouldRefresh = await MainActor.run {
                self.optimisticPlaybackTransition.cancel(ifExpecting: targetState)
            }
            guard shouldRefresh else { return }

            await controller.updatePlaybackInfo()
        }
    }

    func nextTrack() {
        guard let controller = activeController else { return }
        Task {
            await MainActor.run {
                beginManualTrackArtworkHandoff()
            }
            await controller.nextTrack()
        }
    }

    func previousTrack() {
        guard let controller = activeController else { return }
        Task {
            await MainActor.run {
                beginManualTrackArtworkHandoff()
            }
            await controller.previousTrack()
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
            workspace.openApplication(at: appURL, configuration: configuration) { (_, error) in
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
        prepareLyricsForCurrentTrack(forceFetch: true, prioritizeVisibleResult: Defaults[.enableLyrics])
    }

    private func handleLyricsPreferenceChange(isEnabled: Bool) {
        showLyrics = isEnabled

        if isEnabled {
            prepareLyricsForCurrentTrack(prioritizeVisibleResult: true)
        } else {
            discardLyrics()
        }
    }

    /// Drops any lyrics state and stops an in-flight fetch.
    private func discardLyrics() {
        activeLyricsKey = nil
        lyricsFetchKey = nil
        lyricsFetchID = nil
        lyricsFetchTask?.cancel()
        lyricsFetchTask = nil
        syncedLyrics = []
        currentLyrics = ""
        currentLyricIndex = -1
        stopLyricSync()
    }

    private func prepareLyricsForCurrentTrack(forceFetch: Bool = false, prioritizeVisibleResult: Bool = false) {
        // `enableLyrics` reached only as far as the display: with lyrics switched
        // off the placeholder was suppressed, but the track title and artist were
        // still sent to LRCLIB on every track change, and nothing consumed the
        // reply. Stop before the request rather than after it.
        guard Defaults[.enableLyrics] else {
            discardLyrics()
            return
        }

        guard let lookup = currentLyricsLookupContext() else {
            discardLyrics()
            return
        }

        let key = lookup.key
        let shouldShowLoading = prioritizeVisibleResult
        let trackChanged = activeLyricsKey != key
        activeLyricsKey = key

        if trackChanged {
            syncedLyrics = []
            currentLyricIndex = -1
            currentLyrics = shouldShowLoading ? "Loading lyrics..." : ""
            stopLyricSync()
        }

        if !forceFetch, let cachedLyrics = lyricsCache[key] {
            applyLyricsToDisplay(cachedLyrics)
            return
        }

        if lyricsFetchKey == key {
            if shouldShowLoading && syncedLyrics.isEmpty {
                currentLyrics = "Loading lyrics..."
            }
            return
        }

        lyricsFetchTask?.cancel()
        lyricsFetchKey = key
        let fetchID = UUID()
        lyricsFetchID = fetchID

        if shouldShowLoading || syncedLyrics.isEmpty {
            currentLyrics = "Loading lyrics..."
        }

        let requestArtist = lookup.requestArtist
        let requestTitle = lookup.requestTitle
        let requestAlbum = lookup.requestAlbum

        lyricsFetchTask = Task { [weak self] in
            guard let self else { return }

            do {
                let lyrics = try await self.fetchLyricsFromAPI(
                    artist: requestArtist,
                    title: requestTitle,
                    album: requestAlbum
                )
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.lyricsFetchID == fetchID, self.activeLyricsKey == key else { return }
                    self.storeLyricsInCache(lyrics, for: key)
                    self.lyricsFetchKey = nil
                    self.lyricsFetchID = nil
                    self.lyricsFetchTask = nil
                    self.applyLyricsToDisplay(lyrics)
                }
            } catch {
                print("Failed to fetch lyrics: \(error)")
                await MainActor.run {
                    guard self.lyricsFetchID == fetchID, self.activeLyricsKey == key else { return }
                    self.lyricsFetchKey = nil
                    self.lyricsFetchID = nil
                    self.lyricsFetchTask = nil
                    self.syncedLyrics = []
                    self.currentLyricIndex = -1
                    self.currentLyrics = "No lyrics found"
                    self.stopLyricSync()
                }
            }
        }
    }

    private func fetchLyricsFromAPI(artist: String, title: String, album: String) async throws -> [LyricLine] {
        guard !artist.isEmpty, !title.isEmpty else { return [] }

        // Normalize input and percent-encode
        let cleanArtist = artist.folding(options: .diacriticInsensitive, locale: .current)
        let cleanTitle = title.folding(options: .diacriticInsensitive, locale: .current)
        let cleanAlbum = album.folding(options: .diacriticInsensitive, locale: .current)
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
               let bestMatch = bestLyricsMatch(in: jsonArray, artist: cleanArtist, title: cleanTitle, album: cleanAlbum) {
                let first = bestMatch
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

    // pi-lens-ignore: large_tuple
    private func currentLyricsLookupContext() -> (key: LyricsLookupKey, requestArtist: String, requestTitle: String, requestAlbum: String)? {
        let requestArtist = normalizedLyricsRequestComponent(artistName)
        let requestTitle = normalizedLyricsTitle(songTitle)
        let requestAlbum = normalizedLyricsRequestComponent(album)

        let key = LyricsLookupKey(
            title: requestTitle.lowercased(),
            artist: requestArtist.lowercased(),
            album: requestAlbum.lowercased()
        )

        return key.isValid ? (key, requestArtist, requestTitle, requestAlbum) : nil
    }

    private func normalizedLyricsRequestComponent(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func normalizedLyricsTitle(_ value: String) -> String {
        var normalized = normalizedLyricsRequestComponent(value)
        let cleanupPatterns = [
            "\\s*\\((feat\\.?|ft\\.?|featuring)[^\\)]*\\)",
            "\\s*\\[(feat\\.?|ft\\.?|featuring)[^\\]]*\\]",
            "\\s*-\\s*(feat\\.?|ft\\.?|featuring)\\s+.*$",
            "\\s*\\((remaster(ed)?|live|mono|stereo)[^\\)]*\\)$",
            "\\s*\\[(remaster(ed)?|live|mono|stereo)[^\\]]*\\]$"
        ]

        for pattern in cleanupPatterns {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return normalizedLyricsRequestComponent(normalized)
    }

    private func bestLyricsMatch(in results: [[String: Any]], artist: String, title: String, album: String) -> [String: Any]? {
        LyricsSearchResults.bestMatch(in: results, artist: artist, title: title, album: album)
    }

    private func applyLyricsToDisplay(_ lyrics: [LyricLine]) {
        syncedLyrics = lyrics
        currentLyricIndex = -1

        guard !lyrics.isEmpty else {
            currentLyrics = Defaults[.enableLyrics] ? "No lyrics found" : ""
            stopLyricSync()
            return
        }

        updateCurrentLyric(for: lyricPlaybackPosition())

        if Defaults[.enableLyrics] {
            startLyricSync()
        } else {
            stopLyricSync()
        }
    }

    private func parseLRC(_ lrc: String) -> [LyricLine] {
        LRCParser.parse(lrc)
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

        // The text is settled independently of whether the index moved. Lyrics
        // arrive with the index already at -1, so keying the text off a change in
        // the index leaves whatever was there before standing.
        let newText = newIndex >= 0 && newIndex < syncedLyrics.count
            ? syncedLyrics[newIndex].text
            : ""

        if newIndex != currentLyricIndex {
            currentLyricIndex = newIndex
        }

        // Compared before assigning: this runs on every sync tick, and writing an
        // unchanged value would republish and redraw for nothing.
        if currentLyrics != newText {
            currentLyrics = newText
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
                let position = self.lyricPlaybackPosition()
                let delay = await MainActor.run { () -> TimeInterval in
                    self.updateCurrentLyric(for: position)
                    return self.delayUntilNextLyric(after: position)
                }

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// Playback position for lyric purposes, tolerant of a missing duration.
    ///
    /// `estimatedPlaybackPosition` clamps to `songDuration`, which is zero until
    /// the duration arrives and for streams that never report one -- so it answers
    /// zero however far playback has actually got, which pegs every lyric at the
    /// start of the track. Elapsed time is the better answer there.
    private func lyricPlaybackPosition(at date: Date = Date()) -> TimeInterval {
        // `estimatedPlaybackPosition` clamps to the duration, so a sender that
        // reports none -- a live stream, or a player that simply does not --
        // pins every estimate to zero and the lyrics stop moving between
        // deliveries. Extrapolate from the anchor directly in that case; a
        // paused track has nothing to extrapolate and stays where it is.
        let position: TimeInterval
        if songDuration > 0 {
            position = max(estimatedPlaybackPosition(at: date), elapsedTime)
        } else if isPlaying {
            position = max(0, elapsedTime + date.timeIntervalSince(timestampDate) * playbackRate)
        } else {
            position = max(0, elapsedTime)
        }
        return position + Self.lyricLeadTime
    }

    /// How far ahead of the voice the lyrics run.
    ///
    /// A line that arrives exactly on its timestamp arrives too late to read:
    /// the word is already being sung by the time the eye finds it. Every
    /// karaoke display leads the voice slightly, and so did this one before the
    /// playback anchor was fixed -- a stale anchor made the estimate run ahead,
    /// which is why the lyrics used to feel better timed while the clock beside
    /// them was wrong.
    ///
    /// So the lead is kept, and made deliberate: a quarter second, applied to
    /// the position every lyric decision is made from, rather than left to
    /// depend on how badly the position was drifting.
    static let lyricLeadTime: TimeInterval = 0.25

    /// Gaps shorter than this are breaths between lines rather than instrumental
    /// breaks; marking them would flicker.
    static let instrumentalBreakThreshold: TimeInterval = 5

    /// Whether playback is in a stretch with no words long enough to be worth
    /// marking, rather than simply between two sung lines.
    ///
    /// LRC marks where singing stops with a bare timestamp, so a break is a
    /// blank line that runs for a while. The run-up to the first line counts too,
    /// which is what covers a song's intro.
    var isInInstrumentalBreak: Bool {
        guard !syncedLyrics.isEmpty else { return false }

        let index = currentLyricIndex
        if index < 0 {
            // Before the first line: the intro is a break if it is long enough.
            return (syncedLyrics.first?.timestamp ?? 0) >= Self.instrumentalBreakThreshold
        }

        guard index < syncedLyrics.count,
              syncedLyrics[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let window = lyricWindow(at: index)
        else { return false }

        return window.end - window.start >= Self.instrumentalBreakThreshold
    }

    /// The stretch of the track the lyric line at `index` is on screen for.
    ///
    /// The window ends where the next line begins, whatever that line is -- an
    /// empty one marks where singing stops, so it closes the window just as a
    /// sung line would.
    func lyricWindow(at index: Int) -> (start: TimeInterval, end: TimeInterval)? {
        // -1 is the run-up to the first line, which is the index the current line
        // holds before any line has started and which the intro marker keys off.
        if index < 0 {
            guard let first = syncedLyrics.first, first.timestamp > 0 else { return nil }
            return (0, first.timestamp)
        }

        guard index < syncedLyrics.count else { return nil }

        let start = syncedLyrics[index].timestamp
        let end: TimeInterval
        if index + 1 < syncedLyrics.count {
            end = syncedLyrics[index + 1].timestamp
        } else if songDuration > start {
            end = songDuration
        } else {
            return nil
        }

        guard end > start else { return nil }
        return (start, end)
    }

    /// How far playback has moved through the line currently on screen, 0...1.
    ///
    /// Drives the highlight that sweeps across the line as it is sung. Returns 0
    /// when there is no line to sweep, so the caller draws an unstarted line
    /// rather than a fully swept one.
    func currentLyricSweepProgress(at date: Date = Date()) -> Double {
        guard let window = lyricWindow(at: currentLyricIndex) else { return 0 }
        let elapsed = lyricPlaybackPosition(at: date) - window.start
        return min(max(elapsed / (window.end - window.start), 0), 1)
    }

    /// How long to wait before the displayed lyric could next change.
    ///
    /// A fixed polling interval shows every line up to that interval late. Sleeping
    /// until the next line's own timestamp lands on the boundary instead. The upper
    /// bound keeps seeks and pauses responsive, and the lower bound stops the loop
    /// from spinning through lines that share a timestamp.
    private func delayUntilNextLyric(after position: TimeInterval) -> TimeInterval {
        let minimumDelay: TimeInterval = 0.05
        let maximumDelay: TimeInterval = 0.25

        guard isPlaying, playbackRate > 0,
              let next = syncedLyrics.first(where: { $0.timestamp > position })
        else { return maximumDelay }

        let untilNext = (next.timestamp - position) / playbackRate
        return min(max(untilNext, minimumDelay), maximumDelay)
    }

    private func stopLyricSync() {
        lyricSyncTask?.cancel()
        lyricSyncTask = nil
    }

    // MARK: - Video Artwork

    func fetchVideoArtwork() {
        guard Defaults[.lockScreenMusicFullscreenVideoArtwork] else {
            videoArtworkURL = nil
            return
        }
        // Se il player non è Apple Music, non toccare videoArtworkURL:
        // SpotifyController gestisce il canvas in modo autonomo tramite liveArtworkURL.
        guard bundleIdentifier == "com.apple.Music" else {
            return
        }

        let title = songTitle
        let artist = artistName

        Task {
            let url = await AnimatedArtworkManager.shared.fetchAnimatedArtworkURL(
                title: title, artist: artist
            )
            await MainActor.run {
                self.videoArtworkURL = url
            }
        }
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
        case .amazonMusic:
            return amazonOrange
        case .tidal, .cider:
            return .accentColor
        case .nowPlaying:
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
        case AmazonMusicController.bundleIdentifier:
            return amazonOrange
        case TidalController.bundleIdentifier:
            return .accentColor
        case CiderController.bundleIdentifier:
            return .accentColor
        default:
            return nil
        }
    }

    private static let appleMusicPink = Color(red: 0.999, green: 0.171, blue: 0.331)
    private static let spotifyGreen = Color(red: 0.0, green: 0.857, blue: 0.302)
    private static let amazonOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
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
        return degrees.truncatingRemainder(dividingBy: 360) >= 0 ? -1 : 1
    }
}

extension View {
    func albumArtFlip(angle: Double) -> some View {
        modifier(AlbumArtFlipModifier(angle: angle))
    }
}
