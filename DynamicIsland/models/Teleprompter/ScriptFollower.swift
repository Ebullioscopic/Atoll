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

/// What the follower thinks the speaker is doing.
enum FollowMode: String, Equatable, Sendable {
    /// Tracking the script word by word.
    case following
    /// Nothing has been heard for a while.
    case waiting
    /// Words are coming, but they are not in the script here.
    case offScript
}

/// A stretch the speaker did not read.
struct SkippedRange: Equatable, Sendable {
    let range: Range<Int>
}

/// A stretch the speaker said that is not in the script.
struct OffScriptRun: Equatable, Sendable {
    /// Where in the script they were when they departed from it.
    let scriptIndex: Int
    var spokenWords: [String]
    let startedAt: TimeInterval
    var endedAt: TimeInterval
}

/// Everything the follower carries between spoken words.
///
/// Deliberately a value type with no references: the position lives here, not in
/// any transcript, which is what lets a speech recognition task be torn down and
/// restarted mid-sentence without losing the reader's place.
struct FollowState: Equatable, Sendable {
    /// Next script word expected. Moves ahead of `confirmedCursor` while a match
    /// is still provisional.
    var cursor: Int = 0
    /// What the prompter actually highlights and scrolls to. Only advances once a
    /// match is confirmed, so a single ambiguous word never moves the display.
    var confirmedCursor: Int = 0

    var mode: FollowMode = .following
    var matchRun: Int = 0
    var offScriptRun: Int = 0
    var lastMatchAt: TimeInterval = 0
    var lastSpokenAt: TimeInterval = 0

    /// A far-off match waiting for corroboration before the cursor jumps to it.
    var jumpTarget: Int?
    var jumpConfirmations: Int = 0

    var skipped: [SkippedRange] = []
    var offScriptRuns: [OffScriptRun] = []
    /// Recent spoken words, for crediting a key phrase said in other words.
    var recentSpoken: [String] = []
    var creditedKeyPhraseIDs: Set<UUID> = []
    var coveredSectionIndices: Set<Int> = []

    /// Words matched, for the pace figure.
    var matchedWordCount: Int = 0
}

/// Tuning for ``ScriptFollower``.
struct FollowConfig: Equatable, Sendable {
    /// How far ahead to look for the next word. Wide enough to absorb a skipped
    /// clause, narrow enough that a common word further on cannot claim a match.
    var lookahead = 12
    /// How far back to look. A hit here means the speaker repeated themselves;
    /// it clears the off-script counter but never rewinds the cursor.
    var lookbehind = 3
    /// Cost per word of distance, so a nearer candidate wins a tie.
    var skipPenalty = 0.06
    /// Consecutive matches before the highlight is allowed to move.
    var confirmRun = 2
    /// Largest gap accepted without corroboration.
    var maxSilentSkip = 8
    /// Corroborating matches required before a long jump is committed.
    var jumpConfirmRun = 4
    /// Consecutive unmatched words before the speaker is called off script.
    var offScriptThreshold = 6
    /// Words of context kept for key-phrase credit.
    var recentSpokenWindow = 25
    /// Seconds of quiet before the mode becomes `.waiting`.
    var waitingAfter: TimeInterval = 1.2

    static let `default` = FollowConfig()
}

/// Precomputed lookups over a script, built once per script rather than per word.
struct ScriptFollowIndex: Sendable {
    /// Normalised words that are rare enough to identify a position on their own,
    /// mapped to where they occur.
    let rareAnchors: [String: [Int]]

    /// A word is an anchor when it is long enough to be distinctive and occurs at
    /// most twice — the two conditions that make it usable as a landmark.
    init(script: TeleprompterScript, maxOccurrences: Int = 2, minimumLength: Int = 5) {
        var counts: [String: [Int]] = [:]
        for (index, token) in script.tokens.enumerated() where token.normalized.count >= minimumLength {
            counts[token.normalized, default: []].append(index)
        }
        rareAnchors = counts.filter { $0.value.count <= maxOccurrences }
    }
}

