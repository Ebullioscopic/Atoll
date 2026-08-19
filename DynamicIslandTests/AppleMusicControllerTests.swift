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
import Combine
import XCTest
@testable import Atoll

@MainActor
final class AppleMusicControllerTests: XCTestCase {
    private actor EventRecorder {
        private var events: [String] = []

        func record(_ event: String) {
            events.append(event)
        }

        func snapshot() -> [String] {
            events
        }
    }

    private actor PlaybackInfoProvider {
        private var values: [AppleMusicPlaybackInfo]

        init(values: [AppleMusicPlaybackInfo]) {
            self.values = values
        }

        func next() -> AppleMusicPlaybackInfo? {
            values.isEmpty ? nil : values.removeFirst()
        }
    }

    private actor OutOfOrderPlaybackInfoProvider {
        private var nextRequestID = 0
        private var continuations: [Int: CheckedContinuation<AppleMusicPlaybackInfo?, Never>] = [:]

        func next() async -> AppleMusicPlaybackInfo? {
            let requestID = nextRequestID
            nextRequestID += 1
            return await withCheckedContinuation { continuation in
                continuations[requestID] = continuation
            }
        }

        func waitForRequestCount(_ count: Int) async {
            while continuations.count < count {
                await Task.yield()
            }
        }

        func complete(requestID: Int, with info: AppleMusicPlaybackInfo?) {
            continuations.removeValue(forKey: requestID)?.resume(returning: info)
        }
    }

    private actor DeferredArtworkProvider {
        private var continuation: CheckedContinuation<Data?, Never>?
        private var completedArtwork: Data?
        private var isCompleted = false

        func fetch(title: String, artist: String, album: String) async -> Data? {
            if isCompleted {
                return completedArtwork
            }

            precondition(
                continuation == nil,
                "DeferredArtworkProvider supports one pending fetch"
            )
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func complete(with artwork: Data?) {
            isCompleted = true
            completedArtwork = artwork
            continuation?.resume(returning: artwork)
            continuation = nil
        }
    }

    func testOptimisticPauseIgnoresStalePlayingEventUntilPausedIsConfirmed() {
        var transition = OptimisticPlaybackTransition()
        transition.begin(expecting: false)

        XCTAssertFalse(transition.shouldApply(eventIsPlaying: true))
        XCTAssertEqual(transition.expectedState, false)
        XCTAssertTrue(transition.shouldApply(eventIsPlaying: false))
        XCTAssertNil(transition.expectedState)
    }

    func testOptimisticResumeIgnoresStalePausedEventUntilPlayingIsConfirmed() {
        var transition = OptimisticPlaybackTransition()
        transition.begin(expecting: true)

        XCTAssertFalse(transition.shouldApply(eventIsPlaying: false))
        XCTAssertEqual(transition.expectedState, true)
        XCTAssertTrue(transition.shouldApply(eventIsPlaying: true))
        XCTAssertNil(transition.expectedState)
    }

    func testManualTrackArtworkHandoffDelaysPosterBy225Milliseconds() async {
        let manager = MusicManager(startsControllerSetup: false)
        let newArtwork = NSImage(size: NSSize(width: 48, height: 48))
        let artworkPublished = expectation(description: "delayed artwork published")
        let startedAt = Date()
        var observedDelay: TimeInterval = 0
        let cancellable = manager.$albumArt.sink { artwork in
            guard artwork === newArtwork else { return }
            observedDelay = Date().timeIntervalSince(startedAt)
            artworkPublished.fulfill()
        }
        defer { manager.destroy() }

        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: newArtwork)

        XCTAssertFalse(manager.albumArt === newArtwork)
        await fulfillment(of: [artworkPublished], timeout: 1)
        XCTAssertGreaterThanOrEqual(observedDelay, 0.20)
        withExtendedLifetime(cancellable) {}
    }

    func testRepeatedManualTrackHandoffPreservesPendingPosterWhenArtworkDoesNotChange() async {
        let manager = MusicManager(startsControllerSetup: false)
        let sharedArtwork = NSImage(size: NSSize(width: 48, height: 48))
        let artworkPublished = expectation(description: "pending shared artwork published")
        let cancellable = manager.$albumArt.sink { artwork in
            guard artwork === sharedArtwork else { return }
            artworkPublished.fulfill()
        }
        defer { manager.destroy() }

        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: sharedArtwork)
        manager.beginManualTrackArtworkHandoff()

        await fulfillment(of: [artworkPublished], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }

    func testRepeatedManualTrackHandoffPublishesOnlyNewestPoster() async {
        let manager = MusicManager(startsControllerSetup: false)
        let firstArtwork = NSImage(size: NSSize(width: 48, height: 48))
        let newestArtwork = NSImage(size: NSSize(width: 64, height: 64))
        let newestArtworkPublished = expectation(description: "newest artwork published")
        var firstArtworkWasPublished = false
        let cancellable = manager.$albumArt.sink { artwork in
            if artwork === firstArtwork {
                firstArtworkWasPublished = true
            } else if artwork === newestArtwork {
                newestArtworkPublished.fulfill()
            }
        }
        defer { manager.destroy() }

        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: firstArtwork)
        manager.beginManualTrackArtworkHandoff()
        manager.updateAlbumArt(newAlbumArt: newestArtwork)

