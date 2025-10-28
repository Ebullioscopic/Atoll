//
//  CPUStatsSharedViews.swift
//  DynamicIsland
//
//  Shared CPU stats UI components reused across the notch stats tab
//  and the legacy stats panel.
//
//  Created by GitHub Copilot on 19/10/2025.
//

import SwiftUI

struct StatsCard<Content: View>: View {
    let title: String
    let padding: CGFloat
    let background: Color
    let cornerRadius: CGFloat
    let content: Content

    init(
        title: String,
        padding: CGFloat = 16,
        background: Color = Color(nsColor: .windowBackgroundColor).opacity(0.65),
        cornerRadius: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.padding = padding
        self.background = background
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
    }
}

struct CPUUsageDashboard: View {
    let breakdown: CPULoadBreakdown
    let loadAverage: LoadAverage
    let uptime: TimeInterval
    let coreCount: Int
    let systemColor: Color
    let userColor: Color
    let idleColor: Color
    let temperature: CPUTemperatureMetrics
    let frequency: CPUFrequencyMetrics?

    var body: some View {
        let usageSection = VStack(alignment: .leading, spacing: 12) {
            Text("Usage")
                .font(.caption)
                .foregroundColor(.secondary)
            DetailRow(color: systemColor.opacity(0.95), label: "System", value: StatsFormatting.percentage(breakdown.system))
            DetailRow(color: userColor.opacity(0.95), label: "User", value: StatsFormatting.percentage(breakdown.user))
            DetailRow(color: idleColor.opacity(0.7), label: "Idle", value: StatsFormatting.percentage(breakdown.idle))
            DetailRow(color: nil, label: "Active", value: StatsFormatting.percentage(breakdown.activeUsage))
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        let systemSection = VStack(alignment: .leading, spacing: 10) {
            Text("System")
                .font(.caption)
                .foregroundColor(.secondary)
            DetailRow(color: nil, label: "Logical cores", value: "\(max(coreCount, 1))")
            DetailRow(color: nil, label: "Uptime", value: StatsFormatting.abbreviatedDuration(uptime))
            Divider().padding(.vertical, 4)
            DetailRow(color: nil, label: "Load 1m", value: String(format: "%.2f", loadAverage.oneMinute))
            DetailRow(color: nil, label: "Load 5m", value: String(format: "%.2f", loadAverage.fiveMinutes))
            DetailRow(color: nil, label: "Load 15m", value: String(format: "%.2f", loadAverage.fifteenMinutes))
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        let primaryGauges = CPUSensorGaugeGroup(
            breakdown: breakdown,
            temperature: temperature,
            frequency: frequency,
            systemColor: systemColor,
            userColor: userColor,
            idleColor: idleColor,
            usageTint: userColor,
            temperatureTint: Color(red: 0.98, green: 0.53, blue: 0.18)
        )
        .frame(maxWidth: .infinity, alignment: .center)

        return ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: 20) {
                primaryGauges
                usageSection
                Divider().padding(.vertical, 4)
                systemSection
            }
            HStack(alignment: .top, spacing: 28) {
                primaryGauges
                    .frame(maxWidth: .infinity, alignment: .center)
                usageSection
                    .frame(maxWidth: .infinity, alignment: .leading)
                systemSection
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct CPUSensorGaugeGroup: View {
    let breakdown: CPULoadBreakdown
    let temperature: CPUTemperatureMetrics
    let frequency: CPUFrequencyMetrics?
    let systemColor: Color
    let userColor: Color
    let idleColor: Color
    let usageTint: Color
    let temperatureTint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            CPUTemperatureGauge(temperature: temperature.celsius, tint: temperatureTint, size: 78, lineWidth: 8)
                .frame(maxWidth: .infinity)
            CPUSegmentDonut(
                breakdown: breakdown,
                systemColor: systemColor,
                userColor: userColor,
                idleColor: idleColor,
                diameter: 118,
                lineWidth: 13
            )
            .frame(width: 118, height: 118)
            .frame(maxWidth: .infinity)
            CPUFrequencyGauge(frequency: frequency, tint: usageTint, size: 78, lineWidth: 8)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct CPUTemperatureGauge: View {
    let temperature: Double?
    let tint: Color
    var size: CGFloat = 84
    var lineWidth: CGFloat = 9
    private let maxTemperature: Double = 110

    var body: some View {
        CircularGaugeView(
            title: "Temperature",
            value: normalizedValue,
            tint: tint,
            centerPrimaryText: centerPrimary,
            subtitle: nil,
            size: size,
            lineWidth: lineWidth
        )
    }

    private var normalizedValue: Double {
        guard let temperature, maxTemperature > 0 else { return 0 }
        return min(max(temperature / maxTemperature, 0), 1)
    }

    private var centerPrimary: String {
        guard let temperature else { return "—" }
        return String(format: "%.0f°", temperature)
    }
}

private struct CPUFrequencyGauge: View {
    let frequency: CPUFrequencyMetrics?
    let tint: Color
    var size: CGFloat = 84
    var lineWidth: CGFloat = 9

    var body: some View {
        CircularGaugeView(
            title: "Frequency",
            value: normalizedValue,
            tint: tint,
            centerPrimaryText: centerPrimary,
            centerSecondaryText: frequency != nil ? "GHz" : nil,
            subtitle: subtitle,
            size: size,
            lineWidth: lineWidth
        )
    }

    private var normalizedValue: Double {
        guard let frequency else { return 0 }
        let candidateMax = frequency.maxOverallGHz > 0 ? frequency.maxOverallGHz : frequency.overallGHz
        let denominator = max(candidateMax, 1.0)
        return min(max(frequency.overallGHz / denominator, 0), 1)
    }

    private var centerPrimary: String {
        guard let frequency else { return "—" }
        return String(format: "%.1f", frequency.overallGHz)
    }

    private var subtitle: String? {
        guard let frequency else { return nil }
        var components: [String] = []
        if let eValue = frequency.eCoreGHz {
            components.append("E \(String(format: "%.1f", eValue))")
        }
        if let pValue = frequency.pCoreGHz {
            components.append("P \(String(format: "%.1f", pValue))")
        }
        return components.isEmpty ? nil : components.joined(separator: " • ")
    }
}

private struct CPUSegmentDonut: View {
    let breakdown: CPULoadBreakdown
    let systemColor: Color
    let userColor: Color
    let idleColor: Color
    var diameter: CGFloat = 132
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(idleColor.opacity(0.3), lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)
            CPUUsageRing(
                breakdown: breakdown,
                systemColor: systemColor,
                userColor: userColor,
                lineWidth: lineWidth
            )
            .frame(width: diameter, height: diameter)
            VStack(spacing: 4) {
                Text(StatsFormatting.percentage(breakdown.activeUsage))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Active")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct CPUUsageRing: View {
    let breakdown: CPULoadBreakdown
    let systemColor: Color
    let userColor: Color
    var lineWidth: CGFloat = 14

    var body: some View {
        let segments = breakdown.normalizedSegments
        ZStack {
            if segments.system > 0 {
                RingArc(start: 0, end: segments.system, color: systemColor, lineWidth: lineWidth)
            }
            if segments.user > 0 {
                RingArc(start: segments.system, end: segments.system + segments.user, color: userColor, lineWidth: lineWidth)
            }
        }
    }
}

struct RingArc: View {
    let start: Double
    let end: Double
    let color: Color
    var lineWidth: CGFloat = 14

    var body: some View {
        Circle()
            .trim(from: CGFloat(start), to: CGFloat(end))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
    }
}

struct LegendRow: View {
    let color: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

struct LoadAverageRow: View {
    let loadAverage: LoadAverage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Load Average")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                LoadAverageValue(label: "1m", value: loadAverage.oneMinute)
                LoadAverageValue(label: "5m", value: loadAverage.fiveMinutes)
                LoadAverageValue(label: "15m", value: loadAverage.fifteenMinutes)
            }
        }
    }
}

struct LoadAverageValue: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "%.2f", value))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}

struct DetailRow: View {
    let color: Color?
    let label: String
    let value: String

