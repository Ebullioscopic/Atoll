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

/// The single notch window must always land on a display: a stored display that
/// is no longer found (macOS 27 renamed the built-in one, #632) used to hide it.
final class NotchHostDisplayTests: XCTestCase {

    func testPreferredDisplayWinsWhileConnected() {
        XCTAssertEqual(NotchHostDisplay.resolve(
            preferred: "Studio", main: "Main", builtIn: "Built-in", first: "First",
            automaticallySwitch: false), "Studio")
        XCTAssertEqual(NotchHostDisplay.resolve(
            preferred: "Studio", main: "Main", builtIn: "Built-in", first: "First",
            automaticallySwitch: true), "Studio")
    }

    func testMissingPreferredFallsBackToBuiltInDisplay() {
        XCTAssertEqual(NotchHostDisplay.resolve(
            preferred: nil, main: "Main", builtIn: "Built-in", first: "First",
            automaticallySwitch: false), "Built-in")
    }

    func testMissingPreferredFollowsMainDisplayWhenSwitchingAutomatically() {
        XCTAssertEqual(NotchHostDisplay.resolve(
            preferred: nil, main: "Main", builtIn: "Built-in", first: "First",
            automaticallySwitch: true), "Main")
    }

    func testClamshellWithoutBuiltInDisplayStillPicksADisplay() {
        XCTAssertEqual(NotchHostDisplay.resolve(
            preferred: nil, main: nil, builtIn: nil, first: "First",
            automaticallySwitch: false), "First")
        XCTAssertEqual(NotchHostDisplay.resolve(
            preferred: nil, main: "Main", builtIn: nil, first: "First",
            automaticallySwitch: false), "Main")
    }
}
