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

struct TimerStatsView: View {
    @ObservedObject private var logger = TimerSessionLogger.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focus Statistics")
                .font(.headline)
                .foregroundColor(.white)

            HStack(spacing: 16) {
                statCard(title: "Today", time: logger.totalFocusTimeToday(), count: logger.sessionCountToday())
                statCard(title: "This Week", time: logger.totalFocusTimeThisWeek(), count: logger.sessionCountThisWeek())
                streakCard(streak: logger.currentStreak())
            }

            if !logger.sessionsToday().isEmpty {
                Divider().background(Color.white.opacity(0.2))

                Text("Today's Sessions")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))

                ForEach(logger.sessionsToday().suffix(5).reversed()) { session in
                    sessionRow(session)
                }
            }
        }
        .padding()
    }

    private func statCard(title: String, time: TimeInterval, count: Int) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            Text(formatDuration(time))
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(.white)
            Text("\(count) session\(count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }

    private func streakCard(streak: Int) -> some View {
        VStack(spacing: 4) {
            Text("Streak")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            Text("\(streak)")
                .font(.system(.title3, design: .monospaced))
                .foregroundColor(streak > 0 ? .orange : .white)
            Text("day\(streak == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }

    private func sessionRow(_ session: TimerSessionLog) -> some View {
        HStack {
            Circle()
                .fill(session.completedFully ? Color.green : Color.yellow)
                .frame(width: 6, height: 6)
            Text(session.label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(formatDuration(session.duration))
                .font(.caption.monospaced())
                .foregroundColor(.white.opacity(0.6))
            Text(session.endDate, style: .time)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        } else {
            return "\(m)m"
        }
    }
}
