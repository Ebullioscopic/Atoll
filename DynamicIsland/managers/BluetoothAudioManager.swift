//
//  BluetoothAudioManager.swift
//  DynamicIsland
//
//  Created for Bluetooth audio device connection detection and monitoring
//  Detects when audio devices connect and displays HUD with battery status
//

import Foundation
import Combine
import AppKit
import Defaults
import SwiftUI
import IOBluetooth
import IOKit

/// Manages detection and monitoring of Bluetooth audio device connections
class BluetoothAudioManager: ObservableObject {
    static let shared = BluetoothAudioManager()
    
    // MARK: - Published Properties
    @Published var lastConnectedDevice: BluetoothAudioDevice?
    @Published var connectedDevices: [BluetoothAudioDevice] = []
    @Published var isBluetoothAudioConnected: Bool = false
    
    // MARK: - Private Properties
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private let coordinator = DynamicIslandViewCoordinator.shared
    private var pollingTimer: Timer?
    private let bluetoothPreferencesSuite = "/Library/Preferences/com.apple.Bluetooth"

    @Published private(set) var batteryStatus: [String: String] = [:]

    private var batteryStatusByAddress: [String: Int] = [:]
    private var batteryStatusByName: [String: Int] = [:]
    private var missingBatteryLog: Set<String> = []
    private var lastBatteryStatusUpdate: Date?
    private let batteryStatusUpdateInterval: TimeInterval = 20
    
    // MARK: - Initialization
    private init() {
        print("🎧 [BluetoothAudioManager] Initializing...")
        setupBluetoothObservers()
        checkInitialDevices()
        startPollingForChanges()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Setup Methods
    
    /// Sets up observers for Bluetooth device connection/disconnection events
    private func setupBluetoothObservers() {
        print("🎧 [BluetoothAudioManager] Setting up Bluetooth observers...")
        
        // Use DistributedNotificationCenter for IOBluetooth notifications
        let dnc = DistributedNotificationCenter.default()
        
        // Observe device connected notifications
        dnc.addObserver(
            self,
            selector: #selector(handleDeviceConnectedNotification(_:)),
            name: NSNotification.Name("IOBluetoothDeviceConnectedNotification"),
            object: nil
        )
        
        // Observe device disconnected notifications
        dnc.addObserver(
            self,
            selector: #selector(handleDeviceDisconnectedNotification(_:)),
            name: NSNotification.Name("IOBluetoothDeviceDisconnectedNotification"),
            object: nil
        )
        
        print("🎧 [BluetoothAudioManager] ✅ Observers registered with DistributedNotificationCenter")
    }
    
    /// Starts polling for device connection changes (fallback mechanism)
    private func startPollingForChanges() {
        print("🎧 [BluetoothAudioManager] Starting polling timer (3s interval)...")
        
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkForDeviceChanges()
        }
    }
    
