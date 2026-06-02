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

final class DoNotDisturbManager: ObservableObject {
    static let shared = DoNotDisturbManager()

    @Published private(set) var isMonitoring = false
    @Published var isDoNotDisturbActive = false
    @Published var currentFocusModeName: String = ""
    @Published var currentFocusModeIdentifier: String = ""

    // Used by the brief-toast UI to show an ON toast when the active mode switches while Focus stays enabled.
    @Published var focusToastTrigger: UUID = UUID()

    /// Briefly `true` after focus turns OFF while toast mode is enabled,
    /// keeping the standalone DoNotDisturbLiveActivity mounted long enough
    /// for the "Off" dismissal animation to play out.
    @Published private(set) var isFocusToastDismissing: Bool = false

    private let notificationCenter = DistributedNotificationCenter.default()
    private let metadataExtractionQueue = DispatchQueue(label: "com.dynamicisland.focus.metadata", qos: .userInitiated)
    private let pollingQueue = DispatchQueue(label: "com.dynamicisland.focus.polling", qos: .utility)
    private let focusLogStream = FocusLogStream()
    private let assertionsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    private var pollingSource: DispatchSourceTimer?
    private var lastAssertionsModificationDate: Date?
    private var modeCancellable: AnyCancellable?
    /// Periodic task that verifies focus is still active when `isDoNotDisturbActive` is true.
    /// Catches cases where the disabled notification fails to fire.
    private var stateVerificationTask: Task<Void, Never>?

    @Published private(set) var monitoringMode: FocusMonitoringMode = Defaults[.focusMonitoringMode]

    /// Timestamp of the last notification-driven state change.
    /// Used to suppress assertions polling from overriding a fresh notification for a short window.
    private var lastNotificationTimestamp: Date = .distantPast
    private static let notificationCooldown: TimeInterval = 4.0

    /// Delayed task that clears retained metadata after the OFF animation completes.
    private var metadataClearTask: Task<Void, Never>?

    /// Task that resets `isFocusToastDismissing` after the OFF toast animation.
    private var toastDismissTask: Task<Void, Never>?

