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

import AudioToolbox
import CoreAudio
import Foundation

/// The CoreAudio property reads shared by the visualizer tap and the per-app
/// volume taps.
///
/// These were originally file-private helpers inside `AudioTap`; both features
/// need the same four lookups, so they live in one place rather than being
/// kept in sync by hand.
enum AudioProcessQuery {

    /// Every process CoreAudio currently knows about, playing or not.
    static func processObjectIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioObjectID>.size) else {
            return []
        }

        var processObjects = [AudioObjectID](
            repeating: kAudioObjectUnknown,
            count: Int(size) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            systemObject, &address, 0, nil, &size, &processObjects
        ) == noErr else {
            return []
        }

        return processObjects.filter { $0 != kAudioObjectUnknown }
    }

    /// The process object backing a running app, if CoreAudio has one for it.
    static func processObject(for pid: pid_t) -> AudioObjectID? {
        var audioObjectID: AudioObjectID = kAudioObjectUnknown
        var pidValue = pid

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let qualifierSize = UInt32(MemoryLayout<pid_t>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            qualifierSize,
            &pidValue,
            &size,
            &audioObjectID
        )

        guard status == noErr, audioObjectID != kAudioObjectUnknown else { return nil }
        return audioObjectID
    }

    static func bundleIdentifier(for processObject: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedBundleIdentifier: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(
            processObject, &address, 0, nil, &size, &unmanagedBundleIdentifier
        ) == noErr, let unmanagedBundleIdentifier else {
            return nil
        }

        return unmanagedBundleIdentifier.takeRetainedValue() as String
    }

    static func pid(for processObject: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)

        guard AudioObjectGetPropertyData(
            processObject, &address, 0, nil, &size, &pid
        ) == noErr else {
            return nil
        }

        return pid
    }

    /// Whether the process is currently sending audio to an output device.
    ///
    /// This is what separates "Safari has an audio session" from "Safari is
    /// actually making noise right now", which is the difference between a
    /// useful app list and one full of silent entries.
    static func isRunningOutput(_ processObject: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        guard AudioObjectGetPropertyData(
            processObject, &address, 0, nil, &size, &value
        ) == noErr else {
            return false
        }

        return value != 0
    }

    // MARK: - Devices

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }

        return deviceID
    }

    static func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedUID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &unmanagedUID
        ) == noErr, let unmanagedUID else {
            return nil
        }

        return unmanagedUID.takeRetainedValue() as String
    }
}
