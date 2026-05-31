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

import Foundation
import Combine
import Defaults
import SwiftUI
import IOKit
import IOKit.ps
import IOKit.graphics
import Darwin
import AppKit
//import Network

struct MemoryBreakdown: Equatable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let freeBytes: UInt64
    let wiredBytes: UInt64
    let activeBytes: UInt64
    let inactiveBytes: UInt64
    let compressedBytes: UInt64
    let appBytes: UInt64
    let cacheBytes: UInt64
    let swap: MemorySwap
    let pressure: MemoryPressure
    
    static let zero = MemoryBreakdown(
        totalBytes: 0,
        usedBytes: 0,
        freeBytes: 0,
        wiredBytes: 0,
        activeBytes: 0,
        inactiveBytes: 0,
        compressedBytes: 0,
        appBytes: 0,
        cacheBytes: 0,
        swap: .zero,
        pressure: .unknown
    )
    
    var usedPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
    
    var freePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(freeBytes) / Double(totalBytes) * 100
    }
    
    var appPercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(appBytes) / Double(totalBytes) * 100
    }
    
    var cachePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(cacheBytes) / Double(totalBytes) * 100
    }
}

struct MemorySwap: Equatable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let freeBytes: UInt64
    
    static let zero = MemorySwap(totalBytes: 0, usedBytes: 0, freeBytes: 0)
}

enum MemoryPressureLevel: String, Equatable {
    case normal
    case warning
    case critical
}

struct MemoryPressure: Equatable {
    let rawValue: Int
    let level: MemoryPressureLevel
    
    static let unknown = MemoryPressure(rawValue: 0, level: .normal)
}

struct CPUCoreUsage: Identifiable, Equatable {
    let id: Int
    let usage: Double
}

// MARK: - GPU Helpers

private final class GPUInfoCollector {
    func collectDevices() -> [GPUDeviceMetrics] {
        var devices: [GPUDeviceMetrics] = []
        let matching = IOServiceMatching(kIOAcceleratorClassName)
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return devices
        }
        defer { IOObjectRelease(iterator) }
        var index = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let properties = copyProperties(for: service),
               let device = makeDevice(from: properties, index: index) {
                devices.append(device)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
            index += 1
        }
        return devices
    }

    private func copyProperties(for service: io_registry_entry_t) -> [String: Any]? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dict
    }

    private func makeDevice(from dict: [String: Any], index: Int) -> GPUDeviceMetrics? {
        guard let ioClass = dict["IOClass"] as? String else { return nil }
        let stats = dict["PerformanceStatistics"] as? [String: Any] ?? [:]
        let vendor = vendorName(from: ioClass) ?? (dict["vendor"] as? String)
        let model = sanitizedModel(primary: stats["model"] as? String,
                                   secondary: dict["model"] as? String,
                                   vendorFallback: vendor)
        let id = "\(model)#\(index + 1)"
        let utilization = percentValue(for: ["Device Utilization %", "GPU Activity(%)"], in: stats)
        let renderUtilization = percentValue(for: ["Renderer Utilization %"], in: stats)
        let tilerUtilization = percentValue(for: ["Tiler Utilization %"], in: stats)
        let temperature = numericValue(for: ["Temperature(C)", "temperature"], in: stats)
        let fanSpeed = intValue(for: ["Fan Speed(%)"], in: stats)
        let coreClock = intValue(for: ["Core Clock(MHz)"], in: stats)
        let memoryClock = intValue(for: ["Memory Clock(MHz)"], in: stats)
        let cores = (dict["gpu-core-count"] as? NSNumber)?.intValue ?? (dict["Cores"] as? Int)
        let isActive = isAcceleratorActive(from: dict)
        return GPUDeviceMetrics(
            id: id,
            vendor: vendor,
            model: model,
            isActive: isActive,
            utilization: utilization,
            renderUtilization: renderUtilization,
            tilerUtilization: tilerUtilization,
            temperature: temperature,
            fanSpeed: fanSpeed,
            coreClock: coreClock,
            memoryClock: memoryClock,
            cores: cores
        )
    }

    private func vendorName(from ioClass: String) -> String? {
        let value = ioClass.lowercased()
        if value.contains("nvidia") {
            return "NVIDIA"
        } else if value.contains("amd") {
            return "AMD"
        } else if value.contains("intel") {
            return "Intel"
        } else if value.contains("agx") || value.contains("apple") {
            return "Apple"
        }
        return nil
    }

    private func sanitizedModel(primary: String?, secondary: String?, vendorFallback: String?) -> String {
        let normalizedPrimary = normalizedString(primary)
        if let normalizedPrimary, !normalizedPrimary.isEmpty {
            return normalizedPrimary
        }
        let normalizedSecondary = normalizedString(secondary)
        if let normalizedSecondary, !normalizedSecondary.isEmpty {
            return normalizedSecondary
        }
        if let vendorFallback, !vendorFallback.isEmpty {
            return "\(vendorFallback) Graphics"
        }
        return "GPU"
    }

    private func normalizedString(_ raw: String?) -> String? {
        guard var value = raw else { return nil }
        value = value.replacingOccurrences(of: "\0", with: "")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func percentValue(for keys: [String], in dict: [String: Any]) -> Double? {
        for key in keys {
            if let number = dict[key] as? NSNumber {
                return clampPercent(number.doubleValue)
            }
            if let value = dict[key] as? Double {
                return clampPercent(value)
            }
            if let value = dict[key] as? Int {
                return clampPercent(Double(value))
            }
        }
        return nil
    }

    private func numericValue(for keys: [String], in dict: [String: Any]) -> Double? {
        for key in keys {
            if let number = dict[key] as? NSNumber {
                return number.doubleValue
            }
            if let value = dict[key] as? Double {
                return value
            }
            if let value = dict[key] as? Int {
                return Double(value)
            }
        }
        return nil
    }

    private func intValue(for keys: [String], in dict: [String: Any]) -> Int? {
        for key in keys {
            if let number = dict[key] as? NSNumber {
                return number.intValue
            }
            if let value = dict[key] as? Int {
                return value
            }
        }
        return nil
    }

    private func isAcceleratorActive(from dict: [String: Any]) -> Bool {
        guard let agcInfo = dict["AGCInfo"] as? [String: Any] else {
            return true
        }
        if let poweredOff = agcInfo["poweredOffByAGC"] as? NSNumber {
            return poweredOff.intValue == 0
        }
        if let poweredOff = agcInfo["poweredOffByAGC"] as? Int {
            return poweredOff == 0
        }
        return true
    }

    private func clampPercent(_ value: Double) -> Double {
        return min(max(value, 0), 100)
    }
}

struct GPUBreakdown: Equatable {
    let render: Double
    let compute: Double
    let video: Double
    let other: Double
    
    static let zero = GPUBreakdown(render: 0, compute: 0, video: 0, other: 0)
    
    var totalUsage: Double {
        render + compute + video + other
    }
}