    var body: some View {
        HStack {
            if let color {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .layoutPriority(0.5)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
        }
    }
}

struct CPUCoreUsageGrid: View {
    let cores: [CPUCoreUsage]
    let accentColor: Color

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 90), spacing: 14, alignment: .top)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(cores) { core in
                CPUCoreUsageCell(core: core, accentColor: accentColor)
            }
        }
    }
}

private struct CPUCoreUsageCell: View {
    let core: CPUCoreUsage
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Core \(core.id + 1)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(StatsFormatting.percentage(core.usage))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(accentColor)
            }
            GeometryReader { proxy in
                let width = proxy.size.width
                let progress = max(0, min(core.usage / 100, 1))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(accentColor)
                        .frame(width: width * progress)
                }
            }
            .frame(height: 8)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
    }
}

struct CPUDetailsGrid: View {
    let breakdown: CPULoadBreakdown
    let loadAverage: LoadAverage
    let uptime: TimeInterval
    let coreCount: Int
    let systemColor: Color
    let userColor: Color
    var showLoadAverage: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Usage Breakdown")
                    .font(.caption)
                    .foregroundColor(.secondary)
                DetailRow(color: nil, label: "Total", value: StatsFormatting.percentage(breakdown.activeUsage))
                DetailRow(color: systemColor, label: "System", value: StatsFormatting.percentage(breakdown.system))
                DetailRow(color: userColor, label: "User", value: StatsFormatting.percentage(breakdown.user))
                DetailRow(color: Color.gray.opacity(0.4), label: "Idle", value: StatsFormatting.percentage(breakdown.idle))
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("System")
                    .font(.caption)
                    .foregroundColor(.secondary)
                DetailRow(color: nil, label: "Logical cores", value: "\(max(coreCount, 1))")
                DetailRow(color: nil, label: "Uptime", value: StatsFormatting.abbreviatedDuration(uptime))
            }

            if showLoadAverage {
                Divider().padding(.vertical, 4)
                LoadAverageRow(loadAverage: loadAverage)
            }
        }
    }
}

