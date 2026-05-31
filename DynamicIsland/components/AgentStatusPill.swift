/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Defaults
import SwiftUI

// MARK: - Compact Pill (closed notch)

struct AgentStatusPill: View {
    @ObservedObject private var manager = AgentStatusManager.shared
    @State private var elapsed: String = "0:00"
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if Defaults[.enableAgentStatus], let session = manager.primarySession {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                
                Text(session.agentName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white)
                
                Text(elapsed)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                
                if session.tokenCount > 0 {
                    Text("\(formatTokens(session.tokenCount))t")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
            )
            .onReceive(timer) { _ in
                elapsed = session.formattedElapsed
            }
            .onAppear {
                elapsed = session.formattedElapsed
            }
        }
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

// MARK: - Expanded View

struct AgentStatusExpandedView: View {
    @ObservedObject private var manager = AgentStatusManager.shared
    @State private var elapsed: String = "0:00"
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        if Defaults[.enableAgentStatus], !manager.activeSessions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(manager.activeSessions.prefix(3)) { session in
                    sessionRow(session)
                }
            }
            .padding(12)
            .onReceive(timer) { _ in
                if let session = manager.primarySession {
                    elapsed = session.formattedElapsed
                }
            }
        }
    }
    
    @ViewBuilder
    private func sessionRow(_ session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                
                Text(session.agentName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(session.formattedElapsed)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }
            
            Text(session.title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(2)
            
            HStack(spacing: 12) {
                Label(session.model, systemImage: "cpu")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                
                if session.tokenCount > 0 {
                    Label("\(session.tokenCount) tokens", systemImage: "number")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Label(session.estimatedCost, systemImage: "dollarsign.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }
}
