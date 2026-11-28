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

/// The fullscreen detector asks the adapter which app macOS reports as Now
/// Playing. It has to read that the same way the Now Playing source does, and
/// treat anything unusable as "unknown" so the caller can fall back.
final class SystemNowPlayingProbeTests: XCTestCase {

    private func bundleID(_ output: String) -> String? {
        SystemNowPlayingProbe.bundleIdentifier(fromAdapterOutput: Data(output.utf8))
    }

    func testProbeReadsBundleIdentifier() {
        XCTAssertEqual(bundleID(#"{"bundleIdentifier":"com.google.Chrome","playing":false}"#), "com.google.Chrome")
    }

    func testProbePrefersParentApplication() {
        XCTAssertEqual(
            bundleID(#"{"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari"}"#),
            "com.apple.Safari"
        )
    }

    func testProbeReturnsNilForUnusableOutput() {
        XCTAssertNil(bundleID(""))
        XCTAssertNil(bundleID("null"))
        XCTAssertNil(bundleID("not json"))
        XCTAssertNil(bundleID(#"{"bundleIdentifier":""}"#))
    }
}
