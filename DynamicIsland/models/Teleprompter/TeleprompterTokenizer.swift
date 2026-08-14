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

/// Splits text into comparable words.
///
/// Both sides of the eventual match — the script and what the speech recogniser
/// heard — go through this, so the two only ever have to agree with each other,
/// not with any external standard.
///
/// ## Why the locale is a parameter and not an afterthought
/// Case folding is locale-dependent, and Turkish is the case that proves it:
/// `İ` lowercases to `i` and `I` to `ı` only under `tr`. Fold with the wrong
/// locale and every capitalised sentence opening becomes a mismatch, which the
/// matcher would read as the speaker going off script.
///
/// Diacritics are folded away deliberately (`ö→o`, `ş→s`, `é→e`). Recognisers are
/// inconsistent about them, and since both sides fold identically the merged
/// minimal pairs never surface — normalised text is compared, never displayed.
enum TeleprompterTokenizer {
    /// Splits on Unicode word boundaries, so it works for scripts without
    /// spaces as well as for Latin text.
    static func words(in text: String) -> [String] {
        var result: [String] = []
        let full = text.startIndex..<text.endIndex
        text.enumerateSubstrings(in: full, options: [.byWords, .localized]) { substring, _, _, _ in
            if let substring, !substring.isEmpty {
                result.append(substring)
            }
        }
        return result
    }

    /// Canonical comparison form of one word.
    ///
    /// Returns an empty string for input with no alphanumeric content, which
    /// callers drop.
    static func normalize(_ word: String, locale: Locale) -> String {
        // Typographic apostrophes and dashes vary by keyboard and by recogniser.
        var text = word
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{201B}", with: "'")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2011}", with: "-")
        text = text.precomposedStringWithCanonicalMapping

        // Order matters, and Turkish is the case that proves it.
        //
        // Folding case and diacritics in one call strips the dot from `İ` first,
        // leaving `I`, which Turkish case rules then lowercase to `ı` — so
        // `İSTANBUL` and `istanbul` end up different, which is the exact failure
        // the locale argument exists to prevent. Case-folding first gives
        // `İSTANBUL` → `istanbul` and `ÖĞRENCİ` → `öğrenci`, and only then are the
        // remaining diacritics removed.
        text = text.folding(options: [.caseInsensitive], locale: locale)
        text = text.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: locale)

        // Keep intra-word apostrophes and hyphens (`don't`, `well-known`) and
        // drop everything else.
        var scalars = String.UnicodeScalarView()
        let characters = Array(text.unicodeScalars)
        for (index, scalar) in characters.enumerated() {
            if CharacterSet.alphanumerics.contains(scalar) {
                scalars.append(scalar)
                continue
            }
            guard scalar == "'" || scalar == "-" else { continue }
            let hasBefore = index > 0 && CharacterSet.alphanumerics.contains(characters[index - 1])
            let hasAfter = index + 1 < characters.count && CharacterSet.alphanumerics.contains(characters[index + 1])
            if hasBefore, hasAfter { scalars.append(scalar) }
        }
        return String(scalars)
    }

    /// Tokenises a run of text into normalised words, dropping anything that
    /// normalises to nothing.
    static func normalizedWords(in text: String, locale: Locale) -> [String] {
        words(in: text)
            .map { normalize($0, locale: locale) }
            .filter { !$0.isEmpty }
    }

    /// Alternative spoken forms for a written word.
    ///
    /// Numbers are the case that matters: a script says `25` and the recogniser
    /// hears "twenty five". Rather than convert spoken words to digits — which
    /// would need a parser per language — the *script* side is expanded once, at
    /// parse time, so matching stays a lookup.
    static func aliases(for word: String, normalized: String, locale: Locale) -> [[String]] {
        guard !normalized.isEmpty, normalized.allSatisfy(\.isNumber) else { return [] }
        guard let value = Int(normalized) else { return [] }

        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = locale
        guard let spelled = formatter.string(from: NSNumber(value: value)) else { return [] }

        let spokenWords = normalizedWords(in: spelled, locale: locale)
        guard !spokenWords.isEmpty, spokenWords != [normalized] else { return [] }
        return [spokenWords]
    }

    /// Words too common to carry meaning, used when deciding whether a key phrase
    /// was covered.
    ///
    /// Only the languages most likely to be presented in are listed; elsewhere the
    /// length heuristic below stands in. An incomplete list makes key-phrase
    /// credit slightly stricter, never wrong.
    private static let stopwords: [String: Set<String>] = [
        "en": ["the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "for", "with",
               "is", "are", "was", "were", "be", "been", "it", "this", "that", "we", "you",
               "i", "our", "your", "as", "at", "by", "from", "so", "if", "not", "can", "will"],
        "tr": ["ve", "veya", "ama", "ile", "bir", "bu", "su", "o", "da", "de", "ki", "icin",
               "gibi", "kadar", "ama", "ancak", "cok", "daha", "en", "her", "ne", "mi", "mu"],
        "de": ["der", "die", "das", "und", "oder", "aber", "mit", "von", "zu", "in", "auf",
               "ein", "eine", "ist", "sind", "war", "wir", "sie", "es", "nicht", "fur"],
        "fr": ["le", "la", "les", "un", "une", "et", "ou", "mais", "de", "du", "des", "a",
               "au", "aux", "en", "que", "qui", "est", "sont", "pour", "avec", "pas"],
        "es": ["el", "la", "los", "las", "un", "una", "y", "o", "pero", "de", "del", "en",
               "que", "es", "son", "para", "con", "no", "por", "su"]
    ]

    /// Whether a word is too common to count towards covering a key phrase.
    static func isStopword(_ normalized: String, locale: Locale) -> Bool {
        if normalized.count <= 2 { return true }
        let language = locale.language.languageCode?.identifier ?? "en"
        return stopwords[language]?.contains(normalized) ?? false
    }

    /// Content words of a phrase, for key-phrase credit.
    ///
    /// Falls back to the full word list when removing stopwords would empty it —
    /// a phrase made entirely of common words is still better matched loosely
    /// than never matched at all.
    static func contentWords(in text: String, locale: Locale) -> [String] {
        let all = normalizedWords(in: text, locale: locale)
        let filtered = all.filter { !isStopword($0, locale: locale) }
        return filtered.isEmpty ? all : filtered
    }
}
