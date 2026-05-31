/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI
import Combine
import Defaults

/// Scrolling agent status ticker for the closed notch bar.
/// Shows active Hermes/Copilot sessions with emoji, title, elapsed time, and a progress shimmer.
struct AgentNotchTicker: View {
    let frameWidth: CGFloat
    
    @ObservedObject private var manager = AgentStatusManager.shared
    @State private var elapsed: TimeInterval = 0
    @State private var timerSub: AnyCancellable?
    @State private var shimmerOffset: CGFloat = -1.0
    
    var body: some View {
        if let session = manager.activeSessions.first {
            HStack(spacing: 6) {
                // Pulsing dot
                Circle()
                    .fill(agentColor(for: session.model))
                    .frame(width: 7, height: 7)
                    .shadow(color: agentColor(for: session.model).opacity(0.8), radius: 3)
                
                // Emoji + agent name
                Text("\(agentEmoji(for: session.model)) \(agentName(for: session.model))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                
                // Title (scrolling if long)
                if manager.activeSessions.count == 1 {
                    Text(session.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                Spacer(minLength: 4)
                
                // Elapsed time
                Text(formatElapsed(elapsed))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(agentColor(for: session.model).opacity(0.9))
                
                // Token count if available
                if session.tokenCount > 0 {
                    Text("\(formatTokens(session.tokenCount))t")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
                
                // Multi-session indicator
                if manager.activeSessions.count > 1 {
                    Text("+\(manager.activeSessions.count - 1)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .frame(width: frameWidth, alignment: .leading)
            .onAppear {
                elapsed = Date().timeIntervalSince(session.startedAt)
                timerSub = Timer.publish(every: 1, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in
                        if let s = manager.activeSessions.first {
                            elapsed = Date().timeIntervalSince(s.startedAt)
                        }
                    }
            }
            .onDisappear {
                timerSub?.cancel()
                timerSub = nil
            }
        }
    }
    
    private func agentColor(for model: String) -> Color {
        let m = model.lowercased()
        if m.contains("opus") { return .purple }
        if m.contains("sonnet") { return .cyan }
        if m.contains("gpt") || m.contains("o1") || m.contains("o3") { return .green }
        if m.contains("gemini") { return .blue }
        return .orange
    }
    
    private func agentEmoji(for model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus") { return "🔮" }
        if m.contains("sonnet") { return "⚡" }
        if m.contains("gpt") || m.contains("o1") || m.contains("o3") { return "🧠" }
        if m.contains("copilot") { return "✨" }
        return "🤖"
    }
    
    private func agentName(for model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("gpt-5") { return "GPT-5" }
        if m.contains("gpt-4") { return "GPT-4" }
        if m.contains("o1") { return "o1" }
        if m.contains("o3") { return "o3" }
        if m.contains("gemini") { return "Gemini" }
        return model.components(separatedBy: "/").last?.prefix(12).description ?? "Agent"
    }
    
    private func formatElapsed(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }
}