struct GPUMetricsSnapshot {
    let usage: Double
    let breakdown: GPUBreakdown
    let devices: [GPUDeviceMetrics]

    static let zero = GPUMetricsSnapshot(usage: 0, breakdown: .zero, devices: [])
}

enum NetworkInterfaceType: String {
    case wifi
    case ethernet
    case loopback
    case cellular
    case other
}

struct NetworkInterfaceMetrics: Identifiable, Equatable {
    let name: String
    let displayName: String
    let type: NetworkInterfaceType
    let ipv4: String?
    let ipv6: String?
    let isActive: Bool
    let currentDownload: Double
    let currentUpload: Double
    let totalDownloaded: Double
    let totalUploaded: Double
    
    var id: String { name }
}

struct DiskDeviceMetrics: Identifiable, Equatable {
    let id: String
    let name: String
    let path: URL
    let totalBytes: UInt64
    let freeBytes: UInt64
    let isRoot: Bool
    let isRemovable: Bool
    
    var usedBytes: UInt64 {
        totalBytes > freeBytes ? totalBytes - freeBytes : 0
    }
    
    var usagePercentage: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
}

struct GPUDeviceMetrics: Identifiable, Equatable {
    let id: String
    let vendor: String?
    let model: String
    let isActive: Bool
    let utilization: Double?
    let renderUtilization: Double?
    let tilerUtilization: Double?
    let temperature: Double?
    let fanSpeed: Int?
    let coreClock: Int?
    let memoryClock: Int?
    let cores: Int?

    var formattedVendorModel: String {
        if let vendor {
            return vendor == model ? model : "\(vendor) \(model)".trimmingCharacters(in: .whitespaces)
        }
        return model
    }

    var utilizationText: String {
        guard let utilization else { return "—" }
        return StatsFormatting.percentage(utilization)
    }

    var temperatureText: String {
        guard let temperature else { return "—" }
        return String(format: "%.0f°C", temperature)
    }
}

struct NetworkTotals: Equatable {
    var downloadedMB: Double
    var uploadedMB: Double
    
    static let zero = NetworkTotals(downloadedMB: 0, uploadedMB: 0)
}

struct DiskTotals: Equatable {
    var readMB: Double
    var writtenMB: Double
    
    static let zero = DiskTotals(readMB: 0, writtenMB: 0)
}

class StatsManager: ObservableObject {
    private struct PublishedStatsSnapshot: Equatable {
        var cpuUsage: Double = 0.0
        var memoryUsage: Double = 0.0
        var gpuUsage: Double = 0.0
        var networkDownload: Double = 0.0
        var networkUpload: Double = 0.0
        var diskRead: Double = 0.0
        var diskWrite: Double = 0.0
        var lastUpdated: Date = .distantPast
        var cpuBreakdown: CPULoadBreakdown = .zero
        var cpuLoadAverage: LoadAverage = .zero
        var cpuCoreUsage: [CPUCoreUsage] = []
        var cpuUptime: TimeInterval = 0
        var cpuTemperature: CPUTemperatureMetrics = CPUTemperatureMetrics(celsius: nil)
        var cpuFrequency: CPUFrequencyMetrics?
        var memoryBreakdown: MemoryBreakdown = .zero
        var gpuBreakdown: GPUBreakdown = .zero
        var gpuDevices: [GPUDeviceMetrics] = []
        var networkTotals: NetworkTotals = .zero
        var diskTotals: DiskTotals = .zero
        var networkInterfaces: [NetworkInterfaceMetrics] = []
        var diskDevices: [DiskDeviceMetrics] = []
        var cpuHistory: [Double]
        var memoryHistory: [Double]
        var gpuHistory: [Double]
        var networkDownloadHistory: [Double]
        var networkUploadHistory: [Double]
        var diskReadHistory: [Double]
        var diskWriteHistory: [Double]
        
        static func initial(historyCount: Int) -> PublishedStatsSnapshot {
            let history = Array(repeating: 0.0, count: historyCount)
            return PublishedStatsSnapshot(
                cpuHistory: history,
                memoryHistory: history,
                gpuHistory: history,
                networkDownloadHistory: history,
                networkUploadHistory: history,
                diskReadHistory: history,
                diskWriteHistory: history
            )
        }
    }
    
    private struct StatsCollectionResult {
        let snapshot: PublishedStatsSnapshot
        let previousNetworkStats: (bytesIn: UInt64, bytesOut: UInt64)
        let previousDiskStats: (bytesRead: UInt64, bytesWritten: UInt64)
        let previousTimestamp: Date
    }
    
    // MARK: - Properties
    static let shared = StatsManager()
    
    @Published var isMonitoring: Bool = false
    @Published private var publishedStats = PublishedStatsSnapshot.initial(historyCount: 30)
    @Published private(set) var topCPUProcesses: [ProcessStats] = []
    
    var cpuUsage: Double { publishedStats.cpuUsage }
    var memoryUsage: Double { publishedStats.memoryUsage }
    var gpuUsage: Double { publishedStats.gpuUsage }
    var networkDownload: Double { publishedStats.networkDownload }
    var networkUpload: Double { publishedStats.networkUpload }
    var diskRead: Double { publishedStats.diskRead }
    var diskWrite: Double { publishedStats.diskWrite }
    var lastUpdated: Date { publishedStats.lastUpdated }
    var cpuBreakdown: CPULoadBreakdown { publishedStats.cpuBreakdown }
    var cpuLoadAverage: LoadAverage { publishedStats.cpuLoadAverage }
    var cpuCoreUsage: [CPUCoreUsage] { publishedStats.cpuCoreUsage }
    var cpuUptime: TimeInterval { publishedStats.cpuUptime }
    var cpuTemperature: CPUTemperatureMetrics { publishedStats.cpuTemperature }
    var cpuFrequency: CPUFrequencyMetrics? { publishedStats.cpuFrequency }
    var memoryBreakdown: MemoryBreakdown { publishedStats.memoryBreakdown }
    var gpuBreakdown: GPUBreakdown { publishedStats.gpuBreakdown }
    var gpuDevices: [GPUDeviceMetrics] { publishedStats.gpuDevices }
    var networkTotals: NetworkTotals { publishedStats.networkTotals }
    var diskTotals: DiskTotals { publishedStats.diskTotals }
    var networkInterfaces: [NetworkInterfaceMetrics] { publishedStats.networkInterfaces }
    var diskDevices: [DiskDeviceMetrics] { publishedStats.diskDevices }
    var cpuHistory: [Double] { publishedStats.cpuHistory }
    var memoryHistory: [Double] { publishedStats.memoryHistory }
    var gpuHistory: [Double] { publishedStats.gpuHistory }
    var networkDownloadHistory: [Double] { publishedStats.networkDownloadHistory }
    var networkUploadHistory: [Double] { publishedStats.networkUploadHistory }
    var diskReadHistory: [Double] { publishedStats.diskReadHistory }
    var diskWriteHistory: [Double] { publishedStats.diskWriteHistory }
    
