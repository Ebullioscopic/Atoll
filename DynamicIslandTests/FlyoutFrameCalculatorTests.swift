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

#if os(macOS)
import AppKit
import XCTest
@testable import Atoll

final class FlyoutFrameCalculatorTests: XCTestCase {

    func testPlacesFrameToRightOfNotch() {
        let screen = NSRect(x: 0, y: 0, width: 3024, height: 1964)
        let size = CGSize(width: 300, height: 100)

        let frame = FlyoutFrameCalculator.frame(
            for: size,
            screenFrame: screen,
            notchWidth: 300,
            rightWingWidth: 20,
            spacing: 12
        )

        XCTAssertEqual(frame, NSRect(x: 1694, y: 1864, width: 300, height: 100))
    }

    func testClampsFrameToRightScreenInset() {
        let screen = NSRect(x: 100, y: 50, width: 1000, height: 800)
        let size = CGSize(width: 700, height: 125)

        let frame = FlyoutFrameCalculator.frame(
            for: size,
            screenFrame: screen,
            notchWidth: 300,
            rightWingWidth: 500,
            spacing: 20
        )

        XCTAssertEqual(frame.minX, 392)
        XCTAssertEqual(frame.maxX, screen.maxX - 8)
        XCTAssertEqual(frame.minY, 725)
    }

    func testRoundsOriginAndSizeToWholePixels() {
        let screen = NSRect(x: 0.25, y: 0.5, width: 1200.5, height: 900.5)
        let size = CGSize(width: 231.49, height: 77.51)

        let frame = FlyoutFrameCalculator.frame(
            for: size,
            screenFrame: screen,
            notchWidth: 200.25,
            rightWingWidth: 10.25,
            spacing: 7.25
        )

        XCTAssertEqual(frame.origin.x, 718)
        XCTAssertEqual(frame.origin.y, 823)
        XCTAssertEqual(frame.size, CGSize(width: 231, height: 78))
    }

    func testPreservesLeftInsetWhenContentIsWiderThanUsableArea() {
        let screen = NSRect(x: 200, y: 0, width: 500, height: 400)
        let size = CGSize(width: 600, height: 90)

        let frame = FlyoutFrameCalculator.frame(
            for: size,
            screenFrame: screen,
            notchWidth: 100,
            rightWingWidth: 0,
            spacing: 8
        )

        XCTAssertEqual(frame.minX, screen.minX + 8)
        XCTAssertEqual(frame.width, 600)
    }
}
#endif
