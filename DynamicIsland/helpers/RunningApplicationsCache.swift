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
import os

/// Bundle identifiers of the running apps, kept current by observing
/// `NSWorkspace.runningApplications`.
///
/// Scanning `runningApplications` and reading each app's `bundleIdentifier`
/// round-trips to launchservicesd, and "is Music running?" is asked from
/// SwiftUI bodies and playback updates — on the main thread, during notch
/// animations. This answers from memory and only rescans when the list changes.
final class RunningApplicationsCache: @unchecked Sendable {
    static let shared = RunningApplicationsCache()

    private let bundleIdentifiers: OSAllocatedUnfairLock<Set<String>>
    private var observation: NSKeyValueObservation?

    private init() {
        bundleIdentifiers = OSAllocatedUnfairLock(initialState: Self.currentBundleIdentifiers())
        observation = NSWorkspace.shared.observe(\.runningApplications, options: []) { [weak self] _, _ in
            let identifiers = Self.currentBundleIdentifiers()
            self?.bundleIdentifiers.withLock { $0 = identifiers }
        }
    }

    func isRunning(_ bundleIdentifier: String) -> Bool {
        bundleIdentifiers.withLock { $0.contains(bundleIdentifier) }
    }

    private static func currentBundleIdentifiers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
