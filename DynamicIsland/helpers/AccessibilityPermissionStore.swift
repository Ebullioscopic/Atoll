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
import Combine
import AppKit
#if canImport(ApplicationServices)
import ApplicationServices
#endif

/// Tracks accessibility permission status and exposes helpers to request access.
@MainActor
final class AccessibilityPermissionStore: ObservableObject {
    static let shared = AccessibilityPermissionStore()

    @Published private(set) var isAuthorized: Bool = AccessibilityPermissionStore.isAccessibilityAuthorized()

    private var pollingTimer: Timer?

    private init() {
        // On macOS Tahoe (26.x), AXIsProcessTrusted() can return stale results
        // after the user toggles the permission. Start continuous polling to detect changes.
        startContinuousPolling()
    }

    deinit {
        pollingTimer?.invalidate()
    }

    func refreshStatus() {
        updateAuthorizationStatus(to: Self.isAccessibilityAuthorized())
    }

    func requestAuthorizationPrompt() {
#if canImport(ApplicationServices)
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
#endif
    }

    func openSystemSettings() {
#if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
#endif
    }

    private func startContinuousPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let status = Self.isAccessibilityAuthorized()
                if status != self.isAuthorized {
                    self.isAuthorized = status
                }
            }
        }
    }

    private func updateAuthorizationStatus(to newValue: Bool) {
        guard newValue != isAuthorized else { return }
        isAuthorized = newValue
    }

    private static func isAccessibilityAuthorized() -> Bool {
#if canImport(ApplicationServices)
        return AXIsProcessTrusted()
#else
        return true
#endif
    }
}
