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

final class AirPodsListeningModeLogTests: XCTestCase {
    func testReadsModeWrittenAfterKey() {
        XCTAssertEqual(AirPodsListeningMode.fromLogLine("bluetoothd: LsnM ANC"), .noiseCancellation)
        XCTAssertEqual(AirPodsListeningMode.fromLogLine("noiseControlMode: Transparency"), .transparency)
        XCTAssertEqual(AirPodsListeningMode.fromLogLine("listeningMode = 3"), .adaptive)
        XCTAssertEqual(AirPodsListeningMode.fromLogLine("LsnM=Normal"), .off)
    }

    func testPrefersTargetOfTransition() {
        XCTAssertEqual(
            AirPodsListeningMode.fromLogLine("LsnM changed from Transparency to ANC"),
            .noiseCancellation
        )
    }

    func testIgnoresModeWordsElsewhereInLine() {
        // Previously "instance" matched "anc" and "ambient" matched transparency.
        XCTAssertNil(AirPodsListeningMode.fromLogLine("LsnM update for instance 4 (ambient route)"))
        XCTAssertNil(AirPodsListeningMode.fromLogLine("noiseControlMode balance changed"))
    }

    func testIgnoresCapabilityAndAmbiguousLines() {
        XCTAssertNil(AirPodsListeningMode.fromLogLine("supported LsnM ANC Transparency AutoANC"))
        XCTAssertNil(AirPodsListeningMode.fromLogLine("LsnM ANC, peer LsnM Transparency"))
    }
}
