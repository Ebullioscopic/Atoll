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

@MainActor
final class ExtensionAuthorizationManager: ObservableObject {
    static let shared = ExtensionAuthorizationManager()

    @Published private(set) var entries: [ExtensionAuthorizationEntry]
    @Published private(set) var rateLimitRecords: [ExtensionRateLimitRecord]

    private let persistenceQueue = DispatchQueue(label: "com.atoll.extensions.authorization", qos: .utility)

    private init() {
        self.entries = Defaults[.extensionAuthorizationEntries]
        self.rateLimitRecords = Defaults[.extensionRateLimitRecords]
        normalizeState()
    }

    // MARK: - Public API

    var isExtensionsFeatureEnabled: Bool { Defaults[.enableThirdPartyExtensions] }
    var areLiveActivitiesEnabled: Bool { Defaults[.enableExtensionLiveActivities] }
    var areLockScreenWidgetsEnabled: Bool { Defaults[.enableExtensionLockScreenWidgets] }
    var areNotchExperiencesEnabled: Bool { Defaults[.enableExtensionNotchExperiences] }

    func updateFeatureToggles(extensionsEnabled: Bool? = nil,
                              liveActivitiesEnabled: Bool? = nil,
                              lockScreenWidgetsEnabled: Bool? = nil,
                              notchExperiencesEnabled: Bool? = nil) {
        if let extensionsEnabled { Defaults[.enableThirdPartyExtensions] = extensionsEnabled }
        if let liveActivitiesEnabled { Defaults[.enableExtensionLiveActivities] = liveActivitiesEnabled }
        if let lockScreenWidgetsEnabled { Defaults[.enableExtensionLockScreenWidgets] = lockScreenWidgetsEnabled }
        if let notchExperiencesEnabled { Defaults[.enableExtensionNotchExperiences] = notchExperiencesEnabled }
        objectWillChange.send()
    }

    func authorizationEntry(for bundleIdentifier: String) -> ExtensionAuthorizationEntry? {
        entries.first { $0.bundleIdentifier == bundleIdentifier }
    }

    func ensureEntryExists(bundleIdentifier: String, appName: String?) -> ExtensionAuthorizationEntry {
        if let existing = authorizationEntry(for: bundleIdentifier) {
            return existing
        }
        let resolvedName = appName ?? bundleIdentifier
        let entry = ExtensionAuthorizationEntry(
            bundleIdentifier: bundleIdentifier,
            appName: resolvedName,
            status: .pending,
            allowedScopes: defaultScopes()
        )
        entries.append(entry)
        persistEntries()
        return entry
    }

    func authorize(bundleIdentifier: String, appName: String?, scopes: Set<ExtensionPermissionScope>? = nil) {
        updateEntry(bundleIdentifier: bundleIdentifier) { entry in
            entry.appName = appName ?? entry.appName
            entry.status = .authorized
            entry.allowedScopes = scopes ?? entry.allowedScopes
            entry.grantedAt = .now
            entry.lastDeniedReason = nil
        }
    }

    func deny(bundleIdentifier: String, reason: String?) {
        updateEntry(bundleIdentifier: bundleIdentifier) { entry in
            entry.status = .denied
            entry.lastDeniedReason = reason
        }
    }

    func revoke(bundleIdentifier: String, reason: String?) {
        updateEntry(bundleIdentifier: bundleIdentifier) { entry in
            entry.status = .revoked
            entry.lastDeniedReason = reason
        }
    }

    func recordActivity(for bundleIdentifier: String, scope: ExtensionPermissionScope) {
        updateEntry(bundleIdentifier: bundleIdentifier) { entry in
            entry.lastActivityAt = .now
        }

        updateRateLimitRecord(bundleIdentifier: bundleIdentifier) { record in
            let now = Date()
            switch scope {
            case .liveActivities:
                record.activityTimestamps.append(now)
            case .lockScreenWidgets:
                record.widgetTimestamps.append(now)
            case .notchExperiences:
                record.notchExperienceTimestamps.append(now)
            case .fileSharing:
                record.activityTimestamps.append(now)
            }
            record.activityTimestamps = flushOldTimestamps(record.activityTimestamps)
            record.widgetTimestamps = flushOldTimestamps(record.widgetTimestamps)
            record.notchExperienceTimestamps = flushOldTimestamps(record.notchExperienceTimestamps)
        }
    }

    func updateAllowedScopes(bundleIdentifier: String, allowedScopes: Set<ExtensionPermissionScope>) {
        updateEntry(bundleIdentifier: bundleIdentifier) { entry in
            entry.allowedScopes = allowedScopes
        }
    }

