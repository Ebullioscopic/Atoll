/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import XCTest
@testable import Atoll

final class AppleMusicAirPlayManagerTests: XCTestCase {
    func testEmptyDeviceListParsesWithoutTrapping() {
        XCTAssertEqual(AppleMusicAirPlayManager.parseDevices(from: .list()), [])
    }

    func testDeviceListParsesFields() {
        let device = NSAppleEventDescriptor.list()
        device.insert(NSAppleEventDescriptor(string: "Kitchen"), at: 1)
        device.insert(NSAppleEventDescriptor(string: "HomePod"), at: 2)
        device.insert(NSAppleEventDescriptor(boolean: true), at: 3)
        device.insert(NSAppleEventDescriptor(string: "AA:BB"), at: 4)
        device.insert(NSAppleEventDescriptor(int32: 40), at: 5)
        let list = NSAppleEventDescriptor.list()
        list.insert(device, at: 1)

        XCTAssertEqual(
            AppleMusicAirPlayManager.parseDevices(from: list),
            [AirPlayDevice(id: "AA:BB", name: "Kitchen", kind: "HomePod", isSelected: true, volume: 40)]
        )
    }
}
