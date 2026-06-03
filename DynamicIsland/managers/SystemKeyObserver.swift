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

import Cocoa

class SystemKeyObserver: NSApplication {
    static let volumeChanged = Notification.Name("DynamicIsland.volumeChanged")
    static let brightnessChanged = Notification.Name("DynamicIsland.brightnessChanged")
    static let keyboardIlluminationChanged = Notification.Name("DynamicIsland.keyboardIlluminationChanged")

    override func sendEvent(_ event: NSEvent) {
        if event.type == .systemDefined && event.subtype.rawValue == 8 {
            let keyCode = ((event.data1 & 0xFFFF0000) >> 16)
            let keyFlags = (event.data1 & 0x0000FFFF)
            // Get the key state. 0xA is KeyDown, OxB is KeyUp
            let keyState = ((keyFlags & 0xFF00) >> 8) == 0xA
            let keyRepeat = keyFlags & 0x1
            mediaKeyEvent(key: Int32(keyCode), state: keyState, keyRepeat: Bool(truncating: keyRepeat as NSNumber))
        }

        super.sendEvent(event)
    }

    func mediaKeyEvent(key: Int32, state: Bool, keyRepeat: Bool) {
        // Only send events on KeyDown. Without this check, these events will happen twice
        if state {
            switch key {
            case NX_KEYTYPE_SOUND_DOWN, NX_KEYTYPE_SOUND_UP, NX_KEYTYPE_MUTE:
                NotificationCenter.default.post(name: SystemKeyObserver.volumeChanged, object: self)
            case NX_KEYTYPE_BRIGHTNESS_UP, NX_KEYTYPE_BRIGHTNESS_DOWN:
                NotificationCenter.default.post(name: SystemKeyObserver.brightnessChanged, object: self)
            case NX_KEYTYPE_ILLUMINATION_DOWN, NX_KEYTYPE_ILLUMINATION_UP:
                NotificationCenter.default.post(name: SystemKeyObserver.keyboardIlluminationChanged, object: self)
            default:
                break
            }
        }
    }
}
