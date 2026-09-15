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

// Private SkyLight/CGS symbols are intentionally isolated here. They provide
// event-driven screen recording detection without polling, but they are not
// public API and may change across macOS releases.
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

private let screenSharingAppBundleIdentifiers: Set<String> = [
    "com.apple.FaceTime",
    "com.apple.ScreenSharing",
    "com.cisco.webexmeetingsapp",
    "com.hnc.Discord",
    "com.microsoft.teams",
    "com.microsoft.teams2",
    "com.skype.skype",
    "com.tinyspeck.slackmacgap",
    "us.zoom.xos"
]

private let screenSharingAppNameTokens: [String] = [
    "discord",
    "facetime",
    "microsoft teams",
    "screen sharing",
    "skype",
    "slack",
    "webex",
    "zoom"
]

private func isScreenSharingApplication(_ application: NSRunningApplication?) -> Bool {
    guard let application else { return false }

    if let bundleIdentifier = application.bundleIdentifier,
       screenSharingAppBundleIdentifiers.contains(bundleIdentifier) {
        return true
    }

    let appName = (application.localizedName ?? "").lowercased()
    return screenSharingAppNameTokens.contains { appName.contains($0) }
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
    func requestStop() async -> Bool
}

struct NativeScreenRecordingStopController: ScreenRecordingStopControlling {
    func requestStop() async -> Bool {
        var sentStopRequest = await sendStopRecordingShortcutViaSystemEvents()

        if Task.isCancelled { return sentStopRequest }
        try? await Task.sleep(for: .milliseconds(120))
        sentStopRequest = await sendStopRecordingShortcutViaCGEvent() || sentStopRequest

        if Task.isCancelled { return sentStopRequest }
        try? await Task.sleep(for: .milliseconds(300))
        sentStopRequest = await sendStopRecordingShortcutViaSystemEvents() || sentStopRequest

        return sentStopRequest
    }

    private func sendStopRecordingShortcutViaSystemEvents() async -> Bool {
        let script = """
        tell application "System Events"
            key down command
            key down control
            key code 53
            delay 0.05
            key up control
            key up command
        end tell
        """

        do {
            try await AppleScriptHelper.executeVoid(script)
            screenRecordingDebugLog("Sent Command-Control-Escape through System Events")
            return true
        } catch {
            screenRecordingDebugLog("System Events stop shortcut failed: \(error)")
            return false
        }
    }

    private func sendStopRecordingShortcutViaCGEvent() async -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            screenRecordingDebugLog("Unable to create CGEventSource for stop shortcut")
            return false
        }

        let flags: CGEventFlags = [.maskCommand, .maskControl]
        let keyCode = CGKeyCode(53)
        let taps: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]

        for tap in taps {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
            keyDown?.flags = flags
            keyDown?.post(tap: tap)

            try? await Task.sleep(for: .milliseconds(45))
            guard !Task.isCancelled else { return false }

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            keyUp?.flags = flags
            keyUp?.post(tap: tap)

            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return false }
        }

        screenRecordingDebugLog("Sent Command-Control-Escape CGEvent stop shortcut")
        return true
    }
}

@MainActor
class ScreenRecordingManager: ObservableObject {
    static let shared = ScreenRecordingManager()

    @Published var isRecording: Bool = false
    @Published var isMonitoring: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var stopControlState: RecordingStopControlState = .unavailable
    @Published var isScreenSharingAppActive: Bool = false

    private let coordinator = DynamicIslandViewCoordinator.shared
    private let stopController: ScreenRecordingStopControlling
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var stopRequestTask: Task<Void, Never>?
    private var stopFailureClearTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []

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
        startScreenSharingAppMonitoring()
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
        stopScreenSharingAppMonitoring()
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

            let nativeStopTask: Task<Void, Never>? = await isNativeMacOSScreenRecordingProcessActive()
                ? Task { @MainActor [weak self] in
                    await self?.stopNativeMacOSScreenRecordingProcesses()
                }
                : nil
            let shortcutStopTask = Task<Bool, Never> { [stopController] in
                await stopController.requestStop()
            }

            await waitForRecordingToStop(maxAttempts: 2)
            guard !Task.isCancelled else { return }

            if isRecording {
                await nativeStopTask?.value
                let shortcutSucceeded = await shortcutStopTask.value
                if !shortcutSucceeded {
                    screenRecordingDebugLog("All stop shortcut delivery attempts failed")
                }
            } else {
                nativeStopTask?.cancel()
                shortcutStopTask.cancel()
            }
            guard !Task.isCancelled else { return }

            if isRecording {
                await waitForRecordingToStop(maxAttempts: 8)
            }

            if isRecording {
                publishStopFailure()
            } else {
                clearStopFailure()
                stopControlState = .unavailable
            }

            stopRequestTask = nil
        }
    }

    private func waitForRecordingToStop(maxAttempts: Int) async {
        var attempts = 0
        while attempts < maxAttempts {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            checkRecordingStatus()
            if !isRecording {
                break
            }
            attempts += 1
        }
    }

    private func isNativeMacOSScreenRecordingProcessActive() async -> Bool {
        await isProcessRunning(named: "screencapture")
    }

    private func isProcessRunning(named processName: String) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            task.arguments = ["-x", processName]
            task.standardOutput = Pipe()
            task.standardError = Pipe()

            do {
                try task.run()
                task.waitUntilExit()
                return task.terminationStatus == 0
            } catch {
                screenRecordingDebugLog("pgrep \(processName) failed: \(error)")
                return false
            }
        }.value
    }

    private func stopNativeMacOSScreenRecordingProcesses() async {
        let attempts = [
            ["-INT", "screencapture"],
            ["-TERM", "screencapture"],
            ["-TERM", "screencaptureui"],
            ["-TERM", "ScreenCaptureUI"]
        ]

        for arguments in attempts {
            guard await isNativeMacOSScreenRecordingProcessActive() else { return }

            await runKillall(arguments)
            guard !Task.isCancelled else { return }

            try? await Task.sleep(for: .milliseconds(180))
            checkRecordingStatus()
            if !isRecording {
                return
            }
        }
    }

    private func runKillall(_ arguments: [String]) async {
        await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = arguments
            task.standardOutput = Pipe()
            task.standardError = Pipe()

            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                screenRecordingDebugLog("killall \(arguments.joined(separator: " ")) failed: \(error)")
            }
        }.value
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

    private func startScreenSharingAppMonitoring() {
        stopScreenSharingAppMonitoring()
        updateScreenSharingAppState()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let activationObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateScreenSharingAppState()
            }
        }

        let terminationObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateScreenSharingAppState()
            }
        }

        workspaceObservers = [activationObserver, terminationObserver]
    }

    private func stopScreenSharingAppMonitoring() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        isScreenSharingAppActive = false
    }

    private func updateScreenSharingAppState() {
        let isActive = isScreenSharingApplication(NSWorkspace.shared.frontmostApplication)
        guard isActive != isScreenSharingAppActive else { return }

        isScreenSharingAppActive = isActive
        screenRecordingDebugLog("Screen sharing app active: \(isActive)")
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

    var shouldShowStopControlsInHUD: Bool {
        switch stopControlState {
        case .ready, .sending, .failed:
            return isRecording
        case .unavailable:
            return false
        }
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
