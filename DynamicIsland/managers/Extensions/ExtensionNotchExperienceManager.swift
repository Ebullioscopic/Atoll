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
final class ExtensionNotchExperienceManager: ObservableObject {
    static let shared = ExtensionNotchExperienceManager()

    @Published private(set) var activeExperiences: [ExtensionNotchExperiencePayload] = []

    private let authorizationManager = ExtensionAuthorizationManager.shared
    private let maxCapacityKey = Defaults.Keys.extensionNotchExperienceCapacity
    private let eventBridge = ExtensionEventBridge.shared
    private var observerToken: NSObjectProtocol?
    private var suppressBroadcast = false
    private let currentProcessID = ProcessInfo.processInfo.processIdentifier

    private init() {
        // Drop persisted experiences whose owning extension app is no longer
        // running — restoring them produces ghost tabs that nothing can
        // dismiss (the extension that would re-present or dismiss is dead).
        activeExperiences = eventBridge.loadPersistedNotchExperiences().filter { payload in
            !NSRunningApplication.runningApplications(
                withBundleIdentifier: payload.bundleIdentifier
            ).isEmpty
        }
        sortExperiences()
        observerToken = eventBridge.observeNotchExperienceSnapshots { [weak self] payloads, sourcePID in
            self?.applySnapshot(payloads, sourcePID: sourcePID)
        }
    }

    deinit {
        if let observerToken {
            eventBridge.removeObserver(observerToken)
        }
    }

    // MARK: - Presentation Lifecycle

    func present(descriptor: AtollNotchExperienceDescriptor, bundleIdentifier: String) throws {
        guard authorizationManager.canProcessNotchExperienceRequest(from: bundleIdentifier) else {
            logDiagnostics("Rejected notch experience \(descriptor.id) from \(bundleIdentifier): scope disabled or bundle unauthorized")
            throw ExtensionValidationError.unauthorized
        }
        guard descriptor.bundleIdentifier == bundleIdentifier else {
            logDiagnostics("Rejected notch experience \(descriptor.id) from \(bundleIdentifier): bundle mismatch (descriptor: \(descriptor.bundleIdentifier))")
            throw ExtensionValidationError.invalidDescriptor("Bundle identifier mismatch")
        }

        try ExtensionDescriptorValidator.validate(descriptor)
        try ensureWebContentSupport(for: descriptor)

        let isUpdate: Bool
        if let index = activeExperiences.firstIndex(where: { $0.descriptor.id == descriptor.id && $0.bundleIdentifier == bundleIdentifier }) {
            let payload = ExtensionNotchExperiencePayload(
                bundleIdentifier: bundleIdentifier,
                descriptor: descriptor,
                receivedAt: activeExperiences[index].receivedAt
            )
            activeExperiences[index] = payload
            sortExperiences()
            isUpdate = true
            Logger.log("Replaced notch experience \(descriptor.id) for \(bundleIdentifier)", category: .extensions)
        } else {
            guard activeExperiences.count < Defaults[maxCapacityKey] else {
                logDiagnostics("Rejected notch experience \(descriptor.id) from \(bundleIdentifier): capacity limit \(Defaults[maxCapacityKey]) reached")
                throw ExtensionValidationError.exceedsCapacity
            }

            let payload = ExtensionNotchExperiencePayload(
                bundleIdentifier: bundleIdentifier,
                descriptor: descriptor,
                receivedAt: .now
            )
            activeExperiences.append(payload)
            sortExperiences()
            isUpdate = false
            logDiagnostics("Queued notch experience \(descriptor.id) for \(bundleIdentifier); total experiences: \(activeExperiences.count)")
        }

        authorizationManager.recordActivity(for: bundleIdentifier, scope: .notchExperiences)
        broadcastSnapshot()

        if let tabConfig = descriptor.tab, Defaults[.enableExtensionNotchTabs] {
            Logger.log("Notch experience tab ready (title: \(tabConfig.title))", category: .extensions)
        }

        if descriptor.minimalistic != nil && Defaults[.enableExtensionNotchMinimalisticOverrides] {
            Logger.log("Notch experience minimalistic override available", category: .extensions)
        }

        if !isUpdate {
            logDiagnostics("Stored notch experience \(descriptor.id) for \(bundleIdentifier); priority \(descriptor.priority.rawValue)")
        }
    }

    func update(descriptor: AtollNotchExperienceDescriptor, bundleIdentifier: String) throws {
        try ExtensionDescriptorValidator.validate(descriptor)
        guard descriptor.bundleIdentifier == bundleIdentifier else {
            logDiagnostics("Rejected notch experience update \(descriptor.id) from \(bundleIdentifier): bundle mismatch (descriptor: \(descriptor.bundleIdentifier))")
            throw ExtensionValidationError.invalidDescriptor("Bundle identifier mismatch")
        }
        guard let index = activeExperiences.firstIndex(where: { $0.descriptor.id == descriptor.id && $0.bundleIdentifier == bundleIdentifier }) else {
            throw ExtensionValidationError.invalidDescriptor("Missing existing notch experience")
        }
        try ensureWebContentSupport(for: descriptor)
        let payload = ExtensionNotchExperiencePayload(
            bundleIdentifier: bundleIdentifier,
            descriptor: descriptor,
            receivedAt: activeExperiences[index].receivedAt
        )
        activeExperiences[index] = payload
        sortExperiences()
        authorizationManager.recordActivity(for: bundleIdentifier, scope: .notchExperiences)
        logDiagnostics("Updated notch experience \(descriptor.id) for \(bundleIdentifier)")
        broadcastSnapshot()
    }

