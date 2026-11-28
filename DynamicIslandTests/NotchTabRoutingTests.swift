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

/// Which tab the notch opens to, and which tabs treat themselves as the player.
final class NotchTabRoutingTests: XCTestCase {
    private let allTabs = StandardNotchTabAvailability(
        home: true, nowPlaying: true, shelf: true, timer: true,
        stats: true, llmUsage: true, notes: true, terminal: true
    ).available

    // MARK: - Automatic

    func testAutomaticOpensNowPlayingWhileMusicPlays() {
        XCTAssertEqual(NotchOpenDestination.automaticTab(isPlaying: true, available: allTabs), .nowPlaying)
    }

    func testAutomaticOpensHomeWhenNothingPlays() {
        XCTAssertEqual(NotchOpenDestination.automaticTab(isPlaying: false, available: allTabs), .home)
    }

    func testAutomaticFallsBackToHomeWithoutMediaControls() {
        let available = allTabs.filter { $0 != .nowPlaying }
        XCTAssertEqual(NotchOpenDestination.automaticTab(isPlaying: true, available: available), .home)
    }

    func testAutomaticFallsBackToNowPlayingWhenHomeIsEmpty() {
        let available = allTabs.filter { $0 != .home }
        XCTAssertEqual(NotchOpenDestination.automaticTab(isPlaying: false, available: available), .nowPlaying)
    }

    func testAutomaticLeavesTheChoiceToTheTabBarWithNeitherTab() {
        let available = allTabs.filter { $0 != .home && $0 != .nowPlaying }
        XCTAssertNil(NotchOpenDestination.automaticTab(isPlaying: true, available: available))
        XCTAssertNil(NotchOpenDestination.automaticTab(isPlaying: false, available: available))
    }

    // MARK: - Fixed destinations

    func testNowPlayingFollowsHomeInTabOrder() {
        XCTAssertEqual(Array(allTabs.prefix(3)), [.home, .nowPlaying, .shelf])
    }

    func testFixedNowPlayingOpensItselfOrFallsBackToHome() {
        XCTAssertEqual(NotchOpenDestination.nowPlaying.resolved(available: allTabs), .nowPlaying)
        let available = allTabs.filter { $0 != .nowPlaying }
        XCTAssertEqual(NotchOpenDestination.nowPlaying.resolved(available: available), .home)
    }

    func testFixedHomeFallsBackToNowPlayingWhenHomeIsEmpty() {
        let available = allTabs.filter { $0 != .home }
        XCTAssertEqual(NotchOpenDestination.home.resolved(available: available), .nowPlaying)
    }

    func testStoredNowPlayingPreferenceRoundTrips() {
        XCTAssertEqual(NotchOpenDestination.selected("nowPlaying", rememberLast: false), .nowPlaying)
    }

    func testEveryTabMapsToItsNotchView() {
        for destination in NotchOpenDestination.allCases {
            if destination.isFixed {
                XCTAssertNotNil(destination.notchView, "\(destination)")
            } else {
                XCTAssertNil(destination.notchView, "\(destination)")
            }
        }
        XCTAssertEqual(NotchOpenDestination.nowPlaying.notchView, .nowPlaying)
        XCTAssertEqual(NotchOpenDestination.home.notchView, .home)
    }

    // MARK: - The player

    func testOnlyNowPlayingAndMinimalisticHomeShowThePlayer() {
        XCTAssertTrue(NotchViews.nowPlaying.showsMusicPlayer(isMinimalistic: false))
        XCTAssertFalse(NotchViews.home.showsMusicPlayer(isMinimalistic: false))
        XCTAssertTrue(NotchViews.home.showsMusicPlayer(isMinimalistic: true))
        XCTAssertFalse(NotchViews.shelf.showsMusicPlayer(isMinimalistic: false))
        XCTAssertFalse(NotchViews.shelf.showsMusicPlayer(isMinimalistic: true))
    }

    func testArrowKeySeekTakesTheKeyboardOnlyOnThePlayer() {
        XCTAssertTrue(notchTabTakesKeyboardInput(.nowPlaying, arrowKeySeekEnabled: true, isMinimalistic: false))
        XCTAssertFalse(notchTabTakesKeyboardInput(.nowPlaying, arrowKeySeekEnabled: false, isMinimalistic: false))
        XCTAssertFalse(notchTabTakesKeyboardInput(.home, arrowKeySeekEnabled: true, isMinimalistic: false))
        XCTAssertTrue(notchTabTakesKeyboardInput(.home, arrowKeySeekEnabled: true, isMinimalistic: true))
    }

    func testThePlayerFitsTheNarrowestOpenNotch() {
        // Now Playing asks for no width of its own; this keeps that true.
        XCTAssertLessThanOrEqual(nowPlayingContentMinimumWidth, recommendedMinimumNotchWidth(forTabCount: 1))
    }
}
