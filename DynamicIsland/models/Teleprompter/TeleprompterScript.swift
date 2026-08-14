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

/// A phrase the speaker should land, counted even when they say it in their own
/// words.
///
/// Matching is on content words rather than the exact wording, which is the point:
/// a presenter who makes the argument differently has still made it.
struct TeleprompterKeyPhrase: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// As written, for display.
    var text: String
    /// Normalised content words, stopwords removed. Empty means the phrase can
    /// never be credited, which the parser avoids by dropping such phrases.
    var contentWords: [String]
    /// Fraction of `contentWords` that must appear for the phrase to count.
    var requiredFraction: Double

    init(id: UUID = UUID(), text: String, contentWords: [String], requiredFraction: Double = 0.6) {
        self.id = id
        self.text = text
        self.contentWords = contentWords
        self.requiredFraction = requiredFraction
    }
}

/// One block of a script, usually introduced by a Markdown heading.
struct TeleprompterSection: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    /// Marked `## !` — the speaker intends to cover this, and the debrief reports
    /// it if they did not.
    var mustCover: Bool
    /// Parsed from a trailing `(1:30)` or `(90s)` on the heading.
    var targetDuration: TimeInterval?
    var keyPhrases: [TeleprompterKeyPhrase]
    /// Range of this section's words within the script's flat token array.
    /// Half-open: `startIndex..<endIndex`.
    var tokenRange: Range<Int>
    /// Paragraphs as written, for rendering. Speaker notes are excluded.
    var paragraphs: [String]
    /// Speaker notes: shown dimmed, never read aloud, and contributing no tokens.
    var notes: [String]
    /// The Keynote slide this section came from, when the script was imported
    /// from a deck. What lets a slide change move the prompter to the right
    /// place without matching on a heading someone may have renamed.
    var slideNumber: Int?

    var wordCount: Int { tokenRange.count }

    init(
        id: UUID = UUID(),
        title: String,
        mustCover: Bool = false,
        targetDuration: TimeInterval? = nil,
        keyPhrases: [TeleprompterKeyPhrase] = [],
        tokenRange: Range<Int>,
        paragraphs: [String] = [],
        notes: [String] = [],
        slideNumber: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.mustCover = mustCover
        self.targetDuration = targetDuration
        self.keyPhrases = keyPhrases
        self.tokenRange = tokenRange
        self.paragraphs = paragraphs
        self.notes = notes
        self.slideNumber = slideNumber
    }
}

/// One word of the script, kept alongside where it came from so the renderer can
/// highlight it and the matcher can compare it.
struct TeleprompterToken: Codable, Equatable, Sendable {
    /// Original spelling, for display.
    let display: String
    /// Case- and diacritic-folded form, for comparison.
    let normalized: String
    /// Index of the owning section.
    let sectionIndex: Int
    /// Alternative readings, so a written `25` matches a spoken "twenty five".
    /// Each alternative is a token sequence.
    let aliases: [[String]]
}

/// A script the prompter can display and follow.
struct TeleprompterScript: Identifiable, Codable, Equatable, Sendable {
    /// Mutable so a re-parse after an edit can keep the script's identity rather
    /// than replacing it with a stranger that has the same name.
    var id: UUID
    var name: String
    /// Markdown as the user provided it. Everything else is derived, so a
    /// re-parse after an edit is always possible.
    var markdown: String
    var localeIdentifier: String
    var sections: [TeleprompterSection]
    var tokens: [TeleprompterToken]
    var createdAt: Date
    var updatedAt: Date
    /// Bumped on every edit, so a recorded take can say whether it still refers
    /// to the script as it is now.
    var revision: Int
    var preferences: TeleprompterScriptPreferences

    var wordCount: Int { tokens.count }

    /// Estimated read time at a given pace, used for the library listing.
    func estimatedDuration(wordsPerMinute: Double) -> TimeInterval {
        guard wordsPerMinute > 0 else { return 0 }
        return Double(wordCount) / wordsPerMinute * 60
    }

    var mustCoverSections: [TeleprompterSection] {
        sections.filter(\.mustCover)
    }

    init(
        id: UUID = UUID(),
        name: String,
        markdown: String,
        localeIdentifier: String,
        sections: [TeleprompterSection],
        tokens: [TeleprompterToken],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 1,
        preferences: TeleprompterScriptPreferences = .init()
    ) {
        self.id = id
        self.name = name
        self.markdown = markdown
        self.localeIdentifier = localeIdentifier
        self.sections = sections
        self.tokens = tokens
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.preferences = preferences
    }
}

/// Per-script display state, remembered so reopening a script feels like
/// returning to it rather than starting over.
struct TeleprompterScriptPreferences: Codable, Equatable, Sendable {
    var fontSize: Double = 28
    var fontChoice: TeleprompterFontChoice = .system
    var wordsPerMinute: Double = 140
    var opacity: Double = 0.9
    var isMirrored: Bool = false
    /// Token index the reader last reached.
    var lastTokenIndex: Int = 0
}