    private init() {
        focusLogStream.onMetadataUpdate = { [weak self] identifier, name in
            self?.handleLogMetadataUpdate(identifier: identifier, name: name)
        }

        modeCancellable = Defaults.publisher(.focusMonitoringMode, options: [])
            .sink { [weak self] change in
                guard let self else { return }

                DispatchQueue.main.async {
                    self.monitoringMode = change.newValue
                }

                self.applyMonitoringModeChange(change.newValue)
            }
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusEnabled(_:)),
            name: .focusModeEnabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusDisabled(_:)),
            name: .focusModeDisabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        isMonitoring = true
        applyMonitoringModeChange(Defaults[.focusMonitoringMode])
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        notificationCenter.removeObserver(self, name: .focusModeEnabled, object: nil)
        notificationCenter.removeObserver(self, name: .focusModeDisabled, object: nil)

        focusLogStream.stop()
        stopAssertionsPolling()
        stateVerificationTask?.cancel()
        stateVerificationTask = nil
        metadataClearTask?.cancel()
        metadataClearTask = nil
        cancelFocusToastDismiss()
        isMonitoring = false

        DispatchQueue.main.async {
            self.isDoNotDisturbActive = false
            self.currentFocusModeIdentifier = ""
            self.currentFocusModeName = ""
        }
    }

    @objc private func handleFocusEnabled(_ notification: Notification) {
        lastNotificationTimestamp = Date()
        apply(notification: notification, isActive: true)
    }

    @objc private func handleFocusDisabled(_ notification: Notification) {
        lastNotificationTimestamp = Date()
        apply(notification: notification, isActive: false)
    }

    private func apply(notification: Notification, isActive: Bool) {
        metadataExtractionQueue.async { [weak self] in
            guard let self = self else { return }

            let metadata = self.extractMetadata(from: notification)
            self.publishMetadata(identifier: metadata.identifier, name: metadata.name, isActive: isActive, source: notification.name.rawValue)
        }
    }

    private func publishMetadata(identifier: String?, name: String?, isActive: Bool?, source: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)

            let isGenericFocusIdentifier = (trimmedIdentifier?.lowercased() == "com.apple.focus")
            let usableIdentifier = (trimmedIdentifier?.isEmpty == false && !isGenericFocusIdentifier) ? trimmedIdentifier : nil
            let usableName = (trimmedName?.isEmpty == false) ? trimmedName : nil

            let previousIdentifier = self.currentFocusModeIdentifier
            let previousName = self.currentFocusModeName
            let previousActive = self.isDoNotDisturbActive

            // When neither identifier nor name is available, only update the active
            // state without overwriting existing mode metadata. This prevents the
            // assertions-poll (which often lacks metadata) from reverting a correct
            // mode set by the log-stream or notification handler.
            if usableIdentifier == nil && usableName == nil {
                if let isActive = isActive, isActive != previousActive {
                    withAnimation(.smooth(duration: 0.25)) {
                        self.isDoNotDisturbActive = isActive
                    }
                    // First activation with no prior mode: default to DND.
                    if isActive && previousIdentifier.isEmpty {
                        self.currentFocusModeIdentifier = FocusModeType.doNotDisturb.rawValue
                        self.currentFocusModeName = FocusModeType.doNotDisturb.displayName
                    }
                    debugPrint("[DoNotDisturbManager] Focus active-only update -> source: \(source) | isActive: \(isActive)")
                }
                return
            }

            let resolvedMode = FocusModeType.resolve(identifier: usableIdentifier, name: usableName)

            let finalIdentifier: String = usableIdentifier ?? resolvedMode.rawValue

            // Compute display name
            let finalName: String
            if resolvedMode == .custom, !FullDiskAccessAuthorization.hasPermission() {
                // Use the provided name if it looks like a real display name (not an
                // icon slug like "graduationcap.fill"). Slugs always contain a dot.
                if let tn = trimmedName, !tn.isEmpty, !tn.contains(".") {
                    finalName = tn
                } else {
                    finalName = "Focus"
                }
            } else if resolvedMode == .custom, FullDiskAccessAuthorization.hasPermission() {
                // With FDA, prefer the real name from ModeConfigurations.json (fixes slug names like graduationcap.fill).
                let lookedUp = FocusMetadataReader.shared.getDisplayName(for: trimmedName ?? "", identifier: finalIdentifier)
                if !lookedUp.isEmpty {
                    finalName = lookedUp
                } else if let tn = trimmedName, !tn.isEmpty, !tn.contains(".") {
                    finalName = tn
                } else {
                    finalName = "Focus"
                }
            } else if let name = trimmedName, !name.isEmpty {
                let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                switch lower {
                case "work":
                    finalName = "Work"
                case "personal", "personal-time":
                    finalName = "Personal"
                case "reduce-interruptions":
                    finalName = "Reduce Interruptions"
                case "sleep", "sleep-mode":
                    finalName = "Sleep"
                case "driving":
                    finalName = "Driving"
                case "default", "dnd", "do-not-disturb", "do not disturb", "donotdisturb":
                    finalName = "Do Not Disturb"
                default:
                    finalName = name
                }
            } else if !resolvedMode.displayName.isEmpty {
                finalName = resolvedMode.displayName
            } else {
                finalName = "Focus"
            }

            let identifierChanged = finalIdentifier != previousIdentifier
            let nameChanged = finalName != previousName
            let shouldToggleActive = isActive.map { $0 != previousActive } ?? false

            if identifierChanged {
                self.currentFocusModeIdentifier = finalIdentifier
            }

            if nameChanged {
                self.currentFocusModeName = finalName.localizedCaseInsensitiveContains("Reduce Interruptions") ? "Reduce Interr." : finalName
            }

            // If Focus remains active and the mode switches (e.g., DND -> Sleep), trigger an ON toast for the new mode.
            if isActive == nil, previousActive == true, identifierChanged {
                self.focusToastTrigger = UUID()
            }

            if identifierChanged || nameChanged || shouldToggleActive {
                debugPrint("[DoNotDisturbManager] Focus update -> source: \(source) | identifier: \(trimmedIdentifier ?? "<nil>") | name: \(trimmedName ?? "<nil>") | resolved: \(resolvedMode.rawValue)")
            }

            guard let isActive = isActive, shouldToggleActive else { return }

            withAnimation(.smooth(duration: 0.25)) {
                self.isDoNotDisturbActive = isActive
            }

            // If Focus turned OFF, retain metadata briefly for the OFF toast,
            // then clear it so stale state doesn't linger.
            if isActive == false {
                self.currentFocusModeIdentifier = previousIdentifier
                self.currentFocusModeName = previousName
                self.scheduleMetadataClear()
                self.beginFocusToastDismissIfNeeded()
            } else {
                // Focus turned ON — cancel any pending metadata clear and toast dismiss.
                self.metadataClearTask?.cancel()
                self.metadataClearTask = nil
                self.cancelFocusToastDismiss()
            }

            // Start or stop periodic verification based on new state.
            self.updateStateVerification(focusActive: isActive)
        }
    }

    /// When focus is believed to be active, periodically verify the assertions
    /// file. If the file shows no active assertions, reset `isDoNotDisturbActive`
    /// to `false`. This catches the case where `_NSDoNotDisturbDisabledNotification`
    /// fails to fire.
    private func updateStateVerification(focusActive: Bool) {
        stateVerificationTask?.cancel()
        stateVerificationTask = nil

        guard focusActive else { return }

        stateVerificationTask = Task { @MainActor [weak self] in
            // Wait a bit before starting verification to let notifications settle.
            try? await Task.sleep(for: .seconds(5))

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.isDoNotDisturbActive else { break }

                // Check the assertions file directly (if FDA is available).
                let focusStillActive = await self.verifyFocusActiveFromAssertions()
                if !focusStillActive {
                    withAnimation(.smooth(duration: 0.25)) {
                        self.isDoNotDisturbActive = false
                    }
                    self.scheduleMetadataClear()
                    self.beginFocusToastDismissIfNeeded()
                    debugPrint("[DoNotDisturbManager] State verification: focus no longer active, resetting.")
                    break
                }
            }
        }
    }

    /// Read the assertions file directly to verify whether focus is truly active.
    /// Returns `true` if the file confirms active assertions, or if the check
    /// cannot be performed (e.g. no FDA) — erring on the side of not falsely resetting.
    private nonisolated func verifyFocusActiveFromAssertions() async -> Bool {
        guard FullDiskAccessAuthorization.hasPermission() else {
            // Can't verify without FDA — conservatively assume still active.
            return true
        }

        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")

        guard let data = try? Data(contentsOf: url),
              !data.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
              let dataArray = root["data"] as? [[String: Any]],
              let firstItem = dataArray.first else {
            // File unreadable/empty — assume focus is off.
            return false
        }

        let assertions = (firstItem["storeAssertionRecords"] as? [Any]) ?? []
        return !assertions.isEmpty
    }

    private func scheduleMetadataClear() {
        metadataClearTask?.cancel()
        metadataClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !self.isDoNotDisturbActive else { return }
            self.currentFocusModeIdentifier = ""
            self.currentFocusModeName = ""
        }
    }

    /// Sets `isFocusToastDismissing` to `true` for ~2.5 seconds when focus turns
    /// OFF while toast mode is enabled. This keeps the standalone DND live activity
    /// mounted long enough for the "Off" toast animation, without permanently
    /// occupying the live-activity slot.
    private func beginFocusToastDismissIfNeeded() {
        guard Defaults[.focusIndicatorNonPersistent] else { return }

        toastDismissTask?.cancel()
        isFocusToastDismissing = true

        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(2500))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.smooth(duration: 0.25)) {
                self.isFocusToastDismissing = false
            }
        }
    }

    /// Cancels any in-progress toast dismiss countdown (e.g. when focus turns back ON).
    private func cancelFocusToastDismiss() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        isFocusToastDismissing = false
    }

    private func handleLogMetadataUpdate(identifier: String?, name: String?) {
        metadataExtractionQueue.async { [weak self] in
            guard let self = self else { return }
            let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)

            let hasIdentifier = (trimmedIdentifier?.isEmpty == false)
            let hasName = (trimmedName?.isEmpty == false)

            guard hasIdentifier || hasName else { return }

            self.publishMetadata(identifier: trimmedIdentifier, name: trimmedName, isActive: nil, source: "log-stream")
        }
    }

    private func extractMetadata(from notification: Notification) -> (name: String?, identifier: String?) {
        var identifier: String?
        var name: String?

        let identifierKeys = [
            "FocusModeIdentifier",
            "focusModeIdentifier",
            "FocusModeUUID",
            "focusModeUUID",
            "UUID",
            "uuid",
            "identifier",
            "Identifier"
        ]

        let nameKeys = [
            "FocusModeName",
            "focusModeName",
            "FocusMode",
            "focusMode",
            "displayName",
            "display_name",
            "name",
            "Name"
        ]

        var candidates: [Any] = []
        if let userInfo = notification.userInfo {
            candidates.append(userInfo)
        }

        if let object = notification.object {
            candidates.append(object)
        }

        debugPrint("[DoNotDisturbManager] raw focus payload -> name: \(notification.name.rawValue), object: \(String(describing: notification.object)), userInfo: \(String(describing: notification.userInfo))")

        for candidate in candidates {
            if identifier == nil {
                identifier = firstMatch(for: identifierKeys, in: candidate)
            }

            if name == nil {
                name = firstMatch(for: nameKeys, in: candidate)
            }

            if identifier != nil && name != nil {
                break
            }
        }

        if identifier == nil || name == nil {
            for candidate in candidates {
                if let decoded = decodeFocusPayloadIfNeeded(candidate) {
                    if identifier == nil {
                        identifier = firstMatch(for: identifierKeys, in: decoded)
                    }

                    if name == nil {
                        name = firstMatch(for: nameKeys, in: decoded)
                    }

                    if identifier != nil && name != nil {
                        break
                    }
                }
            }
        }

        if identifier == nil || name == nil {
            for candidate in candidates {
                if let object = candidate as? NSObject {
                    if identifier == nil, let extractedIdentifier = extractIdentifier(fromFocusObject: object) {
                        identifier = extractedIdentifier
                    }

                    if name == nil, let extractedName = extractDisplayName(fromFocusObject: object) {
                        name = extractedName
                    }

                    if identifier != nil && name != nil {
                        break
                    }
                }
            }
        }

        if identifier == nil || name == nil {
            var descriptionSources: [Any] = candidates

            for candidate in candidates {
                if let decoded = decodeFocusPayloadIfNeeded(candidate) {
                    descriptionSources.append(decoded)
                }
            }

            for candidate in descriptionSources {
                let description = String(describing: candidate)

                if identifier == nil, let inferredIdentifier = FocusMetadataDecoder.extractIdentifier(from: description) {
                    identifier = inferredIdentifier
                }

                if name == nil, let inferredName = FocusMetadataDecoder.extractName(from: description) {
                    name = inferredName
                }

                if identifier != nil && name != nil {
                    break
                }
            }
        }

        if identifier == nil || name == nil {
            if let logMetadata = focusLogStream.latestMetadata() {
                if identifier == nil {
                    identifier = logMetadata.identifier
                }

                if name == nil {
                    name = logMetadata.name
                }
            }
        }

        return (name, identifier)
    }

}