    /// Checks for device connection/disconnection changes
    private func checkForDeviceChanges() {
        // Check if Bluetooth is powered on
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
            // Bluetooth is off - clear connected devices if any
            if !connectedDevices.isEmpty {
                print("🎧 [BluetoothAudioManager] ⚠️ Bluetooth powered off - clearing connected devices")
                connectedDevices.removeAll()
                isBluetoothAudioConnected = false
            }
            return
        }
        
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }
        
        let currentlyConnectedAddresses = Set(
            pairedDevices
                .filter { $0.isConnected() && isAudioDevice($0) }
                .compactMap { $0.addressString }
        )
        
        let previousAddresses = Set(connectedDevices.map { $0.address })
        
        // Check for new connections
        let newAddresses = currentlyConnectedAddresses.subtracting(previousAddresses)
        if !newAddresses.isEmpty {
            print("🎧 [BluetoothAudioManager] 🔍 Polling detected new connection(s)")
            checkForNewlyConnectedDevices()
        }
        
        // Check for disconnections
        let removedAddresses = previousAddresses.subtracting(currentlyConnectedAddresses)
        if !removedAddresses.isEmpty {
            print("🎧 [BluetoothAudioManager] 🔍 Polling detected disconnection(s)")
            updateConnectedDevices()
        }
    }
    
    /// Checks for already connected Bluetooth audio devices on init
    private func checkInitialDevices() {
        print("🎧 [BluetoothAudioManager] Checking for initially connected devices...")
        
        // Check if Bluetooth is powered on
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
            print("🎧 [BluetoothAudioManager] ⚠️ Bluetooth is powered off - skipping initial check")
            return
        }
        
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            print("🎧 [BluetoothAudioManager] No paired devices found")
            return
        }
        
        let connectedAudioDevices = pairedDevices.filter { device in
            device.isConnected() && isAudioDevice(device)
        }
        
        print("🎧 [BluetoothAudioManager] Found \(connectedAudioDevices.count) connected audio devices")
        
        connectedDevices = connectedAudioDevices.compactMap { device in
            createBluetoothAudioDevice(from: device)
        }
        
        // Update connection state
        isBluetoothAudioConnected = !connectedDevices.isEmpty
        
        refreshBatteryLevelsForConnectedDevices()

        if let lastDevice = connectedDevices.last {
            lastConnectedDevice = lastDevice
            print("🎧 [BluetoothAudioManager] ✅ Bluetooth audio connected: \(lastDevice.name)")
        }
    }
    
    // MARK: - Device Event Handlers
    
    /// Handles Bluetooth device connection notification from DistributedNotificationCenter
    @objc private func handleDeviceConnectedNotification(_ notification: Notification) {
        print("🎧 [BluetoothAudioManager] 📡 Device connection notification received")
        
        // Re-check all devices since distributed notification doesn't contain device object
        checkForNewlyConnectedDevices()
    }
    
    /// Handles Bluetooth device disconnection notification from DistributedNotificationCenter
    @objc private func handleDeviceDisconnectedNotification(_ notification: Notification) {
        print("🎧 [BluetoothAudioManager] 📡 Device disconnection notification received")
        
        // Re-check all devices to update connection state
        updateConnectedDevices()
    }
    
    /// Checks for newly connected devices and displays HUD for new ones
    private func checkForNewlyConnectedDevices() {
        // Check if Bluetooth is powered on
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
            print("🎧 [BluetoothAudioManager] ⚠️ Bluetooth is powered off - skipping device check")
            return
        }
        
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }
        
        let currentlyConnectedDevices = pairedDevices.filter { device in
            device.isConnected() && isAudioDevice(device)
        }
        
        // Find devices that are newly connected
        for device in currentlyConnectedDevices {
            let address = device.addressString ?? "Unknown"
            
            // Check if this device wasn't in our list before
            if !connectedDevices.contains(where: { $0.address == address }) {
                print("🎧 [BluetoothAudioManager] 🎉 New audio device connected: \(device.name ?? "Unknown")")
                
                guard let audioDevice = createBluetoothAudioDevice(from: device) else {
                    continue
                }
                
                // Add to connected devices
                connectedDevices.append(audioDevice)
                lastConnectedDevice = audioDevice
                isBluetoothAudioConnected = true

                refreshBatteryLevelsForConnectedDevices()
                
                // Show HUD for new connection
                if let refreshedDevice = connectedDevices.last {
                    showDeviceConnectedHUD(refreshedDevice)
                } else {
                    showDeviceConnectedHUD(audioDevice)
                }
            }
        }
    }
    
    /// Updates the list of connected devices (for disconnections)
    private func updateConnectedDevices() {
        guard let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return
        }
        
        let currentlyConnectedAddresses = pairedDevices
            .filter { $0.isConnected() && isAudioDevice($0) }
            .compactMap { $0.addressString }
        
        // Remove disconnected devices
        let previousCount = connectedDevices.count
        connectedDevices.removeAll { device in
            !currentlyConnectedAddresses.contains(device.address)
        }
        
        if connectedDevices.count < previousCount {
            print("🎧 [BluetoothAudioManager] 👋 Audio device(s) disconnected")
        }
        
        isBluetoothAudioConnected = !connectedDevices.isEmpty

        refreshBatteryLevelsForConnectedDevices()
    }
    
    /// Handles Bluetooth device connection event (legacy - kept for compatibility)
    private func handleDeviceConnected(_ notification: Notification) {
        guard let device = notification.object as? IOBluetoothDevice else {
            print("🎧 [BluetoothAudioManager] ⚠️ Could not extract device from notification")
            return
        }
        
        // Only handle audio devices
        guard isAudioDevice(device) else {
            print("🎧 [BluetoothAudioManager] Device is not an audio device, ignoring")
            return
        }
        
        print("🎧 [BluetoothAudioManager] 🎉 Audio device connected: \(device.name ?? "Unknown")")
        
        guard let audioDevice = createBluetoothAudioDevice(from: device) else {
            return
        }
        
        // Add to connected devices list
        if !connectedDevices.contains(where: { $0.address == audioDevice.address }) {
            connectedDevices.append(audioDevice)
        }
        
        // Update last connected device
        lastConnectedDevice = audioDevice
        isBluetoothAudioConnected = true
        
        // Show HUD
        showDeviceConnectedHUD(audioDevice)
    }
    
    /// Handles Bluetooth device disconnection event
    private func handleDeviceDisconnected(_ notification: Notification) {
        guard let device = notification.object as? IOBluetoothDevice else {
            return
        }
        
        guard isAudioDevice(device) else {
            return
        }
        
        print("🎧 [BluetoothAudioManager] 👋 Audio device disconnected: \(device.name ?? "Unknown")")
        
        // Remove from connected devices
        let address = device.addressString ?? "Unknown"
        connectedDevices.removeAll { $0.address == address }
        isBluetoothAudioConnected = !connectedDevices.isEmpty
    }
    
    // MARK: - Device Detection Helpers
    
    /// Determines if a Bluetooth device is an audio device
    private func isAudioDevice(_ device: IOBluetoothDevice) -> Bool {
        // Check if device has audio service UUID
        let audioServiceUUID = IOBluetoothSDPUUID(uuid16: 0x110B)  // Audio Sink
        let headsetServiceUUID = IOBluetoothSDPUUID(uuid16: 0x1108)  // Headset
        let handsfreeServiceUUID = IOBluetoothSDPUUID(uuid16: 0x111E)  // Handsfree
        
        // Check if device has any audio-related services
        if device.getServiceRecord(for: audioServiceUUID) != nil {
            return true
        }
        if device.getServiceRecord(for: headsetServiceUUID) != nil {
            return true
        }
        if device.getServiceRecord(for: handsfreeServiceUUID) != nil {
            return true
        }
        
        // Check device class (major class: Audio/Video)
        let deviceClass = device.classOfDevice
        let majorClass = (deviceClass >> 8) & 0x1F
        let audioVideoMajorClass: UInt32 = 0x04
        
        return majorClass == audioVideoMajorClass
    }
    
    /// Creates a BluetoothAudioDevice model from IOBluetoothDevice
    private func createBluetoothAudioDevice(from device: IOBluetoothDevice) -> BluetoothAudioDevice? {
        let name = device.name ?? "Bluetooth Device"
        let address = device.addressString ?? "Unknown"
        let batteryLevel = getBatteryLevel(from: device)
        let deviceType = detectDeviceType(from: device, name: name)
        
        return BluetoothAudioDevice(
            name: name,
            address: address,
            batteryLevel: batteryLevel,
            deviceType: deviceType
        )
    }
    
    /// Extracts battery level from Bluetooth device
    private func getBatteryLevel(from device: IOBluetoothDevice) -> Int? {
        updateBatteryStatuses()

        if let level = batteryLevelFromRegistry(forAddress: device.addressString) {
            clearMissingBatteryInfo(for: device)
            return level
        }

        if let name = device.name, let level = batteryLevelFromRegistry(forName: name) {
            clearMissingBatteryInfo(for: device)
            return level
        }

        if let level = batteryLevelFromDefaults(forAddress: device.addressString) {
            clearMissingBatteryInfo(for: device)
            return level
        }

        if let name = device.name, let level = batteryLevelFromDefaults(forName: name) {
            clearMissingBatteryInfo(for: device)
            return level
        }

        logMissingBatteryInfo(for: device)
        return nil
    }
    
    /// Detects the type of audio device based on name and properties
    private func detectDeviceType(from device: IOBluetoothDevice, name: String) -> BluetoothAudioDeviceType {
        let lowercaseName = name.lowercased()
        
        // Check for specific AirPods models
        if lowercaseName.contains("airpods") {
            if lowercaseName.contains("max") {
                return .airpodsMax
            } else if lowercaseName.contains("pro") {
                return .airpodsPro
            }
            return .airpods
        }
        
        // Check for other brands
        if lowercaseName.contains("beats") {
            return .beats
        } else if lowercaseName.contains("speaker") || lowercaseName.contains("boombox") {
            return .speaker
        } else if lowercaseName.contains("headphone") || lowercaseName.contains("headset") || 
                  lowercaseName.contains("buds") || lowercaseName.contains("earbuds") {
            return .headphones
        }
        
        // Check device class for more specific detection
        let deviceClass = device.classOfDevice
        let minorClass = (deviceClass >> 2) & 0x3F
        
        // Minor classes for audio devices
        switch minorClass {
        case 0x01: return .headphones  // Wearable Headset
        case 0x02: return .headphones  // Hands-free
        case 0x06: return .headphones  // Headphones
        case 0x08: return .speaker     // Portable Audio
        case 0x0C: return .speaker     // Loudspeaker
        default: return .generic
        }
    }

    private func refreshBatteryLevelsForConnectedDevices() {
        updateBatteryStatuses(force: true)

        var updatedDevices: [BluetoothAudioDevice] = []
        for device in connectedDevices {
            let refreshedLevel =
                batteryLevelFromRegistry(forAddress: device.address)
                ?? batteryLevelFromRegistry(forName: device.name)
                ?? batteryLevelFromDefaults(forAddress: device.address)
                ?? batteryLevelFromDefaults(forName: device.name)
                ?? device.batteryLevel
            let updatedDevice = device.withBatteryLevel(refreshedLevel)
            updatedDevices.append(updatedDevice)

            if let refreshedLevel {
                clearMissingBatteryInfo(forName: device.name, address: device.address)
            } else {
                logMissingBatteryInfo(forName: device.name, address: device.address)
            }
        }

        connectedDevices = updatedDevices
        if let last = connectedDevices.last {
            lastConnectedDevice = last
        }
    }

    private func batteryLevelFromDefaults(forAddress address: String?) -> Int? {
        guard let address, !address.isEmpty else { return nil }
        guard let preferences = UserDefaults(suiteName: bluetoothPreferencesSuite) else { return nil }
        guard let deviceCache = preferences.object(forKey: "DeviceCache") as? [String: Any] else { return nil }

        let normalizedTarget = normalizeBluetoothIdentifier(address)
        var bestMatch: Int?

        for (key, value) in deviceCache {
            guard let payload = value as? [String: Any] else { continue }
            if matchesBluetoothIdentifier(normalizedTarget, key: key, payload: payload) {
                if let level = extractBatteryPercentage(from: payload) {
                    let clamped = clampBatteryPercentage(level)
                    bestMatch = max(bestMatch ?? clamped, clamped)
                }
            }
        }

        return bestMatch
    }

    private func batteryLevelFromDefaults(forName name: String) -> Int? {
        guard !name.isEmpty else { return nil }
        guard let preferences = UserDefaults(suiteName: bluetoothPreferencesSuite) else { return nil }
        guard let deviceCache = preferences.object(forKey: "DeviceCache") as? [String: Any] else { return nil }

        var bestMatch: Int?

        for value in deviceCache.values {
            guard let payload = value as? [String: Any] else { continue }
            let candidateName = (payload["Name"] as? String) ?? (payload["DeviceName"] as? String)
            if let candidateName, candidateName.caseInsensitiveCompare(name) == .orderedSame {
                if let level = extractBatteryPercentage(from: payload) {
                    let clamped = clampBatteryPercentage(level)
                    bestMatch = max(bestMatch ?? clamped, clamped)
                }
            }
        }

        return bestMatch
    }

    private func batteryLevelFromRegistry(forName name: String) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = normalizeProductName(trimmed)
        guard !normalized.isEmpty else { return nil }
        if let value = batteryStatusByName[normalized] {
            return clampBatteryPercentage(value)
        }
        return nil
    }

    private func updateBatteryStatuses(force: Bool = false) {
        let now = Date()
        if !force, let lastBatteryStatusUpdate,
           now.timeIntervalSince(lastBatteryStatusUpdate) < batteryStatusUpdateInterval {
            return
        }

        var combinedAddressPercentages: [String: Int] = [:]
        var combinedNamePercentages: [String: Int] = [:]

        let registry = collectRegistryBatteryLevels()
        mergeBatteryLevels(into: &combinedAddressPercentages, from: registry.addresses)
        mergeBatteryLevels(into: &combinedNamePercentages, from: registry.names)

        let defaults = collectDefaultsBatteryLevels()
        mergeBatteryLevels(into: &combinedAddressPercentages, from: defaults.addresses)
        mergeBatteryLevels(into: &combinedNamePercentages, from: defaults.names)

        let profiler = collectSystemProfilerBatteryLevels()
        mergeBatteryLevels(into: &combinedAddressPercentages, from: profiler.addresses)
        mergeBatteryLevels(into: &combinedNamePercentages, from: profiler.names)

        var statuses: [String: String] = [:]
        for (key, value) in combinedAddressPercentages {
            statuses[key] = String(clampBatteryPercentage(value))
        }

        let applyUpdates = {
            self.batteryStatus = statuses
            self.batteryStatusByAddress = combinedAddressPercentages
            self.batteryStatusByName = combinedNamePercentages
            self.lastBatteryStatusUpdate = now
        }

        if Thread.isMainThread {
            applyUpdates()
        } else {
            DispatchQueue.main.sync(execute: applyUpdates)
        }
    }

    private func mergeBatteryLevels(into target: inout [String: Int], from source: [String: Int]) {
        guard !source.isEmpty else { return }
        for (key, value) in source {
            guard !key.isEmpty else { continue }
            if let existing = target[key] {
                target[key] = max(existing, value)
            } else {
                target[key] = value
            }
        }
    }

    private func collectRegistryBatteryLevels() -> (addresses: [String: Int], names: [String: Int]) {
        var addressPercentages: [String: Int] = [:]
        var namePercentages: [String: Int] = [:]

        var iterator = io_iterator_t()
        let matchingDict: CFDictionary = IOServiceMatching("AppleDeviceManagementHIDEventService")

        let servicePort: mach_port_t
        if #available(macOS 12.0, *) {
            servicePort = kIOMainPortDefault
        } else {
            servicePort = kIOMasterPortDefault
        }

        let kernResult = IOServiceGetMatchingServices(servicePort, matchingDict, &iterator)

        if kernResult == KERN_SUCCESS {
            var entry: io_object_t = IOIteratorNext(iterator)
            while entry != 0 {
                if let percent = IORegistryEntryCreateCFProperty(entry, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int {
                    let normalizedPercent = clampBatteryPercentage(percent)

                    let identifierKeys = ["DeviceAddress", "SerialNumber", "BD_ADDR"]
                    for key in identifierKeys {
                        if let identifier = stringValue(forKey: key, entry: entry) {
                            let normalizedIdentifier = normalizeBluetoothIdentifier(identifier)
                            if !normalizedIdentifier.isEmpty {
                                if let existing = addressPercentages[normalizedIdentifier] {
                                    addressPercentages[normalizedIdentifier] = max(existing, normalizedPercent)
                                } else {
                                    addressPercentages[normalizedIdentifier] = normalizedPercent
                                }
                            }
                        }
                    }

                    let nameKeys = [
                        "Product",
                        "ProductName",
                        "DeviceName",
                        "Name",
                        "USB Product Name",
                        "Bluetooth Product Name"
                    ]

                    for key in nameKeys {
                        if let product = stringValue(forKey: key, entry: entry) {
                            let normalizedName = normalizeProductName(product)
                            if !normalizedName.isEmpty {
                                if let existing = namePercentages[normalizedName] {
                                    namePercentages[normalizedName] = max(existing, normalizedPercent)
                                } else {
                                    namePercentages[normalizedName] = normalizedPercent
                                }
                            }
                        }
                    }
                }

                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
        }

        IOObjectRelease(iterator)

        return (addressPercentages, namePercentages)
    }

    private func collectDefaultsBatteryLevels() -> (addresses: [String: Int], names: [String: Int]) {
        guard let preferences = UserDefaults(suiteName: bluetoothPreferencesSuite),
              let deviceCache = preferences.object(forKey: "DeviceCache") as? [String: Any] else {
            return ([:], [:])
        }

        var addressPercentages: [String: Int] = [:]
        var namePercentages: [String: Int] = [:]

        for (key, value) in deviceCache {
            guard let payload = value as? [String: Any] else { continue }
            guard let level = extractBatteryPercentage(from: payload) else { continue }
            let clamped = clampBatteryPercentage(level)

            let normalizedKey = normalizeBluetoothIdentifier(key)
            if !normalizedKey.isEmpty {
                addressPercentages[normalizedKey] = max(addressPercentages[normalizedKey] ?? clamped, clamped)
            }

            for identifier in identifiersFromDeviceCachePayload(payload) {
                addressPercentages[identifier] = max(addressPercentages[identifier] ?? clamped, clamped)
            }

            if let name = (payload["Name"] as? String) ?? (payload["DeviceName"] as? String) {
                let normalizedName = normalizeProductName(name)
                if !normalizedName.isEmpty {
                    namePercentages[normalizedName] = max(namePercentages[normalizedName] ?? clamped, clamped)
                }
            }
        }

        return (addressPercentages, namePercentages)
    }

    private func collectSystemProfilerBatteryLevels() -> (addresses: [String: Int], names: [String: Int]) {
        guard let root = systemProfilerBluetoothDictionary() else {
            return ([:], [:])
        }

        var addressPercentages: [String: Int] = [:]
        var namePercentages: [String: Int] = [:]

        if let connectedList = root["device_connected"] as? [[String: [String: Any]]] {
            for deviceGroup in connectedList {
                for (rawName, payload) in deviceGroup {
                    guard let percent = extractSystemProfilerBatteryPercentage(from: payload) else { continue }
                    let clamped = clampBatteryPercentage(percent)

                    let normalizedName = normalizeProductName(rawName)
                    if !normalizedName.isEmpty {
                        namePercentages[normalizedName] = max(namePercentages[normalizedName] ?? clamped, clamped)
                    }

                    for address in profilerAddressCandidates(from: payload) {
                        let normalizedAddress = normalizeBluetoothIdentifier(address)
                        if !normalizedAddress.isEmpty {
                            addressPercentages[normalizedAddress] = max(addressPercentages[normalizedAddress] ?? clamped, clamped)
                        }
                    }
                }
            }
        }

        return (addressPercentages, namePercentages)
    }

    private func identifiersFromDeviceCachePayload(_ payload: [String: Any]) -> [String] {
        var identifiers: Set<String> = []
        let candidateKeys = ["DeviceAddress", "Address", "BD_ADDR", "SerialNumber"]

        for key in candidateKeys {
            if let value = payload[key] as? String {
                let normalized = normalizeBluetoothIdentifier(value)
                if !normalized.isEmpty {
                    identifiers.insert(normalized)
                }
            } else if let data = payload[key] as? Data,
                      let ascii = String(data: data, encoding: .utf8) {
                let normalized = normalizeBluetoothIdentifier(ascii)
                if !normalized.isEmpty {
                    identifiers.insert(normalized)
                }
            }
        }

        return Array(identifiers)
    }

    private func systemProfilerBluetoothDictionary() -> [String: Any]? {
        let process = Process()
        process.launchPath = "/usr/sbin/system_profiler"
        process.arguments = ["SPBluetoothDataType", "-json"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }
        guard !data.isEmpty else { return nil }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let entries = jsonObject["SPBluetoothDataType"] as? [[String: Any]],
              let root = entries.first else {
            return nil
        }

        return root
    }

    private func extractSystemProfilerBatteryPercentage(from payload: [String: Any]) -> Int? {
        let preferredKeys = [
            "device_batteryLevelCase",
            "device_batteryLevelLeft",
            "device_batteryLevelRight",
            "device_batteryLevelMain",
            "device_batteryLevel",
            "device_batteryLevelCombined",
            "device_batteryPercentCombined",
            "Left Battery Level",
            "Right Battery Level",
            "Battery Level",
            "BatteryPercent"
        ]

        var values: [Int] = []

        for key in preferredKeys {
            if let raw = payload[key], let converted = convertToBatteryPercentage(raw) {
                values.append(converted)
            }
        }

        if values.isEmpty {
            for (key, raw) in payload where key.lowercased().contains("battery") {
                if let converted = convertToBatteryPercentage(raw) {
                    values.append(converted)
                }
            }
        }

        let validValues = values.filter { $0 >= 0 }
        return validValues.max()
    }

    private func profilerAddressCandidates(from payload: [String: Any]) -> [String] {
        var addresses: Set<String> = []
        let keys = [
            "device_address",
            "device_mac_address",
            "device_serial_num",
            "device_serialNumber",
            "device_serial_number"
        ]

        for key in keys {
            if let value = payload[key] as? String, !value.isEmpty {
                addresses.insert(value)
            } else if let data = payload[key] as? Data,
                      let ascii = String(data: data, encoding: .utf8), !ascii.isEmpty {
                addresses.insert(ascii)
            }
        }

        return Array(addresses)
    }

    private func batteryLevelFromRegistry(forAddress address: String?) -> Int? {
        guard let address, !address.isEmpty else { return nil }
        let normalized = normalizeBluetoothIdentifier(address)
        if let value = batteryStatusByAddress[normalized] {
            return clampBatteryPercentage(value)
        }
        if let storedValue = batteryStatus[normalized], let value = Int(storedValue) {
            return clampBatteryPercentage(value)
        }
        return nil
    }

    private func extractBatteryPercentage(from payload: [String: Any]) -> Int? {
        let keys = [
            "BatteryPercent",
            "BatteryPercentCase",
            "BatteryPercentLeft",
            "BatteryPercentRight",
            "BatteryPercentSingle",
            "BatteryPercentCombined",
            "BatteryPercentMain",
            "device_batteryLevelLeft",
            "device_batteryLevelRight",
            "device_batteryLevelMain",
            "Left Battery Level",
            "Right Battery Level"
        ]

        var values: [Int] = []

        for key in keys {
            guard let raw = payload[key] else { continue }
            if let converted = convertToBatteryPercentage(raw) {
                values.append(converted)
            }
        }

        if values.isEmpty,
           let services = payload["Services"] as? [[String: Any]] {
            for service in services {
                if let serviceValues = service["BatteryPercentages"] as? [String: Any] {
                    for value in serviceValues.values {
                        if let converted = convertToBatteryPercentage(value) {
                            values.append(converted)
                        }
                    }
                }
            }
        }

        return values.max()
    }

    private func convertToBatteryPercentage(_ value: Any) -> Int? {
        if let number = value as? Int {
            if number == 1 {
                return 100
            }
            return number
        }
        if let number = value as? Double {
            if number <= 1.0 {
                return Int(number * 100)
            }
            return Int(number)
        }
        if let string = value as? String {
            let trimmed = string.replacingOccurrences(of: "%", with: "")
            if let doubleValue = Double(trimmed) {
                if doubleValue <= 1.0 {
                    return Int(doubleValue * 100)
                }
                return Int(doubleValue)
            }
        }

        return nil
    }

    private func clampBatteryPercentage(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }

    private func matchesBluetoothIdentifier(_ normalizedTarget: String, key: String, payload: [String: Any]) -> Bool {
        if normalizeBluetoothIdentifier(key) == normalizedTarget {
            return true
        }

        let candidateFields: [String?] = [
            payload["DeviceAddress"] as? String,
            payload["Address"] as? String,
            payload["BD_ADDR"] as? String,
            payload["SerialNumber"] as? String
        ]

        for field in candidateFields {
            if let field, normalizeBluetoothIdentifier(field) == normalizedTarget {
                return true
            }
        }

        if let deviceAddressData = payload["DeviceAddress"] as? Data,
           let ascii = String(data: deviceAddressData, encoding: .utf8),
           normalizeBluetoothIdentifier(ascii) == normalizedTarget {
            return true
        }

        if let addressData = payload["BD_ADDR"] as? Data,
           let ascii = String(data: addressData, encoding: .utf8),
           normalizeBluetoothIdentifier(ascii) == normalizedTarget {
            return true
        }

        if let serialData = payload["SerialNumber"] as? Data,
           let ascii = String(data: serialData, encoding: .utf8),
           normalizeBluetoothIdentifier(ascii) == normalizedTarget {
            return true
        }

        return false
    }

    private func logMissingBatteryInfo(for device: IOBluetoothDevice) {
        let name = device.name ?? ""
        let address = device.addressString ?? ""
        logMissingBatteryInfo(forName: name, address: address)
    }

    private func clearMissingBatteryInfo(for device: IOBluetoothDevice) {
        let name = device.name ?? ""
        let address = device.addressString ?? ""
        clearMissingBatteryInfo(forName: name, address: address)
    }

    private func logMissingBatteryInfo(forName name: String, address: String) {
        let key = missingBatteryKey(name: name, address: address)
        guard !missingBatteryLog.contains(key) else { return }
        missingBatteryLog.insert(key)

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        let displayName = trimmedName.isEmpty ? "unknown device" : trimmedName
        let isUnknownAddress = trimmedAddress.caseInsensitiveCompare("unknown") == .orderedSame
        let displayAddress = (trimmedAddress.isEmpty || isUnknownAddress) ? "N/A" : trimmedAddress
        print("🎧 [BluetoothAudioManager] ⚠️ Battery percentage unavailable for \(displayName) (\(displayAddress))")
    }

    private func clearMissingBatteryInfo(forName name: String, address: String) {
        let key = missingBatteryKey(name: name, address: address)
        missingBatteryLog.remove(key)
    }

    private func missingBatteryKey(name: String, address: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedName = normalizeProductName(trimmedName)

        let isUnknownAddress = trimmedAddress.caseInsensitiveCompare("unknown") == .orderedSame
        let normalizedAddress = (trimmedAddress.isEmpty || isUnknownAddress) ? "" : normalizeBluetoothIdentifier(trimmedAddress)

        if normalizedName.isEmpty && normalizedAddress.isEmpty {
            return "unknown"
        }

        return normalizedName + "#" + normalizedAddress
    }

    private func stringValue(forKey key: String, entry: io_object_t) -> String? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }

        let value = unmanaged.takeRetainedValue()

        if let string = value as? String, !string.isEmpty {
            return string
        }

        if let data = value as? Data, let ascii = String(data: data, encoding: .utf8), !ascii.isEmpty {
            return ascii
        }

        return nil
    }

    private func normalizeBluetoothIdentifier(_ value: String) -> String {
        return value
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
    }

    private func normalizeProductName(_ name: String) -> String {
        let components = name
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        return components.joined()
    }
    
    // MARK: - HUD Display
    
    /// Shows HUD notification for newly connected audio device
    private func showDeviceConnectedHUD(_ device: BluetoothAudioDevice) {
        guard Defaults[.showBluetoothDeviceConnections] else { return }
        
        print("🎧 [BluetoothAudioManager] 📱 Showing device connected HUD")
        
        // Convert battery percentage to 0.0-1.0 value
        let reportedBattery = device.batteryLevel
            ?? batteryLevelFromRegistry(forAddress: device.address)
            ?? batteryLevelFromRegistry(forName: device.name)
            ?? batteryLevelFromDefaults(forAddress: device.address)
            ?? batteryLevelFromDefaults(forName: device.name)

        let batteryValue: CGFloat = if let battery = reportedBattery {
            CGFloat(clampBatteryPercentage(battery)) / 100.0
        } else {
            0.0  // 0 means battery info not available
        }
        
        // Show HUD via coordinator
        coordinator.toggleSneakPeek(
            status: true,
            type: .bluetoothAudio,
            duration: 2.5,
            value: batteryValue,
            icon: device.deviceType.sfSymbol
        )
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        print("🎧 [BluetoothAudioManager] Cleaning up observers...")
        
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        let dnc = DistributedNotificationCenter.default()
        dnc.removeObserver(self)
        observers.removeAll()
        cancellables.removeAll()
    }

    @MainActor
    func refreshConnectedDeviceBatteries() {
        refreshBatteryLevelsForConnectedDevices()
    }
}

