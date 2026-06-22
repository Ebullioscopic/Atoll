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
import Combine
import AppKit
import Defaults
import SwiftUI
import IOBluetooth
import IOKit
import CoreBluetooth

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
    private let batteryReader = BluetoothLEBatteryReader()
    private var isLiveBatteryRefreshInFlight = false

    private let appleVendorID: UInt16 = 0x05AC
    private let devicePIDMap: [UInt16: BluetoothAudioDeviceType] = [
        0x2002: .airpods,      // Gen 1 AirPods
        0x200F: .airpods,      // Gen 2 AirPods
        0x2013: .airpodsGen3,  // Gen 3 AirPods
        0x2019: .airpodsGen4,  // Gen 4 AirPods
        0x201B: .airpodsGen4,  // Gen 4 AirPods ANC
        0x200A: .airpodsMax,   // AirPods Max Lightning
        0x201F: .airpodsMax,   // AirPods Max USB-C
        0x200E: .airpodsPro,   // AirPods Pro Gen 1
        0x2014: .airpodsPro,   // AirPods Pro Gen 2 Lightning
        0x2024: .airpodsPro,   // AirPods Pro Gen 2 USB-C
        0x2027: .airpodsPro3,  // AirPods Pro Gen 3
        0x2017: .beatsstudio,  // Beats Studio Pro
        0x2009: .beatsstudio,  // Beats Studio 3
        0x2006: .beatssolo,    // Beats Solo 3
        0x200C: .beatssolo     // Beats Solo Pro
    ]

    @Published private(set) var batteryStatus: [String: String] = [:]

    private var batteryStatusByAddress: [String: Int] = [:]
    private var batteryStatusByName: [String: Int] = [:]
    private var missingBatteryLog: Set<String> = []
    private var lastBatteryStatusUpdate: Date?
    private let batteryStatusUpdateInterval: TimeInterval = 20
    private let pmsetFetchQueue = DispatchQueue(label: "com.dynamicisland.bluetooth.pmset", qos: .utility)
    private var isPmsetRefreshInFlight = false
    private var lastPmsetRefreshDate: Date?
    private let pmsetRefreshCooldown: TimeInterval = 5
    private var hudBatteryWaitTasks: [UUID: Task<Void, Never>] = [:]
    private let hudBatteryWaitInterval: TimeInterval = 0.3
    private let hudBatteryWaitTimeout: TimeInterval = 1.8
    
    // MARK: - Initialization
    private init() {
        print("🎧 [BluetoothAudioManager] Initializing...")
        setupBluetoothObservers()
        DispatchQueue.main.async { [weak self] in
            self?.checkInitialDevices()
            self?.startPollingForChanges()
        }
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
        let removedDevices = connectedDevices.filter { device in
            !currentlyConnectedAddresses.contains(device.address)
        }
        connectedDevices.removeAll { device in
            !currentlyConnectedAddresses.contains(device.address)
        }
        
        if !removedDevices.isEmpty {
            print("🎧 [BluetoothAudioManager] 👋 Audio device(s) disconnected")
            removedDevices.forEach { cancelHUDBatteryWait(for: $0) }
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
        let removed = connectedDevices.filter { $0.address == address }
        connectedDevices.removeAll { $0.address == address }
        removed.forEach { cancelHUDBatteryWait(for: $0) }
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

    // MARK: - PID-based device detection

    /// Extract a UInt16 from common payload formats (Int/NSNumber/String including hex like "0x201B").
    private func extractUInt16(from payload: [String: Any], keys: [String]) -> UInt16? {
        for key in keys {
            guard let raw = payload[key] else { continue }

            if let number = raw as? NSNumber {
                return UInt16(truncatingIfNeeded: number.uint16Value)
            }
            if let intValue = raw as? Int {
                return UInt16(truncatingIfNeeded: intValue)
            }
            if let string = raw as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if trimmed.hasPrefix("0x") {
                    let hex = trimmed.dropFirst(2)
                    if let value = UInt16(hex, radix: 16) { return value }
                } else if let value = UInt16(trimmed, radix: 10) {
                    return value
                }
            }
        }
        return nil
    }

    /// Recursively search nested dictionaries/arrays for the first UInt16 value whose key matches `predicate`.
    private func deepSearchUInt16(in value: Any, predicate: (String) -> Bool) -> UInt16? {
        if let dict = value as? [String: Any] {
            for (key, entry) in dict {
                if predicate(key) {
                    if let found = extractUInt16(from: dict, keys: [key]) {
                        return found
                    }
                    if let number = entry as? NSNumber { return UInt16(truncatingIfNeeded: number.uint16Value) }
                    if let intValue = entry as? Int { return UInt16(truncatingIfNeeded: intValue) }
                    if let string = entry as? String {
                        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if trimmed.hasPrefix("0x"), let value = UInt16(trimmed.dropFirst(2), radix: 16) { return value }
                        if let value = UInt16(trimmed, radix: 10) { return value }
                    }
                }
            }

            for entry in dict.values {
                if let found = deepSearchUInt16(in: entry, predicate: predicate) { return found }
            }
            return nil
        }

        if let array = value as? [Any] {
            for entry in array {
                if let found = deepSearchUInt16(in: entry, predicate: predicate) { return found }
            }
            return nil
        }

        return nil
    }

    /// Fallback: attempt to get VendorID/ProductID from system_profiler SPBluetoothDataType JSON.
    private func vendorProductIDsFromSystemProfiler(forNormalizedAddress target: String) -> (vendor: UInt16, product: UInt16)? {
        guard !target.isEmpty else { return nil }
        guard let root = systemProfilerBluetoothDictionary() else { return nil }
        guard let deviceConnected = root["device_connected"] as? [Any] else { return nil }

        func pidFromPayload(_ payload: [String: Any]) -> UInt16? {
            if let raw = payload["device_productID"] as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if trimmed.hasPrefix("0x"), let value = UInt16(trimmed.dropFirst(2), radix: 16) { return value }
                if let value = UInt16(trimmed, radix: 16) { return value }
            }
            let productKeys = ["device_productID", "ProductID", "product_id", "productID", "DeviceProductID", "ProductId", "Product ID"]
            return extractUInt16(from: payload, keys: productKeys)
                ?? deepSearchUInt16(in: payload) { $0.lowercased().contains("productid") }
        }

        func vidFromPayload(_ payload: [String: Any]) -> UInt16? {
            let vendorKeys = ["device_vendorID", "VendorID", "vendor_id", "vendorID", "DeviceVendorID", "VendorId", "Vendor ID"]
            return extractUInt16(from: payload, keys: vendorKeys)
                ?? deepSearchUInt16(in: payload) { $0.lowercased().contains("vendorid") }
        }

        for item in deviceConnected {
            guard let dict = item as? [String: Any],
                  let nameKey = dict.keys.first,
                  let infoAny = dict[nameKey],
                  let payload = infoAny as? [String: Any] else {
                continue
            }

            if let address = payload["device_address"] as? String {
                if normalizeBluetoothIdentifier(address) != target { continue }
            } else {
                let candidates = profilerAddressCandidates(from: payload).map(normalizeBluetoothIdentifier)
                if !candidates.contains(target) { continue }
            }

            if let pid = pidFromPayload(payload) {
                if let vid = vidFromPayload(payload) {
                    return (vendor: vid, product: pid)
                }
                if devicePIDMap[pid] != nil {
                    return (vendor: appleVendorID, product: pid)
                }
            }
        }

        return nil
    }

    /// Attempts to find VendorID/ProductID for a device using Bluetooth caches.
    private func vendorProductIDs(for device: IOBluetoothDevice) -> (vendor: UInt16, product: UInt16)? {
        guard let preferences = UserDefaults(suiteName: bluetoothPreferencesSuite),
              let deviceCache = preferences.object(forKey: "DeviceCache") as? [String: Any] else {
            return nil
        }

        let target = normalizeBluetoothIdentifier(device.addressString ?? "")
        guard !target.isEmpty else { return nil }

        let vendorKeys = [
            "VendorID", "vendor_id", "vendorID",
            "device_vendorID", "DeviceVendorID", "device_vendor_id",
            "device_vendorId", "DeviceVendorId",
            "VendorId", "Vendor ID",
            "VendorIDSource", "VendorIDSourceLocal", "VendorIDSourceRemote"
        ]
        let productKeys = [
            "ProductID", "product_id", "productID",
            "device_productID", "DeviceProductID", "device_product_id",
            "device_productId", "DeviceProductId",
            "ProductId", "Product ID",
            "ProductIDSource", "ProductIDSourceLocal", "ProductIDSourceRemote"
        ]

        for (key, value) in deviceCache {
            guard let payload = value as? [String: Any] else { continue }
            if matchesBluetoothIdentifier(target, key: key, payload: payload) {
                let vendor = extractUInt16(from: payload, keys: vendorKeys)
                    ?? deepSearchUInt16(in: payload) { $0.lowercased().contains("vendorid") }

                let product = extractUInt16(from: payload, keys: productKeys)
                    ?? deepSearchUInt16(in: payload) { $0.lowercased().contains("productid") }

                if let product {
                    if let vendor {
                        return (vendor: vendor, product: product)
                    }
                    if devicePIDMap[product] != nil {
                        return (vendor: appleVendorID, product: product)
                    }
                }
            }
        }

        if let coreCache = preferences.object(forKey: "CoreBluetoothCache") as? [String: [String: Any]] {
            for payload in coreCache.values {
                if let addressValue = payload["DeviceAddress"]
                    ?? payload["Address"]
                    ?? payload["BD_ADDR"]
                    ?? payload["device_address"],
                   let address = normalizeBluetoothIdentifier(from: addressValue),
                   address == target {
                    let vendor = extractUInt16(from: payload, keys: vendorKeys)
                        ?? deepSearchUInt16(in: payload) { $0.lowercased().contains("vendorid") }

                    let product = extractUInt16(from: payload, keys: productKeys)
                        ?? deepSearchUInt16(in: payload) { $0.lowercased().contains("productid") }

                    if let product {
                        if let vendor {
                            return (vendor: vendor, product: product)
                        }
                        if devicePIDMap[product] != nil {
                            return (vendor: appleVendorID, product: product)
                        }
                    }
                }
            }
        }

        if let fromProfiler = vendorProductIDsFromSystemProfiler(forNormalizedAddress: target) {
            return fromProfiler
        }

        return nil
    }

    /// Attempts to detect AirPods/Beats type using vendor/product IDs.
    private func airPodsTypeFromPID(_ device: IOBluetoothDevice) -> BluetoothAudioDeviceType? {
        if let ids = vendorProductIDs(for: device) {
            return devicePIDMap[ids.product]
        }
        return nil
    }
    
    /// Detects the type of audio device based on name and properties
    private func detectDeviceType(from device: IOBluetoothDevice, name: String) -> BluetoothAudioDeviceType {
        let lowercaseName = name.lowercased()

        if let pidBasedType = airPodsTypeFromPID(device) {
            return pidBasedType
        }
        
        // Check for specific AirPods models
        if lowercaseName.contains("airpods") {
            if lowercaseName.contains("max") {
                return .airpodsMax
            } else if lowercaseName.contains("pro") {
                if lowercaseName.contains("3") || lowercaseName.contains("gen 3") || lowercaseName.contains("gen3") {
                    return .airpodsPro3
                }
                return .airpodsPro
            } else if lowercaseName.contains("gen 4")
                        || lowercaseName.contains("gen4")
                        || lowercaseName.contains("4th")
                        || lowercaseName.contains("airpods 4")
                        || lowercaseName.contains("airpods4") {
                return .airpodsGen4
            } else if lowercaseName.contains("gen 3")
                        || lowercaseName.contains("gen3")
                        || lowercaseName.contains("3rd")
                        || lowercaseName.contains("third")
                        || lowercaseName.contains("airpods 3")
                        || lowercaseName.contains("airpods3") {
                return .airpodsGen3
            }
            return .airpods
        }
        
        // Check for other brands
        if lowercaseName.contains("beats") {
            if lowercaseName.contains("studio") {
                return .beatsstudio
            }
            if lowercaseName.contains("solo") {
                return .beatssolo
            }
            return .beatssolo
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

    private func refreshBatteryLevelsForConnectedDevices(forceCacheRefresh: Bool = true) {
        if forceCacheRefresh {
            updateBatteryStatuses(force: true)
        }

        applyConnectedDeviceBatteryLevels()
        triggerLiveBatteryRefreshIfNeeded()
    }

    private func applyConnectedDeviceBatteryLevels(triggerPmsetFallback: Bool = true) {
        guard !connectedDevices.isEmpty else {
            lastConnectedDevice = nil
            return
        }

        var updatedDevices: [BluetoothAudioDevice] = []
        for device in connectedDevices {
            let refreshedLevel = bestBatteryLevel(for: device)
            let updatedDevice = device.withBatteryLevel(refreshedLevel)
            updatedDevices.append(updatedDevice)

            if let refreshedLevel {
                clearMissingBatteryInfo(forName: device.name, address: device.address)
            } else {
                logMissingBatteryInfo(forName: device.name, address: device.address)
            }
        }

        connectedDevices = updatedDevices
        if let last = updatedDevices.last {
            lastConnectedDevice = last
        }

        if triggerPmsetFallback,
           updatedDevices.contains(where: { $0.batteryLevel == nil }) {
            requestPmsetFallback(reason: "missing battery after refresh")
        }
    }

    private func bestBatteryLevel(for device: BluetoothAudioDevice) -> Int? {
        batteryLevelFromRegistry(forAddress: device.address)
            ?? batteryLevelFromRegistry(forName: device.name)
            ?? batteryLevelFromDefaults(forAddress: device.address)
            ?? batteryLevelFromDefaults(forName: device.name)
            ?? device.batteryLevel
    }

    private func requestPmsetFallback(reason: String) {
        guard connectedDevices.contains(where: { $0.batteryLevel == nil }) else { return }
        guard !isPmsetRefreshInFlight else { return }

        let now = Date()
        if let lastPmsetRefreshDate,
           now.timeIntervalSince(lastPmsetRefreshDate) < pmsetRefreshCooldown {
            return
        }

        isPmsetRefreshInFlight = true
        print("🎧 [BluetoothAudioManager] 🔄 Triggering pmset fallback (\(reason))")
        pmsetFetchQueue.async { [weak self] in
            guard let self else { return }
            let entries = self.collectPmsetAccessoryBatteryEntries()
            DispatchQueue.main.async {
                self.handlePmsetFallbackResults(entries)
            }
        }
    }

    private func handlePmsetFallbackResults(_ entries: [PmsetAccessoryBatteryEntry]) {
        isPmsetRefreshInFlight = false
        lastPmsetRefreshDate = Date()
        guard !entries.isEmpty else { return }

        var updatedNames = batteryStatusByName
        let newlyFilled = mergePmsetEntries(entries, into: &updatedNames, logNewEntries: true)
        guard !newlyFilled.isEmpty else { return }

        batteryStatusByName = updatedNames
        applyConnectedDeviceBatteryLevels(triggerPmsetFallback: false)

        if let level = hudBatteryLevelCandidate() {
            updateActiveBluetoothHUDBattery(with: level)
        }
    }

    private func triggerLiveBatteryRefreshIfNeeded() {
        guard !connectedDevices.isEmpty else { return }
        guard connectedDevices.contains(where: { $0.batteryLevel == nil }) else { return }
        guard !isLiveBatteryRefreshInFlight else { return }

        let lookups = coreBluetoothLookups(for: connectedDevices)
        guard !lookups.isEmpty else { return }

        isLiveBatteryRefreshInFlight = true
        batteryReader.fetchBatteryLevels(for: lookups) { [weak self] results in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isLiveBatteryRefreshInFlight = false
                self.handleLiveBatteryResults(results)
            }
        }
    }

    private func coreBluetoothLookups(for devices: [BluetoothAudioDevice]) -> [BluetoothLEBatteryReader.Lookup] {
        let snapshot = coreBluetoothCacheSnapshot()
        guard snapshot.hasEntries else { return [] }

        var lookups: [BluetoothLEBatteryReader.Lookup] = []
        var seenUUIDs: Set<UUID> = []

        for device in devices {
            let normalizedAddress = normalizeBluetoothIdentifier(device.address)
            let normalizedName = normalizeProductName(device.name)
            guard !normalizedAddress.isEmpty || !normalizedName.isEmpty else { continue }

            let uuid = snapshot.byAddress[normalizedAddress]
                ?? snapshot.byName[normalizedName]

            guard let uuid, !seenUUIDs.contains(uuid) else { continue }
            seenUUIDs.insert(uuid)

            let canonicalName = snapshot.namesByUUID[uuid] ?? normalizedName
            lookups.append(
                .init(
                    uuid: uuid,
                    addressKey: normalizedAddress.isEmpty ? nil : normalizedAddress,
                    nameKey: canonicalName.isEmpty ? nil : canonicalName
                )
            )
        }

        return lookups
    }

    private func handleLiveBatteryResults(_ results: [BluetoothLEBatteryReader.Result]) {
        guard !results.isEmpty else { return }

        var didUpdate = false

        for result in results {
            let level = clampBatteryPercentage(result.level)

            if let addressKey = result.addressKey, !addressKey.isEmpty {
                let previous = batteryStatusByAddress[addressKey] ?? -1
                if level > previous {
                    batteryStatusByAddress[addressKey] = level
                    batteryStatus[addressKey] = String(level)
                    didUpdate = true
                }
            }

            if let nameKey = result.nameKey, !nameKey.isEmpty {
                let previous = batteryStatusByName[nameKey] ?? -1
                if level > previous {
                    batteryStatusByName[nameKey] = level
                    didUpdate = true
                }
            }
        }

        guard didUpdate else { return }

        applyConnectedDeviceBatteryLevels()
        if let level = hudBatteryLevelCandidate() {
            updateActiveBluetoothHUDBattery(with: level)
        }
    }

    private func updateActiveBluetoothHUDBattery(with level: Int?) {
        guard let level else { return }
        DispatchQueue.main.async {
            guard self.coordinator.sneakPeek.show,
                  self.coordinator.sneakPeek.type == .bluetoothAudio else { return }
            self.coordinator.sneakPeek.value = CGFloat(level) / 100.0
        }
    }

    private func hudBatteryLevelCandidate() -> Int? {
        lastConnectedDevice?.batteryLevel
            ?? connectedDevices.last(where: { $0.batteryLevel != nil })?.batteryLevel
    }

    private func coreBluetoothCacheSnapshot() -> CoreBluetoothCacheSnapshot {
        guard let preferences = UserDefaults(suiteName: bluetoothPreferencesSuite),
              let coreCache = preferences.object(forKey: "CoreBluetoothCache") as? [String: [String: Any]] else {
            return .empty
        }

        var byAddress: [String: UUID] = [:]
        var byName: [String: UUID] = [:]
        var namesByUUID: [UUID: String] = [:]

        for (uuidString, payload) in coreCache {
            guard let uuid = UUID(uuidString: uuidString) else { continue }

            let addressKeys = ["DeviceAddress", "Address", "BD_ADDR", "device_address"]
            for key in addressKeys {
                if let value = payload[key], let normalized = normalizeBluetoothIdentifier(from: value) {
                    byAddress[normalized] = uuid
                }
            }

            if let serialValue = payload["SerialNumber"], let normalizedSerial = normalizeBluetoothIdentifier(from: serialValue) {
                byAddress[normalizedSerial] = uuid
            }

            let nameKeys = ["Name", "DeviceName", "ProductName", "Product", "device_name"]
            for key in nameKeys {
                if let value = payload[key], let normalizedName = normalizeProductName(from: value) {
                    byName[normalizedName] = uuid
                    namesByUUID[uuid] = normalizedName
                }
            }
        }

        return CoreBluetoothCacheSnapshot(byAddress: byAddress, byName: byName, namesByUUID: namesByUUID)
    }

    private func normalizeBluetoothIdentifier(from value: Any) -> String? {
        if let string = value as? String {
            let normalized = normalizeBluetoothIdentifier(string)
            return normalized.isEmpty ? nil : normalized
        }

        if let data = value as? Data,
           let ascii = String(data: data, encoding: .utf8) {
            let normalized = normalizeBluetoothIdentifier(ascii)
            return normalized.isEmpty ? nil : normalized
        }

        return nil
    }

    private func normalizeProductName(from value: Any) -> String? {
        if let string = value as? String {
            let normalized = normalizeProductName(string)
            return normalized.isEmpty ? nil : normalized
        }
        if let data = value as? Data,
           let ascii = String(data: data, encoding: .utf8) {
            let normalized = normalizeProductName(ascii)
            return normalized.isEmpty ? nil : normalized
        }
        return nil
    }

    private struct CoreBluetoothCacheSnapshot {
        let byAddress: [String: UUID]
        let byName: [String: UUID]
        let namesByUUID: [UUID: String]

        var hasEntries: Bool {
            !byAddress.isEmpty || !byName.isEmpty
        }

        static let empty = CoreBluetoothCacheSnapshot(byAddress: [:], byName: [:], namesByUUID: [:])
    }

    private struct PmsetAccessoryBatteryEntry {
        let displayName: String
        let normalizedName: String
        let level: Int
    }

    @discardableResult
    private func mergePmsetEntries(
        _ entries: [PmsetAccessoryBatteryEntry],
        into names: inout [String: Int],
        logNewEntries: Bool
    ) -> [PmsetAccessoryBatteryEntry] {
        guard !entries.isEmpty else { return [] }

        var newlyFilled: [PmsetAccessoryBatteryEntry] = []

        for entry in entries {
            let clamped = clampBatteryPercentage(entry.level)
            let previous = names[entry.normalizedName]

            if previous == nil {
                newlyFilled.append(entry)
                names[entry.normalizedName] = clamped
                continue
            }

            if let previous, clamped > previous {
                names[entry.normalizedName] = clamped
            }
        }

        if logNewEntries {
            for entry in newlyFilled {
                print("🎧 [BluetoothAudioManager] ℹ️ pmset reported \(entry.level)% for \(entry.displayName)")
            }
        }

        return newlyFilled
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

        let pmsetEntries = collectPmsetAccessoryBatteryEntries()
        mergePmsetEntries(pmsetEntries, into: &combinedNamePercentages, logNewEntries: true)

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

    private func collectPmsetAccessoryBatteryEntries() -> [PmsetAccessoryBatteryEntry] {
        let process = Process()
        process.launchPath = "/usr/bin/pmset"
        process.arguments = ["-g", "accps"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return []
        }

        guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
            return []
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"^\s*-\s*(.+?)\s*(?:\(.+?\))?\s+(\d+)\s*%"#,
            options: [.anchorsMatchLines]
        ) else {
            return []
        }

        var entries: [PmsetAccessoryBatteryEntry] = []
        let nsOutput = output as NSString
        let range = NSRange(location: 0, length: nsOutput.length)

        regex.enumerateMatches(in: output, options: [], range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 3 else { return }

            let rawName = nsOutput
                .substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let percentString = nsOutput.substring(with: match.range(at: 2))

            guard !rawName.isEmpty, let level = Int(percentString) else { return }

            let normalizedName = normalizeProductName(rawName)
            guard !normalizedName.isEmpty else { return }
            if normalizedName.hasPrefix("internalbattery") {
                return
            }

            entries.append(
                PmsetAccessoryBatteryEntry(
                    displayName: rawName,
                    normalizedName: normalizedName,
                    level: level
                )
            )
        }

        return entries
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

    private func cancelHUDBatteryWait(for device: BluetoothAudioDevice) {
        let cancelBlock = { [weak self] in
            guard let self else { return }
            self.hudBatteryWaitTasks[device.id]?.cancel()
            self.hudBatteryWaitTasks.removeValue(forKey: device.id)
        }

        if Thread.isMainThread {
            cancelBlock()
        } else {
            DispatchQueue.main.async(execute: cancelBlock)
        }
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

        cancelHUDBatteryWait(for: device)

        if let battery = bestBatteryLevel(for: device) {
            presentDeviceConnectedHUD(device: device, batteryLevel: battery)
            return
        }

        requestPmsetFallback(reason: "hud missing battery")

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(self.hudBatteryWaitTimeout)
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: UInt64(self.hudBatteryWaitInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }

                let batteryInfo = await MainActor.run { () -> (BluetoothAudioDevice, Int)? in
                    guard let refreshedDevice = self.connectedDevices.first(where: { $0.id == device.id }),
                          let battery = self.bestBatteryLevel(for: refreshedDevice) else {
                        return nil
                    }
                    return (refreshedDevice, battery)
                }

                if let (refreshedDevice, battery) = batteryInfo {
                    await MainActor.run {
                        self.presentDeviceConnectedHUD(device: refreshedDevice, batteryLevel: battery)
                    }
                    self.cancelHUDBatteryWait(for: device)
                    return
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.presentDeviceConnectedHUD(device: device, batteryLevel: nil)
            }
            self.cancelHUDBatteryWait(for: device)
        }

        hudBatteryWaitTasks[device.id] = task
    }

    private func presentDeviceConnectedHUD(device: BluetoothAudioDevice, batteryLevel: Int?) {
        guard Defaults[.showBluetoothDeviceConnections] else { return }

        print("🎧 [BluetoothAudioManager] 📱 Showing device connected HUD")

        let batteryValue: CGFloat = if let batteryLevel {
            CGFloat(clampBatteryPercentage(batteryLevel)) / 100.0
        } else {
            0.0
        }

        HUDSuppressionCoordinator.shared.suppressVolumeHUD(for: 1.5)

        Task { @MainActor in
            coordinator.toggleSneakPeek(
                status: true,
                type: .bluetoothAudio,
                duration: 2.5,
                value: batteryValue,
                icon: device.deviceType.sfSymbol
            )
        }
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
        hudBatteryWaitTasks.values.forEach { $0.cancel() }
        hudBatteryWaitTasks.removeAll()
    }

    @MainActor
    func refreshConnectedDeviceBatteries() {
        refreshBatteryLevelsForConnectedDevices()
    }

    @MainActor
    func activeDeviceIconSymbol() -> String? {
        if let prioritizedDevice = connectedDevices.last ?? lastConnectedDevice {
            return prioritizedDevice.deviceType.sfSymbol
        }
        return nil
    }
}

