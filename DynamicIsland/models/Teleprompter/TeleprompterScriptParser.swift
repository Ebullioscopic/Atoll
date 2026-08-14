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

/// Turns Markdown into a script the prompter can display and follow.
///
/// Markdown is the only format this understands, and every importer converts to
/// it first. That keeps one parser to test rather than one per file type, and it
/// means the user can always see and edit exactly what the prompter will read.
///
/// ## Syntax
/// - `#`…`######` — a section heading.
/// - `## ! Title` — a section the speaker means to cover; the debrief reports it
///   if they did not.
/// - `## Title (1:30)` or `(90s)` — a target duration for that section.
/// - `> key: ship it by Friday` — a phrase to land, credited even when said in
///   the speaker's own words.
/// - Any other `> line` — a speaker note. Shown dimmed and **contributing no
///   tokens**, because you do not read your notes aloud and a phantom word would
///   register as a skip.
/// - Fenced code blocks and `---` rules are skipped entirely.
///
/// Pure and total: any input produces a script, possibly an empty one.
enum TeleprompterScriptParser {
    static func parse(
        markdown: String,
        name: String,
        locale: Locale,
        now: Date = Date()
    ) -> TeleprompterScript {
        var sections: [TeleprompterSection] = []
        var tokens: [TeleprompterToken] = []

        var currentTitle = ""
        var currentMustCover = false
        var currentDuration: TimeInterval?
        var currentKeyPhrases: [TeleprompterKeyPhrase] = []
        var currentParagraphs: [String] = []
        var currentNotes: [String] = []
        var currentStart = 0
        var hasOpenSection = false
        var inFencedBlock = false

        func closeSection() {
            // A heading with nothing under it is still a section: it is a
            // navigation target and may be a must-cover marker.
            guard hasOpenSection || !currentParagraphs.isEmpty || !currentNotes.isEmpty else { return }
            sections.append(
                TeleprompterSection(
                    title: currentTitle,
                    mustCover: currentMustCover,
                    targetDuration: currentDuration,
                    keyPhrases: currentKeyPhrases,
                    tokenRange: currentStart..<tokens.count,
                    paragraphs: currentParagraphs,
                    notes: currentNotes
                )
            )
            currentTitle = ""
            currentMustCover = false
            currentDuration = nil
            currentKeyPhrases = []
            currentParagraphs = []
            currentNotes = []
            currentStart = tokens.count
            hasOpenSection = false
        }

        func appendTokens(from text: String) {
            let sectionIndex = sections.count
            for word in TeleprompterTokenizer.words(in: text) {
                let normalized = TeleprompterTokenizer.normalize(word, locale: locale)
                guard !normalized.isEmpty else { continue }
                tokens.append(
                    TeleprompterToken(
                        display: word,
                        normalized: normalized,
                        sectionIndex: sectionIndex,
                        aliases: TeleprompterTokenizer.aliases(for: word, normalized: normalized, locale: locale)
                    )
                )
            }
        }

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFencedBlock.toggle()
                continue
            }
            if inFencedBlock { continue }
            if line.isEmpty { continue }

