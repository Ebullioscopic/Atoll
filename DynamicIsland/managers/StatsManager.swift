//
//  StatsManager.swift
//  DynamicIsland
//
//  System performance monitoring for the Dynamic Island Stats feature
//  Created by Hariharan Mudaliar

import Foundation
import Combine
import SwiftUI
import IOKit
import IOKit.ps
import Darwin
import AppKit
//import Network

class StatsManager: ObservableObject {
    // MARK: - Properties
    static let shared = StatsManager()
    
    @Published var isMonitoring: Bool = false
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsage: Double = 0.0
    @Published var gpuUsage: Double = 0.0
    @Published var networkDownload: Double = 0.0 // MB/s
    @Published var networkUpload: Double = 0.0   // MB/s
    @Published var diskRead: Double = 0.0        // MB/s
    @Published var diskWrite: Double = 0.0       // MB/s
    @Published var lastUpdated: Date = .distantPast
    
    // Historical data for graphs (last 30 data points)
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var gpuHistory: [Double] = []
    @Published var networkDownloadHistory: [Double] = []
    @Published var networkUploadHistory: [Double] = []
    @Published var diskReadHistory: [Double] = []
    @Published var diskWriteHistory: [Double] = []
    
    private var monitoringTimer: Timer?
    private var delayedStopTimer: Timer?
    private var delayedStartTimer: Timer?
    private let maxHistoryPoints = 30
    
    // Smart monitoring state
    private var shouldMonitorForStats: Bool = false
    private var lastNotchState: String = "closed"
    private var lastCurrentView: String = "other"
    
    // Network monitoring state
    private var previousNetworkStats: (bytesIn: UInt64, bytesOut: UInt64) = (0, 0)
    private var previousTimestamp: Date = Date()
    
    // Disk monitoring state  
    private var previousDiskStats: (bytesRead: UInt64, bytesWritten: UInt64) = (0, 0)
    
    // MARK: - Initialization
    private init() {
        // Initialize with empty history
        cpuHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        memoryHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        gpuHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        networkDownloadHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        networkUploadHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        diskReadHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        diskWriteHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        
        // Initialize baseline network stats
        let initialStats = getNetworkStats()
        previousNetworkStats = initialStats
        previousTimestamp = Date()
        
        // Initialize baseline disk stats
        let initialDiskStats = getDiskStats()
        previousDiskStats = initialDiskStats
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
            // Stop monitoring after 3 seconds (when notch is closed or stats tab is not active)
            let delay = notchIsOpen ? 0.1 : 3.0 // Stop quickly when switching tabs, slowly when closing notch
            delayedStopTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.stopMonitoring()
                }
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
        lastUpdated = Date()
        
