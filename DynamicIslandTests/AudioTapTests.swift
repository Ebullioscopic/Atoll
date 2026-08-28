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

final class AudioTapTests: XCTestCase {
    private let targets = [
        "com.apple.Music",
        "com.spotify.client",
        "com.tidal.desktop",
    ]

    func testMatchesMainApplicationAudioProcess() {
        XCTAssertEqual(
            AudioTapTargetMatcher.targetBundleIdentifier(
                for: "com.tidal.desktop",
                among: targets
            ),
            "com.tidal.desktop"
        )
    }

    func testMatchesNestedPlayerAudioProcess() {
        XCTAssertEqual(
            AudioTapTargetMatcher.targetBundleIdentifier(
                for: "com.tidal.desktop.player",
                among: targets
            ),
            "com.tidal.desktop"
        )
    }

    func testMatchesBundleIdentifiersCaseInsensitively() {
        XCTAssertEqual(
            AudioTapTargetMatcher.targetBundleIdentifier(
                for: "COM.APPLE.MUSIC",
                among: targets
            ),
            "com.apple.Music"
        )
    }

    func testDoesNotMatchLookalikeBundleIdentifier() {
        XCTAssertNil(
            AudioTapTargetMatcher.targetBundleIdentifier(
                for: "com.tidal.desktopish.player",
                among: targets
            )
        )
    }

    func testDoesNotMatchUnrelatedAudioProcess() {
        XCTAssertNil(
            AudioTapTargetMatcher.targetBundleIdentifier(
                for: "com.example.video-player",
                among: targets
            )
        )
    }
}
