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

    /// Follow-up checks are capped: later playback is picked up by the
    /// Space, frontmost-app and play-state triggers instead of polling.
    func testRecheckDelayStopsAfterThreeAttempts() {
        let delays = (0..<5).map { FullscreenHidePolicy.recheckDelay(afterRechecks: $0) }
        XCTAssertEqual(delays, [2, 4, 8, nil, nil])
    }

    // MARK: windowFit

    /// A 1512×982 notched display: the safe area stops 38 pt below the top.
    private let safeArea = CGRect(x: 0, y: 0, width: 1512, height: 944)

    func testWholeSafeAreaIsAWholeScreenWindow() {
        XCTAssertEqual(FullscreenHidePolicy.windowFit(window: safeArea, safeArea: safeArea), .whole)
    }

    /// Split View panes fill the height but only part of the width (#409).
    func testSplitViewPanesAreTiles() {
        let left = CGRect(x: 0, y: 0, width: 754, height: 944)
        let right = CGRect(x: 758, y: 0, width: 754, height: 944)
        let narrow = CGRect(x: 0, y: 0, width: 500, height: 944)
        XCTAssertEqual(FullscreenHidePolicy.windowFit(window: left, safeArea: safeArea), .tile)
        XCTAssertEqual(FullscreenHidePolicy.windowFit(window: right, safeArea: safeArea), .tile)
        XCTAssertEqual(FullscreenHidePolicy.windowFit(window: narrow, safeArea: safeArea), .tile)
    }

    func testOrdinaryWindowsAreNotFullscreenShaped() {
        let floating = CGRect(x: 200, y: 200, width: 800, height: 600)
        let shortHalf = CGRect(x: 0, y: 0, width: 756, height: 870)
        let sidebar = CGRect(x: 0, y: 0, width: 200, height: 944)
        XCTAssertEqual(FullscreenHidePolicy.windowFit(window: floating, safeArea: safeArea), .none)
        XCTAssertEqual(FullscreenHidePolicy.windowFit(window: shortHalf, safeArea: safeArea), .none)
        XCTAssertEqual(FullscreenHidePolicy.windowFit(window: sidebar, safeArea: safeArea), .none)
    }

    /// The fullscreen check reads the window that is on screen, not any other
    /// window of the same app (#345).
    func testSameWindowMatchesOnlyTheDetectedFrame() {
        let detected = CGRect(x: 0, y: 38, width: 1512, height: 944)
        XCTAssertTrue(FullscreenHidePolicy.isSameWindow(CGRect(x: 0, y: 39, width: 1512, height: 944), as: detected))
        XCTAssertFalse(FullscreenHidePolicy.isSameWindow(CGRect(x: 1512, y: 0, width: 1920, height: 1080), as: detected))
    }
}
