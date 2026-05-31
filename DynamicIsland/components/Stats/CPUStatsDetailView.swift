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

struct CPUStatsDetailView: View {
    @ObservedObject private var statsManager = StatsManager.shared
    @State private var topProcesses: [ProcessStats] = []
    
    private let systemColor = Color(red: 0.94, green: 0.32, blue: 0.28)
    private let userColor = Color(red: 0.27, green: 0.52, blue: 0.97)
    private let idleColor = Color.gray.opacity(0.28)
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StatsCard(title: String(localized: "CPU Overview")) {
                    CPUUsageDashboard(
                        breakdown: statsManager.cpuBreakdown,
                        loadAverage: statsManager.cpuLoadAverage,
                        uptime: statsManager.cpuUptime,
                        coreCount: statsManager.cpuCoreUsage.count,
                        systemColor: systemColor,
                        userColor: userColor,
                        idleColor: idleColor,
                        temperature: statsManager.cpuTemperature,
                        frequency: statsManager.cpuFrequency
                    )
                }

                StatsCard(title: String(localized: "Top Processes")) {
                    CPUProcessList(processes: topProcesses, accentColor: userColor)
                }
                
                if !statsManager.cpuCoreUsage.isEmpty {
                    StatsCard(title: String(localized: "Per-Core Usage")) {
                        CPUCoreUsageGrid(cores: statsManager.cpuCoreUsage, accentColor: userColor)
                    }
                }
            }
            .padding(16)
        }
        .onReceive(statsManager.$topCPUProcesses) { processes in
            topProcesses = Array(processes.prefix(8))
        }
        .onAppear {
            statsManager.refreshProcessStatsNow()
            topProcesses = Array(statsManager.topCPUProcesses.prefix(8))
        }
    }
}
