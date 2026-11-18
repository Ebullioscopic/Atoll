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
            rechecksDone: 0))
    }

    func testStopsRecheckingWithoutCandidates() {
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .nowPlayingOnly, detectionEnabled: true, hasFullscreenCandidate: false, isHidden: false,
            rechecksDone: 0))
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .nowPlayingOnly, detectionEnabled: true, hasFullscreenCandidate: true, isHidden: true,
            rechecksDone: 0))
    }

    func testNeverRechecksOutsideNowPlayingOnly() {
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .always, detectionEnabled: true, hasFullscreenCandidate: true, isHidden: false,
            rechecksDone: 0))
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .never, detectionEnabled: true, hasFullscreenCandidate: true, isHidden: false,
            rechecksDone: 0))
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .nowPlayingOnly, detectionEnabled: false, hasFullscreenCandidate: true, isHidden: false,
            rechecksDone: 0))
    }

    /// Someone working in a fullscreen app that never plays anything must not
    /// pay for a Now Playing query every two seconds for as long as it stays open.
    func testStopsRecheckingOnceTheBudgetIsSpent() {
        let budget = FullscreenHidePolicy.maxRechecksPerChange
        XCTAssertEqual(budget, 15)
        XCTAssertTrue(FullscreenHidePolicy.shouldKeepRechecking(
            option: .nowPlayingOnly, detectionEnabled: true, hasFullscreenCandidate: true, isHidden: false,
            rechecksDone: budget - 1))
        XCTAssertFalse(FullscreenHidePolicy.shouldKeepRechecking(
            option: .nowPlayingOnly, detectionEnabled: true, hasFullscreenCandidate: true, isHidden: false,
            rechecksDone: budget))
    }
}
