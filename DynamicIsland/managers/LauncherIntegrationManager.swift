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
import Foundation
import SwiftUI

/// Detected launcher application type
enum LauncherType: String, CaseIterable {
    case spotlight = "com.apple.Spotlight"
    case alfred = "com.runningwithcrayons.Alfred"
    case raycast = "com.raycast.macos"

    var displayName: String {
        switch self {
        case .spotlight: return "Spotlight"
        case .alfred: return "Alfred"
        case .raycast: return "Raycast"
        }
    }

    var iconName: String {
        switch self {
        case .spotlight: return "magnifyingglass"
        case .alfred: return "command"
        case .raycast: return "rays"
        }
    }
}

/// Monitors frontmost application changes and detects when a launcher
/// (Spotlight, Alfred, or Raycast) becomes active, publishing state for
/// the notch to expand and show a launcher backdrop view.
@MainActor
class LauncherIntegrationManager: ObservableObject {
    static let shared = LauncherIntegrationManager()

    @Published var isLauncherActive: Bool = false
    @Published var activeLauncher: LauncherType?

    private var cancellables = Set<AnyCancellable>()
    private var deactivationWorkItem: DispatchWorkItem?

    private static let launcherBundleIDs: Set<String> = Set(LauncherType.allCases.map(\.rawValue))

    private init() {
        setupObservers()
    }

    private func setupObservers() {
        // Observe frontmost application changes
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .compactMap { notification -> NSRunningApplication? in
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.handleAppActivation(app)
            }
            .store(in: &cancellables)

        // Observe app deactivation to dismiss launcher view
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didDeactivateApplicationNotification)
            .compactMap { notification -> NSRunningApplication? in
                notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.handleAppDeactivation(app)
            }
            .store(in: &cancellables)
    }

    private func handleAppActivation(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              Self.launcherBundleIDs.contains(bundleID),
              let launcherType = LauncherType(rawValue: bundleID) else {
            return
        }

        deactivationWorkItem?.cancel()
        deactivationWorkItem = nil

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            self.activeLauncher = launcherType
            self.isLauncherActive = true
        }

        // Expand notch and switch to launcher view
        let coordinator = DynamicIslandViewCoordinator.shared
        coordinator.currentView = .launcher
    }

    private func handleAppDeactivation(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              Self.launcherBundleIDs.contains(bundleID) else {
            return
        }

        // Small delay to avoid flickering during launcher transitions
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.isLauncherActive = false
                self.activeLauncher = nil
            }

            let coordinator = DynamicIslandViewCoordinator.shared
            if coordinator.currentView == .launcher {
                coordinator.currentView = .home
            }
        }
        deactivationWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }
}