            // A leading backslash escapes the line: whatever follows is prose,
            // never a marker. Imported text — Keynote's presenter notes, say —
            // is written by someone who never agreed to this syntax, and a note
            // that happens to start with `#` must not silently invent a section
            // and pull the slide mapping out of step.
            if line.hasPrefix("\\") {
                let spoken = strippingInlineMarkup(String(line.dropFirst()))
                guard !spoken.isEmpty else { continue }
                currentParagraphs.append(spoken)
                appendTokens(from: spoken)
                continue
            }
            // A horizontal rule, not three words.
            if line.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }), line.count >= 3 { continue }

            if let heading = parseHeading(line) {
                closeSection()
                currentTitle = heading.title
                currentMustCover = heading.mustCover
                currentDuration = heading.targetDuration
                hasOpenSection = true
                continue
            }

            if line.hasPrefix(">") {
                let body = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if let phraseText = parseKeyPhrase(body) {
                    let words = TeleprompterTokenizer.contentWords(in: phraseText, locale: locale)
                    // A phrase with no content words could never be credited, so
                    // storing it would only mislead the debrief.
                    if !words.isEmpty {
                        currentKeyPhrases.append(
                            TeleprompterKeyPhrase(text: phraseText, contentWords: words)
                        )
                    }
                } else if !body.isEmpty {
                    currentNotes.append(body)
                }
                continue
            }

            let spoken = strippingInlineMarkup(line)
            guard !spoken.isEmpty else { continue }
            currentParagraphs.append(spoken)
            appendTokens(from: spoken)
        }

        closeSection()

        return TeleprompterScript(
            name: name,
            markdown: markdown,
            localeIdentifier: locale.identifier,
            sections: sections,
            tokens: tokens,
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Line kinds

    struct Heading: Equatable {
        var title: String
        var mustCover: Bool
        var targetDuration: TimeInterval?
    }

    /// Parses `## ! Intro (1:30)`.
    static func parseHeading(_ line: String) -> Heading? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }
        guard hashes.count <= 6 else { return nil }

        var rest = String(line.dropFirst(hashes.count))
        // `#hashtag` is not a heading; Markdown requires the space.
        guard rest.isEmpty || rest.hasPrefix(" ") || rest.hasPrefix("\t") else { return nil }
        rest = rest.trimmingCharacters(in: .whitespaces)

        var mustCover = false
        if rest.hasPrefix("!") {
            mustCover = true
            rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        let (title, duration) = extractTrailingDuration(from: rest)
        return Heading(title: title, mustCover: mustCover, targetDuration: duration)
    }

    /// Parses the `key:` prefix of a blockquote line, tolerating spacing.
    static func parseKeyPhrase(_ blockquoteBody: String) -> String? {
        let lowered = blockquoteBody.lowercased()
        guard lowered.hasPrefix("key") else { return nil }

        var rest = String(blockquoteBody.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix(":") else { return nil }
        rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// Splits a trailing `(1:30)`, `(90s)` or `(2m)` off a heading.
    static func extractTrailingDuration(from title: String) -> (title: String, duration: TimeInterval?) {
        guard title.hasSuffix(")"), let open = title.lastIndex(of: "(") else {
            return (title, nil)
        }
        let inside = String(title[title.index(after: open)..<title.index(before: title.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        guard let duration = parseDuration(inside) else { return (title, nil) }

        let remaining = String(title[title.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        return (remaining, duration)
    }

    /// `1:30`, `90s`, `2m`, `45`.
    static func parseDuration(_ text: String) -> TimeInterval? {
        guard !text.isEmpty else { return nil }

        if text.contains(":") {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let minutes = Int(parts[0]), let seconds = Int(parts[1]),
                  minutes >= 0, seconds >= 0, seconds < 60
            else { return nil }
            return TimeInterval(minutes * 60 + seconds)
        }

        if text.hasSuffix("s"), let value = Double(text.dropLast()) {
            return value >= 0 ? value : nil
        }
        if text.hasSuffix("m"), let value = Double(text.dropLast()) {
            return value >= 0 ? value * 60 : nil
        }
        if let value = Double(text), value >= 0 {
            return value
        }
        return nil
    }

    /// Removes the markers a reader should not say out loud.
    ///
    /// Emphasis, links and inline code are unwrapped rather than dropped: the
    /// words inside them are part of the script.
    static func strippingInlineMarkup(_ line: String) -> String {
        var text = line

        // Images first: an image is a link with a `!` in front, so unwrapping
        // links before removing images would leave the `!` and the alt text
        // behind as words to read aloud.
        text = text.replacingOccurrences(
            of: #"!\[[^\]]*\]\([^)]*\)"#,
            with: "",
            options: .regularExpression
        )
        // `[label](url)` keeps the label.
        text = text.replacingOccurrences(
            of: #"\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        // Emphasis and inline code markers.
        text = text.replacingOccurrences(of: #"[*_`~]"#, with: "", options: .regularExpression)
        // Leading list markers.
        text = text.replacingOccurrences(
            of: #"^\s*([-+*]|\d+[.)])\s+"#,
            with: "",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespaces)
    }
}
