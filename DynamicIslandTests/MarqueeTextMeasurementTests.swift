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

/// The marquee measures a loop of two copies of the text and has to recover the
/// width of a single copy from it. Getting that arithmetic wrong is invisible in
/// the layout but makes short text scroll, so it is pinned here.
final class MarqueeTextMeasurementTests: XCTestCase {

    func testWidthIsRecoveredFromTheTwoCopiesAndTheGap() {
        let singleCopy: CGFloat = 120
        let loop = singleCopy * 2 + MarqueeText.loopSpacing

        XCTAssertEqual(MarqueeText.textWidth(fromLoopWidth: loop), singleCopy, accuracy: 0.001)
    }

    func testTextThatExactlyFillsItsColumnDoesNotMeasureAsOverflowing() {
        let columnWidth: CGFloat = 180
        let loop = columnWidth * 2 + MarqueeText.loopSpacing

        // This is the case the old `loopWidth / 2` got wrong: it reported
        // columnWidth + loopSpacing / 2, so the text read as too wide to fit.
        XCTAssertFalse(MarqueeText.textWidth(fromLoopWidth: loop) > columnWidth)
    }

    func testShorterTextStaysComfortablyInsideItsColumn() {
        let columnWidth: CGFloat = 180
        let singleCopy: CGFloat = 175
        let loop = singleCopy * 2 + MarqueeText.loopSpacing

        XCTAssertFalse(MarqueeText.textWidth(fromLoopWidth: loop) > columnWidth)
    }

    func testGenuinelyOverflowingTextStillMeasuresAsOverflowing() {
        let columnWidth: CGFloat = 180
        let singleCopy: CGFloat = 260
        let loop = singleCopy * 2 + MarqueeText.loopSpacing

        XCTAssertTrue(MarqueeText.textWidth(fromLoopWidth: loop) > columnWidth)
    }

    func testAnUnmeasuredLoopDoesNotProduceANegativeWidth() {
        XCTAssertEqual(MarqueeText.textWidth(fromLoopWidth: 0), 0)
        XCTAssertEqual(MarqueeText.textWidth(fromLoopWidth: MarqueeText.loopSpacing / 2), 0)
    }
}
