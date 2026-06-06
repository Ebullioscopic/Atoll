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

@preconcurrency import Foundation
import AppKit
import Defaults
import Combine

// MARK: - BetterDisplay OSD Notification Model

/// Matches the JSON structure dispatched by BetterDisplay's OSD notification system.
/// See: https://github.com/waydabber/BetterDisplay/wiki/Integration-features,-CLI#osd-notification-dispatch-integration
struct BetterDisplayOSDNotification: Codable {
    var displayID: Int?
    var systemIconID: Int?
    var customSymbol: String?
    var text: String?
    var lock: Bool?
    var controlTarget: String?
    var value: Double?
    var maxValue: Double?
    var symbolFadeAfter: Int?
    var symbolSizeMultiplier: Double?
    var textFadeAfter: Int?
}

// MARK: - BetterDisplay Request / Response Models

/// JSON structure for sending commands to BetterDisplay via distributed notifications.
struct BetterDisplayRequestData: Codable {
    var uuid: String?
    var commands: [String] = []
    var parameters: [String: String?] = [:]
}

/// JSON structure for receiving responses from BetterDisplay.
struct BetterDisplayResponseData: Codable {
    var uuid: String?
    var result: Bool?
    var payload: String?
}

// MARK: - BetterDisplay Control Target Classification

enum BetterDisplayControlCategory {
    case brightness
    case volume
    case other
}

private let brightnessControlTargets: Set<String> = [
    "combinedBrightness",
    "hardwareBrightness",
    "softwareBrightness"
]

private let volumeControlTargets: Set<String> = [
    "volume",
    "mute"
]

// MARK: - BetterDisplay Manager

/// Manages integration with the BetterDisplay app (waydabber.BetterDisplay).
///
/// Responsibilities:
/// - Detect whether BetterDisplay is installed
/// - Observe OSD notifications from BetterDisplay and route them to Atoll's HUD pipeline
/// - Provide request/response primitives for controlling display properties
@MainActor
final class BetterDisplayManager: ObservableObject {
    static let shared = BetterDisplayManager()

    /// The bundle identifier of BetterDisplay.
    nonisolated static let bundleID = "pro.betterdisplay.BetterDisplay"

    // Notification names
    private static let osdNotificationName = NSNotification.Name("com.betterdisplay.BetterDisplay.osd")
    private static let requestNotificationName = NSNotification.Name("com.betterdisplay.BetterDisplay.request")
    private static let responseNotificationName = NSNotification.Name("com.betterdisplay.BetterDisplay.response")
    private static let launchedNotificationName = NSNotification.Name("pro.betterdisplay.BetterDisplay.launched")
    private static let terminatedNotificationName = NSNotification.Name("pro.betterdisplay.BetterDisplay.terminated")

    // MARK: Published state

    /// Whether BetterDisplay is currently detected (installed) on this machine.
    @Published private(set) var isDetected: Bool = false

    /// Whether BetterDisplay is currently running and ready for communication.
    @Published private(set) var isRunning: Bool = false

    // MARK: Private

    private var osdObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?
    private var workspaceTermObserver: NSObjectProtocol?
    private var launchedObserver: NSObjectProtocol?
    private var terminatedObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private weak var coordinator: DynamicIslandViewCoordinator?

    private var isBetterDisplayIntegrationEnabled: Bool {
        Defaults[.enableThirdPartyDDCIntegration] && Defaults[.thirdPartyDDCProvider] == .betterDisplay
    }

    private var isExternalVolumeListenerEnabled: Bool {
        isBetterDisplayIntegrationEnabled && Defaults[.enableExternalVolumeControlListener]
    }

    private init() {
        isDetected = Self.checkInstallation()
        isRunning = Self.checkRunning()
        setupWorkspaceObserver()
        setupLifecycleObservers()
        setupSettingsObserver()
    }

    // MARK: - Public API

    /// Configure with the view coordinator for HUD dispatch.
    func configure(coordinator: DynamicIslandViewCoordinator) {
        self.coordinator = coordinator
        refreshListeningState()
    }

    /// Refresh detection status (e.g. after app install/uninstall).
    func refreshDetectionStatus() {
        let wasDetected = isDetected
        let wasRunning = isRunning
        isDetected = Self.checkInstallation()
        isRunning = Self.checkRunning()
        if wasDetected != isDetected {
            NSLog("📺 BetterDisplay detection changed: detected=\(isDetected)")
        }
        if wasRunning != isRunning {
            NSLog("📺 BetterDisplay running state changed: running=\(isRunning)")
        }
        refreshListeningState()
    }

    // MARK: - Detection

