/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import CodeIslandUI
import SwiftUI

/// The Atoll-owned notch route for the persistent Code Island tab.
struct NotchCodeIslandView: View {
    @ObservedObject private var host = CodeIslandHost.shared

    var body: some View {
        CodeIslandDashboardView(
            state: host.dashboardState,
            openSettings: {
                SettingsWindowController.shared.showWindow(destination: .codeIsland)
            }
        )
    }
}