    func dismiss(experienceID: String, bundleIdentifier: String) {
        let previousCount = activeExperiences.count
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            activeExperiences.removeAll { $0.descriptor.id == experienceID && $0.bundleIdentifier == bundleIdentifier }
        }
        guard previousCount != activeExperiences.count else { return }
        Logger.log("Dismissed notch experience \(experienceID) from \(bundleIdentifier)", category: .extensions)
        ExtensionXPCServiceHost.shared.notifyNotchExperienceDismiss(bundleIdentifier: bundleIdentifier, experienceID: experienceID)
        ExtensionRPCServer.shared.notifyNotchExperienceDismiss(bundleIdentifier: bundleIdentifier, experienceID: experienceID)
        logDiagnostics("Removed notch experience \(experienceID) for \(bundleIdentifier); remaining: \(activeExperiences.count)")
        broadcastSnapshot()
    }

    func dismissAll(for bundleIdentifier: String) {
        let ids = activeExperiences
            .filter { $0.bundleIdentifier == bundleIdentifier }
            .map { $0.descriptor.id }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            activeExperiences.removeAll { $0.bundleIdentifier == bundleIdentifier }
        }
        ids.forEach {
            ExtensionXPCServiceHost.shared.notifyNotchExperienceDismiss(bundleIdentifier: bundleIdentifier, experienceID: $0)
            ExtensionRPCServer.shared.notifyNotchExperienceDismiss(bundleIdentifier: bundleIdentifier, experienceID: $0)
        }
        if !ids.isEmpty {
            logDiagnostics("Removed all notch experiences for \(bundleIdentifier); ids: \(ids.joined(separator: ", "))")
            broadcastSnapshot()
        }
    }

    // MARK: - Presentation Resolution

    func highestPriorityTabPayload() -> ExtensionNotchExperiencePayload? {
        guard Defaults[.enableThirdPartyExtensions],
              Defaults[.enableExtensionNotchExperiences],
              Defaults[.enableExtensionNotchTabs] else {
            return nil
        }
        return activeExperiences.first(where: { $0.descriptor.tab != nil })
    }

    func minimalisticReplacementPayload() -> ExtensionNotchExperiencePayload? {
        guard Defaults[.enableThirdPartyExtensions],
              Defaults[.enableExtensionNotchExperiences],
              Defaults[.enableExtensionNotchMinimalisticOverrides] else {
            return nil
        }
        return activeExperiences.first(where: { $0.descriptor.minimalistic != nil })
    }

    func payload(bundleIdentifier: String, experienceID: String) -> ExtensionNotchExperiencePayload? {
        activeExperiences.first { $0.bundleIdentifier == bundleIdentifier && $0.descriptor.id == experienceID }
    }

    func payload(experienceID: String) -> ExtensionNotchExperiencePayload? {
        activeExperiences.first { $0.descriptor.id == experienceID }
    }

    // MARK: - Snapshot Sync

    private func sortExperiences() {
        activeExperiences.sort(by: descriptorComparator)
    }

    private func descriptorComparator(lhs: ExtensionNotchExperiencePayload, rhs: ExtensionNotchExperiencePayload) -> Bool {
        if lhs.priority == rhs.priority {
            return lhs.receivedAt < rhs.receivedAt
        }
        return lhs.priority > rhs.priority
    }

    private func broadcastSnapshot() {
        guard !suppressBroadcast else { return }
        eventBridge.broadcastNotchExperienceSnapshot(activeExperiences)
        logDiagnostics("Broadcasted notch experience snapshot (count: \(activeExperiences.count))")
    }

    private func applySnapshot(_ payloads: [ExtensionNotchExperiencePayload], sourcePID: Int32) {
        guard sourcePID != currentProcessID else { return }
        suppressBroadcast = true
        activeExperiences = payloads.sorted(by: descriptorComparator)
        suppressBroadcast = false
        logDiagnostics("Applied external notch experience snapshot from PID \(sourcePID) (count: \(payloads.count))")
    }

    private func ensureWebContentSupport(for descriptor: AtollNotchExperienceDescriptor) throws {
        guard descriptor.hasWebContent else { return }
        guard Defaults[.enableExtensionNotchInteractiveWebViews] else {
            logDiagnostics("Rejected notch experience \(descriptor.id) due to web content while interactive web views are disabled")
            throw ExtensionValidationError.unsupportedContent
        }
    }

    private func logDiagnostics(_ message: String) {
        guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
        Logger.log(message, category: .extensions)
    }
}

private extension AtollNotchExperienceDescriptor {
    var hasWebContent: Bool {
        if tab?.webContent != nil { return true }
        if minimalistic?.webContent != nil { return true }
        return false
    }
}
