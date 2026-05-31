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

import SwiftUI

/// A launcher-themed backdrop view displayed in the notch when Spotlight,
/// Alfred, or Raycast is active. Provides a visual search bar frame that
/// complements the launcher's own UI.
struct LauncherView: View {
    @ObservedObject private var launcherManager = LauncherIntegrationManager.shared

    var body: some View {
        HStack(spacing: 12) {
            // Search icon
            Image(systemName: launcherManager.activeLauncher?.iconName ?? "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            // Placeholder search bar
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .frame(height: 32)
                .overlay(
                    HStack(spacing: 8) {
                        Text(searchPlaceholder)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                )

            // Launcher badge
            if let launcher = launcherManager.activeLauncher {
                Text(launcher.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var searchPlaceholder: String {
        guard let launcher = launcherManager.activeLauncher else {
            return "Search..."
        }
        switch launcher {
        case .spotlight:
            return "Spotlight Search"
        case .alfred:
            return "Alfred"
        case .raycast:
            return "Raycast"
        }
    }
}
