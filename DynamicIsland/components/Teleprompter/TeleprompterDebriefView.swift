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

/// What happened during the take that just finished.
///
/// Ordered by what a presenter would want to know first: whether they said the
/// things they meant to, then how they paced it, then exactly where they left
/// the script. Anything that is not a problem is simply absent — a debrief that
/// always fills the same space teaches you to stop reading it.
struct TeleprompterDebriefView: View {
    let take: TeleprompterTake
    let script: TeleprompterScript?
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            missedSections
            paceRow
            departures
            skips
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: take.missedSectionIDs.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(take.missedSectionIDs.isEmpty ? .green : .orange)
            Text("Take finished")
                .font(.system(size: 13, weight: .semibold))
            Text(TeleprompterScriptTextView.durationText(take.duration))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if isStale {
                Text("script edited since")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
                    .help(Text("This take describes an earlier version of the script."))
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Dismiss the debrief"))
        }
    }

    /// The take may describe text that has since been edited, in which case its
    /// figures no longer refer to what is on screen.
    private var isStale: Bool {
        guard let script else { return false }
        return script.revision != take.scriptRevision
    }

    @ViewBuilder
    private var missedSections: some View {
        if take.missedSectionIDs.isEmpty {
            Label(
                String(localized: "You covered everything you meant to."),
                systemImage: "checkmark.seal.fill"
            )
            .font(.caption)
            .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Label(
                    String(localized: "Not covered"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)

                ForEach(missedTitles, id: \.self) { title in
                    Text("· " + title)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    private var missedTitles: [String] {
        guard let script else { return [] }
        return take.missedSectionIDs.compactMap { id in
            script.sections.first { $0.id == id }?.title
        }
        .map { $0.isEmpty ? String(localized: "Untitled section") : $0 }
    }

    private var paceRow: some View {
        HStack(spacing: 14) {
            statistic(
                String(localized: "Pace"),
                "\(Int(take.speakingWordsPerMinute.rounded())) wpm",
                help: String(localized: "Words a minute while actually speaking. The overall figure, pauses included, is \(Int(take.rawWordsPerMinute.rounded())).")
            )
            statistic(
                String(localized: "Read"),
                "\(Int((take.completionFraction * 100).rounded()))%",
                help: String(localized: "How much of the script you actually read, not counting anything skipped over.")
            )
            if let longest = take.longestPause, longest.duration >= TakeStatsBuilder.pauseThreshold {
                statistic(
                    String(localized: "Longest pause"),
                    TeleprompterScriptTextView.durationText(longest.duration),
                    help: String(localized: "At \(TeleprompterScriptTextView.durationText(longest.offset)) into the take.")
                )
            }
            Spacer(minLength: 0)
        }
    }

    private func statistic(_ label: String, _ value: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .help(Text(help))
    }

    @ViewBuilder
    private var departures: some View {
        if !take.departures.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Off script")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(take.departures.prefix(3).enumerated()), id: \.offset) { _, departure in
                    HStack(alignment: .top, spacing: 6) {
                        Text(TeleprompterScriptTextView.durationText(departure.offset))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text("“\(departure.spokenText)”")
                            .font(.caption)
                            .italic()
                            .lineLimit(2)
                    }
                }
                if take.departures.count > 3 {
                    Text("+\(take.departures.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var skips: some View {
        if !take.skips.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("Skipped")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(take.skips.prefix(3).enumerated()), id: \.offset) { _, skip in
                    Text("· \(skip.text)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if take.skips.count > 3 {
                    Text("+\(take.skips.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
