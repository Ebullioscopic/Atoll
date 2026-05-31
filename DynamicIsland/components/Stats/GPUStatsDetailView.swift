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

struct GPUStatsDetailView: View {
    @ObservedObject private var statsManager = StatsManager.shared
    @State private var topProcesses: [ProcessStats] = []
    
    private let accentColor = Color.purple
    private let cardBackground = Color(nsColor: .windowBackgroundColor).opacity(0.65)
    private let processDisplayLimit = 8
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StatsCard(title: String(localized: "GPU Overview"), padding: 16, background: cardBackground, cornerRadius: 12) {
                    GPUUsageDashboard(
                        usage: statsManager.gpuUsage,
                        breakdown: statsManager.gpuBreakdown,
                        averageUsage: statsManager.avgGpuUsage,
                        lastUpdated: statsManager.lastUpdated,
                        accentColor: accentColor,
                        primaryDevice: statsManager.gpuDevices.first
                    )
                }
                
                StatsCard(title: String(localized: "Top Processes"), padding: 16, background: cardBackground, cornerRadius: 12) {
                    CPUProcessList(processes: topProcesses, accentColor: accentColor, displayLimit: processDisplayLimit)
                }

                if !statsManager.gpuDevices.isEmpty {
                    StatsCard(title: String(localized: "Devices"), padding: 16, background: cardBackground, cornerRadius: 12) {
                        GPUDeviceList(devices: statsManager.gpuDevices, accentColor: accentColor)
                    }
                }
            }
            .padding(16)
        }
        .frame(minWidth: 360, minHeight: 380)
        .onAppear(perform: refreshProcessesOnAppear)
        .onReceive(statsManager.objectWillChange) { _ in
            refreshProcesses()
        }
    }
    
    private func refreshProcesses() {
        let processes = statsManager.getProcessesRankedByGPU()
        topProcesses = Array(processes.prefix(processDisplayLimit))
    }
    
    private func refreshProcessesOnAppear() {
        statsManager.refreshProcessStatsNow()
        refreshProcesses()
    }
}

