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

final class CustomVisualizerTests: XCTestCase {
    func testAcceptsWebAndFileURLs() {
        XCTAssertEqual(
            CustomVisualizer.animationURL(from: " https://example.com/a.json "),
            URL(string: "https://example.com/a.json")
        )
        XCTAssertEqual(
            CustomVisualizer.animationURL(from: "file:///Users/me/a.json"),
            URL(fileURLWithPath: "/Users/me/a.json")
        )
    }

    func testTurnsLocalPathIntoFileURL() {
        XCTAssertEqual(
            CustomVisualizer.animationURL(from: "/Users/me/lottie.json"),
            URL(fileURLWithPath: "/Users/me/lottie.json")
        )
    }

    func testRejectsInputThatCannotBeLoaded() {
        XCTAssertNil(CustomVisualizer.animationURL(from: ""))
        XCTAssertNil(CustomVisualizer.animationURL(from: "lottie.json"))
        XCTAssertNil(CustomVisualizer.animationURL(from: "ftp://example.com/a.json"))
        XCTAssertNil(CustomVisualizer.animationURL(from: "https://"))
    }
}
