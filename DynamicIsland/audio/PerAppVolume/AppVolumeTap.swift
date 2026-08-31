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

import Accelerate
import AudioToolbox
import CoreAudio
import Foundation
import os.log

private let volumeTapLog = OSLog(subsystem: "com.atoll.dynamicisland", category: "PerAppVolume")

/// Re-routes one app's audio through Atoll so its level can be changed
/// independently of the system volume.
///
/// The mechanism is the one macOS gives us for this: a process tap with
/// `mutedWhenTapped` silences the app's own path to the device, and a private
/// *stacked* aggregate device -- the tap plus the real output device -- gives
/// us an IO callback where we scale the samples and write them back out. The
/// app is therefore never audible except through this callback, which is why
/// the tap has to be torn down carefully rather than just abandoned.
final class AppVolumeTap {
    let bundleIdentifier: String
    let processObjectIDs: [AudioObjectID]
    let outputDeviceUID: String

    /// Linear gain, 0...1. Read on the realtime thread, written from the main
    /// thread; a 32-bit aligned store cannot tear on arm64, so the realtime
    /// side always observes either the old or the new value, never a mix.
    nonisolated(unsafe) var gain: Float = 1.0

    /// Gain actually applied to the last sample of the previous buffer.
    ///
    /// Each buffer ramps from this to `gain` instead of jumping, because
    /// stepping the gain between buffers puts a discontinuity in the waveform
    /// -- audible as a click while dragging the slider.
    nonisolated(unsafe) private var appliedGain: Float = 1.0

    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var isInvalidated = false

    init(bundleIdentifier: String, processObjectIDs: [AudioObjectID], outputDeviceUID: String) throws {
        self.bundleIdentifier = bundleIdentifier
        self.processObjectIDs = processObjectIDs
        self.outputDeviceUID = outputDeviceUID

        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        description.name = "Atoll volume tap for \(bundleIdentifier)"

        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            throw AppVolumeTapError.tapCreationFailed(status)
        }

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Atoll-\(bundleIdentifier)",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceClockDeviceKey: outputDeviceUID,
            // Private keeps it out of Sound settings; stacked is what makes the
            // aggregate render to the real device rather than just capture.
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: false,
                kAudioSubTapUIDKey: description.uuid.uuidString
            ]]
        ]

        status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            // The tap is already live at this point and would keep the app
            // muted with nothing rendering it, so tear down before throwing.
            invalidate()
            throw AppVolumeTapError.aggregateCreationFailed(status)
        }
    }

    deinit {
        invalidate()
    }

    func activate() throws {
        let queue = DispatchQueue(label: "com.atoll.pervolume.\(bundleIdentifier)", qos: .userInteractive)

        var status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateDeviceID, queue) {
            [weak self] _, inputData, _, outputData, _ in
            self?.render(inputData, outputData)
        }
        guard status == noErr, let ioProcID else {
            invalidate()
            throw AppVolumeTapError.ioProcCreationFailed(status)
        }

        status = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard status == noErr else {
            invalidate()
            throw AppVolumeTapError.deviceStartFailed(status)
        }
    }

    /// Stops rendering and destroys the tap, unmuting the app's own path.
    ///
    /// Safe to call more than once, and called from `deinit`, so an owner that
    /// simply drops the tap still restores the app's audio.
    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true

        if let ioProcID {
            AudioDeviceStop(aggregateDeviceID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    // MARK: - Realtime

    /// Runs on CoreAudio's realtime thread: no allocation, no locks, no logging.
    private func render(_ inputData: UnsafePointer<AudioBufferList>, _ outputData: UnsafeMutablePointer<AudioBufferList>) {
        let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let outputBuffers = UnsafeMutableAudioBufferListPointer(outputData)

        let target = gain
        let start = appliedGain
        appliedGain = target

        for index in 0..<outputBuffers.count {
            guard index < inputBuffers.count,
                  let outputBytes = outputBuffers[index].mData,
                  let inputBytes = inputBuffers[index].mData else { continue }

            let sampleCount = min(
                Int(outputBuffers[index].mDataByteSize),
                Int(inputBuffers[index].mDataByteSize)
            ) / MemoryLayout<Float>.size
            guard sampleCount > 0 else { continue }

            let output = outputBytes.assumingMemoryBound(to: Float.self)
            let input = inputBytes.assumingMemoryBound(to: Float.self)

            if start == 1.0 && target == 1.0 {
                if inputBytes != outputBytes {
                    memcpy(outputBytes, inputBytes, sampleCount * MemoryLayout<Float>.size)
                }
            } else if start == 0.0 && target == 0.0 {
                vDSP_vclr(output, 1, vDSP_Length(sampleCount))
            } else if start == target {
                var scalar = target
                vDSP_vsmul(input, 1, &scalar, output, 1, vDSP_Length(sampleCount))
            } else {
                // Ramp across the buffer so a slider drag does not click.
                var value = start
                var step = (target - start) / Float(sampleCount)
                vDSP_vrampmul(input, 1, &value, &step, output, 1, vDSP_Length(sampleCount))
            }
        }
    }
}

enum AppVolumeTapError: Error, CustomStringConvertible {
    case tapCreationFailed(OSStatus)
    case aggregateCreationFailed(OSStatus)
    case ioProcCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)

    var description: String {
        switch self {
        case .tapCreationFailed(let status):
            return "AudioHardwareCreateProcessTap failed (\(status))"
        case .aggregateCreationFailed(let status):
            return "AudioHardwareCreateAggregateDevice failed (\(status))"
        case .ioProcCreationFailed(let status):
            return "AudioDeviceCreateIOProcIDWithBlock failed (\(status))"
        case .deviceStartFailed(let status):
            return "AudioDeviceStart failed (\(status))"
        }
    }
}