        await fulfillment(of: [newestArtworkPublished], timeout: 1)
        XCTAssertFalse(firstArtworkWasPublished)
        withExtendedLifetime(cancellable) {}
    }

    func testAlbumArtAssignmentIsNotDelayed() {
        let manager = MusicManager(startsControllerSetup: false)
        let newArtwork = NSImage(size: NSSize(width: 32, height: 32))
        defer { manager.destroy() }

        manager.updateAlbumArt(newAlbumArt: newArtwork)

        XCTAssertTrue(manager.albumArt === newArtwork)
    }

    func testNextTrackRefreshesPlaybackInfoWithoutWaitingForNotification() async {
        let recorder = EventRecorder()
        let controller = AppleMusicController(
            commandUpdateDelay: .zero,
            startsObservers: false,
            commandExecutor: { command in
                await recorder.record("command:\(command)")
            },
            playbackInfoProvider: {
                await recorder.record("refresh")
                return nil
            }
        )

        await controller.nextTrack()

        let events = await recorder.snapshot()
        XCTAssertEqual(events, ["command:next track", "refresh"])
    }

    func testPlaybackStatePublicationReturnsToMainActor() async {
        let statePublished = expectation(description: "playback state published on main actor")
        let controller = AppleMusicController(
            startsObservers: false,
            playbackInfoProvider: {
                AppleMusicPlaybackInfo(
                    isPlaying: true,
                    title: "Main Actor Song",
                    artist: "Main Actor Artist",
                    album: "Main Actor Album",
                    currentTime: 0,
                    duration: 180,
                    isShuffled: false,
                    repeatMode: .off,
                    artwork: Data("artwork".utf8)
                )
            }
        )
        let cancellable = controller.playbackStatePublisher
            .dropFirst()
            .sink { _ in
                XCTAssertTrue(Thread.isMainThread)
                statePublished.fulfill()
            }

        await Task.detached {
            await controller.updatePlaybackInfo()
        }.value

        await fulfillment(of: [statePublished], timeout: 1)
        withExtendedLifetime(cancellable) {}
    }

    func testOlderPlaybackRefreshCannotOverwriteNewerState() async {
        let provider = OutOfOrderPlaybackInfoProvider()
        let controller = AppleMusicController(
            startsObservers: false,
            playbackInfoProvider: { await provider.next() }
        )
        var publishedTitles: [String] = []
        let cancellable = controller.playbackStatePublisher
            .dropFirst()
            .sink { publishedTitles.append($0.title) }
        let oldInfo = AppleMusicPlaybackInfo(
            isPlaying: true,
            title: "Old Song",
            artist: "Old Artist",
            album: "Old Album",
            currentTime: 10,
            duration: 180,
            isShuffled: false,
            repeatMode: .off,
            artwork: Data("old-artwork".utf8)
        )
        let newInfo = AppleMusicPlaybackInfo(
            isPlaying: true,
            title: "New Song",
            artist: "New Artist",
            album: "New Album",
            currentTime: 0,
            duration: 180,
            isShuffled: false,
            repeatMode: .off,
            artwork: Data("new-artwork".utf8)
        )

        let olderRefresh = Task { await controller.updatePlaybackInfo() }
        await provider.waitForRequestCount(1)
        let newerRefresh = Task { await controller.updatePlaybackInfo() }
        await provider.waitForRequestCount(2)

        await provider.complete(requestID: 1, with: newInfo)
        await newerRefresh.value
        await provider.complete(requestID: 0, with: oldInfo)
        await olderRefresh.value

        XCTAssertEqual(publishedTitles, ["New Song"])
        withExtendedLifetime(cancellable) {}
    }

    func testPublishesNewTrackBeforeCatalogArtworkFinishes() async {
        let oldArtwork = Data("old-artwork".utf8)
        let newArtwork = Data("new-artwork".utf8)
        let deferredArtwork = DeferredArtworkProvider()
        let artworkPublished = expectation(description: "new artwork published")
        let playbackInfoProvider = PlaybackInfoProvider(values: [
            AppleMusicPlaybackInfo(
                isPlaying: true,
                title: "Old Song",
                artist: "Old Artist",
                album: "Old Album",
                currentTime: 30,
                duration: 180,
                isShuffled: false,
                repeatMode: .off,
                artwork: oldArtwork
            ),
            AppleMusicPlaybackInfo(
                isPlaying: true,
                title: "New Song",
                artist: "New Artist",
                album: "New Album",
                currentTime: 0,
                duration: 180,
                isShuffled: false,
                repeatMode: .off,
                artwork: nil
            )
        ])
        let controller = AppleMusicController(
            startsObservers: false,
            playbackInfoProvider: { await playbackInfoProvider.next() },
            catalogArtworkProvider: { title, artist, album in
                await deferredArtwork.fetch(title: title, artist: artist, album: album)
            }
        )
        var states: [PlaybackState] = []
        let cancellable = controller.playbackStatePublisher.sink { state in
            states.append(state)
            if state.artwork == newArtwork {
                artworkPublished.fulfill()
            }
        }

        await controller.updatePlaybackInfo()
        XCTAssertEqual(states.last?.artwork, oldArtwork)

        await controller.updatePlaybackInfo()

        XCTAssertEqual(states.last?.title, "New Song")
        XCTAssertNil(states.last?.artwork, "The previous song poster must clear before the network fallback completes")

        await deferredArtwork.complete(with: newArtwork)
        await fulfillment(of: [artworkPublished], timeout: 1)
        XCTAssertEqual(states.last?.artwork, newArtwork)

        withExtendedLifetime(cancellable) {}
    }
}
