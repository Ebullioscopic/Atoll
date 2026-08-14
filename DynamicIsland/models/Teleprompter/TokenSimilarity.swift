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

/// How closely a spoken word matches a written one.
enum MatchQuality: Equatable, Sendable {
    case exact
    /// Close enough to accept — a recogniser slip, a spelling variant, or a
    /// different inflection of the same stem.
    case near
    case none

    var weight: Double {
        switch self {
        case .exact: return 1.0
        case .near: return 0.75
        case .none: return 0
        }
    }
}

/// Compares two already-normalised words.
///
/// ## Why short words are held to a stricter standard
/// Fuzzy-matching function words is where a naive matcher destroys itself:
/// `the`, `then`, `they` and `there` are all within one or two edits of each
/// other, and they are the most frequent words in any script. One wrong match on
/// `the` can move the cursor to the wrong paragraph. So below five characters
/// only an exact match counts.
///
/// Pure, allocation-light and bounded: the follower calls this up to fifteen
/// times per spoken word.
enum TokenSimilarity {
    static func compare(_ spoken: String, _ written: String) -> MatchQuality {
        if spoken == written { return .exact }
        if spoken.isEmpty || written.isEmpty { return .none }

        let spokenChars = Array(spoken)
        let writtenChars = Array(written)

        // Function words are too dense in edit space to fuzzy-match safely, and
        // four characters is not a high enough bar: `they` and `then` are both
        // four letters, one edit apart, and among the commonest words in any
        // script. Five keeps them out while still admitting `color`/`colour`.
        // `there`/`their` survives the length test but fails on distance, which
        // is two rather than one.
        guard spokenChars.count >= 5, writtenChars.count >= 5 else { return .none }

        let lengthDifference = abs(spokenChars.count - writtenChars.count)
        let shorter = min(spokenChars.count, writtenChars.count)
        let tolerance = shorter >= 8 ? 2 : 1

        if lengthDifference <= tolerance,
           editDistance(spokenChars, writtenChars, limit: tolerance) <= tolerance {
            return .near
        }

        // Agglutinative languages stack suffixes onto a stable stem: `kitap` /
        // `kitapları`, `öğrenci` / `öğrenciler`. Without this, Turkish, Finnish
        // and Hungarian would report a miss on nearly every inflected word. Four
        // shared characters is the floor — a two-letter stem like `ev` would
        // match far too much.
        if lengthDifference <= 3, sharedPrefixLength(spokenChars, writtenChars) >= 4 {
            return .near
        }

        return .none
    }

    /// Length of the common leading run.
    static func sharedPrefixLength(_ lhs: [Character], _ rhs: [Character]) -> Int {
        var count = 0
        while count < lhs.count, count < rhs.count, lhs[count] == rhs[count] {
            count += 1
        }
        return count
    }

    /// Levenshtein distance, abandoned as soon as it exceeds `limit`.
    ///
    /// Two rows rather than a full matrix, and an early exit, because this runs
    /// on the hot path of every partial speech result.
    static func editDistance(_ lhs: [Character], _ rhs: [Character], limit: Int) -> Int {
        if abs(lhs.count - rhs.count) > limit { return limit + 1 }
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for i in 1...lhs.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...rhs.count {
                let substitution = previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
                rowMinimum = min(rowMinimum, current[j])
            }
            // Every remaining row can only grow, so this row already settles it.
            if rowMinimum > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
