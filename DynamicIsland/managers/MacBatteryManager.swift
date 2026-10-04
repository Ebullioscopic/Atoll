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

import Foundation
import IOKit
import IOKit.ps

/// Lightweight helper for querying macOS battery charging status and ETA.
final class MacBatteryManager {
    static let shared = MacBatteryManager()

    private init() {}

    struct BatteryStatus {
        let timeRemainingMinutes: Int?
        let isCharging: Bool
        let percentage: Int?
    }

    func currentStatus() -> BatteryStatus {
        guard let sourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sourcesList = IOPSCopyPowerSourcesList(sourcesInfo)?.takeRetainedValue() as? [CFTypeRef] else {
            return BatteryStatus(timeRemainingMinutes: nil, isCharging: false, percentage: nil)
        }

        for source in sourcesList {
            guard let description = IOPSGetPowerSourceDescription(sourcesInfo, source)?.takeUnretainedValue() as? [String: Any],
                  let type = description[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType else {
                continue
            }

            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let timeRemaining = description[kIOPSTimeToFullChargeKey] as? Int
            let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int
            let maxCapacity = description[kIOPSMaxCapacityKey] as? Int

            let percentage: Int?
            if let current = currentCapacity, let max = maxCapacity, max > 0 {
                percentage = (current * 100) / max
            } else {
                percentage = nil
            }

            return BatteryStatus(
                timeRemainingMinutes: timeRemaining,
                isCharging: isCharging,
                percentage: percentage
            )
        }

        return BatteryStatus(timeRemainingMinutes: nil, isCharging: false, percentage: nil)
    }

    /// Power flowing through the battery and the connected adapter's rating.
    struct PowerReading: Equatable {
        /// The connected adapter's rated power, e.g. 96. `nil` on battery or
        /// when macOS does not report it.
        let adapterWatts: Int?
        /// Battery power: positive while charging, negative while the battery
        /// is discharging. `nil` if it cannot be read.
        let batteryWatts: Double?
        let isCharging: Bool
        let isPluggedIn: Bool

        /// What the battery menu should show, or `nil` to show nothing.
        ///
        /// `AppleSmartBattery` refreshes Voltage/Amperage on its own slow cycle,
        /// so for tens of seconds after the cable is plugged in or pulled out
        /// it still describes the previous state (e.g. "using 18W" while
        /// plugged in). The figure is only shown when its sign agrees with
        /// the power source state macOS reports right now.
        var displayed: (charging: Bool, watts: Double)? {
            guard let watts = batteryWatts else { return nil }
            if isCharging, watts > 0 { return (true, watts) }
            if !isPluggedIn, watts < 0 { return (false, -watts) }
            return nil
        }
    }

    func currentPower() -> PowerReading {
        let status = currentStatus()
        return PowerReading(adapterWatts: Self.adapterWatts(), batteryWatts: Self.batteryWatts(),
                            isCharging: status.isCharging, isPluggedIn: Self.isOnACPower())
    }

    private static func isOnACPower() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else {
            return false
        }
        return (type as String) == kIOPSACPowerValue
    }

    static func adapterWatts() -> Int? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
              let watts = details[kIOPSPowerAdapterWattsKey] as? Int, watts > 0 else {
            return nil
        }
        return watts
    }

    private static func batteryWatts() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        func number(_ key: String) -> NSNumber? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
        }
        guard let voltage = number("Voltage"), let amperage = number("Amperage") else { return nil }
        return watts(millivolts: voltage.int64Value, milliamps: amperage.int64Value)
    }

    /// `Amperage` is a signed value that IOKit may hand back as its unsigned
    /// bit pattern (e.g. 18446744073709550376 for -1240 mA); `int64Value`
    /// restores the sign either way.
    static func watts(millivolts: Int64, milliamps: Int64) -> Double? {
        guard millivolts > 0 else { return nil }
        return Double(millivolts) * Double(milliamps) / 1_000_000
    }

    /// "96W", or `nil` when there is nothing meaningful to show.
    static func formattedWatts(_ watts: Double?) -> String? {
        guard let watts, abs(watts) >= 0.5 else { return nil }
        return "\(Int(abs(watts).rounded()))W"
    }

    func formattedTimeToFullCharge() -> String? {
        let status = currentStatus()
        guard status.isCharging, let minutes = status.timeRemainingMinutes, minutes > 0 else {
            return nil
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(remainingMinutes)m"
    }
}