struct CPUProcessList: View {
    let processes: [ProcessStats]
    let accentColor: Color
    var displayLimit: Int? = nil
    @State var orderBy: OrderBy = .cpuUsage

    private var visibleProcesses: [ProcessStats] {
        // processes ordered by selected order
        let sorted = processes.sorted(by: {
            switch orderBy {
                case .cpuUsage:
                    return $0.cpuUsage > $1.cpuUsage
                case .mbExact:
                    return $0.memoryUsage > $1.memoryUsage
            }
        })

        // limit
        if let limit = displayLimit {
            return Array(sorted.prefix(limit))
        }

        return sorted
    }

    var body: some View {
        VStack(spacing: 8) {
            // order by picker
            Picker("Order by", selection: $orderBy) {
                Text("Memory Usage").tag(OrderBy.mbExact)
                Text("CPU Usage").tag(OrderBy.cpuUsage)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.vertical, 16)

            // processes
            if visibleProcesses.isEmpty {
                Text("No process data yet. Keep stats open for a moment.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // order processes by mb or %
                ForEach(visibleProcesses) { process in
                    CPUProcessRow(process: process, accentColor: accentColor)
                    if process.id != visibleProcesses.last?.id {
                        Divider().padding(.leading, 32)
                    }
                }
            }
        }
    }
}

struct CPUProcessRow: View {
    let process: ProcessStats
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            iconView
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(process.memoryUsageString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(process.cpuUsageString)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(accentColor)
        }
    }

    private var iconView: some View {
        Group {
            if let icon = process.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    accentColor.opacity(0.15)
                    Image(systemName: "app")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(accentColor)
                }
            }
        }
    }
}
