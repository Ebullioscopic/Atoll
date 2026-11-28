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

final class LRCParserTests: XCTestCase {

    func testReadsMinutesSecondsAndHundredths() {
        let lines = LRCParser.parse("[01:23.45]Hello")

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.timestamp ?? 0, 83.45, accuracy: 0.0001)
    }

    func testFractionIsScaledByHowManyDigitsAreWritten() {
        // ".5" is five tenths, not five hundredths.
        XCTAssertEqual(LRCParser.parse("[00:10.5]a").first?.timestamp ?? 0, 10.5, accuracy: 0.0001)
        XCTAssertEqual(LRCParser.parse("[00:10.50]a").first?.timestamp ?? 0, 10.5, accuracy: 0.0001)
        XCTAssertEqual(LRCParser.parse("[00:10.500]a").first?.timestamp ?? 0, 10.5, accuracy: 0.0001)
    }

    func testMillisecondTimestampsAreNotDropped() {
        // Three-digit fractions are common and used to fail the whole match,
        // which silently discarded every line in the file.
        let lines = LRCParser.parse("[01:23.456]Hello")

        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.timestamp ?? 0, 83.456, accuracy: 0.0001)
        XCTAssertEqual(lines.first?.text, "Hello")
    }

    func testALineWithSeveralTimestampsIsEmittedAtEachOfThem() {
        // A repeated chorus is written once with one tag per repetition.
        let lines = LRCParser.parse("[00:12.00][00:45.30][01:30.00]Chorus")

        XCTAssertEqual(lines.map(\.text), ["Chorus", "Chorus", "Chorus"])
        XCTAssertEqual(lines.map(\.timestamp), [12.0, 45.3, 90.0])
    }

    func testTrailingTimestampsAreNotLeftInTheText() {
        let lines = LRCParser.parse("[00:12.00][00:45.30]Chorus")

        XCTAssertEqual(Set(lines.map(\.text)), ["Chorus"])
    }

    func testOffsetTagShiftsEveryLine() {
        // A positive offset means the lyrics should show earlier.
        let lines = LRCParser.parse("[offset:+500]\n[00:10.00]a\n[00:20.00]b")

        XCTAssertEqual(lines.map(\.timestamp), [9.5, 19.5])
    }

    func testNegativeOffsetDelaysEveryLine() {
        let lines = LRCParser.parse("[offset:-250]\n[00:10.00]a")

        XCTAssertEqual(lines.first?.timestamp ?? 0, 10.25, accuracy: 0.0001)
    }

    func testOffsetNeverPushesALineBeforeTheStartOfTheTrack() {
        let lines = LRCParser.parse("[offset:+5000]\n[00:01.00]a")

        XCTAssertEqual(lines.first?.timestamp, 0)
    }

    func testMetadataIsIgnored() {
        let lines = LRCParser.parse("[ar:Artist]\n[ti:Title]\n[00:20.00]real")

        XCTAssertEqual(lines.map(\.text), ["real"])
    }

    func testATimestampWithNoTextIsKeptAsAGapMarker() {
        // LRC marks where singing stops with a bare timestamp, and that is what
        // delimits an instrumental break -- dropping it loses the gap entirely.
        let lines = LRCParser.parse("[00:10.00]sung\n[00:12.00]\n[00:30.00]sung again")

        XCTAssertEqual(lines.map(\.timestamp), [10, 12, 30])
        XCTAssertEqual(lines.map(\.text), ["sung", "", "sung again"])
    }

    func testLinesComeBackInTimeOrder() {
        let lines = LRCParser.parse("[00:30.00]c\n[00:10.00]a\n[00:20.00]b")

        XCTAssertEqual(lines.map(\.text), ["a", "b", "c"])
    }
}
