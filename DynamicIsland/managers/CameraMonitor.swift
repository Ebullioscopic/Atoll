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
import CoreMediaIO
import AVFoundation
import SwiftUI
import Combine

// MARK: - CMIOObject Property Listener (Event-driven approach)
private func cameraPropertyListener(
    objectID: CMIOObjectID,
    numberAddresses: UInt32,
    addresses: UnsafePointer<CMIOObjectPropertyAddress>?,
    clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let context = clientData else { return OSStatus(kCMIOHardwareNoError) }
    let monitor = Unmanaged<CameraMonitor>.fromOpaque(context).takeUnretainedValue()
    
    DispatchQueue.main.async {
        print("CameraMonitor: 📷 Camera property changed")
        monitor.checkCameraStatus()
    }
    
    return OSStatus(kCMIOHardwareNoError)
}

@MainActor
class CameraMonitor: ObservableObject {
    // MARK: - Published Properties
    @Published var isCameraActive: Bool = false
    @Published var activeApp: String? = nil
    @Published var isMonitoring: Bool = false
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var isListenerRegistered: Bool = false
    private var cameraDeviceIDs: [CMIOObjectID] = []
    private var deactivationTask: Task<Void, Never>?
    private var deviceListListener: CMIOObjectPropertyListenerBlock?
    private var inUseObservations: [NSKeyValueObservation] = []
    private var captureDevicesByUID: [String: AVCaptureDevice] = [:]
    
    // MARK: - Configuration
    // Pure event-driven - no polling
    
    // MARK: - Initialization
    init() {
        // No initial setup needed
    }
    
