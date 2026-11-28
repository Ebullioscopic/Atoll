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
import CoreAudio
import SwiftUI
import Combine

/// Watches whether any app is recording from a microphone.
///
/// The answer comes from CoreAudio's per-process `IsRunningInput` flag — the
/// same "is this process capturing input" fact macOS uses for its own orange
/// dot — rather than from whether the default input *device* is running.
/// Reading the device alone went wrong in several ways: the monitor bound to
/// whichever device was the default at start-up and never rebound when the
/// default changed or that device disappeared, so its last "running" reading
/// could stick; a device that also does output reports itself running while it
/// only plays audio; and an app recording from a non-default microphone was
/// missed entirely.
///
/// Everything is event-driven: listeners on the process list, on each
/// process's input flag, on the default input device and on that device's
/// running state all lead to the same recount, and nothing polls.
@MainActor
class MicrophoneMonitor: ObservableObject {
    // MARK: - Published Properties
    @Published var isMicActive: Bool = false
    @Published var activeApp: String? = nil
    @Published var isMonitoring: Bool = false
    
    // MARK: - Private Properties
    private var defaultInputDevice: AudioDeviceID = 0
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var deactivationTask: Task<Void, Never>?
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    
    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    
    // MARK: - Initialization
    init() {}
    
    // MARK: - Public Methods
    
    /// Start monitoring microphone usage
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("MicrophoneMonitor: 🟢 Starting microphone monitoring...")
        isMonitoring = true
        
        installSystemListeners()
        rebindDefaultInputDevice()
        syncProcessListeners()
        checkMicrophoneStatus()
    }
    
    /// Stop monitoring microphone usage
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        print("MicrophoneMonitor: 🛑 Stopping monitoring...")
        isMonitoring = false
        
        removeSystemListeners()
        removeDeviceListener()
        removeAllProcessListeners()
        
        deactivationTask?.cancel()
        deactivationTask = nil
        if isMicActive {
            isMicActive = false
        }
        activeApp = nil
    }
    
    /// Toggle monitoring state
    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    /// Recount who is recording and publish the result. Turning on is
    /// immediate; turning off waits briefly so an app that restarts its input
    /// stream does not make the indicator blink.
    func checkMicrophoneStatus() {
        guard isMonitoring else { return }
        
        if isInputRunning() {
            deactivationTask?.cancel()
            deactivationTask = nil
            if !isMicActive {
                print("MicrophoneMonitor: 🔄 Microphone became ACTIVE")
                withAnimation(.smooth) {
                    isMicActive = true
                }
                activeApp = "Unknown App"
            }
        } else if isMicActive {
            guard deactivationTask == nil else { return }
            deactivationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled, let self else { return }
                self.deactivationTask = nil
                if !self.isInputRunning() {
                    print("MicrophoneMonitor: ⚪ Microphone INACTIVE (debounced)")
                    withAnimation(.smooth) {
                        self.isMicActive = false
                    }
                    self.activeApp = nil
                }
            }
        }
    }
    
    // MARK: - State
    
    /// Whether any other process is capturing audio input right now.
    ///
    /// Atoll's own process is left out: its audio visualiser and per-app
    /// volume taps read audio through aggregate devices, and that must not
    /// light the indicator. If CoreAudio returns no process list at all, the
    /// default input device's running state is used instead.
    private func isInputRunning() -> Bool {
        let processes = AudioProcessQuery.processObjectIDs()
        guard !processes.isEmpty else {
            return defaultInputDevice != 0 && Self.isDeviceRunningSomewhere(defaultInputDevice)
        }
        return processes.contains { process in
            Self.isRunningInput(process) && AudioProcessQuery.pid(for: process) != ownPID
        }
    }
    
    // MARK: - Listeners
    
    private func installSystemListeners() {
        if defaultDeviceListener == nil {
            var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, self.isMonitoring else { return }
                    self.rebindDefaultInputDevice()
                    self.checkMicrophoneStatus()
                }
            }
            if AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, .main, block) == noErr {
                defaultDeviceListener = block
            }
        }
        
        if processListListener == nil {
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in
                    guard let self, self.isMonitoring else { return }
                    self.syncProcessListeners()
                    self.checkMicrophoneStatus()
                }
            }
            if AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, .main, block) == noErr {
                processListListener = block
            }
        }
    }
    
    private func removeSystemListeners() {
        if let block = defaultDeviceListener {
            var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectRemovePropertyListenerBlock(Self.systemObject, &address, .main, block)
            defaultDeviceListener = nil
        }
        if let block = processListListener {
            var address = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(Self.systemObject, &address, .main, block)
            processListListener = nil
        }
    }
    
    /// Follow the current default input device, dropping the listener on the
    /// previous one. The device's running state is only a prompt to recount.
    private func rebindDefaultInputDevice() {
        let device = getDefaultInputDevice()
        guard device != defaultInputDevice || deviceListener == nil else { return }
        
        removeDeviceListener()
        defaultInputDevice = device
        guard device != 0 else {
            print("MicrophoneMonitor: ⚠️ No input device found")
            return
        }
        
        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.checkMicrophoneStatus() }
        }
        if AudioObjectAddPropertyListenerBlock(device, &address, .main, block) == noErr {
            deviceListener = block
        }
    }
    
    private func removeDeviceListener() {
        guard let block = deviceListener else { return }
        var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectRemovePropertyListenerBlock(defaultInputDevice, &address, .main, block)
        deviceListener = nil
    }
    
    /// Keep one `IsRunningInput` listener per live process object.
    private func syncProcessListeners() {
        let current = Set(AudioProcessQuery.processObjectIDs())
        
        for (process, block) in processListeners where !current.contains(process) {
            var address = Self.address(kAudioProcessPropertyIsRunningInput)
            AudioObjectRemovePropertyListenerBlock(process, &address, .main, block)
            processListeners[process] = nil
        }
        
        for process in current where processListeners[process] == nil {
            var address = Self.address(kAudioProcessPropertyIsRunningInput)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.checkMicrophoneStatus() }
            }
            if AudioObjectAddPropertyListenerBlock(process, &address, .main, block) == noErr {
                processListeners[process] = block
            }
        }
    }
    
    private func removeAllProcessListeners() {
        for (process, block) in processListeners {
            var address = Self.address(kAudioProcessPropertyIsRunningInput)
            AudioObjectRemovePropertyListenerBlock(process, &address, .main, block)
        }
        processListeners.removeAll()
    }
    
    // MARK: - CoreAudio reads
    
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
    
    /// Get default input device ID
    private func getDefaultInputDevice() -> AudioDeviceID {
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        
        let status = AudioObjectGetPropertyData(Self.systemObject, &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return 0 }
        return deviceID
    }
    
    private static func isRunningInput(_ process: AudioObjectID) -> Bool {
        readFlag(process, kAudioProcessPropertyIsRunningInput)
    }
    
    private static func isDeviceRunningSomewhere(_ device: AudioDeviceID) -> Bool {
        readFlag(device, kAudioDevicePropertyDeviceIsRunningSomewhere)
    }
    
    private static func readFlag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else {
            return false
        }
        return value != 0
    }
}

// MARK: - Extensions

extension MicrophoneMonitor {
    /// Get current microphone status without async
    var currentMicStatus: Bool {
        return isMicActive
    }
    
    /// Check if monitoring is available
    var isMonitoringAvailable: Bool {
        return getDefaultInputDevice() != 0
    }
}
