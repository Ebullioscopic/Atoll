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

import XCTest
@testable import Atoll

/// A track with no timed lyrics available still shows its words, but nothing
/// may claim to know which of them is being sung.
final class UnsyncedLyricsTests: XCTestCase {
    private let body = """
    No smoke with no fire
    No silence if there's no sound

    One way or another
    You're going to put me out
    """

    func testAPlainBodyBecomesOneLinePerLine() {
        let lines = LyricLine.untimedLines(from: body)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines.first?.text, "No smoke with no fire")
        XCTAssertEqual(lines.last?.text, "You're going to put me out")
    }

    func testBlankLinesAreDropped() {
        XCTAssertFalse(LyricLine.untimedLines(from: body).contains { $0.text.isEmpty })
    }

    func testSurroundingWhitespaceIsTrimmed() {
        let lines = LyricLine.untimedLines(from: "   padded line   \n\tanother\t")
        XCTAssertEqual(lines.map(\.text), ["padded line", "another"])
    }

    func testUntimedLinesAreMarkedAsSuch() {
        XCTAssertTrue(LyricLine.untimedLines(from: body).allSatisfy { !$0.isTimed })
    }

    func testAParsedLRCLineIsTimed() {
        XCTAssertTrue(LyricLine(timestamp: 12, text: "sung here").isTimed)
    }

    func testAnEmptyBodyYieldsNothing() {
        XCTAssertTrue(LyricLine.untimedLines(from: "\n\n   \n").isEmpty)
    }

    func testEqualityDistinguishesTimedFromUntimed() {
        XCTAssertNotEqual(
            LyricLine(timestamp: 0, text: "same words", isTimed: true),
            LyricLine(timestamp: 0, text: "same words", isTimed: false)
        )
    }
}