/// Works out where in a script the speaker is.
///
/// ## The shape of the problem
/// A presenter pauses, skips a clause, ad-libs a sentence, repeats themselves,
/// and jumps to another section — and the recogniser mishears some of it. A
/// matcher that simply advances on every word loses them within seconds.
///
/// So this is a **forward-biased sliding window with deferred commit**:
///
/// - The next word is looked for in a small window ahead of the cursor, with
///   nearer candidates preferred, so a skipped clause is absorbed silently.
/// - A backward window catches repetition without ever rewinding the highlight.
/// - The highlight only moves once a match is *confirmed*, so one ambiguous word
///   cannot drag the prompter somewhere else.
/// - A match far ahead is treated as a *candidate* needing corroboration, which
///   is what stops one coincidental `and` four hundred words away from
///   teleporting the reader to the end.
/// - When nothing matches for a while the cursor **freezes** rather than
///   guessing. Waiting for the speaker is the correct behaviour when you do not
///   know where they are.
///
/// ## Cost
/// Per spoken word: at most `lookahead + lookbehind` comparisons, each a bounded
/// edit distance over short strings. No pass over the whole script, ever, so it
/// is cheap enough to run on every partial recognition result.
///
/// Pure and injected-time, which is how the whole behaviour is testable without
/// speaking.
enum ScriptFollower {
    /// Something worth telling the UI about.
    enum Event: Equatable, Sendable {
        case matched(scriptIndex: Int)
        case skipped(Range<Int>)
        case wentOffScript(atScriptIndex: Int)
        case returnedToScript(scriptIndex: Int)
        case creditedKeyPhrase(id: UUID, sectionIndex: Int)
        case coveredSection(Int)
        case jumped(from: Int, to: Int)
        case finished
    }

    /// Folds newly heard words into the state.
    ///
    /// - Parameter spoken: only the words that are *new* since the last call.
    ///   Feeding a whole cumulative transcript would re-walk it every time.
    @discardableResult
    static func advance(
        state: inout FollowState,
        spoken: [String],
        script: TeleprompterScript,
        index: ScriptFollowIndex,
        config: FollowConfig = .default,
        now: TimeInterval
    ) -> [Event] {
        var events: [Event] = []
        guard !script.tokens.isEmpty else { return events }

        // A tick with no words: the only thing that can change is going quiet.
        if spoken.isEmpty {
            if state.mode != .offScript, now - state.lastSpokenAt > config.waitingAfter {
                state.mode = .waiting
            }
            return events
        }

        for word in spoken {
            state.lastSpokenAt = now
            remember(word, in: &state, config: config)

            if let hit = findForward(word, state: state, script: script, config: config) {
                apply(forwardHit: hit, state: &state, script: script, config: config, now: now, events: &events)
                continue
            }

            if findBackward(word, state: state, script: script, config: config) != nil {
                // The speaker repeated themselves; they have not left the script,
                // but the cursor must not go backwards.
                state.offScriptRun = 0
                if state.mode == .offScript {
                    state.mode = .following
                    events.append(.returnedToScript(scriptIndex: state.confirmedCursor))
                }
                continue
            }

            // Nothing nearby. Before concluding they have left the script,
            // see whether this word names a distinctive place elsewhere — which
            // is what jumping to another section actually looks like.
            if considerAnchorJump(word, state: &state, script: script, index: index, config: config, now: now, events: &events) {
                continue
            }
            recordOffScript(word, state: &state, config: config, now: now, events: &events)
        }

        creditKeyPhrases(state: &state, script: script, config: config, events: &events)
        updateCoverage(state: &state, script: script, events: &events)

        if state.confirmedCursor >= script.tokens.count {
            events.append(.finished)
        }
        return events
    }

    // MARK: - Matching

    private struct ForwardHit {
        let scriptIndex: Int
        /// How many script words were passed over to reach it.
        let gap: Int
        /// How many spoken words the match consumed, for a number alias.
        let consumed: Int
    }

    /// Best candidate at or ahead of the cursor, preferring the nearest.
    private static func findForward(
        _ word: String,
        state: FollowState,
        script: TeleprompterScript,
        config: FollowConfig
    ) -> ForwardHit? {
        let start = state.cursor
        guard start < script.tokens.count else { return nil }
        let end = min(start + config.lookahead, script.tokens.count)

        var best: ForwardHit?
        var bestScore = 0.0

        for candidate in start..<end {
            let token = script.tokens[candidate]
            var quality = TokenSimilarity.compare(word, token.normalized)

            // A written `25` also answers to the first word of "twenty five".
            if quality == .none {
                for alias in token.aliases where alias.first == word {
                    quality = .exact
                    break
                }
            }
            guard quality != .none else { continue }

            let distance = Double(candidate - start)
            let score = quality.weight - distance * config.skipPenalty
            if score > bestScore {
                bestScore = score
                best = ForwardHit(scriptIndex: candidate, gap: candidate - start, consumed: 1)
            }
        }
        return best
    }

