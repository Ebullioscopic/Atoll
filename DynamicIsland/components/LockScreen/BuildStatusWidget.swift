/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI
import Defaults

struct BuildStatusWidget: View {
    @ObservedObject private var manager = BuildStatusManager.shared
    @Default(.enableLockScreenBuildStatusWidget) private var enabled

    @State private var animationPhase: Double = 0

    var body: some View {
        if enabled && manager.isBuildActive {
            HStack(spacing: 4) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.orange)
                    .symbolEffect(.pulse, isActive: true)

                Text("Building")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange)

                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            }
            .frame(height: 20)
        }
    }
}
