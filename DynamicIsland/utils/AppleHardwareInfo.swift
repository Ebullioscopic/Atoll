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
import IOKit
import Darwin

enum ApplePlatform: String {
    case intel
    case m1
    case m1Pro
    case m1Max
    case m1Ultra
    case m2
    case m2Pro
    case m2Max
    case m2Ultra
    case m3
    case m3Pro
    case m3Max
    case m3Ultra
    case m4
    case m4Pro
    case m4Max
    case m4Ultra
    case m5
    case m5Pro
    case m5Max
    case m5Ultra
}

struct CPUClusterFrequencies {
    let eCoreFrequencies: [Int32]
    let pCoreFrequencies: [Int32]
}

struct CPUClusterCounts {
    let eCores: Int
    let pCores: Int
}

final class AppleHardwareInfo {
    static let shared = AppleHardwareInfo()
    let cpuName: String?
    let platform: ApplePlatform?
    let logicalCoreCount: Int
    let clusterCounts: CPUClusterCounts
    let clusterFrequencies: CPUClusterFrequencies

    private init() {
        let name = AppleHardwareInfo.fetchCPUName()
        cpuName = name
        platform = AppleHardwareInfo.detectPlatform(from: name)
        logicalCoreCount = AppleHardwareInfo.fetchLogicalCoreCount()
        clusterCounts = AppleHardwareInfo.fetchClusterCounts()
        clusterFrequencies = AppleHardwareInfo.fetchClusterFrequencies(cpuName: name ?? "")
    }

    private static func fetchCPUName() -> String? {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        let result = sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        guard result == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func fetchLogicalCoreCount() -> Int {
        var cores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("hw.logicalcpu", &cores, &size, nil, 0)
        return result == 0 ? Int(cores) : ProcessInfo.processInfo.processorCount
    }

    private static func detectPlatform(from cpuName: String?) -> ApplePlatform? {
        guard let name = cpuName?.lowercased() else { return nil }
        if name.contains("intel") { return .intel }
        if name.contains("m1") {
            if name.contains("ultra") { return .m1Ultra }
            if name.contains("max") { return .m1Max }
            if name.contains("pro") { return .m1Pro }
            return .m1
        }
        if name.contains("m2") {
            if name.contains("ultra") { return .m2Ultra }
            if name.contains("max") { return .m2Max }
            if name.contains("pro") { return .m2Pro }
            return .m2
        }
        if name.contains("m3") {
            if name.contains("ultra") { return .m3Ultra }
            if name.contains("max") { return .m3Max }
            if name.contains("pro") { return .m3Pro }
            return .m3
        }
        if name.contains("m4") {
            if name.contains("ultra") { return .m4Ultra }
            if name.contains("max") { return .m4Max }
            if name.contains("pro") { return .m4Pro }
            return .m4
        }
        if name.contains("m5") {
            if name.contains("ultra") { return .m5Ultra }
            if name.contains("max") { return .m5Max }
            if name.contains("pro") { return .m5Pro }
            return .m5
        }
        return nil
    }

    private static func fetchClusterCounts() -> CPUClusterCounts {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("AppleARMPE"), &iterator) == KERN_SUCCESS else {
            return CPUClusterCounts(eCores: 0, pCores: 0)
        }
        defer { IOObjectRelease(iterator) }
        var eCoreCount: Int32 = 0
        var pCoreCount: Int32 = 0

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var children = io_iterator_t()
            guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &children) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(children) }

            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                guard let name = di_getIOName(child), name == "cpus", let props = di_getIOProperties(child) else { continue }
                if let data = props.object(forKey: "e-core-count") as? Data {
                    eCoreCount = data.withUnsafeBytes { $0.load(as: Int32.self) }
                }
                if let data = props.object(forKey: "p-core-count") as? Data {
                    pCoreCount = data.withUnsafeBytes { $0.load(as: Int32.self) }
                }
            }
        }

        return CPUClusterCounts(eCores: Int(eCoreCount), pCores: Int(pCoreCount))
    }

    private static func fetchClusterFrequencies(cpuName: String) -> CPUClusterFrequencies {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("AppleARMIODevice"), &iterator) == KERN_SUCCESS else {
            return CPUClusterFrequencies(eCoreFrequencies: [], pCoreFrequencies: [])
        }
        defer { IOObjectRelease(iterator) }

        let lowerName = cpuName.lowercased()
        let isM4 = lowerName.contains("m4")
        let isM5 = lowerName.contains("m5")
        var eFreq: [Int32] = []
        var pFreq: [Int32] = []

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let name = di_getIOName(service), name == "pmgr", let props = di_getIOProperties(service) else { continue }

            if let data = props["voltage-states1-sram"] as? Data {
                eFreq = di_convertCFDataToFrequencies(data, isM4: isM4 || isM5)
            }
            if let data = props["voltage-states5-sram"] as? Data {
                pFreq = di_convertCFDataToFrequencies(data, isM4: isM4 || isM5)
            }
        }

        return CPUClusterFrequencies(eCoreFrequencies: eFreq, pCoreFrequencies: pFreq)
    }
}
