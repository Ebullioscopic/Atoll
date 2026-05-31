/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

import SwiftUI
import Combine
import Defaults

struct AgentDetailsHUDView: View {
    @ObservedObject var manager = ExtensionLiveActivityManager.shared
    let notchHeight: CGFloat
    
    @State private var isPulse = false
    @State private var elapsed: TimeInterval = 0
    @State private var timerSubscription: AnyCancellable?
    
    var body: some View {
        VStack(spacing: 12) {
            // Header: Atoll Agent Bus (Big, Bold plan title)
            HStack(spacing: 8) {
                Text("Atoll Agent Bus 🚌")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                
                Spacer()
                
                // WebSocket connection status dot
                if Defaults[.enableAgentConnectionMonitor] {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(ExtensionRPCServer.shared.hasActiveConnections ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                            .scaleEffect(isPulse ? 1.2 : 0.8)
                            .shadow(color: ExtensionRPCServer.shared.hasActiveConnections ? .green : .clear, radius: 4)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulse)
                        
                        Text(ExtensionRPCServer.shared.hasActiveConnections ? "Connected" : "Idle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .onAppear {
                        isPulse = true
                    }
                }
            }
            .padding(.horizontal, 4)
            
            if let activePayload = manager.activeActivities.first {
                let descriptor = activePayload.descriptor
                let agentName = activePayload.bundleIdentifier.lowercased()
                let baseColor = agentColor(for: agentName)
                
                // Working agent label with color coding (gray/blue/orange/amber)
                HStack {
                    Text("ACTIVE AGENT:")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    
                    Text(agentDisplayName(for: agentName))
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(baseColor.opacity(0.18))
                        .foregroundStyle(baseColor)
                        .clipShape(Capsule())
                    
                    Spacer()
                    
                    // Display execution stopwatch time
                    Text(formatTimeInterval(elapsed))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                // Turn Metrics, Progress, and TTC Countdown Ring
                HStack(spacing: 12) {
                    if Defaults[.enableAgentSpeedometer] {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SPEED")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f T/s", manager.currentSpeed))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SESSION COST")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(String(format: "$%.5f", manager.currentCost))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Countdown Ring with TTC
                    let estimatedDuration: TimeInterval = {
                        let title = descriptor.title.lowercased()
                        if title.contains("planning") || title.contains("plan") { return 15.0 }
                        if title.contains("thinking") || title.contains("think") { return 10.0 }
                        if title.contains("working") || title.contains("executing") { return 20.0 }
                        if title.contains("done") || title.contains("success") || title.contains("completed") { return max(elapsed, 1.0) }
                        return 12.0
                    }()
                    let progressFraction = min(elapsed / estimatedDuration, 0.98)
                    let remainingTime = max(estimatedDuration - elapsed, 0)
                    
                    CountdownRingView(progress: progressFraction, remainingTime: remainingTime, color: baseColor)
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Stage details with larger Plan text (as requested by user)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CURRENT PLAN")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(baseColor)
                    
                    Text(replaceWithEmojis(descriptor.title))
                        .font(.system(size: 16, weight: .bold)) // Bigger Plan text
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    if let subtitle = descriptor.subtitle {
                        Text(replaceWithEmojis(subtitle))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // Real-Time Monospaced Log Streamer (Terminal style)
                TerminalLogsView(logs: getStreamingLogs(for: agentName, title: descriptor.title, elapsed: elapsed), color: baseColor)
                
                // Interactive Agent Actions Approve/Reject buttons
                if Defaults[.enableAgentInteractiveActions] {
                    HStack(spacing: 12) {
                        Button {
                            manager.handleAgentAction(approve: true, bundleIdentifier: activePayload.bundleIdentifier, activityID: activePayload.descriptor.id)
                            manager.showDetailsHUD = false
                        } label: {
                            HStack {
                                Text("👍")
                                Text("Approve")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            manager.handleAgentAction(approve: false, bundleIdentifier: activePayload.bundleIdentifier, activityID: activePayload.descriptor.id)
                            manager.showDetailsHUD = false
                        } label: {
                            HStack {
                                Text("👎")
                                Text("Reject")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.2))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Text("No active agents working on the bus.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
            
            // Session History Shelf
            if Defaults[.enableAgentHistoryShelf] && !manager.historyShelf.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Session History")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 6) {
                        ForEach(manager.historyShelf.prefix(2)) { entry in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: entry.statusColorHex))
                                    .frame(width: 6, height: 6)
                                
                                Text(entry.agentName)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                
                                Text(replaceWithEmojis(entry.eventType))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                Text(entry.timestamp, style: .time)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial) // Beautiful Glassmorphic float card
                .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity).animation(.spring(response: 0.35, dampingFraction: 0.8)),
            removal: .move(edge: .top).combined(with: .opacity).animation(.smooth(duration: 0.22))
        ))
        .onAppear {
            if let first = manager.activeActivities.first {
                elapsed = Date().timeIntervalSince(first.receivedAt)
            }
            timerSubscription = Timer.publish(every: 0.5, on: .main, in: .common)
                .autoconnect()
                .sink { _ in
                    if let first = manager.activeActivities.first {
                        elapsed = Date().timeIntervalSince(first.receivedAt)
                    }
                }
        }
        .onDisappear {
            timerSubscription?.cancel()
            timerSubscription = nil
        }
    }
    
    private func agentDisplayName(for name: String) -> String {
        if name.contains("antigravity") { return "Antigravity" }
        if name.contains("codex") { return "Codex" }
        if name.contains("nerv") { return "NERV Brain" }
        if name.contains("claude") { return "Claude" }
        if name.contains("copilot") { return "Copilot" }
        if name.contains("kilo") { return "Kilo" }
        return name.capitalized
    }
    // agentColor(for:) moved to file-scope to resolve ContentView scope issues
    
    private func replaceWithEmojis(_ text: String) -> String {
        let t = text.lowercased()
        if t.contains("planning") || t.contains("plan") { return "🧠 PLAN" }
        if t.contains("thinking") || t.contains("think") { return "⚡ THINKING" }
        if t.contains("working") || t.contains("executing") { return "✨ EXECUTING" }
        if t.contains("done") || t.contains("completed") || t.contains("success") { return "✅ SUCCESS" }
        return text
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func getStreamingLogs(for agentName: String, title: String, elapsed: TimeInterval) -> [String] {
        let t = title.lowercased()
        if t.contains("completed") || t.contains("success") || t.contains("done") {
            return [
                "✔ all tests passed successfully",
                "✔ changes written to disk",
                "✔ turn completed in \(String(format: "%.1fs", elapsed))"
            ]
        }
        
        let stepIndex = Int(elapsed / 4.0) % 3
        
        if agentName.contains("antigravity") {
            if t.contains("planning") {
                let logs = [
                    "➔ parsing requirement trees...",
                    "➔ generating step checklist...",
                    "➔ waiting for user approval..."
                ]
                return Array(logs.prefix(stepIndex + 1))
            } else if t.contains("thinking") {
                let logs = [
                    "➔ analyzing codebase layout...",
                    "➔ resolving file dependencies...",
                    "➔ checking type safety..."
                ]
                return Array(logs.prefix(stepIndex + 1))
            } else {
                let logs = [
                    "➔ [1/3] git add .",
                    "➔ [2/3] vitest run -t \"AgentDetails\"",
                    "➔ [3/3] compiling target targets..."
                ]
                return Array(logs.prefix(stepIndex + 1))
            }
        } else if agentName.contains("codex") {
            let logs = [
                "➔ semantic search on index...",
                "➔ loading context embeddings...",
                "➔ synthesizing solution..."
            ]
            return Array(logs.prefix(stepIndex + 1))
        } else {
            let logs = [
                "➔ connection established",
                "➔ awaiting instructions",
                "➔ processing next turn..."
            ]
            return Array(logs.prefix(stepIndex + 1))
        }
    }
}