    deinit {
        // Clean up listeners synchronously
        if isListenerRegistered, !cameraDeviceIDs.isEmpty {
            var propertyAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
            )
            
            let context = Unmanaged.passUnretained(self).toOpaque()
            
            for deviceID in cameraDeviceIDs {
                CMIOObjectRemovePropertyListener(
                    deviceID,
                    &propertyAddress,
                    cameraPropertyListener,
                    context
                )
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring camera usage
    func startMonitoring() {
        guard !isMonitoring else {
            print("CameraMonitor: Already monitoring, skipping start")
            return
        }
        
        print("CameraMonitor: 🟢 Starting camera monitoring...")
        
        isMonitoring = true
        
        installDeviceListListeners()
        rebindDevices()
        
        // Check initial state
        checkCameraStatus()
        
        print("CameraMonitor: ✅ Started monitoring (event-driven CMIO + AVFoundation check)")
    }
    
    /// Stop monitoring camera usage
    func stopMonitoring() {
        guard isMonitoring else {
            print("CameraMonitor: Not monitoring, skipping stop")
            return
        }
        
        print("CameraMonitor: 🛑 Stopping monitoring...")
        
        isMonitoring = false
        
        // Remove property listener
        if isListenerRegistered {
            removePropertyListener()
        }
        removeDeviceListListeners()
        inUseObservations.removeAll()
        captureDevicesByUID.removeAll()
        
        // Reset state
        deactivationTask?.cancel()
        deactivationTask = nil
        if isCameraActive {
            isCameraActive = false
        }
        activeApp = nil
        
        print("CameraMonitor: ✅ Stopped monitoring")
    }
    
    /// Toggle monitoring state
    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    // MARK: - Private Methods
    
    /// Re-read the camera list and move every listener onto it.
    ///
    /// Cameras come and go while Atoll runs — a phone exposed through a
    /// Camera Extension, Continuity Camera, a USB webcam — and a camera that
    /// was not there when monitoring started used to have no listener at all,
    /// so its use was never noticed.
    private func rebindDevices() {
        if isListenerRegistered {
            removePropertyListener()
        }
        cameraDeviceIDs = enumerateCameraDevices()
        if cameraDeviceIDs.isEmpty {
            print("CameraMonitor: ⚠️ No camera devices found")
        } else {
            print("CameraMonitor: 📷 Found \(cameraDeviceIDs.count) camera device(s)")
        }
        setupPropertyListener()
        
        // `isInUseByAnotherApplication` is key-value observable, which covers
        // devices whose CoreMediaIO running state never sends a notification.
        let captureDevices = Self.captureDevices()
        captureDevicesByUID = Dictionary(
            captureDevices.map { ($0.uniqueID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        inUseObservations = captureDevices.map { device in
            device.observe(\.isInUseByAnotherApplication, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.checkCameraStatus() }
            }
        }
    }
    
    /// Listen for cameras being added or removed, from CoreMediaIO's device
    /// list and from AVFoundation's connect/disconnect notifications.
    private func installDeviceListListeners() {
        if deviceListListener == nil {
            var address = Self.devicesAddress
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.devicesChanged() }
            }
            if CMIOObjectAddPropertyListenerBlock(
                CMIOObjectID(kCMIOObjectSystemObject), &address, .main, block
            ) == OSStatus(kCMIOHardwareNoError) {
                deviceListListener = block
            }
        }
        
        guard cancellables.isEmpty else { return }
        let center = NotificationCenter.default
        center.publisher(for: AVCaptureDevice.wasConnectedNotification)
            .merge(with: center.publisher(for: AVCaptureDevice.wasDisconnectedNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.devicesChanged() }
            .store(in: &cancellables)
    }
    
    private func removeDeviceListListeners() {
        if let block = deviceListListener {
            var address = Self.devicesAddress
            CMIOObjectRemovePropertyListenerBlock(
                CMIOObjectID(kCMIOObjectSystemObject), &address, .main, block
            )
            deviceListListener = nil
        }
        cancellables.removeAll()
    }
    
    private func devicesChanged() {
        guard isMonitoring else { return }
        rebindDevices()
        checkCameraStatus()
    }
    
    private static var devicesAddress: CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }
    
    private static func captureDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
    
    /// The device's unique ID, which is the same string AVFoundation reports
    /// as `AVCaptureDevice.uniqueID`.
    private func deviceUID(_ deviceID: CMIOObjectID) -> String? {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = CMIOObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, dataSize, &dataSize, &uid
        )
        guard status == OSStatus(kCMIOHardwareNoError), let uid else { return nil }
        return uid.takeRetainedValue() as String
    }
    
    /// Enumerate all camera devices using CoreMediaIO
    private func enumerateCameraDevices() -> [CMIOObjectID] {
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        
        var dataSize: UInt32 = 0
        var status = CMIOObjectGetPropertyDataSize(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == OSStatus(kCMIOHardwareNoError), dataSize > 0 else {
            print("CameraMonitor: ⚠️ Failed to get devices data size (status: \(status))")
            return []
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: deviceCount)
        
        status = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &dataSize,
            &devices
        )
        
        guard status == OSStatus(kCMIOHardwareNoError) else {
            print("CameraMonitor: ⚠️ Failed to get devices (status: \(status))")
            return []
        }
        
        // Filter for video input devices
        let videoDevices = devices.filter { deviceID in
            return isVideoInputDevice(deviceID)
        }
        
        return videoDevices
    }
    
    /// Check if device is a video input device
    private func isVideoInputDevice(_ deviceID: CMIOObjectID) -> Bool {
        // Check if device has video input streams
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIODevicePropertyScopeInput),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        
        var dataSize: UInt32 = 0
        let status = CMIOObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        return status == OSStatus(kCMIOHardwareNoError) && dataSize > 0
    }
    
    /// Setup CoreMediaIO property listener
    private func setupPropertyListener() {
        guard !cameraDeviceIDs.isEmpty else { return }
        
        // Listen for device running state changes
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        // Add listener for each camera device
        for deviceID in cameraDeviceIDs {
            let status = CMIOObjectAddPropertyListener(
                deviceID,
                &propertyAddress,
                cameraPropertyListener,
                context
            )
            
            if status == OSStatus(kCMIOHardwareNoError) {
                print("CameraMonitor: ✅ Property listener registered for device \(deviceID)")
                isListenerRegistered = true
            } else {
                print("CameraMonitor: ⚠️ Failed to register listener for device \(deviceID) (status: \(status))")
            }
        }
    }
    
