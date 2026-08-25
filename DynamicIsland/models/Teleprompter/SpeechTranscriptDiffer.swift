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

/// What changed between two partial transcripts.
struct TranscriptDelta: Equatable, Sendable {
    /// Words to hand to the matcher, in order.
    let newWords: [String]
    /// True when the recogniser rewrote words it had already reported.
    let revisedTail: Bool
}

/// Turns a stream of cumulative partial transcripts into the incremental words
/// the matcher expects.
///
/// ## Why this exists
/// `SFSpeechRecognizer` reports the **whole utterance so far** on every partial
/// result, and freely rewrites its recent guesses as more audio arrives —
/// "I have a dre" becomes "I have a dream". Feeding each cumulative transcript
/// to the matcher would re-walk the same words dozens of times and advance the
/// cursor far past where the speaker is.
///
/// ## The revision rule
/// A rewrite near the end is normal and is accepted. A rewrite *deep* in text the
/// recogniser already settled on is treated as noise and ignored, because acting
/// on it would mean rewinding a highlight the reader has already passed — and a
/// prompter that jumps backwards is worse than one that is briefly stale.
///
/// Pure and total; the seam that makes the whole engine testable without audio.
enum SpeechTranscriptDiffer {
    /// How many trailing words the recogniser is still allowed to change its mind
    /// about.
    static let provisionalTail = 4

    static func delta(
        previous: [String],
        current: [String],
        provisionalTail: Int = Self.provisionalTail
    ) -> TranscriptDelta {
        let shared = commonPrefixLength(previous, current)

        // Nothing was rewritten: everything past the shared prefix is new.
        if shared == previous.count {
            return TranscriptDelta(
                newWords: Array(current[shared...]),
                revisedTail: false
            )
        }

        // A rewrite inside the provisional tail is the recogniser doing its job.
        if shared >= previous.count - provisionalTail {
            return TranscriptDelta(
                newWords: Array(current[shared...]),
                revisedTail: true
            )
        }

        // A deep rewrite. Keep only what is genuinely beyond what was already
        // reported; re-emitting the middle would drag the cursor backwards.
        guard current.count > previous.count else {
            return TranscriptDelta(newWords: [], revisedTail: true)
        }
        return TranscriptDelta(
            newWords: Array(current[previous.count...]),
            revisedTail: true
        )
    }

    static func commonPrefixLength(_ lhs: [String], _ rhs: [String]) -> Int {
        var count = 0
        while count < lhs.count, count < rhs.count, lhs[count] == rhs[count] {
            count += 1
        }
        return count
    }
}
