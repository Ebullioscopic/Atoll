/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
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

import CoreAudio
import XCTest
@testable import Atoll

/// Covers the decisions the per-app volume feature makes before it touches
/// CoreAudio: which apps get a tap, what gain that tap runs at, how helper
/// processes are folded into the app the user recognises, and the row order.
final class PerAppVolumeTests: XCTestCase {

    // MARK: - needsTap

    func testAppAtFullVolumeAndUnmutedIsNotTapped() {
        // The whole point of the check: Atoll must not insert itself into the
        // audio path of every app on the Mac just to list it.
        XCTAssertFalse(PerAppVolumeManager.needsTap(volume: 1.0, isMuted: false))
    }

    func testAnyAdjustmentRequiresATap() {
        XCTAssertTrue(PerAppVolumeManager.needsTap(volume: 0.5, isMuted: false))
        XCTAssertTrue(PerAppVolumeManager.needsTap(volume: 0.0, isMuted: false))
        XCTAssertTrue(PerAppVolumeManager.needsTap(volume: 1.0, isMuted: true))
    }

    func testOutOfRangeVolumesClampBeforeTheTapDecision() {
        // A stored 1.4 would otherwise read as "adjusted" forever, holding a
        // tap that applies a gain of exactly 1.
        XCTAssertFalse(PerAppVolumeManager.needsTap(volume: 1.4, isMuted: false))
        XCTAssertTrue(PerAppVolumeManager.needsTap(volume: -0.2, isMuted: false))
    }

    // MARK: - effectiveGain

    func testGainFollowsVolumeWhenUnmuted() {
        XCTAssertEqual(PerAppVolumeManager.effectiveGain(volume: 0.25, isMuted: false), 0.25)
        XCTAssertEqual(PerAppVolumeManager.effectiveGain(volume: 1.0, isMuted: false), 1.0)
    }

    func testMuteWinsOverTheSlider() {
        // Changing the level of a muted app must not make it audible again.
        XCTAssertEqual(PerAppVolumeManager.effectiveGain(volume: 0.8, isMuted: true), 0)
    }

    func testGainIsClamped() {
        XCTAssertEqual(PerAppVolumeManager.effectiveGain(volume: 3.0, isMuted: false), 1.0)
        XCTAssertEqual(PerAppVolumeManager.effectiveGain(volume: -1.0, isMuted: false), 0.0)
    }

    // MARK: - percentLabel

    func testPercentLabelRoundsToWholePercent() {
        XCTAssertEqual(PerAppVolumeManager.percentLabel(0), "0%")
        XCTAssertEqual(PerAppVolumeManager.percentLabel(0.5), "50%")
        XCTAssertEqual(PerAppVolumeManager.percentLabel(0.333), "33%")
        XCTAssertEqual(PerAppVolumeManager.percentLabel(1), "100%")
    }

    // MARK: - canonicalBundleIdentifier

    func testRunningAppKeepsItsOwnIdentifier() {
        XCTAssertEqual(
            PerAppVolumeManager.canonicalBundleIdentifier("com.spotify.client", among: ["com.spotify.client"]),
            "com.spotify.client"
        )
    }

    func testHelperProcessRollsUpToItsParentApp() {
        // CoreAudio reports TIDAL's audio under the player helper, which is not
        // an app the user would recognise in a list.
        XCTAssertEqual(
            PerAppVolumeManager.canonicalBundleIdentifier(
                "com.tidal.desktop.player",
                among: ["com.tidal.desktop"]
            ),
            "com.tidal.desktop"
        )
    }

    func testLongestRunningAncestorWins() {
        XCTAssertEqual(
            PerAppVolumeManager.canonicalBundleIdentifier(
                "com.foo.bar.helper.renderer",
                among: ["com.foo", "com.foo.bar"]
            ),
            "com.foo.bar"
        )
    }

    func testUnknownProcessKeepsItsOwnIdentifier() {
        XCTAssertEqual(
            PerAppVolumeManager.canonicalBundleIdentifier("com.unknown.thing", among: []),
            "com.unknown.thing"
        )
    }

    func testSingleComponentIdentifierIsLeftAlone() {
        // The roll-up loop must not run itself down to an empty string.
        XCTAssertEqual(PerAppVolumeManager.canonicalBundleIdentifier("coreaudiod", among: []), "coreaudiod")
    }

    // MARK: - sorting

    func testPlayingAppsSortAboveEverythingElse() {
        let apps = [
            makeApp("com.b", name: "Bravo", isPlaying: false),
            makeApp("com.a", name: "Alpha", isPlaying: true)
        ]

        let sorted = PerAppVolumeManager.sorted(apps, adjusted: { _ in false })
        XCTAssertEqual(sorted.map(\.bundleIdentifier), ["com.a", "com.b"])
    }

    func testAdjustedAppsSortAboveUntouchedOnes() {
        let apps = [
            makeApp("com.a", name: "Alpha", isPlaying: false),
            makeApp("com.z", name: "Zulu", isPlaying: false)
        ]

        // Alphabetical order would put Alpha first; the adjustment overrides it.
        let sorted = PerAppVolumeManager.sorted(apps, adjusted: { $0 == "com.z" })
        XCTAssertEqual(sorted.map(\.bundleIdentifier), ["com.z", "com.a"])
    }

    func testOtherwiseAppsSortByName() {
        let apps = [
            makeApp("com.c", name: "Charlie", isPlaying: false),
            makeApp("com.a", name: "alpha", isPlaying: false),
            makeApp("com.b", name: "Bravo", isPlaying: false)
        ]

        let sorted = PerAppVolumeManager.sorted(apps, adjusted: { _ in false })
        XCTAssertEqual(sorted.map(\.name), ["alpha", "Bravo", "Charlie"])
    }

    // MARK: - fallbackName

    func testFallbackNameUsesTheLastIdentifierComponent() {
        XCTAssertEqual(PerAppVolumeManager.fallbackName(for: "com.example.Widget"), "Widget")
        XCTAssertEqual(PerAppVolumeManager.fallbackName(for: "coreaudiod"), "coreaudiod")
    }

    // MARK: - Helpers

    private func makeApp(_ identifier: String, name: String, isPlaying: Bool) -> AudioApp {
        AudioApp(
            bundleIdentifier: identifier,
            name: name,
            isPlaying: isPlaying,
            processObjectIDs: [AudioObjectID(1)]
        )
    }
}
