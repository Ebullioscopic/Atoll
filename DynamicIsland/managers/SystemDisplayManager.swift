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
import Cocoa

class SystemDisplayManager {
    private init() {}

    private static var method = SensorMethod.standard

    static func getDisplayBrightness() throws -> Float {
        switch SystemDisplayManager.method {
        case .standard:
            do {
                return try getStandardDisplayBrightness()
            } catch {
                method = .m1
            }
        case .m1:
            do {
                return try getM1DisplayBrightness()
            } catch {
                method = .allFailed
            }
        case .allFailed:
            throw SensorError.Display.notFound
        }
        return try getDisplayBrightness()
    }

    private static func getStandardDisplayBrightness() throws -> Float {
        var brightness: float_t = 1
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"))
        defer {
            IOObjectRelease(service)
        }

        let result = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &brightness)
        if result != kIOReturnSuccess {
            throw SensorError.Display.notStandard
        }
        return brightness
    }
    
    private static func getM1DisplayBrightness() throws -> Float {
        let task = Process()
        task.launchPath = "/usr/libexec/corebrightnessdiag"
        task.arguments = ["status-info"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary,
           let displays = plist["CBDisplays"] as? [String: [String: Any]] {
            for display in displays.values {
                if let displayInfo = display["Display"] as? [String: Any],
                    displayInfo["DisplayServicesIsBuiltInDisplay"] as? Bool == true,
                    let brightness = displayInfo["DisplayServicesBrightness"] as? Float {
                        return brightness
                }
            }
        }
        throw SensorError.Display.notSilicon
    }
}
