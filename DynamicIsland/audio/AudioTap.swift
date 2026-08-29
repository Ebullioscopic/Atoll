/*
 * Atoll (DynamicIsland)
 * Original work Copyright (C) 2026 ZephyrCodesStuff (https://github.com/ZephyrCodesStuff/rtaudio)
 * Modified work Copyright (C) 2026 Atoll Contributors
 *
 * CoreAudio tap for capturing real-time audio from music applications.
 * Uses macOS 14.2+ Process Tap API for efficient audio capture.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This file is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AppKit
import AudioToolbox
import CoreAudio
import Defaults
import simd
import os.log

private let audioTapLog = OSLog(subsystem: "com.atoll.dynamicisland", category: "AudioTap")

// Debug: track callback invocations
private var callbackCount: Int = 0

// CoreAudio fires this on a high-priority background real-time thread.
let audioIOProc: AudioDeviceIOProc = {
    inDevice, inNow, inInputData, inInputTime, outOutputData, inOutputTime, clientData in

    guard let clientData = clientData else { return noErr }
    let scanner = Unmanaged<AudioTap>.fromOpaque(clientData).takeUnretainedValue()

    if scanner.isPaused { return noErr }

    let mutableInputData = UnsafeMutablePointer(mutating: inInputData)
    let bufferList = UnsafeMutableAudioBufferListPointer(mutableInputData)

    if let firstBuffer = bufferList.first, let data = firstBuffer.mData {
        // CoreAudio gives us byte size, divide by 4 (Float size) to get array length
        let floatCount = Int32(firstBuffer.mDataByteSize) / Int32(MemoryLayout<Float>.size)

        let floatData = data.assumingMemoryBound(to: Float.self)

        // Pass the mono array directly to C++
        scanner.bridge.processBuffer(floatData, count: floatCount)
        
        // Debug: log periodically with audio level info
        callbackCount += 1
        if callbackCount % 1000 == 0 {
            // Calculate max absolute value in buffer to check if audio is present
            var maxVal: Float = 0.0
            for i in 0..<Int(floatCount) {
                let absVal = abs(floatData[i])
                if absVal > maxVal { maxVal = absVal }
            }
            os_log(.debug, log: audioTapLog, "🔊 Audio callback fired %d times, buffer size: %d, max amplitude: %f", callbackCount, floatCount, maxVal)
        }
    }

    return noErr
}

private func getAudioObjectID(for pid: pid_t) -> AudioObjectID? {
    var audioObjectID: AudioObjectID = kAudioObjectUnknown
    var pidValue = pid

    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let qualifierSize = UInt32(MemoryLayout<pid_t>.size)

    // We query the global system object (kAudioObjectSystemObject)
    // We pass the PID as the "qualifier", and it returns the AudioObjectID
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        qualifierSize,
        &pidValue,
        &size,
        &audioObjectID
    )

    if status == noErr && audioObjectID != kAudioObjectUnknown {
        return audioObjectID
    }

    return nil
}

private func getAudioProcessObjectIDs() -> [AudioObjectID] {
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
        systemObject,
        &address,
        0,
        nil,
        &size,
        &processObjects
    ) == noErr else {
        return []
    }

    return processObjects.filter { $0 != kAudioObjectUnknown }
}

private func getBundleIdentifier(for audioProcessObject: AudioObjectID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyBundleID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var unmanagedBundleIdentifier: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

    guard AudioObjectGetPropertyData(
        audioProcessObject,
        &address,
        0,
        nil,
        &size,
        &unmanagedBundleIdentifier
    ) == noErr,
          let unmanagedBundleIdentifier else {
        return nil
    }

    return unmanagedBundleIdentifier.takeRetainedValue() as String
}

private func getPID(for audioProcessObject: AudioObjectID) -> pid_t? {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioProcessPropertyPID,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var pid: pid_t = 0
    var size = UInt32(MemoryLayout<pid_t>.size)

    guard AudioObjectGetPropertyData(
        audioProcessObject,
        &address,
        0,
        nil,
        &size,
        &pid
    ) == noErr else {
        return nil
    }

    return pid
}

enum AudioTapTargetMatcher {
    /// CoreAudio exposes helper processes separately from their parent app. A
    /// player such as TIDAL therefore appears as `com.tidal.desktop.player`
    /// even though the app selected by the user is `com.tidal.desktop`.
    static func targetBundleIdentifier(
        for audioProcessBundleIdentifier: String,
        among targetBundleIdentifiers: [String]
    ) -> String? {
        let processIdentifier = audioProcessBundleIdentifier.lowercased()
        return targetBundleIdentifiers.first { targetIdentifier in
            let normalizedTarget = targetIdentifier.lowercased()
            return processIdentifier == normalizedTarget
                || processIdentifier.hasPrefix(normalizedTarget + ".")
        }
    }
}

/// Singleton class for real-time audio capture from music apps
class AudioTap: NSObject {
    static let shared = AudioTap()
    
    let bridge = AudioBridge()
    var isPaused: Bool = false
    private var displayMagnitudes: [Float] = Array(repeating: 0, count: 6)

    // CoreAudio stuff
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID? = nil
    private var captureIsRunning = false
    private var updateTimer: Timer?
    
    // Serial queue to prevent race conditions
    private let audioQueue = DispatchQueue(label: "com.atoll.audiotap", qos: .userInitiated)
    
    // Debounce restart requests
    private var pendingRestartWorkItem: DispatchWorkItem?

    private let targetBundleIDs = [
        "com.apple.Music",
        "com.spotify.client",
        "com.amazon.music",
        "sh.cider.genten.mac",
        "com.apple.Safari",
        "com.tidal.desktop",
        "tv.plex.plexamp",
        "com.roon.Roon",
        "com.audirvana.Audirvana-Studio",
        "com.vox.vox",
        "com.coppertino.Vox",
    ]

    private override init() {
        super.init()
    }

    @objc private func updateSmoothedMagnitudes() {
        let nsMagnitudes = bridge.getSmoothedMagnitudes()
        let targetLevels = nsMagnitudes.map { $0.floatValue }
        
        let smoothingFactor: Float = 0.4
        
        for i in 0..<min(targetLevels.count, displayMagnitudes.count) {
            let difference = targetLevels[i] - displayMagnitudes[i]
            displayMagnitudes[i] += difference * smoothingFactor
        }
    }

    func getSmoothedMagnitudes() -> [Float] {
        return displayMagnitudes
    }

    func startCapture() async {
        await withCheckedContinuation { continuation in
            audioQueue.async { [weak self] in
                self?.startCaptureSync()
                continuation.resume()
            }
        }
    }
    
    private func startCaptureSync() {
        guard !captureIsRunning else {
            print("⚠️ [AudioTap] Capture already running, skipping start")
            return
        }

        var targetProcessObjects = Set<AudioObjectID>()
        var bundleIdentifierByProcessObject: [AudioObjectID: String] = [:]

        // AirPods/Bluetooth output + Spotify don't mix: process-tapping Spotify into our
        // private aggregate device disturbs the system Now Playing / AVRCP session, so the
        // AirPods pause gesture finds no target and macOS falls back to Siri. Spotify is
        // controlled via AppleScript and registers weakly with MediaRemote, which is why
        // only it is affected (Apple Music etc. stay registered). While a Bluetooth route is
        // active, skip tapping Spotify to preserve media control — the visualizer stays live
        // for Spotify on wired/built-in output and for every other app on any output.
        let bluetoothOutputActive = AudioRouteManager.shared.isDefaultOutputBluetooth()

        // Enumerate CoreAudio's process objects rather than relying only on
        // NSRunningApplication. Electron players commonly render and play from
        // nested helpers; TIDAL, for example, emits audio from
        // `com.tidal.desktop.player`, while its main app PID has no audio object.
        for processObject in getAudioProcessObjectIDs() {
            guard let processBundleIdentifier = getBundleIdentifier(for: processObject),
                  let targetBundleIdentifier = AudioTapTargetMatcher.targetBundleIdentifier(
                    for: processBundleIdentifier,
                    among: targetBundleIDs
                  ) else {
                continue
            }

            if shouldSkipSpotifyTap(
                bundleIdentifier: targetBundleIdentifier,
                bluetoothOutputActive: bluetoothOutputActive
            ) {
                print("⏭️ [AudioTap] Bluetooth output active — skipping Spotify tap to preserve AirPods media control")
                continue
            }

            targetProcessObjects.insert(processObject)
            bundleIdentifierByProcessObject[processObject] = processBundleIdentifier
            let pidDescription = getPID(for: processObject).map(String.init) ?? "unknown"
            print("🎯 [AudioTap] Found audio process \(processBundleIdentifier) with PID: \(pidDescription), AudioObjectID: \(processObject)")
        }

        // Preserve the previous PID translation as a fallback for applications
        // whose CoreAudio process does not publish a bundle identifier.
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleIdentifier = app.bundleIdentifier,
                  targetBundleIDs.contains(bundleIdentifier) else { continue }
            if shouldSkipSpotifyTap(
                bundleIdentifier: bundleIdentifier,
                bluetoothOutputActive: bluetoothOutputActive
            ) {
                continue
            }
            if let processObject = getAudioObjectID(for: app.processIdentifier),
               targetProcessObjects.insert(processObject).inserted {
                bundleIdentifierByProcessObject[processObject] = bundleIdentifier
                print("🎯 [AudioTap] Found \(app.localizedName ?? "App") with PID: \(app.processIdentifier), AudioObjectID: \(processObject)")
            }
        }

        if targetProcessObjects.isEmpty {
            print("⚠️ [AudioTap] None of our target apps are running right now.")
            return
        }

        let sortedTargetProcessObjects = targetProcessObjects.sorted { lhs, rhs in
            let lhsBundleIdentifier = bundleIdentifierByProcessObject[lhs]?.lowercased() ?? ""
            let rhsBundleIdentifier = bundleIdentifierByProcessObject[rhs]?.lowercased() ?? ""
            return lhsBundleIdentifier == rhsBundleIdentifier
                ? lhs < rhs
                : lhsBundleIdentifier < rhsBundleIdentifier
        }

        let description = CATapDescription()
        description.processes = sortedTargetProcessObjects
        description.isMixdown = true
        description.isMono = true
        
        print("📋 [AudioTap] Creating tap for \(sortedTargetProcessObjects.count) processes: \(sortedTargetProcessObjects)")

        tapID = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else {
            print("🛑 [AudioTap] Tap Error: \(status) (\(fourCharCodeToString(status)))")
            return
        }
        print("✅ [AudioTap] Created process tap with ID: \(tapID)")

        // Get the tap's unique hardware UID
        var tapUID: CFString = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.stride)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        status = withUnsafeMutablePointer(to: &tapUID) { uidPtr in
            AudioObjectGetPropertyData(tapID, &propertyAddress, 0, nil, &propertySize, uidPtr)
        }
        guard status == noErr else {
            print("🛑 [AudioTap] UID Error: \(status) (\(fourCharCodeToString(status)))")
            cleanupPartialSetup()
            return
        }
        print("✅ [AudioTap] Got tap UID: \(tapUID)")

        // Create the Aggregate Device (a "virtual microphone" that we can route the tap into)
        let tapList = [[kAudioSubTapUIDKey: tapUID]]
        let aggregateDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Atoll_Virtual_Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,  // Hides it from the user's sound settings
            kAudioAggregateDeviceTapListKey: tapList,
        ]

        aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(
            aggregateDict as CFDictionary, &aggregateDeviceID)
        guard status == noErr else {
            print("🛑 [AudioTap] Aggregate Error: \(status) (\(fourCharCodeToString(status)))")
            cleanupPartialSetup()
            return
        }
        print("✅ [AudioTap] Created aggregate device with ID: \(aggregateDeviceID)")

        // Bind the Callback to the device
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        status = AudioDeviceCreateIOProcID(aggregateDeviceID, audioIOProc, selfPointer, &ioProcID)

        guard status == noErr, let validIOProcID = ioProcID else {
            print("🛑 [AudioTap] IOProc Error: \(status) (\(fourCharCodeToString(status)))")
            cleanupPartialSetup()
            return
        }
        print("✅ [AudioTap] Created IO proc")

        // Start listening
        status = AudioDeviceStart(aggregateDeviceID, validIOProcID)
        guard status == noErr else {
            print("🛑 [AudioTap] Start Error: \(status) (\(fourCharCodeToString(status)))")
            cleanupPartialSetup()
            return
        }

        captureIsRunning = true
        callbackCount = 0
        
        DispatchQueue.main.async { [weak self] in
            self?.updateTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0 / 60.0, target: self as Any, selector: #selector(self?.updateSmoothedMagnitudes), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            self?.updateTimer = timer
        }
        
        print("🟢 [AudioTap] CoreAudio CATap flowing through Aggregate Device!")
    }

    private func shouldSkipSpotifyTap(
        bundleIdentifier: String,
        bluetoothOutputActive: Bool
    ) -> Bool {
        bluetoothOutputActive
            && bundleIdentifier.caseInsensitiveCompare(SpotifyController.bundleIdentifier) == .orderedSame
    }
    
    private func cleanupPartialSetup() {
        if let validIOProcID = ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, validIOProcID)
        }
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = kAudioObjectUnknown
        aggregateDeviceID = kAudioObjectUnknown
        ioProcID = nil
        
        DispatchQueue.main.async { [weak self] in
            self?.updateTimer?.invalidate()
            self?.updateTimer = nil
        }
    }

    func restartCapture() {
        // Cancel any pending restart
        pendingRestartWorkItem?.cancel()
        
        // Debounce: wait 500ms before actually restarting
        let workItem = DispatchWorkItem { [weak self] in
            self?.audioQueue.async {
                print("🔄 [AudioTap] Restarting capture...")
                self?.stopCaptureSync()
                // Small delay to let CoreAudio fully release resources
                Thread.sleep(forTimeInterval: 0.1)
                // Re-read the setting instead of trusting the state at scheduling time: the
                // waveform can be switched off during the debounce window, and a stale
                // restart must not bring capture back up behind the user's back.
                guard Defaults[.enableRealTimeWaveform] else {
                    print("⏹️ [AudioTap] Waveform disabled during restart, staying stopped")
                    return
                }
                self?.startCaptureSync()
            }
        }
        pendingRestartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    func stopCapture() {
        // Drop a queued restart first, otherwise a debounced route/app change can resurrect
        // capture right after the caller asked us to stop.
        pendingRestartWorkItem?.cancel()
        pendingRestartWorkItem = nil

        audioQueue.sync { [weak self] in
            self?.stopCaptureSync()
        }
    }
    
    private func stopCaptureSync() {
        guard captureIsRunning else { return }

        // Stop listening
        if let validIOProcID = ioProcID, aggregateDeviceID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateDeviceID, validIOProcID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, validIOProcID)
        }

        // Destroy resources
        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }

        tapID = kAudioObjectUnknown
        aggregateDeviceID = kAudioObjectUnknown
        ioProcID = nil
        captureIsRunning = false
        
        DispatchQueue.main.async { [weak self] in
            self?.updateTimer?.invalidate()
            self?.updateTimer = nil
            // Reset display magnitudes safely on main thread
            self?.displayMagnitudes = Array(repeating: 0, count: 6)
        }

        print("🔴 [AudioTap] CoreAudio CATap capture stopped")
    }
    
    var isCapturing: Bool {
        captureIsRunning
    }

    deinit {
        stopCaptureSync()
    }
}

// Helper to convert OSStatus to readable string
private func fourCharCodeToString(_ code: OSStatus) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xFF),
        UInt8((code >> 16) & 0xFF),
        UInt8((code >> 8) & 0xFF),
        UInt8(code & 0xFF)
    ]
    if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) {
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
    return String(code)
}
