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
import IOKit.hid
import ObjectiveC.runtime

final class KeyboardBrightnessSensor {
    private init() {}

    private static let maxKeyboardBrightness: Float = 342
    private static let coreBrightnessClient = CoreBrightnessClient()
    private static var method = SensorMethod.standard

    static func currentLevel() throws -> Float {
        if let client = coreBrightnessClient, let value = client.currentBrightness() {
            return clamp(value)
        }
        switch method {
        case .standard:
            do {
                return normalizedValue(fromRaw: try readStandardRawLevel())
            } catch {
                method = .m1
            }
        case .m1:
            do {
                return normalizedValue(fromRaw: try readM1RawLevel())
            } catch {
                method = .allFailed
            }
        case .allFailed:
            throw SensorError.Keyboard.notFound
        }
        return try currentLevel()
    }

    static func setLevel(_ level: Float) throws {
        let clamped = max(0, min(1, level))
        if let client = coreBrightnessClient, client.setBrightness(clamped) {
            return
        }
        let raw = rawValue(fromNormalized: clamped)
        do {
            try writeStandard(rawLevel: raw)
        } catch {
            method = .m1
            throw error
        }
    }

    private static func clamp(_ value: Float) -> Float {
        max(0, min(1, value))
    }

    private static func normalizedValue(fromRaw rawLevel: Float) -> Float {
        let clamped = max(0, min(1, rawLevel))
        if clamped <= 0.07 {
            return 0
        }
        let value = log10(clamped + 0.03) + 1
        return max(0, min(1, value))
    }

    private static func rawValue(fromNormalized normalized: Float) -> Float {
        guard normalized > 0 else { return 0 }
        let powValue = powf(10, normalized - 1) - 0.03
        return max(0, min(1, powValue))
    }

    private static func readStandardRawLevel() throws -> Float {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleHIDKeyboardEventDriverV2"))
        guard service != 0 else {
            throw SensorError.Keyboard.notStandard
        }
        defer { IOObjectRelease(service) }

        guard let property: CFTypeRef = IORegistryEntryCreateCFProperty(
            service,
            "KeyboardBacklightBrightness" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeUnretainedValue() else {
            throw SensorError.Keyboard.notStandard
        }
        if CFGetTypeID(property) == CFNumberGetTypeID(), let number = property as? CFNumber {
            var rawValue: Float = 0
            if CFNumberGetValue(number, .floatType, &rawValue) {
                return rawValue / maxKeyboardBrightness
            }
        }
        throw SensorError.Keyboard.notStandard
    }

    private static func readM1RawLevel() throws -> Float {
        let task = Process()
        task.launchPath = "/usr/libexec/corebrightnessdiag"
        task.arguments = ["status-info"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? NSDictionary,
           let keyboards = plist["CBKeyboards"] as? [String: [String: Any]] {
            for keyboard in keyboards.values {
                if let backlightInfo = keyboard["CBKeyboardBacklightContainer"] as? [String: Any],
                   backlightInfo["KeyboardBacklightBuiltIn"] as? Bool == true,
                   let brightness = backlightInfo["KeyboardBacklightBrightness"] as? Float {
                    return brightness
                }
            }
        }

        throw SensorError.Keyboard.notSilicon
    }

    private static func writeStandard(rawLevel: Float) throws {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleHIDKeyboardEventDriverV2"))
        guard service != 0 else {
            throw SensorError.Keyboard.notStandard
        }
        defer { IOObjectRelease(service) }

        var scaled = rawLevel * maxKeyboardBrightness
        guard let number = CFNumberCreate(kCFAllocatorDefault, .floatType, &scaled) else {
            throw SensorError.Keyboard.notStandard
        }
        let status = IORegistryEntrySetCFProperty(service, "KeyboardBacklightBrightness" as CFString, number)
        if status != KERN_SUCCESS {
            throw SensorError.Keyboard.notStandard
        }
    }
}

// MARK: - CoreBrightness bridge
private final class CoreBrightnessClient {
    private static let keyboardID: UInt64 = 1
    private var clientInstance: NSObject?
    private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

    init?() {
        var loaded = false
        let bundlePaths = [
            "/System/Library/PrivateFrameworks/CoreBrightness.framework",
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        ]
        for path in bundlePaths where !loaded {
            if let bundle = Bundle(path: path) {
                loaded = bundle.load()
            }
        }
        guard loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            return nil
        }
        clientInstance = cls.init()
    }

    func currentBrightness() -> Float? {
        guard let clientInstance,
              let getter: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
        else { return nil }
        return getter(clientInstance, getSelector, Self.keyboardID)
    }

    func setBrightness(_ value: Float) -> Bool {
        guard let clientInstance,
              let setter: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
        else { return false }
        return setter(clientInstance, setSelector, value, Self.keyboardID).boolValue
    }

    private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
    private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

    private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
        guard let cls = object_getClass(object),
              let method = class_getInstanceMethod(cls, selector)
        else { return nil }
        let imp = method_getImplementation(method)
        return unsafeBitCast(imp, to: T.self)
    }
}
