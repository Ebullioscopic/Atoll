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
import ObjectiveC.runtime

final class CoreBrightnessDisplayClient {
    static let shared = CoreBrightnessDisplayClient()

    private static let builtInDisplayID: UInt64 = 0

    private var clientInstance: NSObject?
    private let getSelector = NSSelectorFromString("brightnessForDisplay:")
    private let setSelector = NSSelectorFromString("setBrightness:forDisplay:")
    private let notificationSelector = NSSelectorFromString("setNotificationBlock:")

    var onBrightnessChange: ((Float) -> Void)?
    private var available = false

    /// Known class names Apple has used across macOS versions for the
    /// CoreBrightness display-brightness client. Ordered newest-first so
    /// we resolve the current name quickly.
    private static let candidateClassNames: [String] = [
        "CBBrightnessProxy",
        "CBDisplayBrightnessClient",
        "BrightnessSystemClient",
        "DisplayBrightnessClient"
    ]

    private init() {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
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
        guard loaded else {
            NSLog("⚠️ CoreBrightnessDisplayClient: CoreBrightness.framework could not be loaded (macOS %@)", osVersion)
            return
        }

        var resolvedClass: NSObject.Type?
        for name in Self.candidateClassNames {
            if let cls = NSClassFromString(name) as? NSObject.Type {
                resolvedClass = cls
                NSLog("✅ CoreBrightnessDisplayClient: Resolved class '%@' (macOS %@)", name, osVersion)
                break
            }
        }

        guard let cls = resolvedClass else {
            NSLog("⚠️ CoreBrightnessDisplayClient: None of the known class names found: %@ (macOS %@)",
                  Self.candidateClassNames.joined(separator: ", "), osVersion)
            return
        }
        clientInstance = cls.init()
        available = clientInstance != nil
    }

    var isAvailable: Bool { available }

    func currentBrightness() -> Float? {
        guard let clientInstance,
              let getter: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
        else { return nil }
        let value = getter(clientInstance, getSelector, Self.builtInDisplayID)
        guard value >= 0, value <= 1 else { return nil }
        return value
    }

    func setBrightness(_ value: Float) -> Bool {
        guard let clientInstance,
              let setter: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
        else { return false }
        return setter(clientInstance, setSelector, value, Self.builtInDisplayID).boolValue
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
