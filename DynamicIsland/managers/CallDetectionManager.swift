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

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - Call Detection Manager (#248)
// Detects active phone/FaceTime calls on macOS by monitoring running applications
// and checking if audio input is being used by call-related processes.

@MainActor
class CallDetectionManager: ObservableObject {
    static let shared = CallDetectionManager()

    @Published var isOnCall: Bool = false
    @Published var callDuration: TimeInterval = 0
    @Published var callAppName: String = ""

    private var pollTask: Task<Void, Never>?
    private var callStartDate: Date?
    private var durationTimer: Timer?

    /// Bundle identifiers of apps that indicate a call is active
    private let callAppBundleIDs: Set<String> = [
        "com.apple.FaceTime"
    ]

    /// Process names that indicate an active call audio session
    private let callAudioProcessNames: Set<String> = [
        "avconferenced",    // FaceTime/phone call audio daemon
        "callservicesd",    // Call services daemon
        "telephonyutilitiesd" // Telephony utilities
    ]

    private var defaultsObservation: AnyCancellable?

    private init() {
        if Defaults[.enableCallDetection] {
            startMonitoring()
        }

        // Observe preference changes
        defaultsObservation = Defaults.publisher(.enableCallDetection)
            .sink { [weak self] change in
                Task { @MainActor in
                    guard let self else { return }
                    if change.newValue {
                        self.startMonitoring()
                    } else {
                        self.stopMonitoring()
                    }
                }
            }
    }

    func startMonitoring() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.checkCallStatus()
                try? await Task.sleep(nanoseconds: 2_000_000_000) // Check every 2 seconds
            }
        }
    }

    func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
        endCall()
    }

    private func checkCallStatus() async {
        let callDetected = await detectActiveCall()

        if callDetected && !isOnCall {
            beginCall()
        } else if !callDetected && isOnCall {
            endCall()
        }
    }

    private func detectActiveCall() async -> Bool {
        // Strategy 1: Check if FaceTime is running and in an active call state
        let runningApps = NSWorkspace.shared.runningApplications
        let facetimeRunning = runningApps.contains { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return callAppBundleIDs.contains(bundleID) && app.isActive == false
            // FaceTime in a call is typically not the frontmost app necessarily,
            // but it will be running. We need the audio check below to confirm.
        }

        // Strategy 2: Check for call-related audio daemon processes
        // avconferenced is the key indicator — it runs when FaceTime/phone calls are active
        // Fix #4: await async version so Process runs off-main
        let hasCallAudioProcess = await checkForCallAudioProcesses()

        // A call is active if call audio daemons are using the microphone
        if hasCallAudioProcess {
            if let app = runningApps.first(where: { callAppBundleIDs.contains($0.bundleIdentifier ?? "") }) {
                callAppName = app.localizedName ?? "FaceTime"
            } else {
                callAppName = "Phone Call"
            }
            return true
        }

        // Strategy 3: Check if FaceTime has a window with call UI (non-setup window)
        if facetimeRunning {
            // If FaceTime is running and has been for a bit, check its window count
            // FaceTime with >1 window usually means an active call
            if let ftApp = runningApps.first(where: { $0.bundleIdentifier == "com.apple.FaceTime" }) {
                callAppName = ftApp.localizedName ?? "FaceTime"
                // Check via accessibility or window list if it's in a call
                // For now, rely on audio process detection above
            }
        }

        return false
    }

    // Fix #4: made async so the blocking Process runs off the main actor
    private func checkForCallAudioProcesses() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                // Use `pgrep` to check for active call audio processes
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
                task.arguments = ["-x", "avconferenced"]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = FileHandle.nullDevice

                do {
                    try task.run()
                    task.waitUntilExit()
                    // Exit status 0 means process found
                    continuation.resume(returning: task.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func beginCall() {
        isOnCall = true
        callStartDate = Date()
        callDuration = 0

        // Start duration timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.callStartDate else { return }
                self.callDuration = Date().timeIntervalSince(start)
            }
        }

        Logger.log("CallDetectionManager: Call started (\(callAppName))", category: .lifecycle)
    }

    private func endCall() {
        guard isOnCall else { return }
        isOnCall = false
        callStartDate = nil
        callDuration = 0
        callAppName = ""
        durationTimer?.invalidate()
        durationTimer = nil

        Logger.log("CallDetectionManager: Call ended", category: .lifecycle)
    }

    /// Formatted call duration string (mm:ss or h:mm:ss)
    var formattedDuration: String {
        let totalSeconds = Int(callDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