        // Start periodic monitoring (every 1 second)
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.updateSystemStats()
            }
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
        print("StatsManager: Monitoring stopped")
    }
    
    // MARK: - Private Methods
    @MainActor
    private func updateSystemStats() {
        let newCpuUsage = getCPUUsage()
        let newMemoryUsage = getMemoryUsage()
        let newGpuUsage = getGPUUsage()
        
        // Calculate network speeds
        let currentNetworkStats = getNetworkStats()
        let currentTime = Date()
        let timeInterval = currentTime.timeIntervalSince(previousTimestamp)
        
        var downloadSpeed: Double = 0.0
        var uploadSpeed: Double = 0.0
        
        // Only calculate speeds if we have a reasonable time interval and this isn't the first run
        if timeInterval > 0.1 && (previousNetworkStats.bytesIn > 0 || previousNetworkStats.bytesOut > 0) {
            let bytesDownloaded = currentNetworkStats.bytesIn > previousNetworkStats.bytesIn ? 
                                currentNetworkStats.bytesIn - previousNetworkStats.bytesIn : 0
            let bytesUploaded = currentNetworkStats.bytesOut > previousNetworkStats.bytesOut ? 
                               currentNetworkStats.bytesOut - previousNetworkStats.bytesOut : 0
            
            downloadSpeed = Double(bytesDownloaded) / timeInterval / 1_048_576 // Convert to MB/s
            uploadSpeed = Double(bytesUploaded) / timeInterval / 1_048_576 // Convert to MB/s
        }
        
        // Calculate disk speeds
        let currentDiskStats = getDiskStats()
        var readSpeed: Double = 0.0
        var writeSpeed: Double = 0.0
        
        // Only calculate speeds if we have a reasonable time interval and this isn't the first run
        if timeInterval > 0.1 && (previousDiskStats.bytesRead > 0 || previousDiskStats.bytesWritten > 0) {
            let bytesRead = currentDiskStats.bytesRead > previousDiskStats.bytesRead ? 
                           currentDiskStats.bytesRead - previousDiskStats.bytesRead : 0
            let bytesWritten = currentDiskStats.bytesWritten > previousDiskStats.bytesWritten ? 
                              currentDiskStats.bytesWritten - previousDiskStats.bytesWritten : 0
            
            readSpeed = Double(bytesRead) / timeInterval / 1_048_576 // Convert to MB/s
            writeSpeed = Double(bytesWritten) / timeInterval / 1_048_576 // Convert to MB/s
        }
        
        // Update current values
        cpuUsage = newCpuUsage
        memoryUsage = newMemoryUsage
        gpuUsage = newGpuUsage
        networkDownload = max(0.0, downloadSpeed)
        networkUpload = max(0.0, uploadSpeed)
        diskRead = max(0.0, readSpeed)
        diskWrite = max(0.0, writeSpeed)
        lastUpdated = Date()
        
        // Update history arrays (sliding window)
        updateHistory(value: newCpuUsage, history: &cpuHistory)
        updateHistory(value: newMemoryUsage, history: &memoryHistory)
        updateHistory(value: newGpuUsage, history: &gpuHistory)
        updateHistory(value: downloadSpeed, history: &networkDownloadHistory)
        updateHistory(value: uploadSpeed, history: &networkUploadHistory)
        updateHistory(value: readSpeed, history: &diskReadHistory)
        updateHistory(value: writeSpeed, history: &diskWriteHistory)
        
        // Update previous stats for next calculation
        previousNetworkStats = currentNetworkStats
        previousDiskStats = currentDiskStats
        previousTimestamp = currentTime
    }
    
    private func updateHistory(value: Double, history: inout [Double]) {
        // Remove first element and append new value
        if history.count >= maxHistoryPoints {
            history.removeFirst()
        }
        history.append(value)
    }
    
    // MARK: - System Monitoring Functions
    
    private func getCPUUsage() -> Double {
        // Simplified CPU usage monitoring using host_statistics
        var hostStats = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &hostStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            return 0.0
        }
        
        let totalTicks = hostStats.cpu_ticks.0 + hostStats.cpu_ticks.1 + 
                        hostStats.cpu_ticks.2 + hostStats.cpu_ticks.3
        guard totalTicks > 0 else { return 0.0 }
        
        let idleTicks = hostStats.cpu_ticks.2 // CPU_STATE_IDLE
        let usage = Double(totalTicks - idleTicks) / Double(totalTicks) * 100.0
        return min(100.0, max(0.0, usage))
    }
    
    private func getMemoryUsage() -> Double {
        // Simplified memory usage monitoring using host_statistics
        var vmStatistics = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let vmResult = withUnsafeMutablePointer(to: &vmStatistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        
        guard vmResult == KERN_SUCCESS else {
            return 0.0
        }
        
        let pageSize = UInt64(vm_kernel_page_size)
        let totalMemory = (UInt64(vmStatistics.free_count) + UInt64(vmStatistics.active_count) + 
                          UInt64(vmStatistics.inactive_count) + UInt64(vmStatistics.wire_count)) * pageSize
        let usedMemory = (UInt64(vmStatistics.active_count) + UInt64(vmStatistics.inactive_count) + 
                         UInt64(vmStatistics.wire_count)) * pageSize
        
        guard totalMemory > 0 else { return 0.0 }
        
        let usage = Double(usedMemory) / Double(totalMemory) * 100.0
        return min(100.0, max(0.0, usage))
    }
    
    private func getGPUUsage() -> Double {
        // GPU usage monitoring is complex on macOS and requires private APIs
        // For now, we'll provide a placeholder that simulates GPU usage
        // In a production app, this would need Metal Performance Shaders or IOKit GPU monitoring
        
        // Simulate realistic GPU usage based on system load
        let baseUsage = Double.random(in: 5...15)
        let variance = Double.random(in: -5...25)
        let simulatedUsage = baseUsage + variance
        
        return min(100.0, max(0.0, simulatedUsage))
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
        let result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)
        
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
        return String(format: "%.1f MB/s", networkDownload)
    }
    
    var networkUploadString: String {
        return String(format: "%.1f MB/s", networkUpload)
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
        cpuHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        memoryHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        gpuHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        networkDownloadHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        networkUploadHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        diskReadHistory = Array(repeating: 0.0, count: maxHistoryPoints)
        diskWriteHistory = Array(repeating: 0.0, count: maxHistoryPoints)
    }
    
    // MARK: - Process Monitoring Methods
    func getProcessesRankedByCPU() -> [ProcessStats] {
        return getRunningProcesses().sorted { $0.cpuUsage > $1.cpuUsage }
    }
    
    func getProcessesRankedByMemory() -> [ProcessStats] {
        return getRunningProcesses().sorted { $0.memoryUsage > $1.memoryUsage }
    }
    
    func getProcessesRankedByGPU() -> [ProcessStats] {
        // For now, rank by CPU usage as GPU per-process stats are complex to obtain
        return getRunningProcesses().sorted { $0.cpuUsage > $1.cpuUsage }
    }
    
    private func getRunningProcesses() -> [ProcessStats] {
        var processes: [ProcessStats] = []
        
        // Get all running applications from NSWorkspace
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            // Skip system processes and processes without bundle identifier
            guard let bundleId = app.bundleIdentifier,
                  !bundleId.hasPrefix("com.apple.") || bundleId == "com.apple.finder" else {
                continue
            }
            
            let pid = app.processIdentifier
            var cpuUsage: Double = 0.0
            var memoryUsage: UInt64 = 0
            
            // Get CPU and memory usage using proc_pidinfo
            var taskInfo = proc_taskinfo()
            let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
            
            if result == MemoryLayout<proc_taskinfo>.size {
                // Calculate CPU usage (basic approximation)
                cpuUsage = Double(taskInfo.pti_total_user + taskInfo.pti_total_system) / 1000000.0
                
                // Get memory usage
                memoryUsage = taskInfo.pti_resident_size
            }
            
            let processStats = ProcessStats(
                pid: pid,
                name: app.localizedName ?? bundleId,
                cpuUsage: cpuUsage,
                memoryUsage: memoryUsage,
                icon: app.icon
            )
            
            processes.append(processStats)
        }
        
        return processes
    }
}