private extension Notification.Name {
    static let focusModeEnabled = Notification.Name("_NSDoNotDisturbEnabledNotification")
    static let focusModeDisabled = Notification.Name("_NSDoNotDisturbDisabledNotification")
}

private extension DoNotDisturbManager {
    func applyMonitoringModeChange(_ mode: FocusMonitoringMode) {
        guard isMonitoring else { return }

        if mode == .useDevTools {
            stopAssertionsPolling()
            focusLogStream.start()
            checkInitialFocusStateViaLog()
        } else {
            focusLogStream.stop()
            startAssertionsPolling()
        }
    }

    /// When using the log-stream mode, `log stream` only delivers future events — it misses any
    /// focus mode that was already active when Atoll launched. This one-shot `log show` reads
    /// recent duetexpertd debug logs to find the most recent `semanticModeIdentifier` event and
    /// seeds the initial focus state from it. Tries progressively larger windows so the common
    /// case (focus toggled recently) resolves in ~1-2s without scanning a full day of logs.
    private func checkInitialFocusStateViaLog() {
        metadataExtractionQueue.async { [weak self] in
            guard let self else { return }

            for window in ["5m", "1h", "24h"] {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
                task.arguments = [
                    "show",
                    "--last", window,
                    "--debug",
                    "--style", "compact",
                    "--predicate", "process == \"duetexpertd\" AND eventMessage CONTAINS \"semanticModeIdentifier\""
                ]
                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = Pipe()

                guard (try? task.run()) != nil else { return }
                task.waitUntilExit()

                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let lines = output.components(separatedBy: "\n").filter {
                    $0.contains("semanticModeIdentifier") && !$0.hasPrefix("Filtering")
                }

                guard let lastLine = lines.last(where: { !$0.isEmpty }) else { continue }

                // starting: 0 means focus ended — nothing to activate.
                guard !lastLine.contains("starting: 0") else { return }

                let identifier = FocusMetadataDecoder.extractIdentifier(from: lastLine)
                let name = FocusMetadataDecoder.extractName(from: lastLine)
                guard identifier != nil || name != nil else { return }

                self.publishMetadata(identifier: identifier, name: name, isActive: true, source: "log-initial")
                return
            }
        }
    }

