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

@MainActor
final class ExtensionLiveActivityManager: ObservableObject {
    static let shared = ExtensionLiveActivityManager()

    @Published private(set) var activeActivities: [ExtensionLiveActivityPayload] = []

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
    }

    deinit {
        if let token = liveActivityObserver {
            eventBridge.removeObserver(token)
        }
    }

    /// Registers an Atoll-owned activity directly in the host. Built-in sources
    /// bypass third-party authorization and are never written to the extension
    /// transport snapshot.
    func presentBuiltIn(descriptor: AtollLiveActivityDescriptor, bundleIdentifier: String) throws {
        guard CodexPresentationConstants.isBuiltInCodex(bundleIdentifier: bundleIdentifier),
              descriptor.isValid else {
            throw ExtensionValidationError.invalidDescriptor("Invalid built-in activity")
        }

        let isUpdate: Bool
        if let index = activeActivities.firstIndex(where: {
            $0.descriptor.id == descriptor.id && $0.bundleIdentifier == bundleIdentifier
        }) {
            activeActivities[index] = ExtensionLiveActivityPayload(
                bundleIdentifier: bundleIdentifier,
                descriptor: descriptor,
                receivedAt: activeActivities[index].receivedAt
            )
            isUpdate = true
        } else {
            activeActivities.append(
                ExtensionLiveActivityPayload(
                    bundleIdentifier: bundleIdentifier,
                    descriptor: descriptor,
                    receivedAt: .now
                )
            )
            isUpdate = false
        }
        sortActivities()

        let config = descriptor.sneakPeekConfig ?? .default
        if config.enabled && (!isUpdate || config.showOnUpdate) {
            triggerSneakPeek(for: descriptor, bundleIdentifier: bundleIdentifier, config: config)
        }
    }

    func dismissBuiltIn(activityID: String, bundleIdentifier: String) {
        guard CodexPresentationConstants.isBuiltInCodex(bundleIdentifier: bundleIdentifier) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            activeActivities.removeAll {
                $0.descriptor.id == activityID && $0.bundleIdentifier == bundleIdentifier
            }
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
            authorizationManager.recordActivity(for: bundleIdentifier, scope: .liveActivities)
            logDiagnostics("Queued live activity \(descriptor.id) for \(bundleIdentifier); total activities: \(activeActivities.count)")
            isUpdate = false
        }
        
        broadcastSnapshot()
        
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
        let externalActivities = activeActivities.filter {
            !CodexPresentationConstants.isBuiltInCodex(bundleIdentifier: $0.bundleIdentifier)
        }
        eventBridge.broadcastLiveActivitySnapshot(externalActivities)
        logDiagnostics("Broadcasted live activity snapshot (count: \(activeActivities.count))")
    }

    private func applySnapshot(_ payloads: [ExtensionLiveActivityPayload], sourcePID: Int32) {
        guard sourcePID != currentProcessID else { return }
        suppressBroadcast = true
        let builtInActivities = activeActivities.filter {
            CodexPresentationConstants.isBuiltInCodex(bundleIdentifier: $0.bundleIdentifier)
        }
        activeActivities = (payloads + builtInActivities).sorted(by: descriptorComparator)
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

    private func logDiagnostics(_ message: String) {
        guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
        Logger.log(message, category: .extensions)
    }
}
