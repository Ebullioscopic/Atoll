//
//  StatsPanelView.swift
//  DynamicIsland
//
//  Created by Ebullioscopic on 13/08/25.
//

import SwiftUI
import Defaults

struct StatsPanelView: View {
    let onClose: () -> Void
    @ObservedObject var statsManager = StatsManager.shared
    @Default(.enableStatsFeature) var enableStatsFeature
    @State private var selectedTimeRange: TimeRange = .last30
    @State private var refreshTimer: Timer?
    
    enum TimeRange: String, CaseIterable {
        case last30 = "Last 30 sec"
        case last60 = "Last 1 min"
        case last300 = "Last 5 min"
        
        var dataPoints: Int {
            switch self {
            case .last30: return 30
            case .last60: return 60
            case .last300: return 300
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            StatsPanelHeader(
                selectedTimeRange: $selectedTimeRange,
                onClose: onClose
            )
            
            Divider()
            
            // Main content
            if !enableStatsFeature {
                // Disabled state
                VStack(spacing: 16) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Stats Feature Disabled")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Enable system stats monitoring in Settings to view detailed performance data.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button("Open Settings") {
                        // TODO: Add settings navigation
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Stats content - Compact two-row layout
                VStack(spacing: 16) {
                    // Top row: System overview cards
                    HStack(spacing: 12) {
                        CompactOverviewCard(
                            title: "CPU",
                            value: statsManager.cpuUsageString,
                            color: .blue,
                            icon: "cpu",
                            data: statsManager.cpuHistory
                        )
                        
                        CompactOverviewCard(
                            title: "Memory",
                            value: statsManager.memoryUsageString,
                            color: .green,
                            icon: "memorychip",
                            data: statsManager.memoryHistory
                        )
                        
                        CompactOverviewCard(
                            title: "GPU",
                            value: statsManager.gpuUsageString,
                            color: .purple,
                            icon: "display",
                            data: statsManager.gpuHistory
                        )
                    }
                    
                    // Bottom row: Network and Disk graphs
                    HStack(spacing: 12) {
                        CompactDualGraph(
                            title: "Network",
                            primaryLabel: "Down",
                            primaryValue: "\(String(format: "%.1f", statsManager.networkDownload / 1024 / 1024)) MB/s",
                            primaryData: statsManager.networkDownloadHistory,
                            primaryColor: .green,
                            secondaryLabel: "Up",
                            secondaryValue: "\(String(format: "%.1f", statsManager.networkUpload / 1024 / 1024)) MB/s",
                            secondaryData: statsManager.networkUploadHistory,
                            secondaryColor: .orange
                        )
                        
                        CompactDualGraph(
                            title: "Disk",
                            primaryLabel: "Read",
                            primaryValue: "\(String(format: "%.1f", statsManager.diskRead / 1024 / 1024)) MB/s",
                            primaryData: statsManager.diskReadHistory,
                            primaryColor: .cyan,
                            secondaryLabel: "Write",
                            secondaryValue: "\(String(format: "%.1f", statsManager.diskWrite / 1024 / 1024)) MB/s",
                            secondaryData: statsManager.diskWriteHistory,
                            secondaryColor: .pink
                        )
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 650, height: 300)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
        .onAppear {
            // Note: Smart monitoring will handle starting/stopping based on UI state
        }
    }
}

// MARK: - Header Component
struct StatsPanelHeader: View {
    @Binding var selectedTimeRange: StatsPanelView.TimeRange
    let onClose: () -> Void
    @ObservedObject var statsManager = StatsManager.shared
    
    var body: some View {
        HStack {
            // Title and status
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.blue)
                    .font(.system(size: 18, weight: .medium))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Performance Monitor")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Circle()
                            .fill(statsManager.isMonitoring ? .green : .red)
                            .frame(width: 6, height: 6)
                        
                        Text(statsManager.isMonitoring ? "Live Monitoring" : "Monitoring Stopped")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if statsManager.isMonitoring {
                            Text("• Updated \(formatLastUpdated(statsManager.lastUpdated))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: 12) {
                // Time range picker
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(StatsPanelView.TimeRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                
                // Monitoring controls
                if statsManager.isMonitoring {
                    Button("Stop") {
                        statsManager.stopMonitoring()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                } else {
                    Button("Start") {
                        statsManager.startMonitoring()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Button("Clear") {
                    statsManager.clearHistory()
                }
                .buttonStyle(.bordered)
                .disabled(statsManager.isMonitoring)
                
                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    private func formatLastUpdated(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Section Container
struct StatsPanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            content
                .padding(16)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
        }
    }
}

// MARK: - System Overview
struct SystemOverviewGrid: View {
    @ObservedObject var statsManager = StatsManager.shared
    
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
            OverviewCard(
                title: "CPU",
                value: statsManager.cpuUsageString,
                color: .blue,
                icon: "cpu"
            )
            
            OverviewCard(
                title: "Memory",
                value: statsManager.memoryUsageString,
                color: .green,
                icon: "memorychip"
            )
            
            OverviewCard(
                title: "GPU",
                value: statsManager.gpuUsageString,
                color: .purple,
                icon: "display"
            )
        }
    }
}

struct OverviewCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .frame(height: 80)
    }
}

// MARK: - Detailed Views (Placeholder implementations)
struct DetailedCPUView: View {
    let timeRange: StatsPanelView.TimeRange
    @ObservedObject var statsManager = StatsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Large timeline graph
            DetailedTimelineGraph(
                data: statsManager.cpuHistory,
                color: .blue,
                title: "CPU Usage Over Time",
                unit: "%",
                timeRange: timeRange
            )
            
            // CPU details
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                DetailMetricCard(title: "Current", value: statsManager.cpuUsageString, color: .blue)
                DetailMetricCard(title: "Average", value: String(format: "%.1f%%", statsManager.avgCpuUsage), color: .blue)
                DetailMetricCard(title: "Peak", value: String(format: "%.1f%%", statsManager.maxCpuUsage), color: .blue)
            }
        }
    }
}

struct DetailedMemoryView: View {
    let timeRange: StatsPanelView.TimeRange
    @ObservedObject var statsManager = StatsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailedTimelineGraph(
                data: statsManager.memoryHistory,
                color: .green,
                title: "Memory Usage Over Time",
                unit: "%",
                timeRange: timeRange
            )
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                DetailMetricCard(title: "Current", value: statsManager.memoryUsageString, color: .green)
                DetailMetricCard(title: "Average", value: String(format: "%.1f%%", statsManager.avgMemoryUsage), color: .green)
                DetailMetricCard(title: "Peak", value: String(format: "%.1f%%", statsManager.maxMemoryUsage), color: .green)
            }
        }
    }
}

