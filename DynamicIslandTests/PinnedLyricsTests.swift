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

/// The bounds check that decides whether the pinned strip has a line to draw.
/// It guards a direct subscript into the lyric array, so the edges matter.
final class PinnedLyricsTests: XCTestCase {

    func testALineInRangeIsDrawn() {
        XCTAssertTrue(PinnedLyricsView.hasCurrentLine(index: 0, lineCount: 3))
        XCTAssertTrue(PinnedLyricsView.hasCurrentLine(index: 2, lineCount: 3))
    }

    func testTheIndexBeforeTheFirstLineDrawsNothing() {
        // -1 is where a track sits before its first timestamp, which is a
        // normal state at the start of every song, not an error.
        XCTAssertFalse(PinnedLyricsView.hasCurrentLine(index: -1, lineCount: 3))
    }

    func testAnIndexPastTheEndDrawsNothing() {
        // Reachable in practice: the index survives a moment longer than the
        // array when a new track's shorter lyrics land first.
        XCTAssertFalse(PinnedLyricsView.hasCurrentLine(index: 3, lineCount: 3))
        XCTAssertFalse(PinnedLyricsView.hasCurrentLine(index: 99, lineCount: 3))
    }

    func testATrackWithNoLyricsDrawsNothing() {
        XCTAssertFalse(PinnedLyricsView.hasCurrentLine(index: 0, lineCount: 0))
        XCTAssertFalse(PinnedLyricsView.hasCurrentLine(index: -1, lineCount: 0))
    }
}