    func startAssertionsPolling() {
        stopAssertionsPolling()
        lastAssertionsModificationDate = nil

        let timer = DispatchSource.makeTimerSource(queue: pollingQueue)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(2), leeway: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.pollAssertionsState()
        }
        timer.resume()
        pollingSource = timer
    }

    func stopAssertionsPolling() {
        pollingSource?.cancel()
        pollingSource = nil
        lastAssertionsModificationDate = nil
    }

    func pollAssertionsState() {
        guard FullDiskAccessAuthorization.hasPermission() else { return }

        // Skip if a notification just arrived — let the notification take precedence
        // to avoid a race where the file hasn't been flushed yet.
        if Date().timeIntervalSince(lastNotificationTimestamp) < DoNotDisturbManager.notificationCooldown {
            return
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: assertionsURL.path),
           let modifiedAt = attributes[.modificationDate] as? Date,
              let lastObservedModificationDate = lastAssertionsModificationDate,
           modifiedAt <= lastObservedModificationDate {
            return
        }

        // Update last-observed modification date before reading content.
        if let attributes = try? FileManager.default.attributesOfItem(atPath: assertionsURL.path),
           let modifiedAt = attributes[.modificationDate] as? Date {
            lastAssertionsModificationDate = modifiedAt
        }

        // Default to OFF — if the file can't be read or parsed, treat as no active focus.
        var isActive = false
        var identifier: String?
        var name: String?

        if let data = try? Data(contentsOf: assertionsURL),
           !data.isEmpty,
           let root = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
           let dataArray = root["data"] as? [[String: Any]],
           let firstItem = dataArray.first {

            let assertions = (firstItem["storeAssertionRecords"] as? [Any]) ?? []
            isActive = !assertions.isEmpty

            if isActive {
                let identifierKeys = [
                    "modeIdentifier",
                    "FocusModeIdentifier",
                    "focusModeIdentifier",
                    "identifier",
                    "Identifier",
                    "focusModeUUID",
                    "UUID",
                    "uuid"
                ]

                let nameKeys = [
                    "activityDisplayName",
                    "displayName",
                    "FocusModeName",
                    "focusModeName",
                    "focusMode",
                    "name",
                    "Name"
                ]

                identifier = firstMatch(for: identifierKeys, in: assertions)
                name = firstMatch(for: nameKeys, in: assertions)
            }
        }

        publishMetadata(identifier: identifier, name: name, isActive: isActive, source: "assertions-poll")
    }
}

// MARK: - Focus Mode Types

enum FocusModeType: String, CaseIterable {
    case doNotDisturb = "com.apple.donotdisturb.mode"
    case work = "com.apple.focus.work"
    case personal = "com.apple.focus.personal"
    case sleep = "com.apple.focus.sleep"
    case driving = "com.apple.focus.driving"
    case fitness = "com.apple.focus.fitness"
    case gaming = "com.apple.focus.gaming"
    case mindfulness = "com.apple.focus.mindfulness"
    case reading = "com.apple.focus.reading"
    case reduceInterruptions = "com.apple.focus.reduce-interruptions"
    case custom = "com.apple.focus.custom"
    case unknown = ""
    
    var displayName: String {
        switch self {
    case .doNotDisturb: return String(localized: "Do Not Disturb")
        case .work: return "Work"
        case .personal: return "Personal"
        case .sleep: return "Sleep"
        case .driving: return "Driving"
        case .fitness: return "Fitness"
        case .gaming: return "Gaming"
        case .mindfulness: return "Mindfulness"
        case .reading: return "Reading"
        case .reduceInterruptions: return "Reduce Interr."
        case .custom: return "Focus"
        case .unknown: return "Focus Mode"
        }
    }
    
    var sfSymbol: String {
        switch self {
        case .doNotDisturb: return "moon.fill"
        case .work: return "briefcase.fill"
        case .personal: return "person.fill"
        case .sleep: return "bed.double.fill"
        case .driving: return "car.fill"
        case .fitness: return "figure.run"
        case .gaming: return "gamecontroller.fill"
        case .mindfulness: return "circle.hexagongrid"
        case .reading: return "book.closed.fill"
        case .reduceInterruptions: return "apple.intelligence"
        case .custom: return "app.badge"
        case .unknown: return "moon.fill"
        }
    }

    var internalSymbolName: String? {
        switch self {
        case .work: return "person.lanyardcard.fill"
        case .mindfulness: return "apple.mindfulness"
        case .gaming: return "rocket.fill"
        default: return nil
        }
    }

