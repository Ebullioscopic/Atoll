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

/// How full an agent session's context window is.
///
/// Amber past 70%, red past 90% — the red band sits where Claude Code starts
/// auto-compacting, which is the point the number becomes actionable.
///
/// When the window size is only assumed and the reading is still small, no ring
/// is drawn: a confident-looking dial built on a guess is worse than an honest
/// token count.
struct AgentContextRing: View {
    let session: AgentSession

    var diameter: CGFloat = 22
    var lineWidth: CGFloat = 2.5

    var body: some View {
        if let fraction = session.contextFraction, session.showsContextFraction {
            ring(fraction: fraction)
                .help(Text(tooltip))
                .accessibilityLabel(Text("Context window"))
                .accessibilityValue(Text(percentText(fraction)))
        } else if let tokens = session.contextTokens {
            // Window unknown: report what is certain.
            Text(Self.compactTokens(tokens))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help(Text(tooltip))
                .accessibilityLabel(Text("Context used"))
        }
    }

    private func ring(fraction: Double) -> some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.01, fraction))
                .stroke(tint(for: fraction), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((fraction * 100).rounded()))")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(tint(for: fraction))
                .monospacedDigit()
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.3), value: fraction)
    }

    private func tint(for fraction: Double) -> Color {
        if fraction >= ContextWindowResolver.redThreshold { return .red }
        if fraction >= ContextWindowResolver.amberThreshold { return .orange }
        return .blue
    }

    private func percentText(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    private var tooltip: String {
        guard let tokens = session.contextTokens else { return "" }
        guard let window = session.contextWindow else {
            return "\(Self.grouped(tokens)) tokens of context"
        }
        var text = "\(Self.grouped(tokens)) / \(Self.compactTokens(window)) tokens"
        if session.contextWindowConfidence == .assumed {
            text += " " + String(localized: "(window size estimated)")
        }
        return text
    }

    /// `512031` → `512k`, `1000000` → `1M`.
    static func compactTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let millions = Double(tokens) / 1_000_000
            let rounded = (millions * 10).rounded() / 10
            return rounded == rounded.rounded() ? "\(Int(rounded))M" : "\(rounded)M"
        }
        if tokens >= 1_000 {
            return "\(Int((Double(tokens) / 1_000).rounded()))k"
        }
        return "\(tokens)"
    }

    /// `512031` → `512,031` in the user's locale.
    static func grouped(_ tokens: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
    }
}
