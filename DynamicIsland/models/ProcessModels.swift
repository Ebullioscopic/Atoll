//
//  ProcessModels.swift
//  DynamicIsland
//
//  Defines process-related models used by stats views/managers.
//

import Foundation
import AppKit

// Ranking categories for process popovers
enum ProcessRankingType {
    case cpu
    case memory
    case gpu
}

// Lightweight model for per-process stats
struct ProcessStats: Identifiable {
    let pid: pid_t
    let name: String
    let cpuUsage: Double
    let memoryUsage: UInt64
    let icon: NSImage?
    
    var id: pid_t { pid }
}


