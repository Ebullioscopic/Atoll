/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import ApplicationServices
import Combine
import Darwin
import Foundation

@MainActor
final class QobuzMediaController: ObservableObject, @preconcurrency MediaControllerProtocol {
    static let bundleIdentifier = "com.qobuz.desktop"

    @Published private var playbackState = PlaybackState(bundleIdentifier: QobuzMediaController.bundleIdentifier)

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var isWorking: Bool { isActive() }
    var supportsLike: Bool { true }

    private var distributedObserver: NSObjectProtocol?
    private var workspaceCancellables = Set<AnyCancellable>()
    private var stateFileSource: DispatchSourceFileSystemObject?
    private var stateFileDescriptor: CInt = -1
    private var assetDirectorySource: DispatchSourceFileSystemObject?
    private var assetDirectoryDescriptor: CInt = -1
    private var localStateRefreshTask: Task<Void, Never>?
    private var assetRefreshTask: Task<Void, Never>?
    private var lastArtworkPath: String?

    private let supportDirectoryURL: URL = {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return supportURL.appendingPathComponent("Qobuz", isDirectory: true)
    }()

    private let assetDirectoryURL: URL = {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return supportURL
            .appendingPathComponent("Qobuz", isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent("Assets", isDirectory: true)
    }()

    init() {
        var initialState = playbackState
        initialState.supportsLike = true
        initialState.isPlaying = isActive()
        playbackState = initialState

        setupDistributedNotificationObserver()
        setupWorkspaceObservers()
        setupLocalStateWatcher()
        setupArtworkCacheWatcher()

        Task { await updatePlaybackInfo() }
    }

    deinit {
        if let distributedObserver {
            DistributedNotificationCenter.default().removeObserver(distributedObserver)
        }
        localStateRefreshTask?.cancel()
        assetRefreshTask?.cancel()
        if let stateFileSource {
            stateFileSource.cancel()
        } else if stateFileDescriptor >= 0 {
            close(stateFileDescriptor)
        }
        stateFileDescriptor = -1
        if let assetDirectorySource {
            assetDirectorySource.cancel()
        } else if assetDirectoryDescriptor >= 0 {
            close(assetDirectoryDescriptor)
        }
        assetDirectoryDescriptor = -1
    }

    func play() async {
        sendMediaKey(NX_KEYTYPE_PLAY)
        await refreshAfterCommand(isPlaying: true)
    }

    func pause() async {
        sendMediaKey(NX_KEYTYPE_PLAY)
        await refreshAfterCommand(isPlaying: false)
    }

    func togglePlay() async {
        sendMediaKey(NX_KEYTYPE_PLAY)
        await refreshAfterCommand(isPlaying: !playbackState.isPlaying)
    }

    func nextTrack() async {
        sendMediaKey(NX_KEYTYPE_FAST)
        await refreshAfterCommand(isPlaying: true)
    }

    func previousTrack() async {
        sendMediaKey(NX_KEYTYPE_REWIND)
        await refreshAfterCommand(isPlaying: true)
    }

    func seek(to time: Double) async {}
    func toggleShuffle() async {}
    func toggleRepeat() async {}

    func toggleLike() async {
        guard accessibilityIsTrusted() else {
            print("[QobuzMediaController] Accessibility permission is required to press the Qobuz Like button in the background.")
            return
        }

        guard pressFirstMatchingAXButton() else {
            print("[QobuzMediaController] Could not find a Qobuz Like/Favorite button in the accessibility tree.")
            return
        }

        var updatedState = playbackState
        updatedState.isLiked.toggle()
        updatedState.supportsLike = true
        updatedState.lastUpdated = Date()
        playbackState = updatedState
    }

    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.bundleIdentifier }
    }

    func updatePlaybackInfo() async {
        refreshFromLocalState()
    }

    private func setupDistributedNotificationObserver() {
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: nil,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleDistributedNotification(notification)
            }
        }
    }

    private func setupWorkspaceObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter

        workspaceCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: workspaceCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .sink { [weak self] notification in
                guard let self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.bundleIdentifier
                else { return }

                var updatedState = self.playbackState
                updatedState.isPlaying = self.isActive()
                updatedState.supportsLike = true
                updatedState.lastUpdated = Date()
                self.playbackState = updatedState

                if app.isTerminated == false {
                    self.setupLocalStateWatcher()
                    self.setupArtworkCacheWatcher()
                    self.scheduleLocalStateRefresh(delay: 250)
                }
            }
            .store(in: &workspaceCancellables)
    }

    private func setupArtworkCacheWatcher() {
        guard assetDirectorySource == nil else { return }

        let path = assetDirectoryURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            print("[QobuzMediaController] Artwork cache directory is not present yet: \(path)")
            return
        }

        assetDirectoryDescriptor = open(path, O_EVTONLY)
        guard assetDirectoryDescriptor >= 0 else {
            print("[QobuzMediaController] Could not watch Qobuz artwork cache: \(path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: assetDirectoryDescriptor,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            self?.scheduleArtworkRefresh()
        }

        source.setCancelHandler { [descriptor = assetDirectoryDescriptor] in
            if descriptor >= 0 {
                close(descriptor)
            }
        }

        assetDirectorySource = source
        source.resume()
    }

    private func setupLocalStateWatcher() {
        guard stateFileSource == nil else { return }

        let stateURL = supportDirectoryURL.appendingPathComponent("player-0.json")
        let path = stateURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            print("[QobuzMediaController] Qobuz player state is not present yet: \(path)")
            return
        }

        stateFileDescriptor = open(path, O_EVTONLY)
        guard stateFileDescriptor >= 0 else {
            print("[QobuzMediaController] Could not watch Qobuz player state: \(path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: stateFileDescriptor,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: DispatchQueue.main
        )

        source.setEventHandler { [weak self] in
            self?.scheduleLocalStateRefresh(delay: 150)
        }

        source.setCancelHandler { [descriptor = stateFileDescriptor] in
            if descriptor >= 0 {
                close(descriptor)
            }
        }

        stateFileSource = source
        source.resume()
    }

    private func handleDistributedNotification(_ notification: Notification) {
        let searchableText = [
            notification.name.rawValue,
            notification.object as? String,
            notification.userInfo?.description
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        guard searchableText.contains("qobuz") || searchableText.contains(Self.bundleIdentifier) else {
            return
        }

        let values = flattenedUserInfo(notification.userInfo)
        let title = value(in: values, matching: ["title", "track", "name"]) ?? playbackState.title
        let artist = value(in: values, matching: ["artist", "subtitle"]) ?? playbackState.artist
        let album = value(in: values, matching: ["album"]) ?? playbackState.album
        let liked = boolValue(in: values, matching: ["liked", "favorite", "favourite"])

        var updatedState = playbackState
        updatedState.title = title
        updatedState.artist = artist
        updatedState.album = album
        updatedState.isPlaying = true
        updatedState.supportsLike = true
        updatedState.isLiked = liked ?? updatedState.isLiked
        updatedState.lastUpdated = Date()
        playbackState = updatedState

        scheduleArtworkRefresh()
    }

    private func scheduleArtworkRefresh() {
        assetRefreshTask?.cancel()
        assetRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.refreshFromLatestArtwork()
            }
        }
    }

    private func scheduleLocalStateRefresh(delay milliseconds: UInt64 = 250) {
        localStateRefreshTask?.cancel()
        localStateRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.refreshFromLocalState()
            }
        }
    }

    private func refreshAfterCommand(isPlaying: Bool) async {
        var updatedState = playbackState
        updatedState.isPlaying = isPlaying
        updatedState.supportsLike = true
        updatedState.lastUpdated = Date()
        playbackState = updatedState

        try? await Task.sleep(for: .milliseconds(250))
        await updatePlaybackInfo()
    }

    private func refreshFromLocalState() {
        guard let snapshot = readLocalSnapshot() else {
            refreshFromLatestArtwork()
            return
        }

        var updatedState = playbackState
        updatedState.bundleIdentifier = Self.bundleIdentifier
        updatedState.title = snapshot.title
        updatedState.artist = snapshot.artist
        updatedState.album = snapshot.album
        updatedState.contentIdentifier = snapshot.contentIdentifier
        updatedState.currentTime = snapshot.currentTime ?? updatedState.currentTime
        updatedState.duration = snapshot.duration ?? updatedState.duration
        updatedState.isShuffled = snapshot.isShuffled
        updatedState.repeatMode = snapshot.repeatMode
        updatedState.isPlaying = isActive()
        updatedState.supportsLike = true

        if let artworkURL = artworkURL(forReleaseID: snapshot.releaseID) ?? latestArtworkURL(),
           let artwork = try? Data(contentsOf: artworkURL),
           !artwork.isEmpty {
            updatedState.artwork = artwork
            lastArtworkPath = artworkURL.path
        }

        updatedState.lastUpdated = Date()
        playbackState = updatedState
    }

    private struct LocalSnapshot {
        var title: String
        var artist: String
        var album: String
        var contentIdentifier: String
        var currentTime: Double?
        var duration: Double?
        var isShuffled: Bool
        var repeatMode: RepeatMode
        var releaseID: String?
    }

    private struct TrackMetadata {
        var title: String
        var artist: String
        var album: String
        var duration: Double?
        var releaseID: String?
    }

    private func readLocalSnapshot() -> LocalSnapshot? {
        let stateURL = supportDirectoryURL.appendingPathComponent("player-0.json")
        guard let stateData = try? Data(contentsOf: stateURL),
              let state = try? JSONSerialization.jsonObject(with: stateData) as? [String: Any],
              let playqueue = state["playqueue"] as? [String: Any],
              let playqueueData = playqueue["data"] as? [String: Any],
              let currentIndex = intValue(playqueueData["currentIndex"])
        else {
            return nil
        }

        let shuffled = boolValue(playqueueData["shuffled"]) ?? false
        let preferredItems = shuffled
            ? playqueueData["shuffledItems"] as? [[String: Any]]
            : playqueueData["items"] as? [[String: Any]]
        let fallbackItems = playqueueData["items"] as? [[String: Any]]

        guard let trackID = trackID(at: currentIndex, in: preferredItems)
            ?? trackID(at: currentIndex, in: fallbackItems),
              let metadata = queryTrackMetadata(trackID: trackID)
        else {
            return nil
        }

        let playback = state["player"] as? [String: Any]
        let playbackData = playback?["data"] as? [String: Any]
        let position = playbackData?["position"] as? [String: Any]
        let currentTimeMilliseconds = doubleValue(position?["value"])

        return LocalSnapshot(
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            contentIdentifier: String(trackID),
            currentTime: currentTimeMilliseconds.map { $0 / 1000.0 },
            duration: metadata.duration,
            isShuffled: shuffled,
            repeatMode: repeatMode(from: playqueueData["repeatMode"]),
            releaseID: metadata.releaseID
        )
    }

    private func trackID(at index: Int, in items: [[String: Any]]?) -> Int? {
        guard let items, items.indices.contains(index) else { return nil }
        return intValue(items[index]["trackId"])
    }

    private func queryTrackMetadata(trackID: Int) -> TrackMetadata? {
        let databasePath = supportDirectoryURL.appendingPathComponent("qobuz.db").path
        let query = """
        select id, title, track_artists_names, release_name, duration, release_id
        from S_Track
        where id = \(trackID)
        union all
        select
          cast(t.track_id as integer) as id,
          t.title as title,
          coalesce(ar.name, 'Qobuz') as track_artists_names,
          coalesce(a.title, t.title) as release_name,
          t.duration as duration,
          t.album_id as release_id
        from L_Track t
        left join L_Album a on a.id = t.album_id
        left join L_Artist ar on ar.id = t.artist_id
        where t.track_id = '\(trackID)' or t.id = \(trackID)
        limit 1;
        """

        guard let row = sqliteJSONRows(databasePath: databasePath, query: query).first else {
            return nil
        }

        return TrackMetadata(
            title: nonEmpty(row["title"] as? String) ?? "Qobuz",
            artist: nonEmpty(row["track_artists_names"] as? String) ?? "Qobuz",
            album: nonEmpty(row["release_name"] as? String) ?? nonEmpty(row["title"] as? String) ?? "Qobuz",
            duration: doubleValue(row["duration"]),
            releaseID: nonEmpty(row["release_id"] as? String)
        )
    }

    private func sqliteJSONRows(databasePath: String, query: String) -> [[String: Any]] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", databasePath, query]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                return []
            }
            return rows
        } catch {
            return []
        }
    }

    private func artworkURL(forReleaseID releaseID: String?) -> URL? {
        guard let releaseID, !releaseID.isEmpty else { return nil }
        let releaseDirectory = assetDirectoryURL.appendingPathComponent(releaseID, isDirectory: true)
        let large = releaseDirectory.appendingPathComponent("large_cover.png")
        if FileManager.default.fileExists(atPath: large.path) {
            return large
        }

        let small = releaseDirectory.appendingPathComponent("small_cover.png")
        if FileManager.default.fileExists(atPath: small.path) {
            return small
        }

        return nil
    }

    private func repeatMode(from value: Any?) -> RepeatMode {
        guard let raw = value as? String else { return .off }
        switch raw {
        case "repeatOne", "one":
            return .one
        case "repeatAll", "all":
            return .all
        default:
            return .off
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            switch value.lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    private func refreshFromLatestArtwork() {
        guard let latestArtworkURL = latestArtworkURL() else {
            return
        }

        guard latestArtworkURL.path != lastArtworkPath else {
            return
        }

        guard let artwork = try? Data(contentsOf: latestArtworkURL), !artwork.isEmpty else {
            return
        }

        lastArtworkPath = latestArtworkURL.path

        var updatedState = playbackState
        updatedState.bundleIdentifier = Self.bundleIdentifier
        updatedState.artwork = artwork
        updatedState.supportsLike = true
        updatedState.isPlaying = isActive() ? updatedState.isPlaying : false
        updatedState.lastUpdated = Date()
        playbackState = updatedState
    }

    private func latestArtworkURL() -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: assetDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var candidates: [(url: URL, date: Date)] = []

        for case let url as URL in enumerator {
            let filename = url.lastPathComponent.lowercased()
            guard filename == "large_cover.png" || filename == "small_cover.png" else {
                continue
            }

            guard let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true,
                  let date = resourceValues.contentModificationDate
            else {
                continue
            }

            candidates.append((url, date))
        }

        return candidates
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.url.lastPathComponent == "large_cover.png"
                }
                return lhs.date > rhs.date
            }
            .first?
            .url
    }

    private func sendMediaKey(_ key: Int32) {
        postMediaKey(key, keyDown: true)
        postMediaKey(key, keyDown: false)
    }

    private func postMediaKey(_ key: Int32, keyDown: Bool) {
        let flags = keyDown ? 0xA00 : 0xB00
        let data1 = (key << 16) | Int32(flags)

        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: Int(data1),
            data2: -1
        )?.cgEvent else {
            return
        }

        event.post(tap: .cghidEventTap)
    }

    private func accessibilityIsTrusted() -> Bool {
        AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary)
    }

    private func pressFirstMatchingAXButton() -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == Self.bundleIdentifier }) else {
            return false
        }

        let root = AXUIElementCreateApplication(app.processIdentifier)
        return pressLikeButton(in: root, depth: 0)
    }

    private func pressLikeButton(in element: AXUIElement, depth: Int) -> Bool {
        guard depth < 9 else { return false }

        if elementLooksLikeLikeButton(element),
           AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return true
        }

        var childrenObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenObject) == .success,
              let children = childrenObject as? [AXUIElement]
        else {
            return false
        }

        for child in children {
            if pressLikeButton(in: child, depth: depth + 1) {
                return true
            }
        }

        return false
    }

    private func elementLooksLikeLikeButton(_ element: AXUIElement) -> Bool {
        let role = axString(element, attribute: kAXRoleAttribute)
        guard role == kAXButtonRole as String else { return false }

        let labels = [
            axString(element, attribute: kAXTitleAttribute),
            axString(element, attribute: kAXDescriptionAttribute),
            axString(element, attribute: kAXHelpAttribute),
            axString(element, attribute: kAXIdentifierAttribute),
            axString(element, attribute: kAXValueAttribute)
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()

        return labels.contains("like")
            || labels.contains("liked")
            || labels.contains("favorite")
            || labels.contains("favourite")
            || labels.contains("favorito")
            || labels.contains("curtir")
            || labels.contains("heart")
            || labels.contains("coracao")
    }

    private func axString(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func flattenedUserInfo(_ userInfo: [AnyHashable: Any]?) -> [String: String] {
        guard let userInfo else { return [:] }

        var output: [String: String] = [:]

        func append(prefix: String, value: Any) {
            switch value {
            case let dictionary as [AnyHashable: Any]:
                for (key, nestedValue) in dictionary {
                    append(prefix: "\(prefix).\(key)", value: nestedValue)
                }
            case let array as [Any]:
                for (index, nestedValue) in array.enumerated() {
                    append(prefix: "\(prefix).\(index)", value: nestedValue)
                }
            default:
                output[prefix.lowercased()] = String(describing: value)
            }
        }

        for (key, value) in userInfo {
            append(prefix: String(describing: key), value: value)
        }

        return output
    }

    private func value(in values: [String: String], matching keys: [String]) -> String? {
        for key in keys {
            if let match = values.first(where: { $0.key.contains(key) })?.value,
               !match.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return match
            }
        }

        return nil
    }

    private func boolValue(in values: [String: String], matching keys: [String]) -> Bool? {
        guard let rawValue = value(in: values, matching: keys)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else {
            return nil
        }

        if ["1", "true", "yes", "liked", "favorite", "favourite"].contains(rawValue) {
            return true
        }

        if ["0", "false", "no", "unliked"].contains(rawValue) {
            return false
        }

        return nil
    }
}
