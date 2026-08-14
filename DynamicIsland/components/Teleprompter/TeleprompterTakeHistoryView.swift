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

/// The takes recorded for one script, newest first.
///
/// Written for a settings pane rather than the notch: there is room here to
/// compare runs, which is the only reason to keep a history at all. The notch
/// shows the take you just finished; this shows whether you are getting better.
struct TeleprompterTakeHistoryView: View {
    let takes: [TeleprompterTake]
    let script: TeleprompterScript?
    let onDelete: (TeleprompterTake) -> Void

    @State private var expandedTakeID: UUID?

    var body: some View {
        if takes.isEmpty {
            Text("No takes yet. Run one and the numbers land here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            trend
            ForEach(takes) { take in
                row(take)
            }
        }
    }

    /// One line saying whether the pace is settling, because a list of numbers
    /// does not answer the question anyone actually has.
    @ViewBuilder
    private var trend: some View {
        let paces = takes.map(\.speakingWordsPerMinute).filter { $0 > 0 }
        if paces.count >= 2 {
            let average = paces.reduce(0, +) / Double(paces.count)
            let latest = paces[0]
            let delta = latest - average
            Label {
                Text("Latest \(Int(latest.rounded())) wpm · \(takes.count) takes average \(Int(average.rounded())) wpm")
            } icon: {
                Image(systemName: abs(delta) < 5
                      ? "equal.circle"
                      : (delta > 0 ? "arrow.up.circle" : "arrow.down.circle"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func row(_ take: TeleprompterTake) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                HStack(spacing: 8) {
                    Button {
                        expandedTakeID = expandedTakeID == take.id ? nil : take.id
                    } label: {
                        Image(systemName: expandedTakeID == take.id ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Show what happened in this take"))

                    Button(role: .destructive) {
                        onDelete(take)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Delete this take"))
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(take.startedAt, style: .date)
                        Text(take.startedAt, style: .time)
                            .foregroundStyle(.secondary)
                        if take.followedVoice {
                            Image(systemName: "waveform")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .help(Text("Followed your voice"))
                        }
                        if isStale(take) {
                            Text("script edited since")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(summary(take))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if expandedTakeID == take.id {
                detail(take)
                    .padding(.leading, 4)
            }
        }
    }

    private func summary(_ take: TeleprompterTake) -> String {
        var parts = [
            TeleprompterScriptTextView.durationText(take.duration),
            "\(Int(take.speakingWordsPerMinute.rounded())) wpm",
            "\(Int((take.completionFraction * 100).rounded()))% " + String(localized: "read")
        ]
        if !take.missedSectionIDs.isEmpty {
            parts.append("\(take.missedSectionIDs.count) " + String(localized: "missed"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func detail(_ take: TeleprompterTake) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if take.missedSectionIDs.isEmpty {
                Text("Covered every section you meant to.")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("Not covered: " + missedTitles(take).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let longest = take.longestPause, longest.duration >= TakeStatsBuilder.pauseThreshold {
                Text("Longest pause \(TeleprompterScriptTextView.durationText(longest.duration)) at \(TeleprompterScriptTextView.durationText(longest.offset)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(take.departures.prefix(3).enumerated()), id: \.offset) { _, departure in
                Text("Off script at \(TeleprompterScriptTextView.durationText(departure.offset)): “\(departure.spokenText)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ForEach(Array(take.skips.prefix(3).enumerated()), id: \.offset) { _, skip in
                Text("Skipped: \(skip.text)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    /// A take taken against text that has since been edited describes an earlier
    /// script, and its section names may no longer resolve.
    private func isStale(_ take: TeleprompterTake) -> Bool {
        guard let script else { return false }
        return script.revision != take.scriptRevision
    }

    private func missedTitles(_ take: TeleprompterTake) -> [String] {
        guard let script else { return [] }
        return take.missedSectionIDs.compactMap { id in
            script.sections.first { $0.id == id }?.title
        }
        .map { $0.isEmpty ? String(localized: "Untitled section") : $0 }
    }
}
