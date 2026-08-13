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
import SwiftUI
import Combine
import Defaults

// MARK: - Indicator Layout Enum
enum IndicatorLayout {
    case none
    case cameraOnly
    case microphoneOnly
    case cameraAndMicrophone
    case recordingOnly
    case recordingWithCamera
    case recordingWithMicrophone
    case recordingWithBoth
    
    // Computed properties for UI positioning
    var showsRecordingPulsator: Bool {
        switch self {
        case .recordingOnly, .recordingWithCamera, .recordingWithMicrophone, .recordingWithBoth:
            return true
        default:
            return false
        }
    }
    
    var showsCameraIndicator: Bool {
        switch self {
        case .cameraOnly, .cameraAndMicrophone, .recordingWithCamera, .recordingWithBoth:
            return true
        default:
            return false
        }
    }
    
    var showsMicrophoneIndicator: Bool {
        switch self {
        case .microphoneOnly, .cameraAndMicrophone, .recordingWithMicrophone, .recordingWithBoth:
            return true
        default:
            return false
        }
    }
    
    // Description for debugging
    var description: String {
        switch self {
        case .none: return "None"
        case .cameraOnly: return "Camera Only"
        case .microphoneOnly: return "Microphone Only"
        case .cameraAndMicrophone: return "Camera + Microphone"
        case .recordingOnly: return "Recording Only"
        case .recordingWithCamera: return "Recording + Camera"
        case .recordingWithMicrophone: return "Recording + Microphone"
        case .recordingWithBoth: return "Recording + Camera + Microphone"
        }
    }
}

// MARK: - Privacy Indicator Manager
@MainActor
class PrivacyIndicatorManager: ObservableObject {
    // MARK: - Singleton
    static let shared = PrivacyIndicatorManager()
    
    // MARK: - Published Properties
    @Published var cameraActive: Bool = false
    @Published var microphoneActive: Bool = false
    @Published var screenRecordingActive: Bool = false
    @Published var isMonitoring: Bool = false
    
    // MARK: - Child Monitors
    private let cameraMonitor = CameraMonitor()
    private let microphoneMonitor = MicrophoneMonitor()
    private var screenRecordingManager: ScreenRecordingManager?
    
    // MARK: - Cancellables
    private var cancellables = Set<AnyCancellable>()

    /// Whether the app has asked for monitoring. A settings change picks which
    /// monitors run inside an active session; it does not open one, so a run that
    /// never calls `startMonitoring()` — UI testing, for one — stays quiet however
    /// the settings move.
    private var monitoringRequested = false
    
    // MARK: - Computed Properties
    
    /// Current indicator layout based on active states
    var indicatorLayout: IndicatorLayout {
        // Respect user settings
        let camera = cameraActive && Defaults[.enableCameraDetection]
        let mic = microphoneActive && Defaults[.enableMicrophoneDetection]
        let recording = screenRecordingActive
        
        // 8 possible combinations
        switch (recording, camera, mic) {
        case (false, false, false):
            return .none
        case (false, true, false):
            return .cameraOnly
        case (false, false, true):
            return .microphoneOnly
        case (false, true, true):
            return .cameraAndMicrophone
        case (true, false, false):
            return .recordingOnly
        case (true, true, false):
            return .recordingWithCamera
        case (true, false, true):
            return .recordingWithMicrophone
        case (true, true, true):
            return .recordingWithBoth
        }
    }
    
    /// Check if any indicator is active (respecting user settings)
    var hasAnyIndicator: Bool {
        let showCamera = cameraActive && Defaults[.enableCameraDetection]
        let showMic = microphoneActive && Defaults[.enableMicrophoneDetection]
        return showCamera || showMic || screenRecordingActive
    }
    
    // MARK: - Initialization
    private init() {
        print("PrivacyIndicatorManager: 🚀 Initializing...")
        setupBindings()
    }
    
    // MARK: - Setup Methods
    
    /// Setup bindings to child monitors
    private func setupBindings() {
        // Bind camera monitor
        cameraMonitor.$isCameraActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self = self else { return }
                if self.cameraActive != isActive {
                    print("PrivacyIndicatorManager: 📷 Camera state: \(isActive)")
                    withAnimation(.smooth) {
                        self.cameraActive = isActive
                    }
                    self.logLayoutChange()
                }
            }
            .store(in: &cancellables)
        
