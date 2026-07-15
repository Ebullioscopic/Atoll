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

struct CPUFrequencyMetrics: Equatable {
    let overallGHz: Double
    let eCoreGHz: Double?
    let pCoreGHz: Double?
    let maxOverallGHz: Double
    let maxECoreGHz: Double?
    let maxPCoreGHz: Double?
}

struct CPUTemperatureMetrics: Equatable {
    let celsius: Double?

    var fahrenheit: Double? {
        guard let celsius else { return nil }
        return celsius * 9.0 / 5.0 + 32.0
    }
}

final class CPUSensorCollector {
    private let hardware = AppleHardwareInfo.shared
    private var channels: CFMutableDictionary?
    private var subscription: IOReportSubscriptionRef?
    private var previousSample: (samples: CFDictionary, time: TimeInterval)?

    init() {
        setupFrequencyChannel()
    }

    deinit {
        if let subscription {
            IOReportCreateSamples(subscription, nil, nil) // best-effort flush
        }
    }

    func readTemperature() -> CPUTemperatureMetrics {
        let platform = hardware.platform
        if let value = primaryTemperatureKeyCandidates.compactMap({ SMC.shared.getValue($0) }).first(where: { $0 < 110 }) {
            return CPUTemperatureMetrics(celsius: value)
        }
        let list = temperatureFallbackKeys(for: platform)
        var total: Double = 0
        var count: Double = 0
        for key in list {
            if let value = SMC.shared.getValue(key), value < 110 {
                total += value
                count += 1
            }
        }
        guard total > 0, count > 0 else {
            return CPUTemperatureMetrics(celsius: nil)
        }
        return CPUTemperatureMetrics(celsius: total / count)
    }

    func readFrequency() -> CPUFrequencyMetrics? {
        guard let channels, let subscription else { return nil }
        let timestamp = Date().timeIntervalSince1970
        guard let currentSample = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue() else {
            return nil
        }
        defer {
            previousSample = (currentSample, timestamp)
        }
        guard let previous = previousSample,
              let diff = IOReportCreateSamplesDelta(previous.samples, currentSample, nil)?.takeRetainedValue() else {
            return nil
        }

        let samples = collectIOSamples(from: diff)
        let eFrequencies = hardware.clusterFrequencies.eCoreFrequencies
        let pFrequencies = hardware.clusterFrequencies.pCoreFrequencies
        let eCount = max(hardware.clusterCounts.eCores, 0)
        let pCount = max(hardware.clusterCounts.pCores, 0)

        var eValues: [Double] = []
        var pValues: [Double] = []

        for sample in samples where sample.group == "CPU Stats" {
            if sample.channel.hasPrefix("ECPU") {
                let value = calculateFrequency(from: sample.delta, freqs: eFrequencies)
                if value > 0 { eValues.append(value) }
            } else if sample.channel.hasPrefix("PCPU") {
                let value = calculateFrequency(from: sample.delta, freqs: pFrequencies)
                if value > 0 { pValues.append(value) }
            }
        }

        let eAverage = eValues.isEmpty ? nil : (eValues.reduce(0, +) / Double(eValues.count))
        let pAverage = pValues.isEmpty ? nil : (pValues.reduce(0, +) / Double(pValues.count))

        guard eAverage != nil || pAverage != nil else {
            return nil
        }

        let overall: Double
        if let eAverage, let pAverage, (eCount + pCount) > 0 {
            overall = ((eAverage * Double(eCount)) + (pAverage * Double(pCount))) / Double(eCount + pCount)
        } else if let eAverage {
            overall = eAverage
        } else if let pAverage {
            overall = pAverage
        } else {
            return nil
        }

        let maxE = eFrequencies.max().map { Double($0) / 1000 }
        let maxP = pFrequencies.max().map { Double($0) / 1000 }
        let maxOverall: Double
        if let maxE, let maxP, (eCount + pCount) > 0 {
            maxOverall = ((maxE * Double(eCount)) + (maxP * Double(pCount))) / Double(max(eCount + pCount, 1))
        } else if let maxE {
            maxOverall = maxE
        } else if let maxP {
            maxOverall = maxP
        } else {
            maxOverall = (overall / 1000)
        }

        return CPUFrequencyMetrics(
            overallGHz: overall / 1000,
            eCoreGHz: eAverage.map { $0 / 1000 },
            pCoreGHz: pAverage.map { $0 / 1000 },
            maxOverallGHz: maxOverall,
            maxECoreGHz: maxE,
            maxPCoreGHz: maxP
        )
    }

