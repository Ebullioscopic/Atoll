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

/// The adapter's diff updates omit what has not changed, so "absent" and
/// "present but null" mean different things for the playback position. Optional
/// decoding renders both as nil, so the distinction is pinned here.
final class NowPlayingPayloadTests: XCTestCase {

    private func decode(_ json: String) throws -> NowPlayingPayload {
        try JSONDecoder().decode(NowPlayingPayload.self, from: Data(json.utf8))
    }

    func testAnOmittedPositionIsNotTreatedAsCleared() throws {
        let payload = try decode(#"{"title":"a"}"#)

        XCTAssertNil(payload.resolvedElapsedTime)
        XCTAssertFalse(payload.clearsElapsedTime)
    }

    func testANullPositionIsTreatedAsCleared() throws {
        let payload = try decode(#"{"elapsedTime":null}"#)

        XCTAssertNil(payload.resolvedElapsedTime)
        XCTAssertTrue(payload.clearsElapsedTime)
    }

    func testANullMicrosecondPositionIsTreatedAsCleared() throws {
        let payload = try decode(#"{"elapsedTimeMicros":null}"#)

        XCTAssertTrue(payload.clearsElapsedTime)
    }

    func testAPositionThatIsActuallyPresentIsNotCleared() throws {
        let payload = try decode(#"{"elapsedTime":12.5}"#)

        XCTAssertEqual(payload.resolvedElapsedTime ?? 0, 12.5, accuracy: 0.0001)
        XCTAssertFalse(payload.clearsElapsedTime)
    }

    func testMicrosecondValuesWinOverTheSecondsForms() throws {
        let payload = try decode(#"{"elapsedTime":9,"elapsedTimeMicros":9720000,"duration":100,"durationMicros":379226000}"#)

        XCTAssertEqual(payload.resolvedElapsedTime ?? 0, 9.72, accuracy: 0.0001)
        XCTAssertEqual(payload.resolvedDuration ?? 0, 379.226, accuracy: 0.0001)
    }

    func testTheMicrosecondAnchorKeepsItsSubSecondPart() throws {
        // The string form is formatted to whole seconds, so preferring it would
        // put the anchor up to a second early and bias playback estimates ahead.
        let payload = try decode(
            #"{"timestamp":"2026-08-21T14:00:13Z","timestampEpochMicros":1787320813448212}"#
        )

        XCTAssertEqual(
            payload.resolvedTimestamp?.timeIntervalSince1970 ?? 0,
            1787320813.448212,
            accuracy: 0.0001
        )
    }

    func testTheStringAnchorIsUsedWhenTheAdapterIgnoresMicros() throws {
        let payload = try decode(#"{"timestamp":"2026-08-21T14:00:13Z"}"#)

        XCTAssertEqual(
            payload.resolvedTimestamp?.timeIntervalSince1970 ?? 0,
            1787320813,
            accuracy: 0.0001
        )
    }
}