struct DetailedNetworkView: View {
    let timeRange: StatsPanelView.TimeRange
    @ObservedObject var statsManager = StatsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DualTimelineGraph(
                positiveData: statsManager.networkDownloadHistory,
                negativeData: statsManager.networkUploadHistory,
                positiveColor: .orange,
                negativeColor: .red,
                title: "Network Activity Over Time",
                positiveLabel: "Download",
                negativeLabel: "Upload",
                unit: "MB/s",
                timeRange: timeRange
            )
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                DetailMetricCard(title: "Download", value: statsManager.networkDownloadString, color: .orange)
                DetailMetricCard(title: "Upload", value: statsManager.networkUploadString, color: .red)
            }
        }
    }
}

struct DetailedDiskView: View {
    let timeRange: StatsPanelView.TimeRange
    @ObservedObject var statsManager = StatsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DualTimelineGraph(
                positiveData: statsManager.diskReadHistory,
                negativeData: statsManager.diskWriteHistory,
                positiveColor: .cyan,
                negativeColor: .yellow,
                title: "Disk Activity Over Time",
                positiveLabel: "Read",
                negativeLabel: "Write",
                unit: "MB/s",
                timeRange: timeRange
            )
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                DetailMetricCard(title: "Read", value: statsManager.diskReadString, color: .cyan)
                DetailMetricCard(title: "Write", value: statsManager.diskWriteString, color: .yellow)
            }
        }
    }
}

