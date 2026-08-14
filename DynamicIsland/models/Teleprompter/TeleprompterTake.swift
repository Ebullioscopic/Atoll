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

import Foundation

/// A silence long enough to be worth mentioning.
struct TakePause: Codable, Equatable, Sendable {
    /// Seconds from the start of the take.
    let offset: TimeInterval
    let duration: TimeInterval
}

/// A stretch of the script that was not read.
struct TakeSkip: Codable, Equatable, Sendable {
    let range: Range<Int>
    /// The words themselves, so the debrief can show what was missed rather than
    /// two numbers.
    let text: String
}

/// A stretch the speaker said that was not in the script.
struct TakeDeparture: Codable, Equatable, Sendable {
    /// Where in the script they were when they left it.
    let scriptIndex: Int
    let spokenText: String
    let offset: TimeInterval
    let duration: TimeInterval
}

/// What happened during one run through a script.
struct TeleprompterTake: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let scriptID: UUID
    /// The script's revision at the time. A take taken against text that has
    /// since been edited should say so rather than pretend to describe the
    /// current script.
    let scriptRevision: Int
    let scriptName: String
    let startedAt: Date
    let duration: TimeInterval
    let localeIdentifier: String
    let followedVoice: Bool

    let matchedWordCount: Int
    /// Matched words over wall-clock time. What an audience experiences.
    let rawWordsPerMinute: Double
    /// Matched words over speaking time, with long pauses removed. What the
    /// speaker can actually act on.
    let speakingWordsPerMinute: Double

    let pauses: [TakePause]
    let coveredSectionIDs: [UUID]
    /// Must-cover sections that were not covered. The headline of the debrief.
    let missedSectionIDs: [UUID]
    let creditedKeyPhraseIDs: [UUID]
    let skips: [TakeSkip]
    let departures: [TakeDeparture]
    /// How far through the script the reader got, 0...1.
    let completionFraction: Double

    var longestPause: TakePause? {
        pauses.max { $0.duration < $1.duration }
    }
}

/// Turns a finished take into the numbers the debrief shows.
///
/// Pure, so every figure below is tested against a fixture rather than measured
/// by reading aloud.
enum TakeStatsBuilder {
    /// Silences at least this long count as a pause rather than a breath.
    static let pauseThreshold: TimeInterval = 1.5

    /// - Parameter speechTimestamps: when words were heard, in seconds from the
    ///   start of the take. Gaps between these are what pauses are derived from.
    static func build(
        script: TeleprompterScript,
        state: FollowState,
        startedAt: Date,
        duration: TimeInterval,
        speechTimestamps: [TimeInterval],
        followedVoice: Bool,
        localeIdentifier: String,
        id: UUID = UUID()
    ) -> TeleprompterTake {
        let pauses = self.pauses(from: speechTimestamps, duration: duration)
        let pausedTime = pauses.reduce(0) { $0 + $1.duration }
        let speakingTime = max(0, duration - pausedTime)

        let covered = state.coveredSectionIndices
            .compactMap { script.sections.indices.contains($0) ? script.sections[$0].id : nil }
        let missed = script.sections.enumerated()
            .filter { $0.element.mustCover && !state.coveredSectionIndices.contains($0.offset) }
            .map(\.element.id)

        return TeleprompterTake(
            id: id,
            scriptID: script.id,
            scriptRevision: script.revision,
            scriptName: script.name,
            startedAt: startedAt,
            duration: duration,
            localeIdentifier: localeIdentifier,
            followedVoice: followedVoice,
            matchedWordCount: state.matchedWordCount,
            rawWordsPerMinute: wordsPerMinute(words: state.matchedWordCount, seconds: duration),
            speakingWordsPerMinute: wordsPerMinute(words: state.matchedWordCount, seconds: speakingTime),
            pauses: pauses,
            coveredSectionIDs: covered,
            missedSectionIDs: missed,
            creditedKeyPhraseIDs: Array(state.creditedKeyPhraseIDs),
            skips: skips(from: state, script: script),
            departures: departures(from: state, startedAt: startedAt),
            completionFraction: completion(state: state, script: script)
        )
    }

    static func wordsPerMinute(words: Int, seconds: TimeInterval) -> Double {
        guard seconds > 0, words > 0 else { return 0 }
        return Double(words) / seconds * 60
    }

    /// Gaps between heard words, plus the gap before the first and after the last.
    static func pauses(from timestamps: [TimeInterval], duration: TimeInterval) -> [TakePause] {
        guard duration > 0 else { return [] }
        let sorted = timestamps.sorted()

        // Nothing heard at all is one long silence, not zero pauses.
        guard let first = sorted.first, let last = sorted.last else {
            return duration >= pauseThreshold ? [TakePause(offset: 0, duration: duration)] : []
        }

        var result: [TakePause] = []
        if first >= pauseThreshold {
            result.append(TakePause(offset: 0, duration: first))
        }
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            let gap = next - previous
            if gap >= pauseThreshold {
                result.append(TakePause(offset: previous, duration: gap))
            }
        }
        let trailing = duration - last
        if trailing >= pauseThreshold {
            result.append(TakePause(offset: last, duration: trailing))
        }
        return result
    }

    /// Skipped ranges with the words filled in.
    static func skips(from state: FollowState, script: TeleprompterScript) -> [TakeSkip] {
        state.skipped.compactMap { skipped in
            let clamped = skipped.range.clamped(to: 0..<script.tokens.count)
            guard !clamped.isEmpty else { return nil }
            let text = clamped.map { script.tokens[$0].display }.joined(separator: " ")
            return TakeSkip(range: clamped, text: text)
        }
    }

    static func departures(from state: FollowState, startedAt: Date) -> [TakeDeparture] {
        state.offScriptRuns.map { run in
            TakeDeparture(
                scriptIndex: run.scriptIndex,
                spokenText: run.spokenWords.joined(separator: " "),
                offset: run.startedAt,
                duration: max(0, run.endedAt - run.startedAt)
            )
        }
    }

    /// How much of the script was actually read, discounting what was skipped
    /// over — otherwise jumping to the end would read as a complete take.
    static func completion(state: FollowState, script: TeleprompterScript) -> Double {
        guard !script.tokens.isEmpty else { return 0 }
        let reached = min(state.confirmedCursor, script.tokens.count)
        let skipped = state.skipped
            .map { $0.range.clamped(to: 0..<script.tokens.count).count }
            .reduce(0, +)
        let read = max(0, reached - skipped)
        return min(1, Double(read) / Double(script.tokens.count))
    }
}