    /// Remove CoreMediaIO property listener
    private func removePropertyListener() {
        guard !cameraDeviceIDs.isEmpty else { return }
        
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        for deviceID in cameraDeviceIDs {
            let status = CMIOObjectRemovePropertyListener(
                deviceID,
                &propertyAddress,
                cameraPropertyListener,
                context
            )
            
            if status == OSStatus(kCMIOHardwareNoError) {
                print("CameraMonitor: ✅ Property listener removed for device \(deviceID)")
            } else {
                print("CameraMonitor: ⚠️ Failed to remove listener for device \(deviceID) (status: \(status))")
            }
        }
        
        isListenerRegistered = false
    }
    
    /// Check current camera status (CMIO approach)
    private func checkCameraStatusCMIO() -> Bool {
        guard !cameraDeviceIDs.isEmpty else { return false }
        
        var propertyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        
        let atollIsCapturing = WebcamManager.shared.isSessionRunning
        
        // Check if any camera device is running
        for deviceID in cameraDeviceIDs {
            var isRunning: UInt32 = 0
            var dataSize = UInt32(MemoryLayout<UInt32>.size)
            
            let status = CMIOObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                dataSize,
                &dataSize,
                &isRunning
            )
            
            guard status == OSStatus(kCMIOHardwareNoError), isRunning != 0 else { continue }
            
            // Camera Extensions can report themselves running somewhere while
            // no app has them open — their host process keeps the stream up —
            // and macOS shows no indicator then. For an external camera
            // AVFoundation can vouch for, its per-app answer wins, unless the
            // stream may be Atoll's own mirror.
            if !atollIsCapturing,
               let uid = deviceUID(deviceID),
               let captureDevice = captureDevicesByUID[uid],
               captureDevice.deviceType != .builtInWideAngleCamera,
               !captureDevice.isInUseByAnotherApplication {
                continue
            }
            return true
        }
        
        return false
    }
    
    /// Check current camera status (AVFoundation fallback)
    private func checkCameraStatusAVFoundation() -> Bool {
        for device in captureDevicesByUID.values {
            if device.isInUseByAnotherApplication {
                return true
            }
        }
        
        return false
    }
    
    /// Check current camera status (hybrid approach)
    func checkCameraStatus() {
        // Try CMIO first, fallback to AVFoundation
        let isCMIOActive = checkCameraStatusCMIO()
        let isAVActive = checkCameraStatusAVFoundation()
        
        let isActive = isCMIOActive || isAVActive
        
        if isActive {
            deactivationTask?.cancel()
            deactivationTask = nil
            if !isCameraActive {
                print("CameraMonitor: 📷 Camera became ACTIVE")
                withAnimation(.smooth) {
                    isCameraActive = true
                }
                activeApp = "Unknown App"
            }
        } else if isCameraActive {
            guard deactivationTask == nil else { return }
            deactivationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled, let self else { return }
                self.deactivationTask = nil
                let stillActive = self.checkCameraStatusCMIO() || self.checkCameraStatusAVFoundation()
                if !stillActive {
                    print("CameraMonitor: ⚪ Camera INACTIVE (debounced)")
                    withAnimation(.smooth) {
                        self.isCameraActive = false
                    }
                    self.activeApp = nil
                }
            }
        }
    }

}

// MARK: - Extensions

extension CameraMonitor {
    /// Get current camera status without async
    var currentCameraStatus: Bool {
        return isCameraActive
    }
    
    /// Check if monitoring is available
    var isMonitoringAvailable: Bool {
        return !enumerateCameraDevices().isEmpty || !AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices.isEmpty
    }
}