        // Bind microphone monitor
        microphoneMonitor.$isMicActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                guard let self = self else { return }
                if self.microphoneActive != isActive {
                    print("PrivacyIndicatorManager: 🎤 Microphone state: \(isActive)")
                    withAnimation(.smooth) {
                        self.microphoneActive = isActive
                    }
                    self.logLayoutChange()
                }
            }
            .store(in: &cancellables)
        
        // Bind screen recording manager
        let screenRecManager = ScreenRecordingManager.shared
        screenRecordingManager = screenRecManager
        
        screenRecManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if self.screenRecordingActive != isRecording {
                    print("PrivacyIndicatorManager: 📹 Screen recording state: \(isRecording)")
                    withAnimation(.smooth) {
                        self.screenRecordingActive = isRecording
                    }
                    self.logLayoutChange()
                }
            }
            .store(in: &cancellables)

        // Follow the detection settings. They used to be read only when deciding
        // what to draw, so switching one off hid its indicator while leaving the
        // monitor registered and publishing. Reacting to the change here means
        // the switch also starts and stops the monitor behind it, without a
        // relaunch. `options: []` so this does not fire before the app has asked
        // for monitoring to start.
        Defaults.publisher(.enableCameraDetection, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyDetectionSettings() }
            .store(in: &cancellables)

        Defaults.publisher(.enableMicrophoneDetection, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyDetectionSettings() }
            .store(in: &cancellables)
    }

    /// Log layout changes for debugging
    private func logLayoutChange() {
        print("PrivacyIndicatorManager: 🔄 Layout changed to: \(indicatorLayout.description)")
        print("PrivacyIndicatorManager: 📊 States - Camera: \(cameraActive), Mic: \(microphoneActive), Recording: \(screenRecordingActive)")
    }
    
    // MARK: - Public Methods
    
    /// Start monitoring the privacy indicators the user has enabled.
    ///
    /// Screen recording is already monitored by `ScreenRecordingManager`.
    func startMonitoring() {
        print("PrivacyIndicatorManager: 🟢 Starting enabled monitors...")
        monitoringRequested = true
        applyDetectionSettings()
        print("PrivacyIndicatorManager: ✅ Enabled monitors started")
    }

    /// Bring each child monitor in line with its setting.
    ///
    /// Both monitors ignore a redundant start or stop and clear their published
    /// state when stopped, so this is safe to call whenever a setting moves.
    private func applyDetectionSettings() {
        guard monitoringRequested else { return }

        if Defaults[.enableCameraDetection] {
            if cameraMonitor.isMonitoringAvailable {
                cameraMonitor.startMonitoring()
            } else {
                print("PrivacyIndicatorManager: ⚠️ Camera monitoring not available")
            }
        } else {
            cameraMonitor.stopMonitoring()
        }

        if Defaults[.enableMicrophoneDetection] {
            if microphoneMonitor.isMonitoringAvailable {
                microphoneMonitor.startMonitoring()
            } else {
                print("PrivacyIndicatorManager: ⚠️ Microphone monitoring not available")
            }
        } else {
            microphoneMonitor.stopMonitoring()
        }

        isMonitoring = cameraMonitor.isMonitoring || microphoneMonitor.isMonitoring
    }
    
    /// Stop monitoring all privacy indicators
    func stopMonitoring() {
        print("PrivacyIndicatorManager: 🛑 Stopping all monitors...")

        monitoringRequested = false
        isMonitoring = false
        
        cameraMonitor.stopMonitoring()
        microphoneMonitor.stopMonitoring()
        
        print("PrivacyIndicatorManager: ✅ All monitors stopped")
    }
    
    /// Toggle monitoring state
    ///
    /// Asked against the request rather than the running monitors: with both
    /// detection settings off a session is open with nothing in it, and reading
    /// the monitors there would take the toggle for off and start one.
    func toggleMonitoring() {
        if monitoringRequested {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    /// Get detailed status string for debugging
    func getStatusString() -> String {
        var status = "Privacy Indicators:\n"
        status += "  Camera: \(cameraActive ? "🟢 Active" : "⚪ Inactive")\n"
        status += "  Microphone: \(microphoneActive ? "🟢 Active" : "⚪ Inactive")\n"
        status += "  Screen Recording: \(screenRecordingActive ? "🟢 Active" : "⚪ Inactive")\n"
        status += "  Layout: \(indicatorLayout.description)"
        return status
    }
}

// MARK: - Extensions

extension PrivacyIndicatorManager {
    /// Get camera monitor instance
    var camera: CameraMonitor {
        return cameraMonitor
    }
    
    /// Get microphone monitor instance
    var microphone: MicrophoneMonitor {
        return microphoneMonitor
    }
    
    /// Get screen recording manager instance
    var screenRecording: ScreenRecordingManager? {
        return screenRecordingManager
    }
}