// MARK: - Models

struct BluetoothAudioDevice: Identifiable {
    let id: UUID
    let name: String
    let address: String
    let batteryLevel: Int?  // 0-100, nil if not available
    let deviceType: BluetoothAudioDeviceType

    init(
        id: UUID = UUID(),
        name: String,
        address: String,
        batteryLevel: Int?,
        deviceType: BluetoothAudioDeviceType
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.batteryLevel = batteryLevel
        self.deviceType = deviceType
    }
}

extension BluetoothAudioDevice {
    func withBatteryLevel(_ batteryLevel: Int?) -> BluetoothAudioDevice {
        BluetoothAudioDevice(
            id: id,
            name: name,
            address: address,
            batteryLevel: batteryLevel,
            deviceType: deviceType
        )
    }
}

enum BluetoothAudioDeviceType {
    case airpods
    case airpodsPro
    case airpodsMax
    case beats
    case headphones
    case speaker
    case generic
    
    var sfSymbol: String {
        switch self {
        case .airpods:
            return "airpods"
        case .airpodsPro:
            return "airpodspro"
        case .airpodsMax:
            return "airpodsmax"
        case .beats:
            return "beats.headphones"
        case .headphones:
            return "headphones"
        case .speaker:
            return "hifispeaker.fill"
        case .generic:
            return "bluetooth.circle.fill"
        }
    }
    
    var displayName: String {
        switch self {
        case .airpods: return "AirPods"
        case .airpodsPro: return "AirPods Pro"
        case .airpodsMax: return "AirPods Max"
        case .beats: return "Beats"
        case .headphones: return "Headphones"
        case .speaker: return "Speaker"
        case .generic: return "Bluetooth Device"
        }
    }
}

// MARK: - Notification Name Constants

private let IOBluetoothDeviceConnectionNotification = "IOBluetoothDeviceConnectionNotification"
private let IOBluetoothDeviceDisconnectionNotification = "IOBluetoothDeviceDisconnectionNotification"