// MARK: - CoreBluetooth Battery Reader

private final class BluetoothLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Lookup {
        let uuid: UUID
        let addressKey: String?
        let nameKey: String?
    }

    struct Result {
        let uuid: UUID
        let level: Int
        let addressKey: String?
        let nameKey: String?
    }

    private enum State {
        case idle
        case requesting
    }

    private static let batteryServiceUUID = CBUUID(string: "180F")
    private static let batteryCharacteristicUUID = CBUUID(string: "2A19")

    private let timeoutInterval: TimeInterval = 6.0

    private var central: CBCentralManager!
    private var state: State = .idle
    private var pendingLookups: [Lookup] = []
    private var lookupByUUID: [UUID: Lookup] = [:]
    private var completion: (([Result]) -> Void)?
    private var pendingPeripherals: [UUID: CBPeripheral] = [:]
    private var results: [UUID: Result] = [:]
    private var missingUUIDs: Set<UUID> = []
    private var timeoutWorkItem: DispatchWorkItem?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func fetchBatteryLevels(for lookups: [Lookup], completion: @escaping ([Result]) -> Void) {
        guard !lookups.isEmpty else {
            completion([])
            return
        }

        guard state == .idle else {
            completion([])
            return
        }

        state = .requesting
        pendingLookups = lookups
        lookupByUUID = Dictionary(uniqueKeysWithValues: lookups.map { ($0.uuid, $0) })
        self.completion = completion
    results.removeAll()
    pendingPeripherals.removeAll()
    missingUUIDs = Set(lookups.map { $0.uuid })

        switch central.state {
        case .poweredOn:
            startRequest()
        case .unauthorized, .unsupported, .poweredOff:
            complete(with: [])
        default:
            break
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard state == .requesting else { return }

        switch central.state {
        case .poweredOn:
            startRequest()
        case .unauthorized, .unsupported, .poweredOff:
            complete(with: [])
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        markPeripheralFinished(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard state == .requesting else { return }
        markPeripheralFinished(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard state == .requesting else { return }
        guard missingUUIDs.contains(peripheral.identifier) else { return }

        missingUUIDs.remove(peripheral.identifier)
        configurePeripheral(peripheral)
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard state == .requesting else { return }

        if let error {
            print("🎧 [BluetoothLEBatteryReader] Service discovery failed: \(error.localizedDescription)")
            markPeripheralFinished(peripheral.identifier)
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryServiceUUID }) else {
            markPeripheralFinished(peripheral.identifier)
            return
        }

        peripheral.discoverCharacteristics([Self.batteryCharacteristicUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard state == .requesting else { return }

        if let error {
            print("🎧 [BluetoothLEBatteryReader] Characteristic discovery failed: \(error.localizedDescription)")
            markPeripheralFinished(peripheral.identifier)
            return
        }

        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryCharacteristicUUID }) else {
            markPeripheralFinished(peripheral.identifier)
            return
        }

        peripheral.readValue(for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard state == .requesting else { return }

        defer { markPeripheralFinished(peripheral.identifier) }

        if let error {
            print("🎧 [BluetoothLEBatteryReader] Battery read failed: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value, let byte = data.first, let lookup = lookupByUUID[peripheral.identifier] else {
            return
        }

        let level = Int(byte)
        results[peripheral.identifier] = Result(
            uuid: peripheral.identifier,
            level: level,
            addressKey: lookup.addressKey,
            nameKey: lookup.nameKey
        )
    }

    // MARK: - Helpers

    private func startRequest() {
        central.stopScan()

        let identifiers = Array(missingUUIDs)
        if !identifiers.isEmpty {
            let peripherals = central.retrievePeripherals(withIdentifiers: identifiers)
            for peripheral in peripherals {
                missingUUIDs.remove(peripheral.identifier)
                configurePeripheral(peripheral)
            }
        }

        let connectedPeripherals = central.retrieveConnectedPeripherals(withServices: [Self.batteryServiceUUID])
        for peripheral in connectedPeripherals where missingUUIDs.contains(peripheral.identifier) {
            missingUUIDs.remove(peripheral.identifier)
            configurePeripheral(peripheral)
        }

        if !missingUUIDs.isEmpty {
            central.scanForPeripherals(withServices: [Self.batteryServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }

        if pendingPeripherals.isEmpty && missingUUIDs.isEmpty {
            complete(with: Array(results.values))
            return
        }

        scheduleTimeout()
    }

    private func configurePeripheral(_ peripheral: CBPeripheral) {
        pendingPeripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self

        switch peripheral.state {
        case .connected:
            peripheral.discoverServices([Self.batteryServiceUUID])
        default:
            central.connect(peripheral, options: nil)
        }
    }

    private func markPeripheralFinished(_ identifier: UUID) {
        pendingPeripherals.removeValue(forKey: identifier)
        missingUUIDs.remove(identifier)

        if missingUUIDs.isEmpty {
            central.stopScan()
        }

        if pendingPeripherals.isEmpty && missingUUIDs.isEmpty {
            complete(with: Array(results.values))
        }
    }

    private func scheduleTimeout() {
        cancelTimeout()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.complete(with: Array(self.results.values))
        }
        timeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutInterval, execute: workItem)
    }

    private func cancelTimeout() {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
    }

    private func complete(with results: [Result]) {
        guard state == .requesting else { return }
        cancelTimeout()
        central.stopScan()
        state = .idle

        pendingPeripherals.removeAll()
        missingUUIDs.removeAll()
        pendingLookups.removeAll()
        lookupByUUID.removeAll()

        let completion = self.completion
        self.completion = nil
        self.results.removeAll()

        completion?(results)
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
    case airpodsGen3
    case airpodsGen4
    case airpodsPro
    case airpodsPro3
    case airpodsMax
    case beats
    case beatsstudio
    case beatssolo
    case headphones
    case speaker
    case generic
    
    var sfSymbol: String {
        switch self {
        case .airpods:
            return "airpods"
        case .airpodsGen3:
            return "airpods.gen3"
        case .airpodsGen4:
            return "airpods.gen4"
        case .airpodsPro:
            return "airpods.pro"
        case .airpodsPro3:
            return "airpods.pro"
        case .airpodsMax:
            return "airpodsmax"
        case .beats:
            return "beats.headphones"
        case .beatsstudio:
            return "beats.headphones"
        case .beatssolo:
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
        case .airpodsGen3: return "AirPods (Gen 3)"
        case .airpodsGen4: return "AirPods (Gen 4)"
        case .airpodsPro: return "AirPods Pro"
        case .airpodsPro3: return "AirPods Pro 3"
        case .airpodsMax: return "AirPods Max"
        case .beats: return "Beats"
        case .beatsstudio: return "Beats Studio"
        case .beatssolo: return "Beats Solo"
        case .headphones: return "Headphones"
        case .speaker: return "Speaker"
        case .generic: return "Bluetooth Device"
        }
    }

    /// Inline HUD only: base filename (no extension) for a looping .mov animation.
    var inlineHUDAnimationBaseName: String {
        String(describing: self)
    }
}

// MARK: - Notification Name Constants

private let IOBluetoothDeviceConnectionNotification = "IOBluetoothDeviceConnectionNotification"
private let IOBluetoothDeviceDisconnectionNotification = "IOBluetoothDeviceDisconnectionNotification"