    /// Check if BetterDisplay is installed by looking for its bundle ID.
    static func checkInstallation() -> Bool {
        // Check running apps first (fast path)
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID }) {
            return true
        }

        // Fallback: check if the app is installed via URL scheme or bundle lookup
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.fileExists(atPath: url.path)
        }

        return false
    }

    /// Check if BetterDisplay is currently running.
    static func checkRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleID })
    }

    // MARK: - OSD Listening

    private func startListening() {
        guard osdObserver == nil else { return }

        osdObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.osdNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleOSDNotification(notification)
            }
        }

        NSLog("✅ BetterDisplay OSD listener started")
    }

    private func stopListening() {
        if let observer = osdObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            osdObserver = nil
            NSLog("⏹ BetterDisplay OSD listener stopped")
        }
    }

    // MARK: - OSD Handling

    private func handleOSDNotification(_ notification: Notification) {
        guard isBetterDisplayIntegrationEnabled, isRunning else { return }

        guard let notificationString = notification.object as? String else {
            NSLog("⚠️ BetterDisplay OSD: unexpected notification format")
            return
        }

        NSLog("📺 BetterDisplay OSD raw payload: \(notificationString)")

        do {
            let osd = try JSONDecoder().decode(
                BetterDisplayOSDNotification.self,
                from: Data(notificationString.utf8)
            )
            let displayIDText = osd.displayID.map { String($0) } ?? "nil"
            let targetText = osd.controlTarget ?? "nil"
            let iconIDText = osd.systemIconID.map { String($0) } ?? "nil"
            let valueText = osd.value.map { String($0) } ?? "nil"
            let maxValueText = osd.maxValue.map { String($0) } ?? "nil"
            let symbolText = osd.customSymbol ?? "nil"
            let textValue = osd.text ?? "nil"
            NSLog(
                "📺 BetterDisplay decoded payload: displayID=\(displayIDText) target=\(targetText) iconID=\(iconIDText) value=\(valueText) maxValue=\(maxValueText) customSymbol=\(symbolText) text=\(textValue)"
            )
            routeOSDToHUD(osd)
        } catch {
            NSLog("⚠️ BetterDisplay OSD decode error: \(error.localizedDescription)")
        }
    }

    /// Route a decoded BetterDisplay OSD notification to the active Atoll HUD variant.
    private func routeOSDToHUD(_ osd: BetterDisplayOSDNotification) {
        let category = classifyControlTarget(osd.controlTarget, systemIconID: osd.systemIconID)
        let normalizedValue = normalizeValue(osd.value, maxValue: osd.maxValue)
        let targetScreen = resolveScreen(for: osd.displayID)
        let isExternalDisplay = isExternal(displayID: osd.displayID, resolvedScreen: targetScreen)
        let inferredMute = osd.controlTarget == "mute" || osd.systemIconID == 4
        let hasVolumeData = category == .volume && osd.value != nil
        let externalVolumeListenerEnabled = isExternalVolumeListenerEnabled
        let targetText = osd.controlTarget ?? "nil"
        let displayIDText = osd.displayID.map { String($0) } ?? "nil"
        let resolvedScreenText = targetScreen?.localizedName ?? "nil"
        let valueText = osd.value.map { String($0) } ?? "nil"
        let maxValueText = osd.maxValue.map { String($0) } ?? "nil"
        let normalizedText = String(format: "%.3f", normalizedValue)

        NSLog(
            "📺 BetterDisplay routed payload: category=\(categoryName(category)) target=\(targetText) displayID=\(displayIDText) resolvedScreen=\(resolvedScreenText) isExternal=\(isExternalDisplay) rawValue=\(valueText) maxValue=\(maxValueText) normalized=\(normalizedText) hasVolumeData=\(hasVolumeData) inferredMute=\(inferredMute) externalVolumeListener=\(externalVolumeListenerEnabled)"
        )

        switch category {
        case .brightness:
            let icon = isExternalDisplay ? "display" : nil
            dispatchBrightnessHUD(value: normalizedValue, customSymbol: icon, onScreen: targetScreen)

        case .volume:
            guard externalVolumeListenerEnabled else {
                NSLog("📺 BetterDisplay volume payload ignored because external volume listener is disabled")
                return
            }
            let isMuted = osd.controlTarget == "mute" || osd.systemIconID == 4
            dispatchVolumeHUD(value: normalizedValue, isMuted: isMuted, onScreen: targetScreen)

        case .other:
            // For unsupported control targets (contrast, gamma, temperature, etc.),
            // show a generic brightness-style HUD if the user has brightness HUD enabled
            let icon = isExternalDisplay ? "display" : osd.customSymbol
            dispatchBrightnessHUD(value: normalizedValue, customSymbol: icon, onScreen: targetScreen)
        }
    }

    // MARK: - HUD Dispatch (mirrors SystemChangesObserver logic)

    private func dispatchVolumeHUD(value: CGFloat, isMuted: Bool, onScreen targetScreen: NSScreen? = nil) {
        if HUDSuppressionCoordinator.shared.shouldSuppressVolumeHUD { return }

        if Defaults[.enableCircularHUD] {
            CircularHUDWindowManager.shared.show(type: .volume, value: value, onScreen: targetScreen)
            return
        }
        if Defaults[.enableVerticalHUD] {
            VerticalHUDWindowManager.shared.show(type: .volume, value: value, icon: "", onScreen: targetScreen)
            return
        }
        if Defaults[.enableCustomOSD] && Defaults[.enableOSDVolume] {
            CustomOSDWindowManager.shared.showVolume(value: value, onScreen: targetScreen)
        }
        if Defaults[.enableSystemHUD] && !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] {
            coordinator?.toggleSneakPeek(
                status: true,
                type: .volume,
                value: value,
                icon: "",
                onScreen: targetScreen
            )
        }
    }

    private func dispatchBrightnessHUD(value: CGFloat, customSymbol: String? = nil, onScreen targetScreen: NSScreen? = nil) {
        let icon = customSymbol ?? ""
        if Defaults[.enableCircularHUD] {
            CircularHUDWindowManager.shared.show(type: .brightness, value: value, icon: icon, onScreen: targetScreen)
            return
        }
        if Defaults[.enableVerticalHUD] {
            VerticalHUDWindowManager.shared.show(type: .brightness, value: value, icon: icon, onScreen: targetScreen)
            return
        }
        if Defaults[.enableCustomOSD] && Defaults[.enableOSDBrightness] {
            CustomOSDWindowManager.shared.showBrightness(value: value, icon: icon, onScreen: targetScreen)
        }
        if Defaults[.enableSystemHUD] && !Defaults[.enableCustomOSD] && !Defaults[.enableVerticalHUD] && !Defaults[.enableCircularHUD] {
            coordinator?.toggleSneakPeek(
                status: true,
                type: .brightness,
                value: value,
                icon: icon,
                onScreen: targetScreen
            )
        }
    }

    // MARK: - Helpers

    /// Resolve a BetterDisplay `displayID` (CGDirectDisplayID) to the matching NSScreen, if any.
    private func resolveScreen(for displayID: Int?) -> NSScreen? {
        guard let displayID else {
            NSLog("📺 BetterDisplay resolveScreen: displayID is nil, falling back to all screens")
            return nil
        }

        if let directDisplayID = UInt32(exactly: displayID),
           let matchedScreen = NSScreen.screens.first(where: { screenNumber(for: $0) == directDisplayID }) {
            return matchedScreen
        }

        // Fallback for payloads that use 1-based display indexes (1, 2, ...)
        if displayID > 0 {
            let index = displayID - 1
            if NSScreen.screens.indices.contains(index) {
                let fallback = NSScreen.screens[index]
                NSLog("📺 BetterDisplay resolveScreen: displayID=\(displayID) resolved via index fallback to '\(fallback.localizedName)'")
                return fallback
            }
        }

        let target = UInt32(displayID)
        let availableScreens = NSScreen.screens.map { screen -> (String, UInt32) in
            let num = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return (screen.localizedName, num)
        }
        NSLog("📺 BetterDisplay resolveScreen: looking for displayID=\(displayID) (UInt32=\(target)) among screens: \(availableScreens)")
        NSLog("📺 BetterDisplay resolveScreen: no match found for displayID=\(displayID), HUD will show on all screens")
        return nil
    }

    /// Whether the given displayID refers to an external (non-built-in) display.
    private func isExternal(displayID: Int?, resolvedScreen: NSScreen?) -> Bool {
        if let resolvedScreen,
           let resolvedDisplayID = screenNumber(for: resolvedScreen) {
            return CGDisplayIsBuiltin(resolvedDisplayID) == 0
        }
        guard let displayID,
              let displayIDValue = UInt32(exactly: displayID) else {
            return false
        }
        return CGDisplayIsBuiltin(displayIDValue) == 0
    }

    private func screenNumber(for screen: NSScreen) -> UInt32? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return screenNumber.uint32Value
    }

    private func classifyControlTarget(_ target: String?, systemIconID: Int?) -> BetterDisplayControlCategory {
        if let target {
            if brightnessControlTargets.contains(target) { return .brightness }
            if volumeControlTargets.contains(target) { return .volume }
        }

        // Fallback to systemIconID
        switch systemIconID {
        case 1: return .brightness  // brightness icon
        case 3: return .volume      // volume icon
        case 4: return .volume      // mute icon
        default: return .other
        }
    }

    private func categoryName(_ category: BetterDisplayControlCategory) -> String {
        switch category {
        case .brightness:
            return "brightness"
        case .volume:
            return "volume"
        case .other:
            return "other"
        }
    }

    /// Normalize a BetterDisplay value (0...maxValue) to 0...1 range.
    private func normalizeValue(_ value: Double?, maxValue: Double?) -> CGFloat {
        guard let value else { return 0 }
        let maxVal = maxValue ?? 1.0
        guard maxVal > 0 else { return 0 }
        return CGFloat(Swift.min(Swift.max(value / maxVal, 0), 1))
    }

    // MARK: - Request API

    /// Send a command to BetterDisplay and optionally receive a response.
    /// - Parameters:
    ///   - commands: e.g. ["set"], ["get"]
    ///   - parameters: e.g. ["brightness": "0.8"]
    ///   - completion: Called with the response on the main queue, or nil on timeout.
    func sendRequest(
        commands: [String],
        parameters: [String: String?],
        completion: (@MainActor @Sendable (BetterDisplayResponseData?) -> Void)? = nil
    ) {
        guard isRunning else {
            NSLog("⚠️ BetterDisplay sendRequest skipped — app is not running")
            completion?(nil)
            return
        }

        let uuid = UUID().uuidString
        let request = BetterDisplayRequestData(uuid: uuid, commands: commands, parameters: parameters)

        // If we need a response, set up a temporary observer
        if let completion {
            // Use a class wrapper so the observer closure can safely capture & cancel
            final class ResponseState: @unchecked Sendable {
                var observer: NSObjectProtocol?
                var timeoutItem: DispatchWorkItem?
            }
            let state = ResponseState()

            let timeoutItem = DispatchWorkItem {
                if let obs = state.observer {
                    DistributedNotificationCenter.default().removeObserver(obs)
                    state.observer = nil
                }
                Task { @MainActor in
                    completion(nil)
                }
            }
            state.timeoutItem = timeoutItem

            state.observer = DistributedNotificationCenter.default().addObserver(
                forName: Self.responseNotificationName,
                object: nil,
                queue: .main
            ) { notification in
                guard let responseString = notification.object as? String,
                      let response = try? JSONDecoder().decode(
                        BetterDisplayResponseData.self,
                        from: Data(responseString.utf8)
                      ),
                      response.uuid == uuid
                else { return }

                state.timeoutItem?.cancel()
                if let obs = state.observer {
                    DistributedNotificationCenter.default().removeObserver(obs)
                    state.observer = nil
                }
                Task { @MainActor in
                    completion(response)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeoutItem)
        }

        // Send the request
        do {
            let encoded = try JSONEncoder().encode(request)
            if let encodedString = String(data: encoded, encoding: .utf8) {
                DistributedNotificationCenter.default().postNotificationName(
                    Self.requestNotificationName,
                    object: encodedString,
                    userInfo: nil,
                    deliverImmediately: true
                )
            }
        } catch {
            NSLog("⚠️ BetterDisplay request encode error: \(error.localizedDescription)")
            completion?(nil)
        }
    }

    // MARK: - Workspace Observer (detect install/uninstall)

    private func setupWorkspaceObserver() {
        let betterDisplayBundleID = Self.bundleID

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == betterDisplayBundleID
            else { return }
            Task { @MainActor in
                self?.refreshDetectionStatus()
            }
        }

        // Also observe app termination — handles crashes and force-quits
        // (orderly quits are caught by the lifecycle observer below)
        workspaceTermObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == betterDisplayBundleID
            else { return }
            Task { @MainActor in
                NSLog("🔴 BetterDisplay terminated (workspace notification)")
                self?.isRunning = false
                self?.refreshListeningState()
            }
        }
    }

    // MARK: - Lifecycle Observers (BetterDisplay launched/terminated notifications)

    /// Listen for distributed notifications sent by BetterDisplay itself
    /// to know when it becomes ready and when it shuts down cleanly.
    private func setupLifecycleObservers() {
        launchedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.launchedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                NSLog("🟢 BetterDisplay launched notification received")
                self?.isDetected = true
                self?.isRunning = true
                self?.refreshListeningState()
            }
        }

        terminatedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.terminatedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                NSLog("🔴 BetterDisplay terminated notification received")
                self?.isRunning = false
                self?.refreshListeningState()
            }
        }
    }

    // MARK: - Settings Observer

    private func refreshListeningState() {
        if isBetterDisplayIntegrationEnabled && isRunning {
            startListening()
        } else {
            stopListening()
        }
    }

    private func setupSettingsObserver() {
        Defaults.publisher(.enableThirdPartyDDCIntegration, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshListeningState()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.thirdPartyDDCProvider, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshListeningState()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        if let osdObserver {
            DistributedNotificationCenter.default().removeObserver(osdObserver)
        }
        if let launchedObserver {
            DistributedNotificationCenter.default().removeObserver(launchedObserver)
        }
        if let terminatedObserver {
            DistributedNotificationCenter.default().removeObserver(terminatedObserver)
        }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        if let workspaceTermObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceTermObserver)
        }
        cancellables.removeAll()
    }
}
