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
import AppKit
import SwiftUI

// Process information structure
struct ProcessStats: Identifiable, Hashable {
    let id = UUID()
    let pid: Int32
    let name: String
    let cpuUsage: Double
    let memoryUsage: UInt64 // in bytes
    let icon: NSImage?
    
    var memoryUsageString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(memoryUsage))
    }
    
    var cpuUsageString: String {
        return String(format: "%.1f%%", cpuUsage)
    }
}

enum ProcessRankingType {
    case cpu
    case memory
    case gpu
    case network
    case disk
    
    var title: String {
        switch self {
        case .cpu: return String(localized: "CPU Usage")
        case .memory: return String(localized: "Memory Usage")
        case .gpu: return String(localized: "GPU Usage")
        case .network: return String(localized: "Network Activity")
        case .disk: return String(localized: "Disk Activity")
        }
    }
    
    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .gpu: return "display"
        case .network: return "network"
        case .disk: return "internaldrive"
        }
    }
    
    var color: Color {
        switch self {
        case .cpu: return .blue
        case .memory: return .green
        case .gpu: return .purple
        case .network: return .orange
        case .disk: return .cyan
        }
    }
}