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

import SwiftUI
import Combine
import Defaults

struct NotchAgentBusView: View {
    @ObservedObject var manager = ExtensionLiveActivityManager.shared

    @State private var elapsed: TimeInterval = 0
    @State private var isPulse = false
    @State private var timerSubscription: AnyCancellable?

    var body: some View {
        VStack(spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Text("🤖 Agent Bus")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)

                Spacer()

                if Defaults[.enableAgentConnectionMonitor] {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ExtensionRPCServer.shared.hasActiveConnections ? Color.green : Color.gray)
                            .frame(width: 9, height: 9)
                            .scaleEffect(isPulse && ExtensionRPCServer.shared.hasActiveConnections ? 1.2 : 0.85)
                            .shadow(color: ExtensionRPCServer.shared.hasActiveConnections ? .green.opacity(0.7) : .clear, radius: 4)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulse)

                        Text(ExtensionRPCServer.shared.hasActiveConnections ? "🟢 Live" : "⚫ Idle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let activePayload = manager.activeActivities.first {
                let descriptor = activePayload.descriptor
                let agentName = activePayload.bundleIdentifier.lowercased()
                let baseColor = agentColor(for: agentName)

                // Active agent badge + elapsed
                HStack {
                    HStack(spacing: 6) {
                        Text(agentEmoji(for: agentName))
                            .font(.system(size: 18))
                        Text(agentDisplayName(for: agentName))
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(baseColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(baseColor.opacity(0.15))
                    .clipShape(Capsule())

                    Spacer()

                    Text("⏱ \(formatTimeInterval(elapsed))")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }

                // Progress bar (indeterminate shimmer while active)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(baseColor.opacity(0.12))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [baseColor.opacity(0.2), baseColor.opacity(0.9), baseColor, baseColor.opacity(0.9), baseColor.opacity(0.2)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * 0.35)
                            .offset(x: isPulse ? geo.size.width * 0.65 : 0)
                            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: isPulse)
                    }
                }
                .frame(height: 6)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                // Metrics row
                if Defaults[.enableAgentSpeedometer] {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("⚡ SPEED")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f T/s", manager.currentSpeed))
                                .font(.system(size: 15, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("💰 COST")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(String(format: "$%.4f", manager.currentCost))
                                .font(.system(size: 15, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Current plan
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("📋")
                            .font(.system(size: 14))
                        Text(descriptor.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    if let subtitle = descriptor.subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Approve/Reject
                if Defaults[.enableAgentInteractiveActions] {
                    HStack(spacing: 12) {
                        Button {
                            manager.handleAgentAction(approve: true, bundleIdentifier: activePayload.bundleIdentifier, activityID: activePayload.descriptor.id)
                        } label: {
                            HStack(spacing: 5) {
                                Text("✅")
                                    .font(.system(size: 14))
                                Text("Approve")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.4), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)

                        Button {
                            manager.handleAgentAction(approve: false, bundleIdentifier: activePayload.bundleIdentifier, activityID: activePayload.descriptor.id)
                        } label: {
                            HStack(spacing: 5) {
                                Text("❌")
                                    .font(.system(size: 14))
                                Text("Reject")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.4), lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Text("📡")
                        .font(.system(size: 36))
                    Text("No active agents")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("Waiting for connections…")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            }

            // Session history
            if Defaults[.enableAgentHistoryShelf] && !manager.historyShelf.isEmpty {
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 6) {
                    Text("📜 History")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.secondary)

                    ForEach(manager.historyShelf.prefix(3)) { entry in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: entry.statusColorHex))
                                .frame(width: 7, height: 7)
                            Text(entry.agentName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                            Text(entry.eventType)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(entry.timestamp, style: .time)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onAppear {
            isPulse = true
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

    private func agentEmoji(for name: String) -> String {
        if name.contains("antigravity") { return "🚀" }
        if name.contains("codex") { return "🧠" }
        if name.contains("nerv") { return "🔮" }
        if name.contains("claude") { return "🪄" }
        if name.contains("copilot") { return "✨" }
        if name.contains("kilo") { return "⚡" }
        return "🤖"
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
