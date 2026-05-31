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
import Defaults
import AtollExtensionKit
import SwiftUI
import AppKit

@MainActor
final class ExtensionLiveActivityManager: ObservableObject {
    static let shared = ExtensionLiveActivityManager()

    @Published private(set) var activeActivities: [ExtensionLiveActivityPayload] = []
    
    // Supercharged agent features state
    @Published var historyShelf: [AgentHistoryEntry] = []
    @Published var currentSpeed: Double = 0.0
    @Published var currentCost: Double = 0.0
    @Published var showDetailsHUD: Bool = false
    @Published var openedByHover: Bool = false
    @Published var triggerParticleBurst: Bool = false
    private var metricsTimer: Timer?

    private let authorizationManager = ExtensionAuthorizationManager.shared
    private let maxCapacityKey = Defaults.Keys.extensionLiveActivityCapacity
    private let eventBridge = ExtensionEventBridge.shared
    private var liveActivityObserver: NSObjectProtocol?
    private var suppressBroadcast = false
    private let currentProcessID = ProcessInfo.processInfo.processIdentifier

    private init() {
        activeActivities = eventBridge.loadPersistedLiveActivities()
        sortActivities()
        liveActivityObserver = eventBridge.observeLiveActivitySnapshots { [weak self] payloads, sourcePID in
            self?.applySnapshot(payloads, sourcePID: sourcePID)
        }
        // Metrics timer is started on-demand when activities are present
    }

    deinit {
        if let token = liveActivityObserver {
            eventBridge.removeObserver(token)
        }
    }

    func present(descriptor: AtollLiveActivityDescriptor, bundleIdentifier: String) throws {
        guard authorizationManager.canProcessLiveActivityRequest(from: bundleIdentifier) else {
            logDiagnostics("Rejected live activity \(descriptor.id) from \(bundleIdentifier): scope disabled or bundle unauthorized")
            throw ExtensionValidationError.unauthorized
        }
        guard descriptor.isValid else {
            logDiagnostics("Rejected live activity \(descriptor.id) from \(bundleIdentifier): descriptor validation failed")
            throw ExtensionValidationError.invalidDescriptor("Structure validation failed")
        }

        let isUpdate: Bool
        if let index = activeActivities.firstIndex(where: { $0.descriptor.id == descriptor.id && $0.bundleIdentifier == bundleIdentifier }) {
            let payload = ExtensionLiveActivityPayload(
                bundleIdentifier: bundleIdentifier,
                descriptor: descriptor,
                receivedAt: activeActivities[index].receivedAt
            )
            activeActivities[index] = payload
            sortActivities()
            startMetricsTimer()
            authorizationManager.recordActivity(for: bundleIdentifier, scope: .liveActivities)
            Logger.log("Replaced extension live activity \(descriptor.id) for \(bundleIdentifier)", category: .extensions)
            isUpdate = true
        } else {
            guard activeActivities.count < Defaults[maxCapacityKey] else {
                logDiagnostics("Rejected live activity \(descriptor.id) from \(bundleIdentifier): capacity limit \(Defaults[maxCapacityKey]) reached")
                throw ExtensionValidationError.exceedsCapacity
            }

            let payload = ExtensionLiveActivityPayload(
                bundleIdentifier: bundleIdentifier,
                descriptor: descriptor,
                receivedAt: .now
            )
            activeActivities.append(payload)
            sortActivities()
            startMetricsTimer()
            authorizationManager.recordActivity(for: bundleIdentifier, scope: .liveActivities)
            logDiagnostics("Queued live activity \(descriptor.id) for \(bundleIdentifier); total activities: \(activeActivities.count)")
            isUpdate = false
        }
        
        broadcastSnapshot()
        
        playSoundForActivity(descriptor: descriptor)
        addToHistoryShelf(descriptor: descriptor, bundleIdentifier: bundleIdentifier)
        
        // Trigger sneak peek (defaulting to enabled for legacy descriptors)
        let resolvedConfig = descriptor.sneakPeekConfig ?? .default
        if resolvedConfig.enabled {
            let shouldShow = !isUpdate || resolvedConfig.showOnUpdate
            if shouldShow {
                triggerSneakPeek(for: descriptor, bundleIdentifier: bundleIdentifier, config: resolvedConfig)
            }
        }
    }