    /// Whether the word matches something just behind the cursor.
    private static func findBackward(
        _ word: String,
        state: FollowState,
        script: TeleprompterScript,
        config: FollowConfig
    ) -> Int? {
        let end = min(state.cursor, script.tokens.count)
        let start = max(0, end - config.lookbehind)
        guard start < end else { return nil }

        for candidate in start..<end
        where TokenSimilarity.compare(word, script.tokens[candidate].normalized) != .none {
            return candidate
        }
        return nil
    }

    private static func apply(
        forwardHit hit: ForwardHit,
        state: inout FollowState,
        script: TeleprompterScript,
        config: FollowConfig,
        now: TimeInterval,
        events: inout [Event]
    ) {
        if hit.gap > config.maxSilentSkip {
            // Too far to accept on one word. Hold it as a candidate until enough
            // corroboration arrives — this is what stops a single coincidental
            // common word from teleporting the reader.
            if state.jumpTarget == hit.scriptIndex || state.jumpTarget == nil {
                state.jumpTarget = hit.scriptIndex
                state.jumpConfirmations += 1
            } else {
                state.jumpTarget = hit.scriptIndex
                state.jumpConfirmations = 1
            }

            guard state.jumpConfirmations >= config.jumpConfirmRun else { return }
            commitJump(to: hit.scriptIndex, state: &state, config: config, now: now, events: &events)
            return
        }

        // A short gap is an ordinary skip: absorb it and carry on.
        if hit.gap > 0 {
            let skipped = state.cursor..<hit.scriptIndex
            state.skipped.append(SkippedRange(range: skipped))
            events.append(.skipped(skipped))
        }

        state.cursor = hit.scriptIndex + 1
        state.matchRun += 1
        state.matchedWordCount += 1
        state.offScriptRun = 0
        state.lastMatchAt = now
        state.jumpTarget = nil
        state.jumpConfirmations = 0

        if state.mode == .offScript {
            state.mode = .following
            events.append(.returnedToScript(scriptIndex: hit.scriptIndex))
        } else {
            state.mode = .following
        }

        // Deferred commit: the highlight waits for corroboration.
        if state.matchRun >= config.confirmRun {
            state.confirmedCursor = state.cursor
        }
        events.append(.matched(scriptIndex: hit.scriptIndex))
    }

    // MARK: - Off script

    private static func recordOffScript(
        _ word: String,
        state: inout FollowState,
        config: FollowConfig,
        now: TimeInterval,
        events: inout [Event]
    ) {
        state.offScriptRun += 1
        state.matchRun = 0

        if var last = state.offScriptRuns.last, last.scriptIndex == state.confirmedCursor,
           state.mode == .offScript {
            last.spokenWords.append(word)
            last.endedAt = now
            state.offScriptRuns[state.offScriptRuns.count - 1] = last
        } else if state.offScriptRun >= config.offScriptThreshold {
            state.offScriptRuns.append(
                OffScriptRun(
                    scriptIndex: state.confirmedCursor,
                    spokenWords: [word],
                    startedAt: now,
                    endedAt: now
                )
            )
        }

        if state.offScriptRun >= config.offScriptThreshold, state.mode != .offScript {
            state.mode = .offScript
            // The cursor deliberately does not move: when you do not know where
            // the speaker is, waiting beats guessing.
            events.append(.wentOffScript(atScriptIndex: state.confirmedCursor))
        }
    }

    /// Treats a distinctive word as a candidate position elsewhere in the script.
    ///
    /// The local window only reaches `lookahead` words ahead, so without this a
    /// speaker who jumps to another section is simply "off script" until the
    /// recovery threshold — several seconds of the prompter sitting still, when
    /// jumping between sections is something presenters do constantly.
    ///
    /// Safety comes from two conditions rather than from a narrow window: the
    /// word has to be **rare** in the script (a common word names no place), and
    /// several such words have to agree on **roughly the same place** before the
    /// cursor moves. One coincidence is not enough.
    ///
    /// - Returns: `true` when the word was consumed as jump evidence.
    private static func considerAnchorJump(
        _ word: String,
        state: inout FollowState,
        script: TeleprompterScript,
        index: ScriptFollowIndex,
        config: FollowConfig,
        now: TimeInterval,
        events: inout [Event]
    ) -> Bool {
        guard let positions = index.rareAnchors[word], !positions.isEmpty else { return false }

        // Corroborate an existing candidate when this word points nearby.
        if let existing = state.jumpTarget,
           let nearby = positions.min(by: { abs($0 - existing) < abs($1 - existing) }),
           abs(nearby - existing) <= config.lookahead {
            state.jumpConfirmations += 1
            state.jumpTarget = nearby
        } else {
            // Prefer a position ahead of where we are; a presenter going back is
            // rarer than one moving on.
            let ahead = positions.first { $0 >= state.cursor }
            state.jumpTarget = ahead ?? positions[0]
            state.jumpConfirmations = 1
        }

        guard let target = state.jumpTarget,
              state.jumpConfirmations >= config.jumpConfirmRun
        else {
            // Held as evidence, so it is not also counted as going off script.
            return true
        }

        commitJump(to: target, state: &state, config: config, now: now, events: &events)
        return true
    }