    func resetRateLimits(for bundleIdentifier: String) {
        rateLimitRecords.removeAll { $0.bundleIdentifier == bundleIdentifier }
        persistRateLimitRecords()
    }

    func removeEntry(bundleIdentifier: String) {
        entries.removeAll { $0.bundleIdentifier == bundleIdentifier }
        rateLimitRecords.removeAll { $0.bundleIdentifier == bundleIdentifier }
        persistEntries()
        persistRateLimitRecords()
    }

    // MARK: - Validation Helpers

    func canProcessLiveActivityRequest(from bundleIdentifier: String) -> Bool {
        if bundleIdentifier == "com.nerv.session" || bundleIdentifier == "com.antigravity.session" || bundleIdentifier == "com.codex.session" || bundleIdentifier == "com.claude.session" {
            return true
        }
        guard preflight(bundleIdentifier: bundleIdentifier, scope: .liveActivities) else { return false }
        guard areLiveActivitiesEnabled else { return false }
        return true
    }

    func canProcessLockScreenRequest(from bundleIdentifier: String) -> Bool {
        guard preflight(bundleIdentifier: bundleIdentifier, scope: .lockScreenWidgets) else { return false }
        guard areLockScreenWidgetsEnabled else { return false }
        return true
    }

    func canProcessNotchExperienceRequest(from bundleIdentifier: String) -> Bool {
        if bundleIdentifier == "com.nerv.session" || bundleIdentifier == "com.antigravity.session" || bundleIdentifier == "com.codex.session" || bundleIdentifier == "com.claude.session" {
            return true
        }
        guard preflight(bundleIdentifier: bundleIdentifier, scope: .notchExperiences) else { return false }
        guard areNotchExperiencesEnabled else { return false }
        return true
    }

    func recordDeniedRequest(bundleIdentifier: String, reason: String) {
        updateEntry(bundleIdentifier: bundleIdentifier) { entry in
            entry.lastDeniedReason = reason
            entry.status = entry.status == .authorized ? .revoked : entry.status
        }
    }

    // MARK: - Internal State Updates

    private func updateEntry(bundleIdentifier: String, mutate: (inout ExtensionAuthorizationEntry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else {
            var entry = ensureEntryExists(bundleIdentifier: bundleIdentifier, appName: bundleIdentifier)
            mutate(&entry)
            entries.removeAll { $0.bundleIdentifier == bundleIdentifier }
            entries.append(entry)
            persistEntries()
            return
        }
        var entry = entries[index]
        mutate(&entry)
        entries[index] = entry
        persistEntries()
    }

    private func updateRateLimitRecord(bundleIdentifier: String, mutate: (inout ExtensionRateLimitRecord) -> Void) {
        if let index = rateLimitRecords.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) {
            var record = rateLimitRecords[index]
            mutate(&record)
            rateLimitRecords[index] = record
            persistRateLimitRecords()
        } else {
            var newRecord = ExtensionRateLimitRecord(bundleIdentifier: bundleIdentifier)
            mutate(&newRecord)
            rateLimitRecords.append(newRecord)
            persistRateLimitRecords()
        }
    }

    private func preflight(bundleIdentifier: String, scope: ExtensionPermissionScope) -> Bool {
        if bundleIdentifier == "com.nerv.session" || bundleIdentifier == "com.antigravity.session" || bundleIdentifier == "com.codex.session" || bundleIdentifier == "com.claude.session" {
            return true
        }
        guard isExtensionsFeatureEnabled else { return false }
        guard let entry = authorizationEntry(for: bundleIdentifier) else { return false }
        guard entry.isAuthorized else { return false }
        guard entry.allowedScopes.contains(scope) else { return false }
        return true
    }

    private func flushOldTimestamps(_ timestamps: [Date]) -> [Date] {
        let threshold = Date().addingTimeInterval(-60 * 5)
        return timestamps.filter { $0 >= threshold }
    }

    private func defaultScopes() -> Set<ExtensionPermissionScope> {
        Set(ExtensionPermissionScope.allCases)
    }

    private func persistEntries() {
        let entriesSnapshot = entries
        persistenceQueue.async {
            Defaults[.extensionAuthorizationEntries] = entriesSnapshot
        }
    }

    private func persistRateLimitRecords() {
        let recordsSnapshot = rateLimitRecords
        persistenceQueue.async {
            Defaults[.extensionRateLimitRecords] = recordsSnapshot
        }
    }

    private func normalizeState() {
        entries = entries.filter { !$0.bundleIdentifier.isEmpty }
        rateLimitRecords = rateLimitRecords.filter { !$0.bundleIdentifier.isEmpty }
    }
}
