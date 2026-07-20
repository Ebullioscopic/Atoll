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
import AppKit
import SwiftUI

@_silgen_name("CGSIsScreenWatcherPresent")
func CGSIsScreenWatcherPresent() -> Bool

@_silgen_name("CGSRegisterNotifyProc")
func CGSRegisterNotifyProc(
    _ callback: (@convention(c) (Int32, Int32, Int32, UnsafeMutableRawPointer?) -> Void)?,
    _ event: Int32,
    _ context: UnsafeMutableRawPointer?
) -> Bool

private func screenRecordingDebugLog(_ message: String) {
#if DEBUG
    print("ScreenRecordingManager: \(message)")
#endif
}

private func screenCaptureEventCallback(eventType: Int32, _: Int32, _: Int32, context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let manager = Unmanaged<ScreenRecordingManager>.fromOpaque(context).takeUnretainedValue()

    DispatchQueue.main.async {
        screenRecordingDebugLog("Screen capture event received (type: \(eventType))")
        manager.checkRecordingStatus()
    }
}

enum RecordingStopControlState: Equatable {
    case unavailable
    case ready
    case sending
    case failed(String)

    var canSubmitStopRequest: Bool {
        switch self {
        case .ready, .failed:
            return true
        case .unavailable, .sending:
            return false
        }
    }

    var isSending: Bool {
        self == .sending
    }

    var failureMessage: String? {
        guard case let .failed(message) = self else { return nil }
        return message
    }
}

protocol ScreenRecordingStopControlling {
    func requestStop() async
}

struct NativeScreenRecordingStopController: ScreenRecordingStopControlling {
    func requestStop() async {
        await sendStopRecordingShortcutViaSystemEvents()

        if Task.isCancelled { return }
        sendStopRecordingShortcut()
    }

    private func sendStopRecordingShortcutViaSystemEvents() async {
        let script = """
        tell application "System Events"
            key code 53 using {command down, control down}
        end tell
        """

        do {
            try await AppleScriptHelper.executeVoid(script)
            screenRecordingDebugLog("Sent Command-Control-Escape through System Events")
        } catch {
            screenRecordingDebugLog("System Events stop shortcut failed: \(error)")
        }
    }

    private func sendStopRecordingShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            screenRecordingDebugLog("Unable to create CGEventSource for stop shortcut")
            return
        }

        let flags: CGEventFlags = [.maskCommand, .maskControl]
        let keyCode = CGKeyCode(53)
        let taps: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]

        for tap in taps {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            keyDown?.flags = flags
            keyDown?.post(tap: tap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            keyUp?.flags = flags
            keyUp?.post(tap: tap)
        }

        screenRecordingDebugLog("Sent Command-Control-Escape CGEvent stop shortcut")
    }
}

@MainActor
class ScreenRecordingManager: ObservableObject {
    static let shared = ScreenRecordingManager()

    @Published var isRecording: Bool = false
    @Published var isMonitoring: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var stopControlState: RecordingStopControlState = .unavailable

    private let coordinator = DynamicIslandViewCoordinator.shared
    private let stopController: ScreenRecordingStopControlling
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var stopRequestTask: Task<Void, Never>?
    private var stopFailureClearTask: Task<Void, Never>?

    private init(stopController: ScreenRecordingStopControlling = NativeScreenRecordingStopController()) {
        self.stopController = stopController
    }

    deinit {
        stopRequestTask?.cancel()
        stopFailureClearTask?.cancel()
        durationTimer?.invalidate()
    }

    func startMonitoring() {
        guard !isMonitoring else {
            screenRecordingDebugLog("Already monitoring, skipping start")
            return
        }

        isMonitoring = true
        setupPrivateAPINotifications()
        checkRecordingStatus()
        screenRecordingDebugLog("Started screen capture monitoring")
    }

    func stopMonitoring() {
        guard isMonitoring else {
            screenRecordingDebugLog("Not monitoring, skipping stop")
            return
        }

        isMonitoring = false
        stopDurationTracking()
        isRecording = false
        stopRequestTask?.cancel()
        stopRequestTask = nil
        clearStopFailure()
        stopControlState = .unavailable
        screenRecordingDebugLog("Stopped screen capture monitoring")
    }

    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    func stopActiveRecording() {
        guard isRecording, stopControlState.canSubmitStopRequest else { return }

        clearStopFailure()
        stopControlState = .sending
        stopRequestTask?.cancel()

        stopRequestTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await stopController.requestStop()
            guard !Task.isCancelled else { return }

            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }

            checkRecordingStatus()

            if isRecording {
                publishStopFailure()
            } else {
                clearStopFailure()
                stopControlState = .unavailable
            }

            stopRequestTask = nil
        }
    }

    private func setupPrivateAPINotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let registeredConnect = CGSRegisterNotifyProc(screenCaptureEventCallback, 1502, context)
        let registeredDisconnect = CGSRegisterNotifyProc(screenCaptureEventCallback, 1503, context)

        if registeredConnect && registeredDisconnect {
            screenRecordingDebugLog("Private API notifications registered")
        } else {
            screenRecordingDebugLog("Failed to register private API notifications")
        }
    }

    func checkRecordingStatus() {
        let currentRecordingState = CGSIsScreenWatcherPresent()
        guard currentRecordingState != isRecording else { return }

        if currentRecordingState {
            startDurationTracking()
            clearStopFailure()
            stopControlState = .ready
            coordinator.toggleExpandingView(status: true, type: .recording)
            withAnimation(.smooth) {
                isRecording = true
            }
            screenRecordingDebugLog("Screen recording started")
        } else {
            stopDurationTracking()
            stopRequestTask?.cancel()
            stopRequestTask = nil
            stopControlState = .unavailable
            clearStopFailure()
            coordinator.toggleExpandingView(status: false, type: .recording)
            withAnimation(.smooth) {
                isRecording = false
            }
            screenRecordingDebugLog("Screen recording stopped")
        }
    }

    private func startDurationTracking() {
        recordingStartTime = Date()
        recordingDuration = 0
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateDuration()
            }
        }

        screenRecordingDebugLog("Started duration tracking")
    }

    private func stopDurationTracking() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingStartTime = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, !self.isRecording, self.recordingStartTime == nil else { return }
            self.recordingDuration = 0
        }

        screenRecordingDebugLog("Stopped duration tracking")
    }

    private func updateDuration() {
        guard let recordingStartTime else { return }
        recordingDuration = Date().timeIntervalSince(recordingStartTime)
    }

    private func clearStopFailure() {
        stopFailureClearTask?.cancel()
        stopFailureClearTask = nil

        if case .failed = stopControlState {
            stopControlState = isRecording ? .ready : .unavailable
        }
    }

    private func publishStopFailure() {
        let message = String(localized: "Unable to stop recording. Use Command-Control-Escape or the macOS recording menu.")
        stopControlState = .failed(message)
        NSSound.beep()

        stopFailureClearTask?.cancel()
        stopFailureClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            if case .failed = stopControlState {
                stopControlState = isRecording ? .ready : .unavailable
            }
            stopFailureClearTask = nil
        }
    }
}

extension ScreenRecordingManager {
    var currentRecordingStatus: Bool {
        isRecording
    }

    var isMonitoringAvailable: Bool {
        true
    }

    var isSendingStopRequest: Bool {
        stopControlState.isSending
    }

    var canStopFromHUD: Bool {
        isRecording && stopControlState.canSubmitStopRequest
    }

    var stopFailureMessage: String? {
        stopControlState.failureMessage
    }

    var formattedDuration: String {
        let totalSeconds = Int(recordingDuration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
