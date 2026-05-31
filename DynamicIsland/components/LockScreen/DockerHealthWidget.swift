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

struct DockerHealthWidget: View {
    @ObservedObject private var manager = DockerHealthManager.shared
    @Default(.enableLockScreenDockerHealthWidget) private var enabled

    var body: some View {
        if enabled && !manager.containers.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                ForEach(manager.containers) { container in
                    Circle()
                        .fill(container.isRunning ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                }

                Text("\(manager.runningCount)/\(manager.containers.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(height: 20)
        }
    }
}