private struct GPUUsageDashboard: View {
    let usage: Double
    let breakdown: GPUBreakdown
    let averageUsage: Double
    let lastUpdated: Date
    let accentColor: Color
    let primaryDevice: GPUDeviceMetrics?
    
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                leftColumn
                breakdownAndMeta
            }
            VStack(alignment: .leading, spacing: 20) {
                leftColumn
                breakdownAndMeta
            }
        }
    }
    
    private func formattedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private var leftColumn: some View {
        GPUEngineGauges(
            usage: usage,
            render: renderEngineUtilization,
            tiler: tilerUtilization,
            accentColor: accentColor
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var breakdownAndMeta: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                breakdownSection
                metaSection
            }
            VStack(alignment: .leading, spacing: 16) {
                breakdownSection
                Divider().padding(.vertical, 4)
                metaSection
            }
        }
    }

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailRow(color: accentColor.opacity(0.9), label: String(localized: "Render"), value: StatsFormatting.percentage(breakdown.render))
            DetailRow(color: accentColor.opacity(0.7), label: String(localized: "Compute"), value: StatsFormatting.percentage(breakdown.compute))
            DetailRow(color: accentColor.opacity(0.55), label: String(localized: "Video"), value: StatsFormatting.percentage(breakdown.video))
            DetailRow(color: accentColor.opacity(0.45), label: String(localized: "Other"), value: StatsFormatting.percentage(breakdown.other))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Averages")
                .font(.caption)
                .foregroundColor(.secondary)
            DetailRow(color: nil, label: String(localized: "Session Avg"), value: StatsFormatting.percentage(averageUsage))
            DetailRow(color: nil, label: String(localized: "Last Update"), value: formattedTimestamp(lastUpdated))
            if let device = primaryDevice {
                Divider().padding(.vertical, 4)
                DetailRow(color: nil, label: String(localized: "Active GPU"), value: device.formattedVendorModel)
                DetailRow(color: nil, label: String(localized: "Status"), value: device.isActive ? String(localized: "Active") : String(localized: "Idle"))
                DetailRow(color: nil, label: String(localized: "Temperature"), value: device.temperatureText)
                if let cores = device.cores {
                    DetailRow(color: nil, label: String(localized: "Cores"), value: "\(cores)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var renderEngineUtilization: Double? {
        primaryDevice?.renderUtilization ?? breakdown.render
    }

    private var tilerUtilization: Double? {
        primaryDevice?.tilerUtilization
    }
}

private struct GPUEngineGauges: View {
    let usage: Double
    let render: Double?
    let tiler: Double?
    let accentColor: Color
    private let ringDiameter: CGFloat = 112
    private let ringLineWidth: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Engine Utilization")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(alignment: .center, spacing: 18) {
                EngineGaugeView(title: String(localized: "Render"), value: render, tint: accentColor, size: 72)
                GPUUsageRing(usage: usage, accentColor: accentColor, diameter: ringDiameter, lineWidth: ringLineWidth)
                EngineGaugeView(title: String(localized: "Tiler"), value: tiler, tint: accentColor.opacity(0.75), size: 72)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct GPUUsageRing: View {
    let usage: Double
    let accentColor: Color
    var diameter: CGFloat = 108
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(accentColor.opacity(0.25), lineWidth: lineWidth)
            RingArc(start: 0, end: CGFloat(min(max(usage / 100, 0), 1)), color: accentColor, lineWidth: lineWidth)
            VStack(spacing: 4) {
                Text(StatsFormatting.percentage(usage))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(String(localized: "stats_resource_active", defaultValue: "Active"))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct EngineGaugeView: View {
    let title: String
    let value: Double?
    let tint: Color
    var size: CGFloat = 68

    var body: some View {
        if let value {
            CircularGaugeView(
                title: title,
                value: min(max(value / 100, 0), 1),
                tint: tint,
                centerPrimaryText: StatsFormatting.percentage(value),
                centerSecondaryText: nil,
                subtitle: nil,
                size: size,
                lineWidth: 7,
                backgroundTint: tint.opacity(0.18)
            )
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 7)
                    .frame(width: size, height: size)
                Text("—")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct GPUDeviceList: View {
    let devices: [GPUDeviceMetrics]
    let accentColor: Color

    var body: some View {
        VStack(spacing: 16) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                GPUDeviceRow(device: device, accentColor: accentColor)
                if index < devices.count - 1 {
                    Divider()
                }
            }
        }
    }
}

private struct GPUDeviceRow: View {
    let device: GPUDeviceMetrics
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(device.isActive ? Color.green.opacity(0.85) : Color.red.opacity(0.7))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.formattedVendorModel)
                        .font(.system(size: 13, weight: .semibold))
                    Text(device.isActive ? String(localized: "stats_resource_active", defaultValue: "Active") : String(localized: "Idle"))
                        .font(.caption2)
                        .foregroundColor(device.isActive ? .green : .secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(device.utilizationText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(accentColor)
                    Text("Utilization")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            VStack(spacing: 8) {
                if let render = device.renderUtilization {
                    DetailRow(color: accentColor.opacity(0.9), label: String(localized: "Renderer"), value: StatsFormatting.percentage(render))
                }
                if let tiler = device.tilerUtilization {
                    DetailRow(color: accentColor.opacity(0.6), label: String(localized: "Tiler"), value: StatsFormatting.percentage(tiler))
                }
                if let temp = device.temperature {
                    DetailRow(color: nil, label: String(localized: "Temperature"), value: String(format: "%.0f°C", temp))
                }
                if let fan = device.fanSpeed {
                    DetailRow(color: nil, label: String(localized: "Fan Speed"), value: "\(fan)%")
                }
                if let coreClock = device.coreClock {
                    DetailRow(color: nil, label: String(localized: "Core Clock"), value: "\(coreClock) MHz")
                }
                if let memoryClock = device.memoryClock {
                    DetailRow(color: nil, label: String(localized: "Memory Clock"), value: "\(memoryClock) MHz")
                }
                if let cores = device.cores {
                    DetailRow(color: nil, label: String(localized: "Cores"), value: "\(cores)")
                }
            }
        }
    }
}
