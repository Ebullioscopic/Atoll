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
import Foundation

/// Exports and imports Atoll's settings as a JSON snapshot of the app's
/// `UserDefaults` domain. Every key is included unless it matches the denylist,
/// so settings added later are covered automatically. Secrets kept in the
/// Keychain are never read; legacy plaintext copies in defaults are denylisted.
enum SettingsPorter {

    static let formatIdentifier = "com.ebullioscopic.atoll.settings"
    static let currentVersion = 1

    enum PorterError: LocalizedError {
        case notASettingsFile
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notASettingsFile:
                return String(localized: "The file is not an Atoll settings backup.")
            case .unsupportedVersion:
                return String(localized: "This settings file was created by a newer version of Atoll. Update Atoll and try again.")
            }
        }
    }

    // MARK: - Denylist

    /// Exact keys that hold user data, device-specific identifiers, permission grants or app state.
    private static let deniedKeys: Set<String> = [
        "ClipboardHistory", "ClipboardPinnedItems", "ColorPickerHistory", "ScreenAssistantFiles",
        "savedNotes", "customTimerSoundPath", "customAppIcons", "selectedAppIconID",
        "calendarSelectionState", "selectedCameraID", "localSendSelectedDeviceID",
        "extensionAuthorizationEntries", "extensionRateLimitRecords",
        "appleNotesLastSyncDate", "newAPIAccounts", "firstLaunch", "LastVersionRun", "releaseName",
    ]

    /// System/framework state (window frames, panels, Sparkle), migration flags and caches.
    private static let deniedPrefixes = [
        "NS", "Apple", "com.apple.", "SU", "did", "hasSeen", "hasShown", "hasLaunched", "hasCompleted",
        "cached", "legacy",
    ]

    /// Case-insensitive fragments for secrets, accounts, caches and window positions.
    private static let deniedFragments = [
        "apikey", "token", "secret", "password", "cookie", "credential", "oauth", "account", "auth",
        "clientid", "cache", "panelposition", "lastsync", "lastvalidated",
    ]

    static func isPortable(_ key: String) -> Bool {
        if deniedKeys.contains(key) { return false }
        if deniedPrefixes.contains(where: key.hasPrefix) { return false }
        let lowered = key.lowercased()
        return !deniedFragments.contains(where: lowered.contains)
    }

    private static var domainName: String {
        Bundle.main.bundleIdentifier ?? "com.ebullioscopic.atoll"
    }

    // MARK: - Export

    static func exportData(defaults: UserDefaults = .standard) throws -> Data {
        let domain = defaults.persistentDomain(forName: domainName) ?? [:]
        var settings: [String: Any] = [:]
        for (key, value) in domain where isPortable(key) {
            settings[key] = encode(value)
        }
        let file: [String: Any] = [
            "format": formatIdentifier,
            "version": currentVersion,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "settings": settings,
        ]
        return try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Import

    /// Parses and validates a backup without applying it. Returns the portable settings it contains.
    static func validate(_ data: Data) throws -> [String: Any] {
        guard let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              file["format"] as? String == formatIdentifier,
              let version = file["version"] as? Int, version >= 1,
              let rawSettings = file["settings"] as? [String: Any]
        else {
            throw PorterError.notASettingsFile
        }
        guard version <= currentVersion else {
            throw PorterError.unsupportedVersion(version)
        }
        var settings: [String: Any] = [:]
        for (key, raw) in rawSettings where isPortable(key) {
            if let value = decode(raw),
               PropertyListSerialization.propertyList(value, isValidFor: .binary) {
                settings[key] = value
            }
        }
        return settings
    }

    /// Replaces the current portable settings with the backup's. Portable keys missing from
    /// the backup are reset to their defaults; denylisted keys are left untouched.
    @MainActor
    static func apply(_ settings: [String: Any], defaults: UserDefaults = .standard) {
        let current = defaults.persistentDomain(forName: domainName) ?? [:]
        for key in current.keys where isPortable(key) && settings[key] == nil {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in settings {
            defaults.set(value, forKey: key)
        }
    }

    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error {
                Logger.log("[SettingsPorter] Relaunch failed: \(error.localizedDescription)", category: .error)
                return
            }
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }

    // MARK: - JSON <-> property list

    // JSON has no date or data type, so those values are wrapped in single-key tagged objects.
    private static let dataTag = "$data"
    private static let dateTag = "$date"

    private static func encode(_ value: Any) -> Any {
        switch value {
        case let data as Data:
            return [dataTag: data.base64EncodedString()]
        case let date as Date:
            return [dateTag: ISO8601DateFormatter().string(from: date)]
        case let array as [Any]:
            return array.map(encode)
        case let dictionary as [String: Any]:
            return dictionary.mapValues(encode)
        default:
            return value
        }
    }

    private static func decode(_ value: Any) -> Any? {
        switch value {
        case is NSNull:
            return nil
        case let dictionary as [String: Any]:
            if dictionary.count == 1, let base64 = dictionary[dataTag] as? String {
                return Data(base64Encoded: base64)
            }
            if dictionary.count == 1, let string = dictionary[dateTag] as? String {
                return ISO8601DateFormatter().date(from: string)
            }
            return dictionary.compactMapValues(decode)
        case let array as [Any]:
            return array.compactMap(decode)
        default:
            return value
        }
    }
}
