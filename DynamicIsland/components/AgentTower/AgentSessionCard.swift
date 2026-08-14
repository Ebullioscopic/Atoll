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

/// One agent session, as a card in the Agents tab.
struct AgentSessionCard: View {
    let session: AgentSession
    /// Called when the user dismisses a finished card.
    let onAcknowledge: () -> Void
    /// Called when the card is clicked, to bring its terminal forward.
    var onJumpToTerminal: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let cwd = session.cwd, !cwd.isEmpty {
                Text(abbreviatedPath(cwd))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(Text(cwd))
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(10)
        .frame(width: 190, height: 104, alignment: .topLeading)
        .background(.white.opacity(isHovering ? 0.10 : 0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if isHovering, session.status == .finished || session.status == .idle {
                Button(action: onAcknowledge) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
                .accessibilityLabel(Text("Dismiss session"))
            }
        }
        .onHover { isHovering = $0 }
        // The whole card reads as one element for VoiceOver; the individual
        // fields are noise on their own.
        .accessibilityElement(children: .combine)
        .contentShape(Rectangle())
        .onTapGesture {
            onJumpToTerminal?()
        }
        .help(Text(onJumpToTerminal == nil ? "" : String(localized: "Click to bring this agent's terminal forward")))
        .accessibilityAddTraits(onJumpToTerminal == nil ? [] : .isButton)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: session.kind.iconSymbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
            Text(session.displayTitle)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            AgentContextRing(session: session)
            statusDot
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(session.status.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(statusColor)
                .lineLimit(1)
            if let progress = session.subagentProgressText {
                Text(progress)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help(Text("Subagents finished"))
            }
            Spacer(minLength: 0)
            elapsedLabel
        }
    }

    /// Ticks once a second only while this card is on screen, which is why the
    /// manager needs no timer of its own.
    private var elapsedLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.elapsedText(session.elapsed(now: context.date)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 6, height: 6)
            .opacity(session.status == .idle ? 0.4 : 1)
    }

    private var statusColor: Color {
        switch session.status {
        case .working: return .blue
        case .waitingOnUser: return .orange
        case .finished: return .green
        case .idle: return .secondary
        }
    }

    /// Shortens a path for a 190pt card: keeps the last two components.
    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var display = path
        if display.hasPrefix(home) {
            display = "~" + display.dropFirst(home.count)
        }
        let parts = display.split(separator: "/")
        guard parts.count > 3 else { return display }
        return "…/" + parts.suffix(2).joined(separator: "/")
    }

    /// `m:ss` under an hour, `h:mm:ss` beyond it.
    static func elapsedText(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours):\(padded(minutes)):\(padded(seconds))"
        }
        return "\(minutes):\(padded(seconds))"
    }

    private static func padded(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