    // MARK: - Private Helpers
    private func setupFrequencyChannel() {
        let names = [
            ("CPU Stats" as CFString, "CPU Complex Performance States" as CFString),
            ("CPU Stats" as CFString, "CPU Core Performance States" as CFString)
        ]
        var mergedChannels: CFMutableDictionary?
        var list: [CFDictionary] = []
        for (group, subgroup) in names {
            if let channel = IOReportCopyChannelsInGroup(group, subgroup, 0, 0, 0)?.takeRetainedValue() {
                list.append(channel)
            }
        }
        guard let first = list.first else { return }
        for channel in list.dropFirst() {
            IOReportMergeChannels(first, channel, nil)
        }
        guard let copy = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, CFDictionaryGetCount(first), first) else {
            return
        }
        mergedChannels = copy
        channels = mergedChannels
        var dictionary: Unmanaged<CFMutableDictionary>?
        subscription = IOReportCreateSubscription(nil, mergedChannels, &dictionary, 0, nil)
        dictionary?.release()
    }

    private struct IOSample {
        let group: String
        let subGroup: String
        let channel: String
        let unit: String
        let delta: CFDictionary
    }

    private func collectIOSamples(from data: CFDictionary) -> [IOSample] {
        let key = "IOReportChannels" as CFString
        var rawValue: UnsafeRawPointer?
        let found = withUnsafeMutablePointer(to: &rawValue) { pointer -> Bool in
            CFDictionaryGetValueIfPresent(data, Unmanaged.passUnretained(key).toOpaque(), pointer)
        }
        guard found, let rawValue else { return [] }
        let array = unsafeBitCast(rawValue, to: CFArray.self)
        var result: [IOSample] = []
        for index in 0..<CFArrayGetCount(array) {
            let element = CFArrayGetValueAtIndex(array, index)
            let entry = unsafeBitCast(element, to: CFDictionary.self)
            let group = IOReportChannelGetGroup(entry)?.takeUnretainedValue() as String? ?? ""
            let subGroup = IOReportChannelGetSubGroup(entry)?.takeUnretainedValue() as String? ?? ""
            let channel = IOReportChannelGetChannelName(entry)?.takeUnretainedValue() as String? ?? ""
            let unit = IOReportChannelGetUnitLabel(entry)?.takeUnretainedValue() as String? ?? ""
            result.append(IOSample(group: group, subGroup: subGroup, channel: channel, unit: unit, delta: entry))
        }
        return result
    }

    private func getResidencies(dict: CFDictionary) -> [(label: String, value: Int64)] {
        let count = IOReportStateGetCount(dict)
        var result: [(String, Int64)] = []
        for index in 0..<count {
            let name = IOReportStateGetNameForIndex(dict, index)?.takeUnretainedValue() as String? ?? ""
            let value = IOReportStateGetResidency(dict, index)
            result.append((name, value))
        }
        return result
    }

    private func calculateFrequency(from dict: CFDictionary, freqs: [Int32]) -> Double {
        guard !freqs.isEmpty else { return 0 }
        let states = getResidencies(dict: dict)
        guard let offset = states.firstIndex(where: { !$0.label.elementsEqual("IDLE") && !$0.label.elementsEqual("DOWN") && !$0.label.elementsEqual("OFF") }) else {
            return 0
        }
        let usage = states.dropFirst(offset).reduce(0.0) { $0 + Double($1.value) }
        guard usage > 0 else { return 0 }
        var total: Double = 0
        for (index, frequency) in freqs.enumerated() {
            let stateIndex = offset + index
            guard states.indices.contains(stateIndex) else { continue }
            let fraction = Double(states[stateIndex].value) / usage
            total += fraction * Double(frequency)
        }
        return total
    }

    private var primaryTemperatureKeyCandidates: [String] {
        ["TC0D", "TC0E", "TC0F", "TC0P", "TC0H"]
    }

    private func temperatureFallbackKeys(for platform: ApplePlatform?) -> [String] {
        switch platform {
        case .m1, .m1Pro, .m1Max, .m1Ultra:
            return ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"]
        case .m2, .m2Pro, .m2Max, .m2Ultra:
            return ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"]
        case .m3, .m3Pro, .m3Max, .m3Ultra:
            return ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"]
        case .m4, .m4Pro, .m4Max, .m4Ultra:
            return ["Te05", "Te09", "Te0H", "Te0S", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        case .m5, .m5Pro, .m5Max, .m5Ultra:
            return ["Te05", "Te09", "Te0H", "Te0S", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"]
        default:
            return ["TC0P", "TC0E", "TC0F", "TC0H", "TC0D"]
        }
    }
}