    var activeIcon: Image {
        resolvedActiveIcon()
    }

    func resolvedActiveIcon(usePrivateSymbol: Bool = true) -> Image {
        if usePrivateSymbol,
           let internalSymbolName,
           let image = Image(internalSystemName: internalSymbolName) {
            return image
        }

        return Image(
            systemName: self == .custom
            ? self.getCustomIconFromFile()
            : sfSymbol
        )
    }

    var accentColor: Color {
        switch self {
        case .doNotDisturb:
            return Color(red: 0.370, green: 0.360, blue: 0.902)
        case .work:
            return Color(red: 0.414, green: 0.769, blue: 0.863, opacity: 1.0)
        case .personal:
            return Color(red: 0.748, green: 0.354, blue: 0.948, opacity: 1.0)
        case .sleep:
            return Color(red: 0.341, green: 0.384, blue: 0.980)
        case .driving:
            return Color(red: 0.988, green: 0.561, blue: 0.153)
        case .fitness:
            return Color(red: 0.176, green: 0.804, blue: 0.459)
        case .gaming:
            return Color(red: 0.043, green: 0.518, blue: 1.000, opacity: 1.0)
        case .mindfulness:
            return Color(red: 0.361, green: 0.898, blue: 0.883, opacity: 1.0)
        case .reading:
            return Color(red: 1.000, green: 0.622, blue: 0.044, opacity: 1.0)
        case .reduceInterruptions:
            return Color(red: 0.686, green: 0.322, blue: 0.871, opacity: 1.0)
        case .custom:
            return self.getCustomAccentColorFromFile()
        case .unknown:
            return Color(red: 0.370, green: 0.360, blue: 0.902)
        }
    }

    var inactiveSymbol: String {
        switch self {
        case .doNotDisturb:
            return "moon.circle.fill"
        default:
            return sfSymbol
        }
    }
}

extension FocusModeType {
    init(identifier: String) {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLowercased = normalized.lowercased()

        guard !normalized.isEmpty else {
            self = .doNotDisturb
            return
        }

        // 1. Exact rawValue match (e.g., "com.apple.focus.work", "com.apple.donotdisturb.mode").
        if let direct = FocusModeType(rawValue: normalized) ?? FocusModeType(rawValue: normalizedLowercased) {
            self = direct
            return
        }

        // 2. Sleep focus is reported as `com.apple.sleep.sleep-mode` by duetexpertd,
        //    not as the rawValue `com.apple.focus.sleep`, so handle it explicitly here.
        if normalizedLowercased == "com.apple.sleep.sleep-mode" {
            self = .sleep
            return
        }

        // 3. macOS custom Focus modes use `com.apple.donotdisturb.mode.<symbol>`.
        //    Must be checked BEFORE the generic prefix match, otherwise the prefix
        //    `com.apple.donotdisturb.mode` would incorrectly resolve to .doNotDisturb.
        if normalizedLowercased.hasPrefix("com.apple.donotdisturb.mode.") {
            let suffix = String(normalizedLowercased.dropFirst("com.apple.donotdisturb.mode.".count))
            if !suffix.isEmpty && suffix != "default" {
                self = .custom
                return
            }
        }

        // 4. Prefix match for known built-in modes (e.g., com.apple.focus.personal-time -> .personal).
        if let resolved = FocusModeType.allCases.first(where: {
            guard !$0.rawValue.isEmpty else { return false }
            return normalized.hasPrefix($0.rawValue) || normalizedLowercased.hasPrefix($0.rawValue)
        }) {
            self = resolved
            return
        }

        // 5. Anything else under com.apple.focus is custom.
        if normalizedLowercased.hasPrefix("com.apple.focus") {
            self = .custom
            return
        }

        self = .doNotDisturb
    }