    func update(descriptor: AtollLiveActivityDescriptor, bundleIdentifier: String) throws {
        guard descriptor.isValid else {
            logDiagnostics("Rejected live activity update \(descriptor.id) from \(bundleIdentifier): descriptor validation failed")
            throw ExtensionValidationError.invalidDescriptor("Structure validation failed")
        }
        guard let index = activeActivities.firstIndex(where: { $0.descriptor.id == descriptor.id && $0.bundleIdentifier == bundleIdentifier }) else {
            throw ExtensionValidationError.invalidDescriptor("Missing existing activity")
        }
        let payload = ExtensionLiveActivityPayload(
            bundleIdentifier: bundleIdentifier,
            descriptor: descriptor,
            receivedAt: activeActivities[index].receivedAt
        )
        activeActivities[index] = payload
        sortActivities()
        authorizationManager.recordActivity(for: bundleIdentifier, scope: .liveActivities)
        logDiagnostics("Updated live activity \(descriptor.id) for \(bundleIdentifier)")
        broadcastSnapshot()
        
        playSoundForActivity(descriptor: descriptor)
        addToHistoryShelf(descriptor: descriptor, bundleIdentifier: bundleIdentifier)
    }

    func dismiss(activityID: String, bundleIdentifier: String) {
        let previousCount = activeActivities.count
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            activeActivities.removeAll { $0.descriptor.id == activityID && $0.bundleIdentifier == bundleIdentifier }
        }
        if previousCount != activeActivities.count {
            Logger.log("Dismissed extension live activity \(activityID) from \(bundleIdentifier)", category: .extensions)
            ExtensionXPCServiceHost.shared.notifyActivityDismiss(bundleIdentifier: bundleIdentifier, activityID: activityID)
            ExtensionRPCServer.shared.notifyActivityDismiss(bundleIdentifier: bundleIdentifier, activityID: activityID)
            logDiagnostics("Removed live activity \(activityID) for \(bundleIdentifier); remaining: \(activeActivities.count)")
            broadcastSnapshot()
            if activeActivities.isEmpty {
                stopMetricsTimer()
            }
        }
    }

    func dismissAll(for bundleIdentifier: String) {
        let ids = activeActivities
            .filter { $0.bundleIdentifier == bundleIdentifier }
            .map { $0.descriptor.id }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            activeActivities.removeAll { $0.bundleIdentifier == bundleIdentifier }
        }
        ids.forEach {
            ExtensionXPCServiceHost.shared.notifyActivityDismiss(bundleIdentifier: bundleIdentifier, activityID: $0)
            ExtensionRPCServer.shared.notifyActivityDismiss(bundleIdentifier: bundleIdentifier, activityID: $0)
        }
        if !ids.isEmpty {
            logDiagnostics("Removed all live activities for \(bundleIdentifier); ids: \(ids.joined(separator: ", "))")
            broadcastSnapshot()
            if activeActivities.isEmpty {
                stopMetricsTimer()
            }
        }
    }

    func sortedActivities(for coexistence: Bool = false) -> [ExtensionLiveActivityPayload] {
        activeActivities
            .filter { coexistence ? $0.descriptor.allowsMusicCoexistence : true }
            .sorted(by: descriptorComparator)
    }

    func payload(bundleIdentifier: String, activityID: String) -> ExtensionLiveActivityPayload? {
        activeActivities.first { $0.bundleIdentifier == bundleIdentifier && $0.descriptor.id == activityID }
    }

    private func descriptorComparator(lhs: ExtensionLiveActivityPayload, rhs: ExtensionLiveActivityPayload) -> Bool {
        if lhs.descriptor.priority == rhs.descriptor.priority {
            return lhs.receivedAt < rhs.receivedAt
        }
        return lhs.descriptor.priority > rhs.descriptor.priority
    }

    private func sortActivities() {
        activeActivities.sort(by: descriptorComparator)
    }

    private func broadcastSnapshot() {
        guard !suppressBroadcast else { return }
        eventBridge.broadcastLiveActivitySnapshot(activeActivities)
        logDiagnostics("Broadcasted live activity snapshot (count: \(activeActivities.count))")
    }

    private func applySnapshot(_ payloads: [ExtensionLiveActivityPayload], sourcePID: Int32) {
        guard sourcePID != currentProcessID else { return }
        suppressBroadcast = true
        activeActivities = payloads.sorted(by: descriptorComparator)
        suppressBroadcast = false
        logDiagnostics("Applied external live activity snapshot from PID \(sourcePID) (count: \(payloads.count))")
    }

    private func triggerSneakPeek(for descriptor: AtollLiveActivityDescriptor, bundleIdentifier: String, config: AtollSneakPeekConfig) {
        let coordinator = DynamicIslandViewCoordinator.shared
        let duration = config.duration ?? 2.5
        let accentColor = descriptor.accentColor.swiftUIColor
        let styleOverride: SneakPeekStyle? = {
            guard let requestedStyle = config.style else { return nil }
            switch requestedStyle {
            case .inline:
                logDiagnostics("Inline sneak peek requested for \(descriptor.id); host will show standard mode instead")
                return .standard
            case .standard:
                return .standard
            }
        }()
        
        let resolvedTitle = descriptor.sneakPeekTitle?.isEmpty == false ? descriptor.sneakPeekTitle! : descriptor.title
        let resolvedSubtitle = descriptor.sneakPeekSubtitle ?? descriptor.subtitle ?? ""
        
        // Pass the activity's id and bundleID to the sneak peek so the specialized view can look up details if needed
        coordinator.toggleSneakPeek(
            status: true,
            type: .extensionLiveActivity(bundleID: bundleIdentifier, activityID: descriptor.id),
            duration: duration,
            value: 0,
            icon: "",
            title: resolvedTitle,
            subtitle: resolvedSubtitle,
            accentColor: accentColor,
            styleOverride: styleOverride
        )
        
        logDiagnostics("Triggered sneak peek for \(descriptor.id) from \(bundleIdentifier) with duration \(duration)s")
    }

    private func startMetricsTimer() {
        guard metricsTimer == nil else { return }
        guard Defaults[.enableAgentSpeedometer] else { return }
        guard !activeActivities.isEmpty else { return }
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
    }
    
    private func stopMetricsTimer() {
        metricsTimer?.invalidate()
        metricsTimer = nil
        currentSpeed = 0.0
    }
    
    private func updateMetrics() {
        guard Defaults[.enableAgentSpeedometer] else { return }
        let hasActiveThinking = activeActivities.contains { payload in
            let title = payload.descriptor.title.lowercased()
            let subtitle = payload.descriptor.subtitle?.lowercased() ?? ""
            return title.contains("working") || title.contains("thinking") || title.contains("executing") || title.contains("planning") || subtitle.contains("working") || subtitle.contains("thinking") || subtitle.contains("executing") || subtitle.contains("planning")
        }
        
        if hasActiveThinking {
            currentSpeed = Double.random(in: 32.0...54.0)
            currentCost += Double.random(in: 0.0008...0.0019)
        } else {
            currentSpeed = 0.0
            // Stop timer when no active activities need metrics
            if activeActivities.isEmpty {
                stopMetricsTimer()
            }
        }
    }
    
    private func playSoundForActivity(descriptor: AtollLiveActivityDescriptor) {
        guard Defaults[.enableAgentAudioCues] else { return }
        
        let title = descriptor.title.lowercased()
        let subtitle = descriptor.subtitle?.lowercased() ?? ""
        
        var soundName = "Pop"
        var isSuccess = false
        
        if title.contains("done") || title.contains("success") || title.contains("completed") || subtitle.contains("done") || subtitle.contains("success") || subtitle.contains("completed") {
            soundName = "Glass"
            isSuccess = true
        } else if title.contains("planning") || subtitle.contains("planning") || subtitle.contains("analyzing") {
            soundName = "Blow"
        } else if title.contains("thinking") || title.contains("working") || title.contains("executing") || subtitle.contains("thinking") || subtitle.contains("working") || subtitle.contains("executing") {
            soundName = "Hero"
        } else if title.contains("action") || title.contains("needs") || title.contains("waiting") || subtitle.contains("action") || subtitle.contains("needs") || subtitle.contains("waiting") {
            soundName = "Sosumi"
        }
        
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.volume = 0.4
            sound.play()
        }
        
        // Trackpad Haptic Feedback (satisfying haptic "click")
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        
        // Trigger particles on success
        if isSuccess {
            triggerParticleBurst = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.triggerParticleBurst = false
            }
        }
    }
    
    private func addToHistoryShelf(descriptor: AtollLiveActivityDescriptor, bundleIdentifier: String) {
        guard Defaults[.enableAgentHistoryShelf] else { return }
        
        let agentName: String = {
            if bundleIdentifier.contains("antigravity") { return "Antigravity" }
            if bundleIdentifier.contains("codex") { return "Codex" }
            if bundleIdentifier.contains("nerv") { return "NERV Brain" }
            if bundleIdentifier.contains("claude") { return "Claude" }
            if bundleIdentifier.contains("copilot") { return "Copilot" }
            if bundleIdentifier.contains("kilo") { return "Kilo" }
            return descriptor.title
        }()
        
        let colorHex: String = {
            let color = descriptor.accentColor
            return String(format: "#%02X%02X%02X", Int(color.red * 255), Int(color.green * 255), Int(color.blue * 255))
        }()
        
        let details = descriptor.subtitle ?? "Working..."
        
        let entry = AgentHistoryEntry(
            id: UUID(),
            timestamp: Date(),
            agentName: agentName,
            eventType: descriptor.title,
            details: details,
            statusColorHex: colorHex
        )
        
        historyShelf.insert(entry, at: 0)
        if historyShelf.count > 5 {
            historyShelf.removeLast()
        }
    }
    
    func handleAgentAction(approve: Bool, bundleIdentifier: String, activityID: String) {
        if Defaults[.enableAgentAudioCues] {
            let soundName = approve ? "Glass" : "Basso"
            NSSound(named: NSSound.Name(soundName))?.play()
            // Trackpad haptic click on approval/rejection
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }
        
        let interactionsFile = NSHomeDirectory() + "/Code/nerv/agent-hooks/interactions.json"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let data: [String: Any] = [
            "timestamp": timestamp,
            "bundleIdentifier": bundleIdentifier,
            "activityID": activityID,
            "action": approve ? "approved" : "rejected"
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) {
            try? jsonData.write(to: URL(fileURLWithPath: interactionsFile))
        }
        
        dismiss(activityID: activityID, bundleIdentifier: bundleIdentifier)
    }

    func rotateActivities() {
        guard activeActivities.count > 1 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            let first = activeActivities.removeFirst()
            activeActivities.append(first)
        }
        if Defaults[.enableAgentAudioCues] {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }
        broadcastSnapshot()
    }

    func togglePauseResume(bundleIdentifier: String, activityID: String) {
        if Defaults[.enableAgentAudioCues] {
            NSSound(named: NSSound.Name("Blow"))?.play()
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }
        
        let interactionsFile = NSHomeDirectory() + "/Code/nerv/agent-hooks/interactions.json"
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let data: [String: Any] = [
            "timestamp": timestamp,
            "bundleIdentifier": bundleIdentifier,
            "activityID": activityID,
            "action": "toggle_pause_resume"
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) {
            try? jsonData.write(to: URL(fileURLWithPath: interactionsFile))
        }
        
        Logger.log("Toggled pause/resume for agent \(activityID) from \(bundleIdentifier)", category: .extensions)
    }

    private func logDiagnostics(_ message: String) {
        guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
        Logger.log(message, category: .extensions)
    }
}