    /// Moves the cursor to a corroborated position, recording what was passed.
    private static func commitJump(
        to target: Int,
        state: inout FollowState,
        config: FollowConfig,
        now: TimeInterval,
        events: inout [Event]
    ) {
        let from = state.confirmedCursor
        if target > from {
            let skipped = from..<target
            state.skipped.append(SkippedRange(range: skipped))
            events.append(.skipped(skipped))
        }

        state.cursor = target + 1
        state.confirmedCursor = state.cursor
        state.jumpTarget = nil
        state.jumpConfirmations = 0
        state.matchRun = config.confirmRun
        state.offScriptRun = 0
        state.lastMatchAt = now
        state.matchedWordCount += 1

        if state.mode == .offScript {
            events.append(.returnedToScript(scriptIndex: target))
        }
        state.mode = .following
        events.append(.jumped(from: from, to: target))
    }

    // MARK: - Credit and coverage

    private static func remember(_ word: String, in state: inout FollowState, config: FollowConfig) {
        state.recentSpoken.append(word)
        if state.recentSpoken.count > config.recentSpokenWindow {
            state.recentSpoken.removeFirst(state.recentSpoken.count - config.recentSpokenWindow)
        }
    }

    /// Credits a key phrase the speaker has covered in their own words.
    ///
    /// Only phrases near the current position are considered, so a phrase from
    /// the far end of the script cannot be credited by coincidence.
    private static func creditKeyPhrases(
        state: inout FollowState,
        script: TeleprompterScript,
        config: FollowConfig,
        events: inout [Event]
    ) {
        guard !state.recentSpoken.isEmpty else { return }
        let heard = Set(state.recentSpoken)
        let current = sectionIndex(for: state.confirmedCursor, in: script)

        for offset in -1...1 {
            let sectionIndex = current + offset
            guard script.sections.indices.contains(sectionIndex) else { continue }
            for phrase in script.sections[sectionIndex].keyPhrases {
                guard !state.creditedKeyPhraseIDs.contains(phrase.id) else { continue }
                guard !phrase.contentWords.isEmpty else { continue }

                let covered = phrase.contentWords.filter { heard.contains($0) }.count
                let fraction = Double(covered) / Double(phrase.contentWords.count)
                guard fraction >= phrase.requiredFraction else { continue }

                state.creditedKeyPhraseIDs.insert(phrase.id)
                events.append(.creditedKeyPhrase(id: phrase.id, sectionIndex: sectionIndex))
            }
        }
    }

    /// A section counts as covered once most of it has been read, or once all of
    /// its key phrases have been credited — a fully ad-libbed but on-message
    /// section still counts.
    private static func updateCoverage(
        state: inout FollowState,
        script: TeleprompterScript,
        events: inout [Event],
        readFraction: Double = 0.7
    ) {
        for (sectionIndex, section) in script.sections.enumerated() {
            guard !state.coveredSectionIndices.contains(sectionIndex) else { continue }
            // A section the reader has not reached cannot be covered, and this
            // runs on every partial result — without the bail, each call would
            // re-scan the whole (growing) skip list for every section ahead.
            guard section.tokenRange.lowerBound <= state.confirmedCursor else { continue }

            var covered = false
            if !section.tokenRange.isEmpty {
                let read = min(state.confirmedCursor, section.tokenRange.upperBound) - section.tokenRange.lowerBound
                let skippedInside = state.skipped
                    .map { $0.range.clamped(to: section.tokenRange).count }
                    .reduce(0, +)
                let effective = max(0, read - skippedInside)
                covered = Double(effective) / Double(section.tokenRange.count) >= readFraction
            }

            if !covered, !section.keyPhrases.isEmpty {
                covered = section.keyPhrases.allSatisfy { state.creditedKeyPhraseIDs.contains($0.id) }
            }

            if covered {
                state.coveredSectionIndices.insert(sectionIndex)
                events.append(.coveredSection(sectionIndex))
            }
        }
    }

    static func sectionIndex(for tokenIndex: Int, in script: TeleprompterScript) -> Int {
        guard !script.tokens.isEmpty else { return 0 }
        let clamped = min(max(0, tokenIndex), script.tokens.count - 1)
        return script.tokens[clamped].sectionIndex
    }
}