    static func resolve(identifier: String?, name: String?) -> FocusModeType {
        if let name, !name.isEmpty {
            if let match = FocusModeType.allCases.first(where: {
                guard !$0.displayName.isEmpty else { return false }
                return $0.displayName.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return match
            }

            // Also try matching the name against known raw identifiers (e.g., a log line may emit "work" or "sleep" as the name).
            let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch lower {
            case "work": return .work
            case "personal", "personal-time": return .personal
            case "sleep", "sleep-mode": return .sleep
            case "driving": return .driving
            case "fitness": return .fitness
            case "gaming": return .gaming
            case "mindfulness": return .mindfulness
            case "reading": return .reading
            case "reduce-interruptions", "reduce interruptions": return .reduceInterruptions
            case "do not disturb", "dnd", "donotdisturb", "do-not-disturb", "default": return .doNotDisturb
            default: break
            }
        }

        if let identifier, !identifier.isEmpty {
            return FocusModeType(identifier: identifier)
        }

        // If a name was provided but didn't match any known English mode names, the
        // system is likely reporting a localized (non-English) name such as "Travail"
        // for Work on a French macOS. Treat it as a custom/unidentified focus mode
        // instead of incorrectly falling back to Do Not Disturb.
        if let name, !name.isEmpty {
            return .custom
        }

        return .doNotDisturb
    }
    
    func getCustomIconFromFile() -> String {
        return FocusMetadataReader.shared.getIcon(
            for: DoNotDisturbManager.shared.currentFocusModeName,
            identifier: DoNotDisturbManager.shared.currentFocusModeIdentifier
        )
    }
    
    func getCustomAccentColorFromFile() -> Color {
        return FocusMetadataReader.shared.getAccentColor(
            for: DoNotDisturbManager.shared.currentFocusModeName,
            identifier: DoNotDisturbManager.shared.currentFocusModeIdentifier
        )
    }
}

// MARK: - Metadata helpers

private extension DoNotDisturbManager {
    func firstMatch(for keys: [String], in value: Any) -> String? {
        if let dictionary = value as? [AnyHashable: Any] {
            for key in keys {
                if let candidate = dictionary[key], let string = normalizedString(from: candidate) {
                    return string
                }
            }

            for nestedValue in dictionary.values {
                if let nestedMatch = firstMatch(for: keys, in: nestedValue) {
                    return nestedMatch
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let nestedMatch = firstMatch(for: keys, in: element) {
                    return nestedMatch
                }
            }
        }

        return nil
    }

    func normalizedString(from value: Any) -> String? {
        switch value {
        case let string as String:
            let cleaned = FocusMetadataDecoder.cleanedString(string)
            return cleaned.isEmpty ? nil : cleaned
        case let number as NSNumber:
            return FocusMetadataDecoder.cleanedString(number.stringValue)
        case let uuid as UUID:
            return uuid.uuidString
        case let uuid as NSUUID:
            return uuid.uuidString
        case let data as Data:
            if let decoded = decodeFocusPayload(from: data) {
                if let nested = firstMatch(for: ["identifier", "Identifier", "uuid", "UUID"], in: decoded) {
                    return nested
                }
                if let name = firstMatch(for: ["name", "Name", "displayName", "display_name"], in: decoded) {
                    return name
                }
            }
            if let string = String(data: data, encoding: .utf8) {
                let cleaned = FocusMetadataDecoder.cleanedString(string)
                return cleaned.isEmpty ? nil : cleaned
            }
            return nil
        case let dict as [AnyHashable: Any]:
            // Attempt to pull common keys from nested dictionaries
            if let nested = firstMatch(for: ["identifier", "Identifier", "uuid", "UUID"], in: dict) {
                return nested
            }
            if let name = firstMatch(for: ["name", "Name", "displayName", "display_name"], in: dict) {
                return name
            }
            return nil
        default:
            return nil
        }
    }

    func decodeFocusPayloadIfNeeded(_ value: Any) -> Any? {
        switch value {
        case let data as Data:
            return decodeFocusPayload(from: data)
        case let data as NSData:
            return decodeFocusPayload(from: data as Data)
        default:
            return nil
        }
    }

    func decodeFocusPayload(from data: Data) -> Any? {
        guard !data.isEmpty else { return nil }

        if let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            return propertyList
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return jsonObject
        }

        if let string = String(data: data, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    func extractIdentifier(fromFocusObject object: NSObject) -> String? {
        if let array = object as? [Any] {
            for element in array {
                if let nested = element as? NSObject, let identifier = extractIdentifier(fromFocusObject: nested) {
                    return identifier
                }
            }
            return nil
        }

        if let identifier = focusString(object, selector: "modeIdentifier") {
            return identifier
        }

        if let identifier = focusString(object, selector: "identifier") {
            return identifier
        }

        if let details = focusObject(object, selector: "details"), let identifier = extractIdentifier(fromFocusObject: details) {
            return identifier
        }

        if let metadata = focusObject(object, selector: "activeModeAssertionMetadata"), let identifier = extractIdentifier(fromFocusObject: metadata) {
            return identifier
        }

        if let configuration = focusObject(object, selector: "activeModeConfiguration"), let identifier = extractIdentifier(fromFocusObject: configuration) {
            return identifier
        }

        if let modeConfiguration = focusObject(object, selector: "modeConfiguration"), let identifier = extractIdentifier(fromFocusObject: modeConfiguration) {
            return identifier
        }

        if let mode = focusObject(object, selector: "mode") {
            return extractIdentifier(fromFocusObject: mode)
        }

        if let identifiers = focusObject(object, selector: "activeModeIdentifiers") {
            if let stringArray = identifiers as? [String] {
                if let first = stringArray.compactMap({ FocusMetadataDecoder.cleanedString($0) }).first(where: { !$0.isEmpty }) {
                    return first
                }
            } else if let array = identifiers as? NSArray {
                for case let string as String in array {
                    let trimmed = FocusMetadataDecoder.cleanedString(string)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }

        return nil
    }

    func extractDisplayName(fromFocusObject object: NSObject) -> String? {
        if let array = object as? [Any] {
            for element in array {
                if let nested = element as? NSObject, let name = extractDisplayName(fromFocusObject: nested) {
                    return name
                }
            }
            return nil
        }

        if let name = focusString(object, selector: "name") {
            return name
        }

        if let name = focusString(object, selector: "displayName") {
            return name
        }

        if let name = focusString(object, selector: "activityDisplayName") {
            return name
        }

        if let descriptor = focusObject(object, selector: "symbolDescriptor"), let name = focusString(descriptor, selector: "name") {
            return name
        }

        if let mode = focusObject(object, selector: "mode"), let name = extractDisplayName(fromFocusObject: mode) {
            return name
        }

        if let details = focusObject(object, selector: "details"), let name = extractDisplayName(fromFocusObject: details) {
            return name
        }

        if let configuration = focusObject(object, selector: "modeConfiguration"), let name = extractDisplayName(fromFocusObject: configuration) {
            return name
        }

        return nil
    }

    func focusObject(_ object: NSObject, selector selectorName: String) -> NSObject? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        guard let value = object.perform(selector)?.takeUnretainedValue() else { return nil }
        return value as? NSObject
    }

    func focusString(_ object: NSObject, selector selectorName: String) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        guard let value = object.perform(selector)?.takeUnretainedValue() else { return nil }

        switch value {
        case let string as String:
            return FocusMetadataDecoder.cleanedString(string)
        case let string as NSString:
            return FocusMetadataDecoder.cleanedString(string as String)
        case let number as NSNumber:
            return FocusMetadataDecoder.cleanedString(number.stringValue)
        default:
            return nil
        }
    }

}

private final class FocusLogStream {
    private let queue = DispatchQueue(label: "com.dynamicisland.focus.logstream", qos: .utility)
    private var process: Process?
    private var pipe: Pipe?
    private var buffer = Data()
    private var isRunning = false
    private var didTerminate = false

    private let metadataLock = NSLock()
    private var lastIdentifier: String?
    private var lastName: String?

    var onMetadataUpdate: ((String?, String?) -> Void)?

    func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isRunning else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = [
                "stream",
                "--no-backtrace",
                "--style",
                "compact",
                "--level",
                "info",
                "--predicate",
                "process == \"duetexpertd\" AND eventMessage CONTAINS \"semanticModeIdentifier\""
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let data = handle.availableData

                if data.isEmpty {
                    self.queue.async { [weak self] in
                        self?.handleTermination()
                    }
                    return
                }

                self.queue.async { [weak self] in
                    self?.handleIncomingData(data)
                }
            }

            process.terminationHandler = { [weak self] _ in
                self?.queue.async {
                    self?.handleTermination()
                }
            }

            do {
                try process.run()
                self.process = process
                self.pipe = pipe
                self.isRunning = true
                self.didTerminate = false
                debugPrint("[FocusLogStream] Started unified log tail for duetexpertd/donotdisturbd Focus metadata")
            } catch {
                debugPrint("[FocusLogStream] Failed to start log stream: \(error)")
                pipe.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.pipe = nil
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isRunning else { return }
            self.handleTermination(terminateProcess: true)
        }
    }

    func latestMetadata() -> (identifier: String?, name: String?)? {
        metadataLock.lock()
        let identifier = lastIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
        metadataLock.unlock()

        let normalizedIdentifier = (identifier?.isEmpty == false) ? identifier : nil
        let normalizedName = (name?.isEmpty == false) ? name : nil

        if normalizedIdentifier == nil && normalizedName == nil {
            return nil
        }

        return (normalizedIdentifier, normalizedName)
    }

    private func handleIncomingData(_ data: Data) {
        buffer.append(data)

        let newline: UInt8 = 0x0A

        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            let trimmedLineData: Data
            if let lastByte = lineData.last, lastByte == 0x0D {
                trimmedLineData = lineData.dropLast()
            } else {
                trimmedLineData = lineData
            }

            guard !trimmedLineData.isEmpty,
                  let line = String(data: trimmedLineData, encoding: .utf8) else {
                continue
            }

            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("Filtering the log data") || trimmed.hasPrefix("Timestamp") {
            return
        }

        if trimmed.lowercased().contains("error") && trimmed.lowercased().contains("predicate") {
            debugPrint("[FocusLogStream] log stream error: \(trimmed)")
        }

        // Clear only when logs explicitly indicate no active mode (helps avoid wiping state during transitions).
        if trimmed.contains("active mode assertion: (null)") || trimmed.contains("activeModeIdentifier: (null)") {
            clearMetadata()
            return
        }

        var updatedIdentifier: String?
        var updatedName: String?

        // Special-case parsing for donotdisturbd logs which include a full DNDMode description.
        // Example: <DNDMode: ... name: Lock In; modeIdentifier: com.apple.donotdisturb.mode.graduationcap.fill; ...>
        if trimmed.contains("<DNDMode:") {
            func extractField(_ key: String) -> String? {
                guard let r = trimmed.range(of: key) else { return nil }
                let suffix = trimmed[r.upperBound...]
                guard let end = suffix.range(of: ";") else { return nil }
                let value = suffix[..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }

            if let v = extractField("modeIdentifier:") { updatedIdentifier = v }
            if let v = extractField("name:") { updatedName = v }
        }

        if updatedIdentifier == nil, let identifier = FocusMetadataDecoder.extractIdentifier(from: trimmed), !identifier.isEmpty {
            updatedIdentifier = identifier
        }

        if updatedName == nil, let name = FocusMetadataDecoder.extractName(from: trimmed), !name.isEmpty {
            updatedName = name
        }

        guard updatedIdentifier != nil || updatedName != nil else { return }

        var identifierToSend: String?
        var nameToSend: String?

        metadataLock.lock()
        if let identifier = updatedIdentifier, !identifier.isEmpty {
            lastIdentifier = identifier
        }

        if let name = updatedName, !name.isEmpty {
            lastName = name
        }

        identifierToSend = lastIdentifier
        nameToSend = lastName
        metadataLock.unlock()

        notifyMetadataUpdate(identifier: identifierToSend, name: nameToSend)
    }

    private func clearMetadata() {
        metadataLock.lock()
        lastIdentifier = nil
        lastName = nil
        metadataLock.unlock()
        notifyMetadataUpdate(identifier: nil, name: nil)
    }

    private func handleTermination(terminateProcess: Bool = false) {
        if didTerminate { return }
        didTerminate = true
        if terminateProcess, let process, process.isRunning {
            process.terminate()
        }

        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe?.fileHandleForReading.closeFile()
        pipe = nil

        process = nil
        buffer.removeAll(keepingCapacity: false)
        isRunning = false
        clearMetadata()
        debugPrint("[FocusLogStream] Stopped unified log tail for duetexpertd/donotdisturbd Focus metadata")
    }

    private func notifyMetadataUpdate(identifier: String?, name: String?) {
        guard let handler = onMetadataUpdate else { return }
        handler(identifier, name)
    }
}

private enum FocusNotificationParsing {
    static let identifierPattern: NSRegularExpression? = {
        let pattern = "com\\.apple\\.(?:focus|donotdisturb|sleep)[A-Za-z0-9_.-]*"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    static let identifierDetailPatterns: [NSRegularExpression] = {
        let patterns = [
            "modeIdentifier:\\s*'([^'\\s]+)'",
            "activityIdentifier:\\s*([A-Za-z0-9._-]+)",
            "semanticModeIdentifier:\\s*([A-Za-z0-9._-]+)"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    static let namePatterns: [NSRegularExpression] = {
        let patterns = [
            "(?i)(?:focusModeName|focusMode|displayName|name)\\s*=\\s*\"([^\"]+)\"",
            "(?i)(?:focusModeName|focusMode|displayName|name)\\s*=\\s*([^;\\n]+)",
            "activityDisplayName:\\s*([^;>\\n]+)",
            "semanticType:\\s*([A-Za-z][A-Za-z0-9 _-]+)",
            "modeIdentifier:\\s*'com\\.apple\\.focus\\.([A-Za-z0-9._-]+)'"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()
}

private enum FocusMetadataDecoder {
    static func cleanedString(_ string: String) -> String {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return trimmed
    }

    static func extractIdentifier(from description: String) -> String? {
        let fullRange = NSRange(description.startIndex..<description.endIndex, in: description)

        if let regex = FocusNotificationParsing.identifierPattern,
           let match = regex.firstMatch(in: description, options: [], range: fullRange),
           match.numberOfRanges > 0,
           let identifierRange = Range(match.range(at: 0), in: description) {
            let candidate = cleanedString(String(description[identifierRange]))
            if !candidate.isEmpty {
                return candidate
            }
        }

        for regex in FocusNotificationParsing.identifierDetailPatterns {
            if let match = regex.firstMatch(in: description, options: [], range: fullRange),
               match.numberOfRanges > 1,
               let identifierRange = Range(match.range(at: 1), in: description) {
                let candidate = cleanedString(String(description[identifierRange]))
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }

        return nil
    }

    static func extractName(from description: String) -> String? {
        let fullRange = NSRange(description.startIndex..<description.endIndex, in: description)

        for regex in FocusNotificationParsing.namePatterns {
            if let match = regex.firstMatch(in: description, options: [], range: fullRange),
               match.numberOfRanges > 1,
               let nameRange = Range(match.range(at: 1), in: description) {
                let candidate = cleanedString(String(description[nameRange]))
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }

        return nil
    }
}

private final class FocusMetadataReader {
    private let pathToDatabase:URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")

    struct DNDConfigRoot: Codable {
        let data: [DNDDataEntry]
    }

    struct DNDDataEntry: Codable {
        let modeConfigurations: [String: DNDModeWrapper]
    }

    struct DNDModeWrapper: Codable {
        let mode: DNDMode
    }

    struct DNDMode: Codable {
        let name: String
        let modeIdentifier: String
        let symbolImageName: String?
        let tintColorName: String?
    }

    private init(){}

    static let shared = FocusMetadataReader()

    private func getModeConfig(for focusName: String, identifier: String? = nil) -> DNDMode? {
        guard FullDiskAccessAuthorization.hasPermission() else { return nil }

        let trimmedName = focusName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let data = try Data(contentsOf: pathToDatabase)
            let root = try JSONDecoder().decode(DNDConfigRoot.self, from: data)

            for entry in root.data {
                for wrapper in entry.modeConfigurations.values {
                    let mode = wrapper.mode

                    if let id = trimmedIdentifier, !id.isEmpty,
                       mode.modeIdentifier.compare(id, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                        return mode
                    }

                    if !trimmedName.isEmpty,
                       mode.name.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                        return mode
                    }
                }
            }
        } catch {
            print("ModeConfigurations.json decode error: \(error)")
        }

        return nil
    }

    func getDisplayName(for focus: String, identifier: String? = nil) -> String {
        guard let mode = getModeConfig(for: focus, identifier: identifier) else { return "" }
        return mode.name
    }

    /// Fetch the icon for the current focus from disk. If the focus is not found return the placeholder `app.badge`
    /// - Returns A string representing the sfSymbol of the current focus
    func getIcon(for focus: String, identifier: String? = nil) -> String {
        guard let mode = getModeConfig(for: focus, identifier: identifier) else { return "app.badge" }
        return mode.symbolImageName ?? "app.badge"
    }

    /// Fetch the accent color for the current focus from disk. If the focus is not found return the placeholder `Color.indigo`
    /// - Returns A Color representing the accent color for the current focus
    func getAccentColor(for focus: String, identifier: String? = nil) -> Color {
        guard let mode = getModeConfig(for: focus, identifier: identifier),
              let colorName = mode.tintColorName else { return .indigo }

        return Color.stringToColor(for: colorName)
    }
}

extension Color {
    static func stringToColor(for string:String) -> Color {
        let cleanName = string.lowercased()
            .replacingOccurrences(of: "system", with: "")
            .replacingOccurrences(of: "color", with: "")
        
        switch cleanName {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "mint": return .mint
        case "teal": return .teal
        case "cyan": return .cyan
        case "blue": return .blue
        case "indigo": return .indigo
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        default: return .indigo
        }
    }
}