struct DetailMetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(6)
    }
}

// MARK: - Enhanced Graph Components
struct DetailedTimelineGraph: View {
    let data: [Double]
    let color: Color
    let title: String
    let unit: String
    let timeRange: StatsPanelView.TimeRange
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            GeometryReader { geometry in
                let maxValue = data.max() ?? 1.0
                let normalizedData = maxValue > 0 ? data.map { $0 / maxValue } : data
                
                ZStack {
                    // Grid lines
                    Path { path in
                        let horizontalLines = 5
                        for i in 0...horizontalLines {
                            let y = geometry.size.height * CGFloat(i) / CGFloat(horizontalLines)
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                        }
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                    
                    // Data line
                    Path { path in
                        guard !normalizedData.isEmpty else { return }
                        
                        let stepX = geometry.size.width / CGFloat(max(1, normalizedData.count - 1))
                        
                        for (index, value) in normalizedData.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = geometry.size.height * (1 - CGFloat(value))
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(color, lineWidth: 2)
                    
                    // Fill area
                    Path { path in
                        guard !normalizedData.isEmpty else { return }
                        
                        let stepX = geometry.size.width / CGFloat(max(1, normalizedData.count - 1))
                        
                        path.move(to: CGPoint(x: 0, y: geometry.size.height))
                        
                        for (index, value) in normalizedData.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = geometry.size.height * (1 - CGFloat(value))
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [color.opacity(0.3), color.opacity(0.1)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .frame(height: 120)
        }
    }
}

struct DualTimelineGraph: View {
    let positiveData: [Double]
    let negativeData: [Double]
    let positiveColor: Color
    let negativeColor: Color
    let title: String
    let positiveLabel: String
    let negativeLabel: String
    let unit: String
    let timeRange: StatsPanelView.TimeRange
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(positiveColor)
                            .frame(width: 8, height: 8)
                        Text(positiveLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(negativeColor)
                            .frame(width: 8, height: 8)
                        Text(negativeLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            GeometryReader { geometry in
                let maxPositive = positiveData.max() ?? 1.0
                let maxNegative = negativeData.max() ?? 1.0
                let maxValue = max(maxPositive, maxNegative)
                
                let normalizedPositive = maxValue > 0 ? positiveData.map { $0 / maxValue } : positiveData
                let normalizedNegative = maxValue > 0 ? negativeData.map { $0 / maxValue } : negativeData
                
                let centerY = geometry.size.height / 2
                
                ZStack {
                    // Center line
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: centerY))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: centerY))
                    }
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    
                    // Positive line and fill
                    Path { path in
                        guard !normalizedPositive.isEmpty else { return }
                        
                        let stepX = geometry.size.width / CGFloat(max(1, normalizedPositive.count - 1))
                        
                        for (index, value) in normalizedPositive.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = centerY - (centerY * CGFloat(value))
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(positiveColor, lineWidth: 2)
                    
                    // Negative line and fill
                    Path { path in
                        guard !normalizedNegative.isEmpty else { return }
                        
                        let stepX = geometry.size.width / CGFloat(max(1, normalizedNegative.count - 1))
                        
                        for (index, value) in normalizedNegative.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = centerY + (centerY * CGFloat(value))
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(negativeColor, lineWidth: 2)
                }
            }
            .frame(height: 120)
        }
    }
}

// MARK: - Compact Components for Two-Row Layout

struct CompactOverviewCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String
    let data: [Double]
    
    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            }
            
            // Mini graph
            CompactGraph(data: data, color: color)
                .frame(height: 40)
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .frame(height: 80)
    }
}

