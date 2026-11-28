/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2026 Atoll Contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import Foundation
import IOKit

/// Battery charge power and total DC input are distinct from adapter capacity.
/// IORegistry telemetry is optional and may update more slowly than the UI.
struct BatteryPowerReading: Equatable {
    let chargingWatts: Double?
    let inputWatts: Double?

    init(properties: [String: Any]) {
        guard properties["ExternalConnected"] as? Bool == true else {
            chargingWatts = nil
            inputWatts = nil
            return
        }

        func value(_ raw: Any?, maximum: Double) -> Double? {
            guard let number = raw as? NSNumber else { return nil }
            let result = number.doubleValue
            guard result.isFinite, result >= 0, result <= maximum else { return nil }
            return result
        }

        // Signed mA is essential: taking abs() would display discharge as charge.
        if properties["IsCharging"] as? Bool == true,
           let voltage = value(properties["Voltage"], maximum: 100_000), voltage > 0,
           let current = value(properties["Amperage"], maximum: 30_000) {
            chargingWatts = voltage * current / 1_000_000
        } else {
            chargingWatts = nil
        }

        let telemetry = properties["PowerTelemetryData"] as? [String: Any]
        inputWatts = value(telemetry?["SystemPowerIn"], maximum: 1_000_000).map { $0 / 1_000 }
    }

    static func current() -> BatteryPowerReading {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return BatteryPowerReading(properties: [:]) }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            return BatteryPowerReading(properties: [:])
        }
        return BatteryPowerReading(properties: dictionary)
    }
}
