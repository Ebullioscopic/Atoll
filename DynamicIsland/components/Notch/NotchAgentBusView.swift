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
import Defaults

struct NotchAgentBusView: View {
    @ObservedObject var manager = ExtensionLiveActivityManager.shared

    @State private var elapsed: TimeInterval = 0
    @State private var isPulse = false
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Text("Agent Bus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()

                if Defaults[.enableAgentConnectionMonitor] {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(ExtensionRPCServer.shared.hasActiveConnections ? Color.green : Color.gray)
                            .frame(width: 7, height: 7)
                            .scaleEffect(isPulse && ExtensionRPCServer.shared.hasActiveConnections ? 1.15 : 0.9)
                            .shadow(color: ExtensionRPCServer.shared.hasActiveConnections ? .green.opacity(0.6) : .clear, radius: 3)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulse)

                        Text(ExtensionRPCServer.shared.hasActiveConnections ? "Connected" : "Idle")
                            .font(.system(size: 10, weight: .medium))
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
                    Text(agentDisplayName(for: agentName))
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(baseColor.opacity(0.18))
                        .foregroundStyle(baseColor)
                        .clipShape(Capsule())

                    Spacer()

                    Text(formatTimeInterval(elapsed))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Progress bar (indeterminate shimmer while active)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(baseColor.opacity(0.15))

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [baseColor.opacity(0.3), baseColor, baseColor.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * 0.3)
                            .offset(x: isPulse ? geo.size.width * 0.7 : 0)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isPulse)
                    }
                }
                .frame(height: 4)
                .clipShape(RoundedRectangle(cornerRadius: 3))

                // Metrics row
                if Defaults[.enableAgentSpeedometer] {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SPEED")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f T/s", manager.currentSpeed))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("COST")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(String(format: "$%.4f", manager.currentCost))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // Current plan
                VStack(alignment: .leading, spacing: 3) {
                    Text(descriptor.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    if let subtitle = descriptor.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Approve/Reject
                if Defaults[.enableAgentInteractiveActions] {
                    HStack(spacing: 10) {
                        Button {
                            manager.handleAgentAction(approve: true, bundleIdentifier: activePayload.bundleIdentifier, activityID: activePayload.descriptor.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text("👍")
                                Text("Approve").fontWeight(.semibold)
                            }
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Button {
                            manager.handleAgentAction(approve: false, bundleIdentifier: activePayload.bundleIdentifier, activityID: activePayload.descriptor.id)
                        } label: {
                            HStack(spacing: 4) {
                                Text("👎")
                                Text("Reject").fontWeight(.semibold)
                            }
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No active agents")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            }

            // Session history
            if Defaults[.enableAgentHistoryShelf] && !manager.historyShelf.isEmpty {
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 4) {
                    Text("History")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    ForEach(manager.historyShelf.prefix(3)) { entry in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: entry.statusColorHex))
                                .frame(width: 5, height: 5)
                            Text(entry.agentName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                            Text(entry.eventType)
                                .font(.system(size: 10))
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear {
            isPulse = true
            if let first = manager.activeActivities.first {
                elapsed = Date().timeIntervalSince(first.receivedAt)
            }
        }
        .onReceive(timer) { _ in
            if let first = manager.activeActivities.first {
                elapsed = Date().timeIntervalSince(first.receivedAt)
            }
        }
    }

    private func agentDisplayName(for name: String) -> String {
        if name.contains("antigravity") { return "Antigravity" }
        if name.contains("codex") { return "Codex" }
        if name.contains("nerv") { return "NERV Brain" }
        if name.contains("claude") { return "Claude" }
        if name.contains("copilot") { return "Copilot" }
        return name.capitalized
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