struct CompactGraph: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else { return }
            
            let maxValue = data.max() ?? 1.0
            let path = Path { path in
                let dataToUse = Array(data.suffix(30)) // Last 30 points
                let stepX = size.width / CGFloat(max(1, dataToUse.count - 1))
                
                for (index, value) in dataToUse.enumerated() {
                    let x = CGFloat(index) * stepX
                    let normalizedValue = maxValue > 0 ? min(value / maxValue, 1.0) : 0
                    let y = size.height - (CGFloat(normalizedValue) * size.height)
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            
            // Fill area
            let fillPath = Path { fillPath in
                let dataToUse = Array(data.suffix(30))
                let stepX = size.width / CGFloat(max(1, dataToUse.count - 1))
                
                fillPath.move(to: CGPoint(x: 0, y: size.height))
                
                for (index, value) in dataToUse.enumerated() {
                    let x = CGFloat(index) * stepX
                    let normalizedValue = maxValue > 0 ? min(value / maxValue, 1.0) : 0
                    let y = size.height - (CGFloat(normalizedValue) * size.height)
                    
                    if index == 0 {
                        fillPath.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        fillPath.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                
                if !dataToUse.isEmpty {
                    fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                }
                fillPath.closeSubpath()
            }
            
            context.fill(
                fillPath,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.3), color.opacity(0.1), Color.clear]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            
            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
    }
}

struct CompactDualGraph: View {
    let title: String
    let primaryLabel: String
    let primaryValue: String
    let primaryData: [Double]
    let primaryColor: Color
    let secondaryLabel: String
    let secondaryValue: String
    let secondaryData: [Double]
    let secondaryColor: Color
    
    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            // Legend and values
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(primaryColor)
                        .frame(width: 6, height: 6)
                    Text(primaryLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(primaryValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(primaryColor)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(secondaryColor)
                        .frame(width: 6, height: 6)
                    Text(secondaryLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(secondaryValue)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(secondaryColor)
                }
            }
            
            // Dual graph
            CompactDualLineGraph(
                primaryData: primaryData,
                primaryColor: primaryColor,
                secondaryData: secondaryData,
                secondaryColor: secondaryColor
            )
            .frame(height: 50)
        }
        .padding(12)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
        .frame(height: 100)
    }
}

struct CompactDualLineGraph: View {
    let primaryData: [Double]
    let primaryColor: Color
    let secondaryData: [Double]
    let secondaryColor: Color
    
    var body: some View {
        Canvas { context, size in
            let maxPrimary = primaryData.max() ?? 1.0
            let maxSecondary = secondaryData.max() ?? 1.0
            let maxValue = max(maxPrimary, maxSecondary)
            
            // Primary line
            if primaryData.count > 1 {
                let path = Path { path in
                    let dataToUse = Array(primaryData.suffix(30))
                    let stepX = size.width / CGFloat(max(1, dataToUse.count - 1))
                    
                    for (index, value) in dataToUse.enumerated() {
                        let x = CGFloat(index) * stepX
                        let normalizedValue = maxValue > 0 ? min(value / maxValue, 1.0) : 0
                        let y = size.height - (CGFloat(normalizedValue) * size.height)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                context.stroke(path, with: .color(primaryColor), lineWidth: 1.5)
            }
            
            // Secondary line
            if secondaryData.count > 1 {
                let path = Path { path in
                    let dataToUse = Array(secondaryData.suffix(30))
                    let stepX = size.width / CGFloat(max(1, dataToUse.count - 1))
                    
                    for (index, value) in dataToUse.enumerated() {
                        let x = CGFloat(index) * stepX
                        let normalizedValue = maxValue > 0 ? min(value / maxValue, 1.0) : 0
                        let y = size.height - (CGFloat(normalizedValue) * size.height)
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                context.stroke(path, with: .color(secondaryColor), lineWidth: 1.5)
            }
        }
    }
}

#Preview {
    StatsPanelView {
        print("Close panel")
    }
    .frame(width: 800, height: 600)
}
