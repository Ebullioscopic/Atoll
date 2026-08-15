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

import Defaults
import SwiftUI

/// The Agents tab: one card per AI coding agent session on this Mac.
struct NotchAgentTowerView: View {
    @ObservedObject private var manager = AgentTowerManager.shared
    @EnvironmentObject var vm: DynamicIslandViewModel

    /// While the pointer is over this tab, the notch's own scroll gestures are
    /// held off. Without this the close-on-scroll gesture eats every wheel event
    /// and the session list cannot be scrolled at all.
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            // An approval outranks the session grid: it is the only thing here
            // that something is actively waiting on.
            if !manager.pendingRequests.isEmpty {
                approvals
            }
            content
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .onHover { updateSuppression(for: $0) }
        .onDisappear { updateSuppression(for: false) }
        .onAppear {
            manager.refreshInstallationState()
            manager.refreshVisibleContexts()
        }
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Agents")
                .font(.system(size: 13, weight: .semibold))

            if manager.runningCount > 0 {
                countBadge(
                    text: "\(manager.runningCount) " + String(localized: "running"),
                    tint: .blue
                )
            }
            if manager.waitingCount > 0 {
                countBadge(
                    text: "\(manager.waitingCount) " + String(localized: "waiting"),
                    tint: .orange
                )
            }

            Spacer(minLength: 0)

            if manager.finishedCount > 0 {
                Button(String(localized: "Clear finished")) {
                    manager.clearInactiveSessions()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func countBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.22), in: Capsule())
            .foregroundStyle(tint)
    }

    private var approvals: some View {
        VStack(spacing: 6) {
            // Worst risk first, so the most consequential decision is on top.
            ForEach(manager.pendingRequests.sorted { lhs, rhs in
                lhs.risk != rhs.risk ? lhs.risk > rhs.risk : lhs.receivedAt < rhs.receivedAt
            }) { request in
                AgentApprovalRequestView(
                    request: request,
                    projectName: manager.sessions.first { $0.id == request.sessionID }?.projectName
                ) { decision in
                    manager.resolve(requestID: request.id, with: decision)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth(duration: 0.2), value: manager.pendingRequests.map(\.id))
    }

    @ViewBuilder
    private var content: some View {
        if !Defaults[.enableAgentTower] {
            message(
                symbol: "power",
                title: String(localized: "Agent Tower is off"),
                detail: String(localized: "Turn it on in Settings to watch your coding agents here.")
            )
        } else if let error = manager.setupError {
            message(symbol: "exclamationmark.triangle", title: String(localized: "Not watching"), detail: error)
        } else if manager.installedKinds.isEmpty {
            message(
                symbol: "puzzlepiece.extension",
                title: String(localized: "No agent connected"),
                detail: String(localized: "Pick which agents to watch in Settings. Atoll adds a hook to that agent's own configuration.")
            )
        } else if manager.sessions.isEmpty {
            message(
                symbol: "moon.zzz",
                title: String(localized: "No sessions yet"),
                detail: String(localized: "Start an agent in a terminal and it will appear here.")
            )
        } else {
            sessionGrid
        }
    }

    private var sessionGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 190), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(manager.sessions) { session in
                    AgentSessionCard(
                        session: session,
                        onAcknowledge: { manager.acknowledge(sessionID: session.id) },
                        onJumpToTerminal: { manager.jumpToTerminal(sessionID: session.id) }
                    )
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func message(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
