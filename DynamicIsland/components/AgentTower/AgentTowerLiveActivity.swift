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

/// Closed-notch indicator for an agent waiting on a decision.
///
/// ## Why this is standalone rather than a `MusicSecondaryLiveActivity` case
/// The secondary slot only renders while music is pairing-eligible, so a
/// secondary-only design would show **nothing at all** when no music is playing —
/// which is most of the time someone is watching an agent work. An approval that
/// silently fails to appear is the one failure this feature cannot afford, so it
/// gets its own branch and outranks music. The low-urgency "N agents running"
/// badge does go through the secondary slot, where coexisting with music is the
/// right behaviour.
///
/// ## Geometry
/// Copied from `PrivacyLiveActivity`, which is a standalone wings layout that
/// ships and works. The shape is load-bearing: `Color.clear` wings with an
/// **explicit** width, a black centre exactly `vm.closedNotchSize.width` wide,
/// and an outer height of `vm.effectiveClosedNotchHeight`. Layouts that deviate —
/// `maxWidth: .infinity` at the top level, or a bare `GeometryReader` — render as
/// a blank black notch.
struct AgentTowerLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var manager = AgentTowerManager.shared

    @State private var isHovering: Bool = false
    @State private var gestureProgress: CGFloat = 0
    @State private var isExpanded: Bool = false

    private var wingHeight: CGFloat {
        vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
    }

    /// Enough room for the icon plus a short label, matching how the privacy
    /// wings size themselves off the notch height.
    private func wingWidth(_ extra: CGFloat) -> CGFloat {
        guard isExpanded else { return 0 }
        return max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2 + extra)
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .background {
                    if isExpanded {
                        HStack(spacing: 4) {
                            Image(systemName: symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(accent)
                                .symbolEffect(.pulse, options: .repeating, isActive: manager.hasPendingApproval)
                            if let label = leadingLabel {
                                Text(label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(accent)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.leading, 6)
                    }
                }
                .frame(width: wingWidth(leadingLabel == nil ? 8 : 52), height: wingHeight)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + (isHovering ? 8 : 0))

            Color.clear
                .background {
                    if isExpanded {
                        trailing
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .padding(.trailing, 6)
                    }
                }
                .frame(width: wingWidth(trailingExtraWidth), height: wingHeight)
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
        .help(Text(tooltip))
        .onAppear {
            withAnimation(.smooth(duration: 0.4)) { isExpanded = true }
        }
        .onChange(of: manager.hasPendingApproval) { _, _ in
            withAnimation(.smooth(duration: 0.3)) { isExpanded = true }
        }
    }

    // MARK: - Trailing content

    @ViewBuilder
    private var trailing: some View {
        if let request = manager.frontmostRequest {
            HStack(spacing: 5) {
                Text(request.toolLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                countdown(for: request)
            }
        } else {
            Text(runningLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// How long the agent will keep waiting, so the strip communicates urgency
    /// without the user having to open the notch.
    private func countdown(for request: AgentPendingRequest) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, request.expiresAt.timeIntervalSince(context.date))
            Text(AgentSessionCard.elapsedText(remaining))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(remaining < 30 ? .red : .orange)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
        }
    }

    private var trailingExtraWidth: CGFloat {
        manager.frontmostRequest == nil ? 44 : 96
    }

    // MARK: - Presentation

    private var symbol: String {
        manager.hasPendingApproval ? "hand.raised.fill" : "sparkles"
    }

    private var accent: Color {
        guard let request = manager.frontmostRequest else { return .blue }
        switch request.risk {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        case .none: return .green
        }
    }

    private var leadingLabel: String? {
        guard manager.pendingRequests.count > 1 else { return nil }
        return "\(manager.pendingRequests.count)"
    }

    private var runningLabel: String {
        let count = manager.runningCount
        return count == 1
            ? String(localized: "1 agent")
            : "\(count) " + String(localized: "agents")
    }

    private var tooltip: String {
        if let request = manager.frontmostRequest {
            return request.toolLabel + " — " + String(localized: "waiting for your decision")
        }
        return runningLabel
    }
}
