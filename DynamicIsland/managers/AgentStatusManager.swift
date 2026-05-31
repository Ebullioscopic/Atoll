/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Combine
import Defaults
import Foundation
import SQLite3
import SwiftUI

// MARK: - AgentSession Model

struct AgentSession: Identifiable, Equatable {
    let id: String
    let title: String
    let model: String
    let startedAt: Date
    let source: String
    var tokenCount: Int
    
    var elapsedTime: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
    
    var formattedElapsed: String {
        let elapsed = Int(elapsedTime)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var agentName: String {
        if source.lowercased().contains("copilot") {
            return "Copilot"
        }
        return "Hermes"
    }
    
    var estimatedCost: String {
        // Rough estimate based on model and tokens
        let costPer1k: Double
        switch model.lowercased() {
        case let m where m.contains("opus"):
            costPer1k = 0.075
        case let m where m.contains("sonnet"):
            costPer1k = 0.015
        case let m where m.contains("gpt-4"):
            costPer1k = 0.03
        default:
            costPer1k = 0.01
        }
        let cost = Double(tokenCount) / 1000.0 * costPer1k
        if cost < 0.01 {
            return "<$0.01"
        }
        return String(format: "$%.2f", cost)
    }
}

// MARK: - AgentStatusManager

@MainActor
class AgentStatusManager: ObservableObject {
    static let shared = AgentStatusManager()
    
    @Published var activeSessions: [AgentSession] = []
    @Published var isActive: Bool = false
    
    private var pollTimer: AnyCancellable?
    private let dbPath: String
    
    var primarySession: AgentSession? {
        activeSessions.first
    }
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.dbPath = "\(home)/.hermes/sessions/sessions.db"
        startPolling()
    }
    
    func startPolling() {
        guard Defaults[.enableAgentStatus] else {
            stopPolling()
            return
        }
        pollTimer = Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.pollSessions()
                }
            }
        // Initial poll
        pollSessions()
    }
    
    func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
        activeSessions = []
        isActive = false
    }
    
    private func pollSessions() {
        guard Defaults[.enableAgentStatus] else {
            stopPolling()
            return
        }
        
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            activeSessions = []
            isActive = false
            return
        }
        defer { sqlite3_close(db) }
        
        var sessions: [AgentSession] = []
        
        // Query active sessions
        let query = "SELECT id, title, model, started_at, source FROM sessions WHERE ended_at IS NULL ORDER BY started_at DESC"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_finalize(stmt) }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let title = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "Agent Task"
            let model = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? "unknown"
            let startedAtStr = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
            let source = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? "hermes"
            
            let startedAt = dateFormatter.date(from: startedAtStr)
                ?? fallbackFormatter.date(from: startedAtStr)
                ?? Date()
            
            let tokenCount = getTokenCount(db: db, sessionId: id)
            
            let session = AgentSession(
                id: id,
                title: title,
                model: model,
                startedAt: startedAt,
                source: source,
                tokenCount: tokenCount
            )
            sessions.append(session)
        }
        
        activeSessions = sessions
        isActive = !sessions.isEmpty
    }
    
    private func getTokenCount(db: OpaquePointer?, sessionId: String) -> Int {
        let query = "SELECT COALESCE(SUM(COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0)), 0) FROM messages WHERE session_id = ?"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        
        sqlite3_bind_text(stmt, 1, sessionId, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }
}