    private var monitoringTimer: Timer?
    private var delayedStopTimer: Timer?
    private var delayedStartTimer: Timer?
    private let maxHistoryPoints = 30
    private let backgroundStatsCollection = true
    private let respectProcessCacheOnTick = true
    private let statsCollectionQueue = DispatchQueue(label: "DynamicIsland.StatsManager.Collection", qos: .utility)
    private var isStatsCollectionInFlight = false
    /// Cached host port to avoid leaking Mach send rights.
    /// Every call to `mach_host_self()` acquires a new send right that must be
    /// explicitly deallocated; caching it once prevents port exhaustion over time.
    private let hostPort: mach_port_t = mach_host_self()
    private let totalPhysicalMemory: UInt64 = {
        var stats = host_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let initHostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_info(initHostPort, HOST_BASIC_INFO, $0, &count)
            }
        }
        mach_port_deallocate(mach_task_self_, initHostPort)
        if result == KERN_SUCCESS {
            return UInt64(stats.max_mem)
        }
        return UInt64(ProcessInfo.processInfo.physicalMemory)
    }()
    
    // Smart monitoring state
    private var shouldMonitorForStats: Bool = false
    private var lastNotchState: String = "closed"
    private var lastCurrentView: String = "other"
    
    // Network monitoring state
    private var previousNetworkStats: (bytesIn: UInt64, bytesOut: UInt64) = (0, 0)
    private var previousTimestamp: Date = Date()
    
    // Disk monitoring state  
    private var previousDiskStats: (bytesRead: UInt64, bytesWritten: UInt64) = (0, 0)
    private var previousCPULoadInfo: host_cpu_load_info?
    private var previousCpuInfo: processor_info_array_t?
    private var previousCpuInfoCount: mach_msg_type_number_t = 0
    private var processorCount: natural_t = 0
    private var previousInterfaceCounters: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var interfaceTotals: [String: NetworkTotals] = [:]
    
    // Per-process monitoring cache (updated via ps sampling)
    private var cachedProcessStats: [ProcessStats] = []
    private var lastProcessStatsUpdate: Date = .distantPast
    private let processStatsUpdateInterval: TimeInterval = 2.0
    private let maxProcessEntries: Int = 20
    private var isProcessRefreshInFlight = false
    private let gpuCollector = GPUInfoCollector()
    private let cpuSensorCollector = CPUSensorCollector()
    private var cancellables = Set<AnyCancellable>()
    private let minUpdateInterval: TimeInterval = 1.0
    private let maxUpdateInterval: TimeInterval = 60.0
    private let notchCloseStopDelay: TimeInterval = 3.0
    private let tabSwitchStopDelay: TimeInterval = 0.1
    
    // MARK: - Initialization
    private init() {
        publishedStats = PublishedStatsSnapshot.initial(historyCount: maxHistoryPoints)
        
        // Initialize baseline network stats
        let initialStats = getNetworkStats()
        previousNetworkStats = initialStats
        previousTimestamp = Date()
        
        // Initialize baseline disk stats
        let initialDiskStats = getDiskStats()
        previousDiskStats = initialDiskStats

        Defaults.publisher(.statsUpdateInterval, options: []).sink { [weak self] change in
            self?.handleUpdateIntervalChange(change.newValue)
        }.store(in: &cancellables)

        Defaults.publisher(.statsStopWhenNotchCloses, options: []).sink { [weak self] change in
            guard let self else { return }

            if change.newValue {
                if self.isMonitoring && self.lastNotchState == "closed" {
                    self.scheduleDelayedStop(after: self.notchCloseStopDelay)
                }
            } else {
                self.delayedStopTimer?.invalidate()
                self.delayedStopTimer = nil
            }
        }.store(in: &cancellables)
    }
    
    deinit {
        stopMonitoring()
        delayedStartTimer?.invalidate()
        delayedStopTimer?.invalidate()
    }
    
    // MARK: - Smart Monitoring
    func updateMonitoringState(notchIsOpen: Bool, currentView: String) {
        let notchState = notchIsOpen ? "open" : "closed"
        
        // Only react to actual state changes
        guard notchState != lastNotchState || currentView != lastCurrentView else { return }
        
        lastNotchState = notchState
        lastCurrentView = currentView
        
        // Cancel any pending timers
        delayedStartTimer?.invalidate()
        delayedStopTimer?.invalidate()
        
        // Determine if we should be monitoring
        shouldMonitorForStats = notchIsOpen && (currentView == "stats")
        
        if shouldMonitorForStats {
            // Start monitoring after 3.5 seconds (when notch is open and stats tab is active)
            delayedStartTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.startMonitoring()
                }
            }
        } else {
            if notchIsOpen && currentView != "stats" {
                scheduleDelayedStop(after: tabSwitchStopDelay)
            } else if !notchIsOpen {
                if Defaults[.statsStopWhenNotchCloses] {
                    scheduleDelayedStop(after: notchCloseStopDelay)
                }
            } else {
                scheduleDelayedStop(after: tabSwitchStopDelay)
            }
        }
    }
    
    // MARK: - Public Monitoring Controls
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        print("StatsManager: Starting monitoring...")
        
        // Reset baseline for accurate measurement
        let initialStats = getNetworkStats()
        previousNetworkStats = initialStats
        
        let initialDiskStats = getDiskStats()
        previousDiskStats = initialDiskStats
        
        previousTimestamp = Date()
        
        isMonitoring = true
        updatePublishedStats {
            $0.lastUpdated = Date()
            $0.networkTotals = .zero
            $0.diskTotals = .zero
        }
        
        scheduleMonitoringTimer()
 
        Task { @MainActor in
            self.updateSystemStats()
        }
        
        print("StatsManager: Monitoring started")
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        // Clean up all timers
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        delayedStartTimer?.invalidate()
        delayedStopTimer?.invalidate()
        
        isMonitoring = false
        isStatsCollectionInFlight = false
        print("StatsManager: Monitoring stopped")
        cachedProcessStats.removeAll()
        lastProcessStatsUpdate = .distantPast
        isProcessRefreshInFlight = false
        previousCPULoadInfo = nil
        if let previousCpuInfo {
            let size = vm_size_t(previousCpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousCpuInfo), size)
        }
        previousCpuInfo = nil
        previousCpuInfoCount = 0
        processorCount = 0
        topCPUProcesses = []
        previousInterfaceCounters.removeAll()
        interfaceTotals.removeAll()
        updatePublishedStats {
            $0.cpuCoreUsage = []
            $0.networkInterfaces = []
            $0.diskDevices = []
            $0.cpuTemperature = CPUTemperatureMetrics(celsius: nil)
            $0.cpuFrequency = nil
        }
    }

    private func scheduleMonitoringTimer() {
        monitoringTimer?.invalidate()

        let configuredInterval = Defaults[.statsUpdateInterval]
        let interval = validatedUpdateInterval(configuredInterval)

        if abs(interval - configuredInterval) > 0.0001 {
            Defaults[.statsUpdateInterval] = interval
        }

        monitoringTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                self.updateSystemStats()
            }
        }
    }

    private func handleUpdateIntervalChange(_ newValue: Double) {
        let interval = validatedUpdateInterval(newValue)

        if abs(interval - newValue) > 0.0001 {
            Defaults[.statsUpdateInterval] = interval
            return
        }

        guard isMonitoring else { return }

        DispatchQueue.main.async { [weak self] in
            self?.scheduleMonitoringTimer()
        }
    }

    private func validatedUpdateInterval(_ value: Double) -> TimeInterval {
        min(max(value, minUpdateInterval), maxUpdateInterval)
    }

    private func scheduleDelayedStop(after delay: TimeInterval) {
        guard delay > 0 else {
            stopMonitoring()
            return
        }

        delayedStopTimer?.invalidate()

        delayedStopTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.stopMonitoring()
            }
        }
    }
    
    private func updatePublishedStats(_ mutate: (inout PublishedStatsSnapshot) -> Void) {
        var snapshot = publishedStats
        mutate(&snapshot)
        if snapshot != publishedStats {
            publishedStats = snapshot
        }
    }
    
    private func collectSystemStatsSnapshot(from currentSnapshot: PublishedStatsSnapshot) -> StatsCollectionResult {
        let cpuMetrics = getCPULoadBreakdown()
        let newCpuUsage = cpuMetrics.activeUsage
        let memorySnapshot = getMemorySnapshot()
        let newMemoryUsage = memorySnapshot.usage
        let gpuSnapshot = getGPUMetrics()
        let newGpuUsage = gpuSnapshot.usage
        let coreUsage = collectCPUCoreUsage()
        
        let currentNetworkStats = getNetworkStats()
        let currentTime = Date()
        let timeInterval = currentTime.timeIntervalSince(previousTimestamp)
        
        var downloadSpeed: Double = 0.0
        var uploadSpeed: Double = 0.0
        var bytesDownloaded: UInt64 = 0
        var bytesUploaded: UInt64 = 0
        
        if timeInterval > 0.1 && (previousNetworkStats.bytesIn > 0 || previousNetworkStats.bytesOut > 0) {
            bytesDownloaded = currentNetworkStats.bytesIn > previousNetworkStats.bytesIn ?
                currentNetworkStats.bytesIn - previousNetworkStats.bytesIn : 0
            bytesUploaded = currentNetworkStats.bytesOut > previousNetworkStats.bytesOut ?
                currentNetworkStats.bytesOut - previousNetworkStats.bytesOut : 0
            
            downloadSpeed = Double(bytesDownloaded) / timeInterval / 1_048_576
            uploadSpeed = Double(bytesUploaded) / timeInterval / 1_048_576
        }
        
        let currentDiskStats = getDiskStats()
        var readSpeed: Double = 0.0
        var writeSpeed: Double = 0.0
        var bytesRead: UInt64 = 0
        var bytesWritten: UInt64 = 0
        
        if timeInterval > 0.1 && (previousDiskStats.bytesRead > 0 || previousDiskStats.bytesWritten > 0) {
            bytesRead = currentDiskStats.bytesRead > previousDiskStats.bytesRead ?
                currentDiskStats.bytesRead - previousDiskStats.bytesRead : 0
            bytesWritten = currentDiskStats.bytesWritten > previousDiskStats.bytesWritten ?
                currentDiskStats.bytesWritten - previousDiskStats.bytesWritten : 0
            
            readSpeed = Double(bytesRead) / timeInterval / 1_048_576
            writeSpeed = Double(bytesWritten) / timeInterval / 1_048_576
        }
        
        var updatedSnapshot = currentSnapshot
        updatedSnapshot.cpuUsage = newCpuUsage
        updatedSnapshot.gpuUsage = newGpuUsage
        updatedSnapshot.memoryUsage = newMemoryUsage
        updatedSnapshot.networkDownload = max(0.0, downloadSpeed)
        updatedSnapshot.networkUpload = max(0.0, uploadSpeed)
        updatedSnapshot.diskRead = max(0.0, readSpeed)
        updatedSnapshot.diskWrite = max(0.0, writeSpeed)
        updatedSnapshot.lastUpdated = Date()
        updatedSnapshot.cpuBreakdown = cpuMetrics
        updatedSnapshot.memoryBreakdown = memorySnapshot.breakdown
        updatedSnapshot.cpuLoadAverage = getLoadAverage()
        updatedSnapshot.gpuBreakdown = gpuSnapshot.breakdown
        updatedSnapshot.gpuDevices = gpuSnapshot.devices
        updatedSnapshot.cpuCoreUsage = coreUsage
        updatedSnapshot.cpuUptime = ProcessInfo.processInfo.systemUptime
        updatedSnapshot.cpuTemperature = cpuSensorCollector.readTemperature()
        if let frequencyMetrics = cpuSensorCollector.readFrequency() {
            updatedSnapshot.cpuFrequency = frequencyMetrics
        }
        
        updateHistory(value: newCpuUsage, history: &updatedSnapshot.cpuHistory)
        updateHistory(value: newMemoryUsage, history: &updatedSnapshot.memoryHistory)
        updateHistory(value: newGpuUsage, history: &updatedSnapshot.gpuHistory)
        updateHistory(value: downloadSpeed, history: &updatedSnapshot.networkDownloadHistory)
        updateHistory(value: uploadSpeed, history: &updatedSnapshot.networkUploadHistory)
        updateHistory(value: readSpeed, history: &updatedSnapshot.diskReadHistory)
        updateHistory(value: writeSpeed, history: &updatedSnapshot.diskWriteHistory)
        
        updatedSnapshot.networkInterfaces = collectNetworkInterfaces(deltaTime: timeInterval)
        updatedSnapshot.diskDevices = collectDiskDevices()
        
        if bytesDownloaded > 0 {
            updatedSnapshot.networkTotals.downloadedMB += Double(bytesDownloaded) / 1_048_576
        }
        if bytesUploaded > 0 {
            updatedSnapshot.networkTotals.uploadedMB += Double(bytesUploaded) / 1_048_576
        }
        if bytesRead > 0 {
            updatedSnapshot.diskTotals.readMB += Double(bytesRead) / 1_048_576
        }
        if bytesWritten > 0 {
            updatedSnapshot.diskTotals.writtenMB += Double(bytesWritten) / 1_048_576
        }
        
        return StatsCollectionResult(
            snapshot: updatedSnapshot,
            previousNetworkStats: currentNetworkStats,
            previousDiskStats: currentDiskStats,
            previousTimestamp: currentTime
        )
    }
    
    @MainActor
    private func applyStatsCollectionResult(_ result: StatsCollectionResult) {
        publishedStats = result.snapshot
        previousNetworkStats = result.previousNetworkStats
        previousDiskStats = result.previousDiskStats
        previousTimestamp = result.previousTimestamp
        refreshProcessStatsIfNeeded(force: !respectProcessCacheOnTick)
    }
    
    // MARK: - Private Methods
    @MainActor
    private func updateSystemStats() {
        guard isMonitoring else { return }
        
        if backgroundStatsCollection {
            guard !isStatsCollectionInFlight else { return }
            isStatsCollectionInFlight = true
            let currentSnapshot = publishedStats
            
            statsCollectionQueue.async { [weak self] in
                guard let self = self else { return }
                let result = self.collectSystemStatsSnapshot(from: currentSnapshot)
                
                Task { @MainActor in
                    defer { self.isStatsCollectionInFlight = false }
                    guard self.isMonitoring else { return }
                    self.applyStatsCollectionResult(result)
                }
            }
            return
        }
        
        let result = collectSystemStatsSnapshot(from: publishedStats)
        applyStatsCollectionResult(result)
    }
    
    private func updateHistory(value: Double, history: inout [Double]) {
        // Remove first element and append new value
        if history.count >= maxHistoryPoints {
            history.removeFirst()
        }
        history.append(value)
    }
    
    // MARK: - System Monitoring Functions
    
    private func getCPULoadBreakdown() -> CPULoadBreakdown {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return cpuBreakdown
        }

        let clamped: (Double) -> Double = { value in
            return min(max(value, 0), 100)
        }

        let breakdown: CPULoadBreakdown

        if let previous = previousCPULoadInfo {
            let userDiff = Double(info.cpu_ticks.0 - previous.cpu_ticks.0)
            let systemDiff = Double(info.cpu_ticks.1 - previous.cpu_ticks.1)
            let idleDiff = Double(info.cpu_ticks.2 - previous.cpu_ticks.2)
            let niceDiff = Double(info.cpu_ticks.3 - previous.cpu_ticks.3)
            let total = userDiff + systemDiff + idleDiff + niceDiff

            if total > 0 {
                let userPercent = ((userDiff + niceDiff) / total) * 100
                let systemPercent = (systemDiff / total) * 100
                let idlePercent = (idleDiff / total) * 100
                breakdown = CPULoadBreakdown(
                    user: clamped(userPercent),
                    system: clamped(systemPercent),
                    idle: clamped(idlePercent)
                )
            } else {
                breakdown = cpuBreakdown
            }
        } else {
            let totalTicks = Double(info.cpu_ticks.0 + info.cpu_ticks.1 + info.cpu_ticks.2 + info.cpu_ticks.3)
            if totalTicks > 0 {
                let userPercent = ((Double(info.cpu_ticks.0) + Double(info.cpu_ticks.3)) / totalTicks) * 100
                let systemPercent = (Double(info.cpu_ticks.1) / totalTicks) * 100
                let idlePercent = (Double(info.cpu_ticks.2) / totalTicks) * 100
                breakdown = CPULoadBreakdown(
                    user: clamped(userPercent),
                    system: clamped(systemPercent),
                    idle: clamped(idlePercent)
                )
            } else {
                breakdown = cpuBreakdown
            }
        }

        previousCPULoadInfo = info
        return breakdown
    }

    private func getLoadAverage() -> LoadAverage {
        var loads = [Double](repeating: 0, count: 3)
        let result = loads.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return getloadavg(baseAddress, 3)
        }
        guard result == 3 else {
            return cpuLoadAverage
        }
        return LoadAverage(oneMinute: loads[0], fiveMinutes: loads[1], fifteenMinutes: loads[2])
    }
    
    private func getMemorySnapshot() -> (usage: Double, breakdown: MemoryBreakdown) {
        // Memory usage monitoring using host_statistics64
        var vmStatistics = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let vmResult = withUnsafeMutablePointer(to: &vmStatistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &size)
            }
        }
        
        guard vmResult == KERN_SUCCESS else {
            return (memoryUsage, memoryBreakdown)
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        let freeBytes = UInt64(vmStatistics.free_count) * pageSize
        let speculativeBytes = UInt64(vmStatistics.speculative_count) * pageSize
        let activeBytes = UInt64(vmStatistics.active_count) * pageSize
        let inactiveBytes = UInt64(vmStatistics.inactive_count) * pageSize
        let wiredBytes = UInt64(vmStatistics.wire_count) * pageSize
        let compressedBytes = UInt64(vmStatistics.compressor_page_count) * pageSize
        let purgeableBytes = UInt64(vmStatistics.purgeable_count) * pageSize
        let externalBytes = UInt64(vmStatistics.external_page_count) * pageSize
        
        let totalMemoryBytes: UInt64
        if totalPhysicalMemory > 0 {
            totalMemoryBytes = totalPhysicalMemory
        } else {
            totalMemoryBytes = freeBytes + speculativeBytes + activeBytes + inactiveBytes + wiredBytes + compressedBytes
        }
        guard totalMemoryBytes > 0 else {
            return (0.0, .zero)
        }
        
        let usedWithoutCache = activeBytes + inactiveBytes + speculativeBytes + wiredBytes + compressedBytes
        let cacheBytes = purgeableBytes + externalBytes
        let usedBytes = usedWithoutCache > cacheBytes ? usedWithoutCache - cacheBytes : 0
        let clampedUsedBytes = min(usedBytes, totalMemoryBytes)
        let freeComputedBytes = totalMemoryBytes > clampedUsedBytes ? totalMemoryBytes - clampedUsedBytes : 0
        let nonAppBytes = wiredBytes + compressedBytes
        let appBytes = clampedUsedBytes > nonAppBytes ? clampedUsedBytes - nonAppBytes : 0
        
        var pressureLevelRaw: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevelRaw, &pressureSize, nil, 0)
        let pressureLevel: MemoryPressureLevel
        switch pressureLevelRaw {
        case 2:
            pressureLevel = .warning
        case 4:
            pressureLevel = .critical
        default:
            pressureLevel = .normal
        }
        let pressure = MemoryPressure(rawValue: Int(pressureLevelRaw), level: pressureLevel)
        
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
        let swapInfo = MemorySwap(
            totalBytes: UInt64(swapUsage.xsu_total),
            usedBytes: UInt64(swapUsage.xsu_used),
            freeBytes: UInt64(swapUsage.xsu_avail)
        )
        
        let usage = Double(clampedUsedBytes) / Double(totalMemoryBytes) * 100.0
        let breakdown = MemoryBreakdown(
            totalBytes: totalMemoryBytes,
            usedBytes: clampedUsedBytes,
            freeBytes: freeComputedBytes,
            wiredBytes: wiredBytes,
            activeBytes: activeBytes,
            inactiveBytes: inactiveBytes,
            compressedBytes: compressedBytes,
            appBytes: appBytes,
            cacheBytes: cacheBytes,
            swap: swapInfo,
            pressure: pressure
        )
        
        return (min(100.0, max(0.0, usage)), breakdown)
    }
    
    private func getGPUMetrics() -> GPUMetricsSnapshot {
        let devices = gpuCollector.collectDevices()
        guard !devices.isEmpty else {
            return .zero
        }
        let utilizationValues = devices.compactMap { $0.utilization }
        let usage: Double
        if utilizationValues.isEmpty {
            usage = 0
        } else {
            usage = utilizationValues.reduce(0, +) / Double(utilizationValues.count)
        }
        let breakdown = makeGPUBreakdown(from: devices)
        return GPUMetricsSnapshot(usage: usage, breakdown: breakdown, devices: devices)
    }
    
    private func makeGPUBreakdown(from devices: [GPUDeviceMetrics]) -> GPUBreakdown {
        guard let primary = devices.first(where: { ($0.utilization ?? 0) > 0 || ($0.renderUtilization ?? 0) > 0 || ($0.tilerUtilization ?? 0) > 0 }) else {
            return .zero
        }
        let fallbackTotal = max((primary.renderUtilization ?? 0) + (primary.tilerUtilization ?? 0), 0)
        let total = max(primary.utilization ?? fallbackTotal, 0)
        if total.isZero {
            return GPUBreakdown(
                render: primary.renderUtilization ?? 0,
                compute: primary.tilerUtilization ?? 0,
                video: 0,
                other: 0
            )
        }
        let render = min(primary.renderUtilization ?? 0, total)
        let tiler = min(primary.tilerUtilization ?? 0, max(total - render, 0))
        let remaining = max(total - render - tiler, 0)
        let compute = remaining * 0.6
        let video = remaining * 0.25
        let other = max(remaining - compute - video, 0)
        return GPUBreakdown(render: render, compute: compute, video: video, other: other)
    }

    private func collectCPUCoreUsage() -> [CPUCoreUsage] {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUsU: natural_t = 0
        let result = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        guard result == KERN_SUCCESS, let cpuInfo else {
            return cpuCoreUsage
        }
        let cpuCount = Int(numCPUsU)
        var usages: [CPUCoreUsage] = []
        usages.reserveCapacity(cpuCount)
        let cpuStateMax = Int(CPU_STATE_MAX)
        if let previousCpuInfo {
            for cpu in 0..<cpuCount {
                let base = cpu * cpuStateMax
                let user = cpuInfo[base + Int(CPU_STATE_USER)] - previousCpuInfo[base + Int(CPU_STATE_USER)]
                let system = cpuInfo[base + Int(CPU_STATE_SYSTEM)] - previousCpuInfo[base + Int(CPU_STATE_SYSTEM)]
                let nice = cpuInfo[base + Int(CPU_STATE_NICE)] - previousCpuInfo[base + Int(CPU_STATE_NICE)]
                let idle = cpuInfo[base + Int(CPU_STATE_IDLE)] - previousCpuInfo[base + Int(CPU_STATE_IDLE)]
                let inUse = user + system + nice
                let total = inUse + idle
                let percent = total > 0 ? Double(inUse) / Double(total) : 0
                usages.append(CPUCoreUsage(id: cpu, usage: max(0, min(percent * 100, 100))))
            }
        } else {
            for cpu in 0..<cpuCount {
                let base = cpu * cpuStateMax
                let user = cpuInfo[base + Int(CPU_STATE_USER)]
                let system = cpuInfo[base + Int(CPU_STATE_SYSTEM)]
                let nice = cpuInfo[base + Int(CPU_STATE_NICE)]
                let idle = cpuInfo[base + Int(CPU_STATE_IDLE)]
                let inUse = user + system + nice
                let total = inUse + idle
                let percent = total > 0 ? Double(inUse) / Double(total) : 0
                usages.append(CPUCoreUsage(id: cpu, usage: max(0, min(percent * 100, 100))))
            }
        }
        if let previousCpuInfo {
            let size = vm_size_t(previousCpuInfoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousCpuInfo), size)
        }
        previousCpuInfo = cpuInfo
        previousCpuInfoCount = numCpuInfo
        processorCount = numCPUsU
        return usages
    }

    private func collectNetworkInterfaces(deltaTime: TimeInterval) -> [NetworkInterfaceMetrics] {
        var interfacesPointer: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&interfacesPointer) == 0, let startPointer = interfacesPointer else {
            return networkInterfaces
        }
        defer { freeifaddrs(startPointer) }
        struct InterfaceAccumulator {
            var name: String
            var flags: UInt32
            var bytesIn: UInt64
            var bytesOut: UInt64
            var ipv4: String?
            var ipv6: String?
        }
        var accumulators: [String: InterfaceAccumulator] = [:]
        var pointer: UnsafeMutablePointer<ifaddrs>? = startPointer
        while let current = pointer {
            let interface = current.pointee
            let name = String(cString: interface.ifa_name)
            var accumulator = accumulators[name] ?? InterfaceAccumulator(name: name, flags: interface.ifa_flags, bytesIn: 0, bytesOut: 0, ipv4: nil, ipv6: nil)
            if let addr = interface.ifa_addr {
                switch Int32(addr.pointee.sa_family) {
                case AF_LINK:
                    if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                        accumulator.bytesIn = UInt64(data.pointee.ifi_ibytes)
                        accumulator.bytesOut = UInt64(data.pointee.ifi_obytes)
                    }
                case AF_INET:
                    accumulator.ipv4 = stringFromSockaddr(addr)
                case AF_INET6:
                    accumulator.ipv6 = stringFromSockaddr(addr)
                default:
                    break
                }
            }
            accumulators[name] = accumulator
            pointer = interface.ifa_next
        }
        var results: [NetworkInterfaceMetrics] = []
        var updatedCounters: [String: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
        for accumulator in accumulators.values {
            guard shouldIncludeInterface(name: accumulator.name) else { continue }
            let previous = previousInterfaceCounters[accumulator.name] ?? (accumulator.bytesIn, accumulator.bytesOut)
            let deltaIn = accumulator.bytesIn >= previous.bytesIn ? accumulator.bytesIn - previous.bytesIn : 0
            let deltaOut = accumulator.bytesOut >= previous.bytesOut ? accumulator.bytesOut - previous.bytesOut : 0
            let speedDivider = max(deltaTime, 0.001)
            let downloadSpeed = Double(deltaIn) / speedDivider / 1_048_576
            let uploadSpeed = Double(deltaOut) / speedDivider / 1_048_576
            var totals = interfaceTotals[accumulator.name] ?? .zero
            totals.downloadedMB += Double(deltaIn) / 1_048_576
            totals.uploadedMB += Double(deltaOut) / 1_048_576
            interfaceTotals[accumulator.name] = totals
            let metrics = NetworkInterfaceMetrics(
                name: accumulator.name,
                displayName: interfaceDisplayName(for: accumulator.name),
                type: interfaceType(for: accumulator.name),
                ipv4: accumulator.ipv4,
                ipv6: accumulator.ipv6,
                isActive: interfaceIsActive(flags: accumulator.flags),
                currentDownload: max(downloadSpeed, 0),
                currentUpload: max(uploadSpeed, 0),
                totalDownloaded: totals.downloadedMB,
                totalUploaded: totals.uploadedMB
            )
            results.append(metrics)
            updatedCounters[accumulator.name] = (accumulator.bytesIn, accumulator.bytesOut)
        }
        previousInterfaceCounters = updatedCounters
        return results.sorted { lhs, rhs in
            if lhs.type == rhs.type {
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            return networkTypeSortOrder(lhs.type) < networkTypeSortOrder(rhs.type)
        }
    }

    private func collectDiskDevices() -> [DiskDeviceMetrics] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey,
            .volumeIsRootFileSystemKey,
            .volumeIsRemovableKey
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return diskDevices
        }
        var devices: [DiskDeviceMetrics] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard let totalCapacity = values.volumeTotalCapacity.flatMap({ Int64($0) }), totalCapacity > 0 else { continue }
            let name = values.volumeName ?? url.lastPathComponent
            let freeCapacityValue: Int64
            if let free = values.volumeAvailableCapacity {
                freeCapacityValue = Int64(free)
            } else if let important = values.volumeAvailableCapacityForImportantUsage {
                freeCapacityValue = important
            } else if let opportunistic = values.volumeAvailableCapacityForOpportunisticUsage {
                freeCapacityValue = opportunistic
            } else {
                freeCapacityValue = 0
            }
            let clampedFree = max(freeCapacityValue, 0)
            let device = DiskDeviceMetrics(
                id: url.path,
                name: name,
                path: url,
                totalBytes: UInt64(totalCapacity),
                freeBytes: UInt64(clampedFree),
                isRoot: values.volumeIsRootFileSystem ?? false,
                isRemovable: values.volumeIsRemovable ?? false
            )
            devices.append(device)
        }
        return devices.sorted { lhs, rhs in
            if lhs.isRoot != rhs.isRoot {
                return lhs.isRoot
            }
            if lhs.isRemovable != rhs.isRemovable {
                return !lhs.isRemovable
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func stringFromSockaddr(_ addressPointer: UnsafePointer<sockaddr>?) -> String? {
        guard let addressPointer else { return nil }
        let family = Int32(addressPointer.pointee.sa_family)
        switch family {
        case AF_INET:
            var addr = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buffer)
        case AF_INET6:
            var addr = addressPointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buffer)
        default:
            return nil
        }
    }

    private func shouldIncludeInterface(name: String) -> Bool {
        guard !name.hasPrefix("lo"),
              !name.hasPrefix("gif"),
              !name.hasPrefix("stf"),
              !name.hasPrefix("awdl"),
              !name.hasPrefix("llw"),
              !name.hasPrefix("utun"),
              !name.hasPrefix("p2p") else {
            return false
        }
        return true
    }

    private func interfaceIsActive(flags: UInt32) -> Bool {
        let isUp = (flags & UInt32(IFF_UP)) == UInt32(IFF_UP)
        let isRunning = (flags & UInt32(IFF_RUNNING)) == UInt32(IFF_RUNNING)
        return isUp && isRunning
    }

    private func interfaceDisplayName(for name: String) -> String {
        if name.hasPrefix("en") {
            return name == "en0" ? "Wi-Fi" : "Ethernet"
        }
        if name.hasPrefix("bridge") {
            return "Bridge"
        }
        if name.hasPrefix("pd") {
            return "USB"
        }
        if name.hasPrefix("vmnet") {
            return "Virtual"
        }
        if name.hasPrefix("ap") {
            return "Hotspot"
        }
        if name.hasPrefix("awdl") {
            return "AirDrop"
        }
        return name.uppercased()
    }

    private func interfaceType(for name: String) -> NetworkInterfaceType {
        if name.hasPrefix("en") {
            if name == "en0" {
                return .wifi
            }
            return .ethernet
        }
        if name.hasPrefix("bridge") || name.hasPrefix("vmnet") {
            return .ethernet
        }
        if name.hasPrefix("ap") {
            return .wifi
        }
        if name.hasPrefix("pdp_ip") {
            return .cellular
        }
        if name.hasPrefix("lo") {
            return .loopback
        }
        return .other
    }

    private func networkTypeSortOrder(_ type: NetworkInterfaceType) -> Int {
        switch type {
        case .wifi:
            return 0
        case .ethernet:
            return 1
        case .cellular:
            return 2
        case .other:
            return 3
        case .loopback:
            return 4
        }
    }
    
    private func getNetworkStats() -> (bytesIn: UInt64, bytesOut: UInt64) {
        // Use BSD sockets to get network interface statistics
        var totalBytesIn: UInt64 = 0
        var totalBytesOut: UInt64 = 0
        
        var ifaddrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrs) == 0 else {
            return (totalBytesIn, totalBytesOut)
        }
        
        defer { freeifaddrs(ifaddrs) }
        
        var ptr = ifaddrs
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            guard let interface = ptr?.pointee,
                  interface.ifa_addr.pointee.sa_family == UInt8(AF_LINK) else {
                continue
            }
            
            let name = String(cString: interface.ifa_name)
            // Skip loopback and virtual interfaces, but include en0, en1, etc. and Wi-Fi interfaces
            guard !name.hasPrefix("lo") && 
                  !name.hasPrefix("gif") && 
                  !name.hasPrefix("stf") && 
                  !name.hasPrefix("bridge") &&
                  !name.hasPrefix("utun") &&
                  !name.hasPrefix("awdl") else {
                continue
            }
            
            // Only count active interfaces (en0, en1, etc.)
            if name.hasPrefix("en") || name.contains("Wi-Fi") {
                if let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) {
                    totalBytesIn += UInt64(data.pointee.ifi_ibytes)
                    totalBytesOut += UInt64(data.pointee.ifi_obytes)
                }
            }
        }
        
        return (totalBytesIn, totalBytesOut)
    }
    
    private func getDiskStats() -> (bytesRead: UInt64, bytesWritten: UInt64) {
        // Use IOKit to get disk I/O statistics from IOStorage service
        var totalBytesRead: UInt64 = 0
        var totalBytesWritten: UInt64 = 0
        
        let matchingDict = IOServiceMatching("IOStorage")
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        
        guard result == KERN_SUCCESS else {
            return (totalBytesRead, totalBytesWritten)
        }
        
        defer { IOObjectRelease(iterator) }
        
        var service: io_registry_entry_t = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            
            var properties: Unmanaged<CFMutableDictionary>?
            let propertiesResult = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
            
            guard propertiesResult == KERN_SUCCESS,
                  let props = properties?.takeRetainedValue() as? [String: Any],
                  let statistics = props["Statistics"] as? [String: Any] else {
                continue
            }
            
            // Use the correct property names for APFS/modern filesystems
            if let bytesRead = statistics["Bytes read from block device"] as? UInt64 {
                totalBytesRead += bytesRead
            }
            
            if let bytesWritten = statistics["Bytes written to block device"] as? UInt64 {
                totalBytesWritten += bytesWritten
            }
        }
        
        return (totalBytesRead, totalBytesWritten)
    }
    
    // MARK: - Computed Properties for UI
    var cpuUsageString: String {
        return String(format: "%.1f%%", cpuUsage)
    }
    
    var memoryUsageString: String {
        return String(format: "%.1f%%", memoryUsage)
    }
    
    var gpuUsageString: String {
        return String(format: "%.1f%%", gpuUsage)
    }
    
    var networkDownloadString: String {
        StatsFormatting.throughput(networkDownload)
    }
    
    var networkUploadString: String {
        StatsFormatting.throughput(networkUpload)
    }
    
    var diskReadString: String {
        return String(format: "%.1f MB/s", diskRead)
    }
    
    var diskWriteString: String {
        return String(format: "%.1f MB/s", diskWrite)
    }
    
    var maxCpuUsage: Double {
        return cpuHistory.max() ?? 0.0
    }
    
    var maxMemoryUsage: Double {
        return memoryHistory.max() ?? 0.0
    }
    
    var maxGpuUsage: Double {
        return gpuHistory.max() ?? 0.0
    }
    
    var avgCpuUsage: Double {
        let nonZeroValues = cpuHistory.filter { $0 > 0 }
        guard !nonZeroValues.isEmpty else { return 0.0 }
        return nonZeroValues.reduce(0, +) / Double(nonZeroValues.count)
    }
    
    var avgMemoryUsage: Double {
        let nonZeroValues = memoryHistory.filter { $0 > 0 }
        guard !nonZeroValues.isEmpty else { return 0.0 }
        return nonZeroValues.reduce(0, +) / Double(nonZeroValues.count)
    }
    
    var avgGpuUsage: Double {
        let nonZeroValues = gpuHistory.filter { $0 > 0 }
        guard !nonZeroValues.isEmpty else { return 0.0 }
        return nonZeroValues.reduce(0, +) / Double(nonZeroValues.count)
    }
    
    // MARK: - Clear History Method
    func clearHistory() {
        updatePublishedStats {
            $0.cpuHistory = Array(repeating: 0.0, count: maxHistoryPoints)
            $0.memoryHistory = Array(repeating: 0.0, count: maxHistoryPoints)
            $0.gpuHistory = Array(repeating: 0.0, count: maxHistoryPoints)
            $0.networkDownloadHistory = Array(repeating: 0.0, count: maxHistoryPoints)
            $0.networkUploadHistory = Array(repeating: 0.0, count: maxHistoryPoints)
            $0.diskReadHistory = Array(repeating: 0.0, count: maxHistoryPoints)
            $0.diskWriteHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        }
    }
    
    // MARK: - Process Monitoring Methods
    @MainActor
    func refreshProcessStatsNow() {
        refreshProcessStatsIfNeeded(force: true)
    }
    
    @MainActor
    func getProcessesRankedByCPU() -> [ProcessStats] {
        refreshProcessStatsIfNeeded()
        return cachedProcessStats.sorted { $0.cpuUsage > $1.cpuUsage }
    }
    
    @MainActor
    func getProcessesRankedByMemory() -> [ProcessStats] {
        refreshProcessStatsIfNeeded()
        return cachedProcessStats.sorted { $0.memoryUsage > $1.memoryUsage }
    }
    
    @MainActor
    func getProcessesRankedByGPU() -> [ProcessStats] {
        // For now, rank by CPU usage as GPU per-process stats are complex to obtain
        refreshProcessStatsIfNeeded()
        return cachedProcessStats.sorted { $0.cpuUsage > $1.cpuUsage }
    }
    
    @MainActor
    private func refreshProcessStatsIfNeeded(force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastProcessStatsUpdate) >= processStatsUpdateInterval else { return }
        guard !isProcessRefreshInFlight else { return }

        isProcessRefreshInFlight = true

        Task.detached { [weak self] in
            guard let self else { return }
            let processes = StatsManager.collectTopProcesses(limit: self.maxProcessEntries)
            await MainActor.run {
                self.cachedProcessStats = processes
                self.lastProcessStatsUpdate = Date()
                self.isProcessRefreshInFlight = false
                self.topCPUProcesses = processes
            }
        }
    }

    private static func collectTopProcesses(limit: Int) -> [ProcessStats] {
        guard limit > 0 else { return [] }

        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-Aceo", "pid,pcpu,comm", "-r"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        defer {
            outputPipe.fileHandleForReading.closeFile()
            errorPipe.fileHandleForReading.closeFile()
        }

        do {
            try task.run()
        } catch {
            NSLog("StatsManager: Failed to run ps command: \(error.localizedDescription)")
            return []
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard !outputData.isEmpty, let output = String(data: outputData, encoding: .utf8) else {
            return []
        }

        var results: [ProcessStats] = []

        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return [] }

        for line in lines.dropFirst() {
            guard let parsed = parseProcessLine(String(line)) else { continue }
            let (pid, cpuUsage, command) = parsed
            let (displayName, icon) = runningApplicationInfo(for: pid, fallbackCommand: command)
            let memoryUsage = residentMemory(for: pid)

            let process = ProcessStats(
                pid: pid,
                name: displayName,
                cpuUsage: cpuUsage,
                memoryUsage: memoryUsage,
                icon: icon
            )

            results.append(process)
            if results.count >= limit { break }
        }

        return results
    }

    private static func parseProcessLine(_ rawLine: String) -> (pid_t, Double, String)? {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let scanner = Scanner(string: trimmed)
        scanner.charactersToBeSkipped = .whitespaces

          guard let pidToken = scanner.scanCharacters(from: .decimalDigits),
              let pidValue = Int32(pidToken) else { return nil }

          let cpuCharacterSet = CharacterSet(charactersIn: "0123456789.,")
          guard let cpuToken = scanner.scanCharacters(from: cpuCharacterSet) else { return nil }
        let normalizedCPU = cpuToken.replacingOccurrences(of: ",", with: ".")
        guard let cpuValue = Double(normalizedCPU), cpuValue.isFinite, cpuValue >= 0 else { return nil }
        _ = scanner.scanCharacters(from: .whitespaces)
        let remainingIndex = scanner.currentIndex
        let command = String(trimmed[remainingIndex...]).trimmingCharacters(in: .whitespaces)

        return (pidValue, cpuValue, command.isEmpty ? "Unknown" : command)
    }

    private static func runningApplicationInfo(for pid: pid_t, fallbackCommand: String) -> (String, NSImage?) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ((name?.isEmpty ?? true) ? fallbackCommand : name!, app.icon)
        }
        return (fallbackCommand, nil)
    }

    private static func residentMemory(for pid: pid_t) -> UInt64 {
        var taskInfo = proc_taskinfo()
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
        guard result == MemoryLayout<proc_taskinfo>.size else { return 0 }
        return taskInfo.pti_resident_size
    }
}
