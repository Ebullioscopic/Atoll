/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import XCTest
@testable import Atoll

/// "Hide only when NowPlaying app is in fullscreen" has to compare the
/// fullscreen app with whatever macOS reports as Now Playing — not with the
/// media source chosen in Atoll — and keep checking while a fullscreen app is
/// shown but playback has not reached it yet.
final class FullscreenHidePolicyTests: XCTestCase {

    private let infuse = "com.firecore.infuse"
    private let chrome = "com.google.Chrome"
    private let music = "com.apple.Music"

    // MARK: shouldHide

    func testAlwaysHidesNativeFullscreen() {
        XCTAssertTrue(FullscreenHidePolicy.shouldHide(
            option: .always, fullscreenBundleID: chrome, nowPlayingBundleID: music, isNativeFullscreen: true))
        XCTAssertFalse(FullscreenHidePolicy.shouldHide(
            option: .always, fullscreenBundleID: chrome, nowPlayingBundleID: music, isNativeFullscreen: false))
    }

    func testNeverHides() {
        XCTAssertFalse(FullscreenHidePolicy.shouldHide(
            option: .never, fullscreenBundleID: infuse, nowPlayingBundleID: infuse, isNativeFullscreen: true))
    }

    func testNowPlayingOnlyHidesWhenFullscreenAppIsNowPlaying() {
        XCTAssertTrue(FullscreenHidePolicy.shouldHide(
            option: .nowPlayingOnly, fullscreenBundleID: infuse, nowPlayingBundleID: infuse, isNativeFullscreen: true))
    }

    func testNowPlayingOnlyIgnoresOtherApps() {
        XCTAssertFalse(FullscreenHidePolicy.shouldHide(
            option: .nowPlayingOnly, fullscreenBundleID: chrome, nowPlayingBundleID: music, isNativeFullscreen: true))
    }

    func testNowPlayingOnlyNeedsAKnownNowPlayingApp() {
        XCTAssertFalse(FullscreenHidePolicy.shouldHide(
            option: .nowPlayingOnly, fullscreenBundleID: chrome, nowPlayingBundleID: nil, isNativeFullscreen: true))
        XCTAssertFalse(FullscreenHidePolicy.shouldHide(
            option: .nowPlayingOnly, fullscreenBundleID: nil, nowPlayingBundleID: nil, isNativeFullscreen: true))
    }

    func testNowPlayingOnlyNeedsNativeFullscreen() {
        XCTAssertFalse(FullscreenHidePolicy.shouldHide(
            option: .nowPlayingOnly, fullscreenBundleID: infuse, nowPlayingBundleID: infuse, isNativeFullscreen: false))
    }

    // MARK: shouldKeepRechecking

    func testKeepsRecheckingWhileANowPlayingCandidateIsShown() {
        XCTAssertTrue(FullscreenHidePolicy.shouldKeepRechecking(
            option: .nowPlayingOnly, detectionEnabled: true, hasFullscreenCandidate: true, isHidden: false,
            nowPlayingIsObserved: true))
    }

    func testStopsRecheckingWithoutCandidates() {
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .nowPlayingOnly, detectionEnabled: true, hasFullscreenCandidate: false, isHidden: false,
            nowPlayingIsObserved: true))
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .nowPlayingOnly, detectionEnabled: true, hasFullscreenCandidate: true, isHidden: true,
            nowPlayingIsObserved: true))
    }

    func testNeverRechecksOutsideNowPlayingOnly() {
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .always, detectionEnabled: true, hasFullscreenCandidate: true, isHidden: false,
            nowPlayingIsObserved: true))
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .never, detectionEnabled: true, hasFullscreenCandidate: true, isHidden: false,
            nowPlayingIsObserved: true))
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .nowPlayingOnly, detectionEnabled: false, hasFullscreenCandidate: true, isHidden: false,
            nowPlayingIsObserved: true))
    }

    /// Under a fixed media source nothing announces that playback moved from
    /// the fullscreen app to another one, so a hidden island is re-checked too
    /// — whether the last answer came from the probe or, after a failed probe,
    /// from the fixed player's own id.
    func testKeepsCheckingAHiddenWindowWhenNowPlayingIsNotObserved() {
        XCTAssertTrue(FullscreenHidePolicy.shouldKeepRechecking(
            option: .nowPlayingOnly, detectionEnabled: true, hasFullscreenCandidate: true, isHidden: true,
            nowPlayingIsObserved: false))
    }

    /// Under the Now Playing source, MusicManager reports every switch, so a
    /// hidden island needs no polling.
    func testStopsCheckingAHiddenWindowWhenNowPlayingIsObserved() {
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .nowPlayingOnly, detectionEnabled: true, hasFullscreenCandidate: true, isHidden: true,
            nowPlayingIsObserved: true))
    }

    /// Playback can start long after the window went fullscreen (browsing a
    /// library first), so checks continue for as long as the app stays
    /// fullscreen, but back off so an app that never plays costs one Now Playing
    /// query per 30 s rather than one every 2 s.
    func testRecheckDelayBacksOffToThirtySeconds() {
        let delays = (0..<7).map { FullscreenHidePolicy.recheckDelay(afterRechecks: $0) }
        XCTAssertEqual(delays, [2, 4, 8, 16, 30, 30, 30])
    }
}
