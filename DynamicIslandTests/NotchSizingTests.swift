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

final class NotchSizingTests: XCTestCase {
    private let base = CGSize(width: 640, height: 200)

    func testBaselineHeaderLeavesHomeHeightUnchanged() {
        let size = headerAdjustedNotchSize(
            from: base,
            isHomeTabActive: true,
            closedNotchHeight: openNotchHeaderBaselineHeight,
            isMinimalistic: false
        )
        XCTAssertEqual(size, base)
    }

    func testTallerHeaderGrowsHomeByTheDifference() {
        let size = headerAdjustedNotchSize(
            from: base,
            isHomeTabActive: true,
            closedNotchHeight: openNotchHeaderBaselineHeight + 9,
            isMinimalistic: false
        )
        XCTAssertEqual(size, CGSize(width: 640, height: 209))
    }

    func testShorterHeaderDoesNotShrinkHome() {
        let size = headerAdjustedNotchSize(
            from: base,
            isHomeTabActive: true,
            closedNotchHeight: 24,
            isMinimalistic: false
        )
        XCTAssertEqual(size, base)
    }

    func testOtherTabsAndMinimalisticAreNotAdjusted() {
        XCTAssertEqual(
            headerAdjustedNotchSize(from: base, isHomeTabActive: false, closedNotchHeight: 44, isMinimalistic: false),
            base
        )
        XCTAssertEqual(
            headerAdjustedNotchSize(from: base, isHomeTabActive: true, closedNotchHeight: 44, isMinimalistic: true),
            base
        )
    }
}
