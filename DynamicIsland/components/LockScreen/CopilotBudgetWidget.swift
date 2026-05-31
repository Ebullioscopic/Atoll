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

struct CopilotBudgetWidget: View {
    @ObservedObject private var manager = CopilotBudgetManager.shared
    @Default(.enableLockScreenCopilotBudgetWidget) private var enabled

    var body: some View {
        if enabled {
            HStack(spacing: 4) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.purple)

                Gauge(value: manager.usageFraction) {
                    EmptyView()
                }
                .gaugeStyle(.linearCapacity)
                .frame(width: 40, height: 6)
                .tint(.purple)

                Text("\(manager.premiumRemaining)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(height: 20)
        }
    }
}
