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
    @Published var activeApp: String?
    @Published var isMonitoring: Bool = false
    
    // MARK: - Private Properties
    private var cancellables = Set<AnyCancellable>()
    private var isListenerRegistered: Bool = false
    private var cameraDeviceIDs: [CMIOObjectID] = []
    
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
        
        // Enumerate camera devices
        cameraDeviceIDs = enumerateCameraDevices()
        
        if cameraDeviceIDs.isEmpty {
            print("CameraMonitor: ⚠️ No camera devices found")
        } else {
            print("CameraMonitor: 📷 Found \(cameraDeviceIDs.count) camera device(s)")
        }
        
        // Setup event listener (CoreMediaIO approach)
        setupPropertyListener()
        
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
        
        // Reset state
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
            
            if status == OSStatus(kCMIOHardwareNoError) && isRunning != 0 {
                return true
            }
        }
        
        return false
    }
    
    /// Check current camera status (AVFoundation fallback)
    private func checkCameraStatusAVFoundation() -> Bool {
        // Use AVFoundation to check if any camera is in use
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        
        for device in discoverySession.devices {
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
        
        // Use OR logic - either method detects usage
        let isActive = isCMIOActive || isAVActive
        
        // Debug logging
        print("CameraMonitor: 🔍 Checking... current=\(isCameraActive), CMIO=\(isCMIOActive), AV=\(isAVActive), final=\(isActive)")
        
        // Update state if changed
        if isActive != isCameraActive {
            print("CameraMonitor: 🔄 State change detected (\(isCameraActive) -> \(isActive))")
            
            withAnimation(.smooth) {
                isCameraActive = isActive
            }
            
            if isActive {
                print("CameraMonitor: 📷 Camera ACTIVE")
                // Could try to identify app here (TODO: investigate)
                activeApp = "Unknown App"
            } else {
                print("CameraMonitor: ⚪ Camera INACTIVE")
                activeApp = nil
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
