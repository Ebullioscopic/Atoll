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

import XCTest
@testable import Atoll

/// Covers the teleprompter's pure core: tokenisation and script parsing. Both
/// feed the voice matcher, so an error here would surface as the prompter
/// mysteriously losing the reader's place.
final class TeleprompterTests: XCTestCase {

    private let english = Locale(identifier: "en_US")
    private let turkish = Locale(identifier: "tr_TR")

    private func parse(_ markdown: String, locale: Locale? = nil) -> TeleprompterScript {
        TeleprompterScriptParser.parse(
            markdown: markdown,
            name: "Test",
            locale: locale ?? english,
            now: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Normalisation

    func testNormalizationFoldsCaseAndDiacritics() {
        XCTAssertEqual(TeleprompterTokenizer.normalize("Hello", locale: english), "hello")
        XCTAssertEqual(TeleprompterTokenizer.normalize("café", locale: english), "cafe")
        XCTAssertEqual(TeleprompterTokenizer.normalize("naïve", locale: english), "naive")
    }

    /// The case that makes the locale parameter load-bearing rather than
    /// decorative: fold Turkish with the wrong locale and every capitalised
    /// sentence opening reads as the speaker going off script.
    func testTurkishFoldingMakesTheseFormsComparable() {
        let written = TeleprompterTokenizer.normalize("İSTANBUL", locale: turkish)
        let spoken = TeleprompterTokenizer.normalize("istanbul", locale: turkish)
        XCTAssertEqual(written, spoken)

        for word in ["Öğrenci", "ogrenci", "ÖĞRENCİ"] {
            XCTAssertEqual(
                TeleprompterTokenizer.normalize(word, locale: turkish),
                "ogrenci",
                "Turkish diacritics must fold so the recogniser and the script agree: \(word)"
            )
        }
    }

    func testIntraWordPunctuationIsKeptAndTheRestDropped() {
        XCTAssertEqual(TeleprompterTokenizer.normalize("don't", locale: english), "don't")
        XCTAssertEqual(TeleprompterTokenizer.normalize("well-known", locale: english), "well-known")
        XCTAssertEqual(TeleprompterTokenizer.normalize("“hello”", locale: english), "hello")
        XCTAssertEqual(TeleprompterTokenizer.normalize("end.", locale: english), "end")
        XCTAssertEqual(TeleprompterTokenizer.normalize("—", locale: english), "")
    }

    /// Curly and straight apostrophes must land on the same token: keyboards and
    /// recognisers disagree about which they produce.
    func testTypographicApostrophesAreUnified() {
        XCTAssertEqual(
            TeleprompterTokenizer.normalize("don\u{2019}t", locale: english),
            TeleprompterTokenizer.normalize("don't", locale: english)
        )
    }

    func testNormalizedWordsDropsEmptyTokens() {
        let words = TeleprompterTokenizer.normalizedWords(in: "Hello, — world!", locale: english)
        XCTAssertEqual(words, ["hello", "world"])
    }

    // MARK: - Number aliases

    /// A script writes `25`; a recogniser hears "twenty five". Expanding the
    /// script side once at parse time keeps matching a lookup instead of needing
    /// a number parser per language.
    func testDigitsGainASpokenAlias() {
        let aliases = TeleprompterTokenizer.aliases(for: "25", normalized: "25", locale: english)
        XCTAssertEqual(aliases.count, 1)
        XCTAssertEqual(aliases.first, ["twenty", "five"])
    }

    func testSpokenAliasesFollowTheLocale() {
        let aliases = TeleprompterTokenizer.aliases(for: "3", normalized: "3", locale: turkish)
        XCTAssertEqual(aliases.first, [TeleprompterTokenizer.normalize("üç", locale: turkish)])
    }

    func testNonNumbersHaveNoAliases() {
        XCTAssertTrue(TeleprompterTokenizer.aliases(for: "hello", normalized: "hello", locale: english).isEmpty)
    }

    // MARK: - Content words

    func testStopwordsAreExcludedFromKeyPhraseContent() {
        let words = TeleprompterTokenizer.contentWords(in: "we should ship it by Friday", locale: english)
        XCTAssertTrue(words.contains("ship"))
        XCTAssertTrue(words.contains("friday"))
        XCTAssertFalse(words.contains("we"))
        XCTAssertFalse(words.contains("by"))
    }

    /// A phrase made entirely of common words is still better matched loosely
    /// than never matched at all.
    func testAPhraseOfOnlyStopwordsKeepsItsWords() {
        let words = TeleprompterTokenizer.contentWords(in: "it is the", locale: english)
        XCTAssertFalse(words.isEmpty)
    }

    // MARK: - Headings

    func testMustCoverMarkerIsRecognisedAndOptional() {
        let script = parse("""
        ## ! Introduction
        Hello there.

        ## Details
        More words.
        """)
        XCTAssertEqual(script.sections.count, 2)
        XCTAssertEqual(script.sections[0].title, "Introduction")
        XCTAssertTrue(script.sections[0].mustCover)
        XCTAssertFalse(script.sections[1].mustCover)
        XCTAssertEqual(script.mustCoverSections.count, 1)
    }

    func testHeadingDurationsAreParsedInEveryAcceptedForm() {
        XCTAssertEqual(TeleprompterScriptParser.parseHeading("## Intro (1:30)")?.targetDuration, 90)
        XCTAssertEqual(TeleprompterScriptParser.parseHeading("## Intro (90s)")?.targetDuration, 90)
        XCTAssertEqual(TeleprompterScriptParser.parseHeading("## Intro (2m)")?.targetDuration, 120)
        XCTAssertEqual(TeleprompterScriptParser.parseHeading("## Intro (45)")?.targetDuration, 45)
        XCTAssertEqual(TeleprompterScriptParser.parseHeading("## Intro (1:30)")?.title, "Intro")
    }

    /// A trailing parenthesis that is not a duration belongs to the title.
    func testNonDurationParenthesesStayInTheTitle() {
        let heading = TeleprompterScriptParser.parseHeading("## Pricing (revised)")
        XCTAssertEqual(heading?.title, "Pricing (revised)")
        XCTAssertNil(heading?.targetDuration)
    }

    func testInvalidDurationsAreRejected() {
        XCTAssertNil(TeleprompterScriptParser.parseDuration("1:75"), "75 seconds is not a time.")
        XCTAssertNil(TeleprompterScriptParser.parseDuration("abc"))
        XCTAssertNil(TeleprompterScriptParser.parseDuration(""))
    }

    /// Markdown requires a space after the hashes, so `#hashtag` is prose.
    func testHashtagIsNotAHeading() {
        XCTAssertNil(TeleprompterScriptParser.parseHeading("#hashtag"))
        XCTAssertNil(TeleprompterScriptParser.parseHeading("####### too many"))
    }

    // MARK: - Key phrases and notes

    func testKeyPhraseSyntaxIsParsedOntoItsSection() {
        let script = parse("""
        ## ! Close
        > key: ship it by Friday
        We need to decide today.
        """)
        let section = script.sections[0]
        XCTAssertEqual(section.keyPhrases.count, 1)
        XCTAssertEqual(section.keyPhrases[0].text, "ship it by Friday")
        XCTAssertTrue(section.keyPhrases[0].contentWords.contains("ship"))
    }

    func testKeyPhrasePrefixToleratesSpacingAndCase() {
        XCTAssertEqual(TeleprompterScriptParser.parseKeyPhrase("key: alpha"), "alpha")
        XCTAssertEqual(TeleprompterScriptParser.parseKeyPhrase("Key : beta"), "beta")
        XCTAssertEqual(TeleprompterScriptParser.parseKeyPhrase("KEY:gamma"), "gamma")
        XCTAssertNil(TeleprompterScriptParser.parseKeyPhrase("keyboard shortcuts"))
        XCTAssertNil(TeleprompterScriptParser.parseKeyPhrase("key:"))
    }

    /// The most important parsing rule: you do not read your notes aloud, so a
    /// note must contribute no tokens. A phantom word would register as a skip
    /// and pull the prompter out of sync.
    func testSpeakerNotesContributeNoTokens() {
        let script = parse("""
        ## Intro
        > Remember to smile here.
        Hello everyone.
        """)
        XCTAssertEqual(script.sections[0].notes, ["Remember to smile here."])
        XCTAssertEqual(script.tokens.map(\.normalized), ["hello", "everyone"])
    }

    // MARK: - Structure

    func testProseBeforeTheFirstHeadingBecomesItsOwnSection() {
        let script = parse("""
        An opening line with no heading.

        ## Then a heading
        More text.
        """)
        XCTAssertEqual(script.sections.count, 2)
        XCTAssertEqual(script.sections[0].title, "")
        XCTAssertEqual(script.sections[0].wordCount, 6)
    }

    /// Token ranges drive both highlighting and the debrief's coverage maths, so
    /// they must tile the token array exactly.
    func testSectionTokenRangesAreContiguousAndCoverEveryToken() {
        let script = parse("""
        ## One
        alpha beta

        ## Two
        gamma delta epsilon

        ## Three
        zeta
        """)
        var expectedStart = 0
        for section in script.sections {
            XCTAssertEqual(section.tokenRange.lowerBound, expectedStart, "Gap or overlap at \(section.title)")
            expectedStart = section.tokenRange.upperBound
        }
        XCTAssertEqual(expectedStart, script.tokens.count)
        XCTAssertEqual(script.wordCount, 6)
    }

    func testEveryTokenKnowsItsSection() {
        let script = parse("""
        ## One
        alpha

        ## Two
        beta gamma
        """)
        XCTAssertEqual(script.tokens.map(\.sectionIndex), [0, 1, 1])
    }

    func testAHeadingWithNoBodyStillBecomesASection() {
        let script = parse("""
        ## ! Placeholder

        ## Real
        words here
        """)
        XCTAssertEqual(script.sections.count, 2)
        XCTAssertEqual(script.sections[0].wordCount, 0)
        XCTAssertTrue(script.sections[0].mustCover, "An empty must-cover section is still a target.")
    }

    // MARK: - Markup that should not be spoken

    func testFencedCodeBlocksAreSkipped() {
        let script = parse("""
        ## Demo
        Run this:

        ```
        rm -rf build
        ```

        Then continue.
        """)
        let words = script.tokens.map(\.normalized)
        XCTAssertFalse(words.contains("rm"))
        XCTAssertTrue(words.contains("continue"))
    }

    func testHorizontalRulesAreSkipped() {
        let script = parse("""
        ## One
        alpha
        ---
        beta
        """)
        XCTAssertEqual(script.tokens.map(\.normalized), ["alpha", "beta"])
    }

    func testInlineMarkupIsUnwrappedNotDropped() {
        XCTAssertEqual(TeleprompterScriptParser.strippingInlineMarkup("This is **bold** text"), "This is bold text")
        XCTAssertEqual(TeleprompterScriptParser.strippingInlineMarkup("Use `swift build` now"), "Use swift build now")
        XCTAssertEqual(TeleprompterScriptParser.strippingInlineMarkup("See [the docs](https://x.com)"), "See the docs")
        XCTAssertEqual(TeleprompterScriptParser.strippingInlineMarkup("- a bullet"), "a bullet")
        XCTAssertEqual(TeleprompterScriptParser.strippingInlineMarkup("1. numbered"), "numbered")
    }

    func testImagesContributeNothing() {
        XCTAssertEqual(TeleprompterScriptParser.strippingInlineMarkup("![alt](pic.png)"), "")
    }

    // MARK: - Partial transcript diffing

    /// The recogniser reports the whole utterance every time, so only the new
    /// tail may reach the matcher.
    func testOnlyNewWordsAreEmittedFromACumulativeTranscript() {
        let delta = SpeechTranscriptDiffer.delta(previous: ["i", "have", "a"], current: ["i", "have", "a", "dream"])
        XCTAssertEqual(delta.newWords, ["dream"])
        XCTAssertFalse(delta.revisedTail)
    }

    func testAnUnchangedTranscriptEmitsNothing() {
        let delta = SpeechTranscriptDiffer.delta(previous: ["hello", "world"], current: ["hello", "world"])
        XCTAssertTrue(delta.newWords.isEmpty)
    }

    /// "I have a dre" becoming "I have a dream" is the recogniser doing its job.
    func testARewriteOfTheRecentTailIsAccepted() {
        let delta = SpeechTranscriptDiffer.delta(
            previous: ["i", "have", "a", "dre"],
            current: ["i", "have", "a", "dream"]
        )
        XCTAssertEqual(delta.newWords, ["dream"])
        XCTAssertTrue(delta.revisedTail)
    }

    /// A rewrite deep in settled text would mean rewinding a highlight the reader
    /// has already passed, which is worse than being briefly stale.
    func testADeepRewriteIsIgnoredExceptForGenuinelyNewWords() {
        let previous = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta"]
        let current = ["alpha", "CHANGED", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota"]

        let delta = SpeechTranscriptDiffer.delta(previous: previous, current: current)
        XCTAssertEqual(delta.newWords, ["iota"], "Only the genuinely new word should be forwarded.")
        XCTAssertTrue(delta.revisedTail)
    }

    func testADeepRewriteWithNothingNewEmitsNothing() {
        let previous = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta"]
        let current = ["alpha", "CHANGED", "gamma", "delta", "epsilon", "zeta", "eta"]
        XCTAssertTrue(SpeechTranscriptDiffer.delta(previous: previous, current: current).newWords.isEmpty)
    }

    /// A new recognition task starts from an empty transcript. Everything it says
    /// is new — and because position lives in the matcher, that is harmless.
    func testAFreshTaskEmitsItsWholeTranscript() {
        let delta = SpeechTranscriptDiffer.delta(previous: [], current: ["and", "so", "we", "continue"])
        XCTAssertEqual(delta.newWords, ["and", "so", "we", "continue"])
    }

    /// Replaying a whole session as growing partials must produce each word once.
    func testStreamingPartialsEmitEveryWordExactlyOnce() {
        let sentence = ["the", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"]
        var previous: [String] = []
        var emitted: [String] = []

        for count in 1...sentence.count {
            let current = Array(sentence[0..<count])
            emitted += SpeechTranscriptDiffer.delta(previous: previous, current: current).newWords
            previous = current
        }
        XCTAssertEqual(emitted, sentence)
    }

    // MARK: - Microphone lease

    /// Two clients on one microphone means silently recording someone's whole
    /// presentation, so only one feature may hold it.
    func testOnlyOneFeatureCanHoldTheMicrophone() {
        let lease = MicrophoneLease.shared
        lease.release(.screenAssistant)
        lease.release(.teleprompter)

        XCTAssertTrue(lease.acquire(.teleprompter))
        XCTAssertFalse(lease.acquire(.screenAssistant))
        XCTAssertEqual(lease.blocker(for: .screenAssistant), .teleprompter)

        lease.release(.teleprompter)
        XCTAssertTrue(lease.acquire(.screenAssistant))
        lease.release(.screenAssistant)
    }

    func testReacquiringAsTheCurrentOwnerSucceeds() {
        let lease = MicrophoneLease.shared
        lease.release(.teleprompter)
        XCTAssertTrue(lease.acquire(.teleprompter))
        XCTAssertTrue(lease.acquire(.teleprompter), "A restart should not have to release first.")
        XCTAssertNil(lease.blocker(for: .teleprompter))
        lease.release(.teleprompter)
    }

    /// A stale teardown must not take the microphone from whoever holds it now.
    func testReleasingWhenNotTheOwnerIsIgnored() {
        let lease = MicrophoneLease.shared
        lease.release(.screenAssistant)
        lease.release(.teleprompter)

        XCTAssertTrue(lease.acquire(.teleprompter))
        lease.release(.screenAssistant)
        XCTAssertEqual(lease.currentOwner, .teleprompter)
        lease.release(.teleprompter)
        XCTAssertNil(lease.currentOwner)
    }

    // MARK: - Library store

    func testLibraryRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("teleprompter-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = TeleprompterLibraryStore(fileURL: url)
        XCTAssertTrue(store.load().isEmpty)

        let script = parse("## ! Intro (1:00)\n> key: land the point\nHello there.")
        store.save([script])

        let reloaded = TeleprompterLibraryStore(fileURL: url).load()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded[0].markdown, script.markdown)
        XCTAssertEqual(reloaded[0].tokens.map(\.normalized), script.tokens.map(\.normalized))
        XCTAssertEqual(reloaded[0].sections[0].keyPhrases.count, 1)
        XCTAssertTrue(reloaded[0].sections[0].mustCover)
        XCTAssertEqual(reloaded[0].sections[0].targetDuration, 60)
    }

    /// A disabled feature must leave no trace, so merely reading the library
    /// cannot bring its directory into existence.
    func testReadingTheLibraryCreatesNothingOnDisk() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teleprompter-untouched-\(UUID().uuidString)", isDirectory: true)
        let url = root.appendingPathComponent("scripts.json")

        XCTAssertTrue(TeleprompterLibraryStore(fileURL: url).load().isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.path),
            "Loading an absent library must not create its folder."
        )
    }

    /// Saving an empty library removes the file rather than leaving `[]` behind.
    func testSavingAnEmptyLibraryRemovesTheFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("teleprompter-\(UUID().uuidString).json")
        let store = TeleprompterLibraryStore(fileURL: url)
        store.save([parse("## One\nalpha")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        store.save([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Key commands

    /// The reader is looking at a camera, so the keyboard has to drive
    /// everything. These are the keys the panel claims.
    func testKeyCommandsCoverPlaybackNavigationAndSectionJumps() {
        XCTAssertEqual(command(keyCode: 49), .togglePlayback)
        XCTAssertEqual(command(keyCode: 124), .nextWord)
        XCTAssertEqual(command(keyCode: 123), .previousWord)
        XCTAssertEqual(command(keyCode: 125), .nextSection)
        XCTAssertEqual(command(keyCode: 126), .previousSection)
        XCTAssertEqual(command(keyCode: 53), .close)
        XCTAssertEqual(command(keyCode: 15, characters: "r"), .restart)
    }

    /// `1` means the first section, so the payload is zero-based.
    func testNumberKeysJumpToTheMatchingSection() {
        XCTAssertEqual(command(keyCode: 18, characters: "1"), .jumpToSection(0))
        XCTAssertEqual(command(keyCode: 25, characters: "9"), .jumpToSection(8))
        XCTAssertNil(command(keyCode: 29, characters: "0"), "There is no zeroth section.")
    }

    func testUnclaimedKeysArePassedOn() {
        XCTAssertNil(command(keyCode: 0, characters: "a"))
    }

    private func command(keyCode: UInt16, characters: String = "") -> TeleprompterKeyCommand? {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        ) else {
            XCTFail("Could not synthesise a key event")
            return nil
        }
        return TeleprompterKeyCommand(event: event)
    }

    // MARK: - Display mode

    func testDisplayModeControlsWhichSurfacesAppear() {
        XCTAssertFalse(TeleprompterDisplayMode.panel.showsNotchTab)
        XCTAssertTrue(TeleprompterDisplayMode.panel.showsPanel)
        XCTAssertTrue(TeleprompterDisplayMode.tab.showsNotchTab)
        XCTAssertFalse(TeleprompterDisplayMode.tab.showsPanel)
        XCTAssertTrue(TeleprompterDisplayMode.both.showsNotchTab)
        XCTAssertTrue(TeleprompterDisplayMode.both.showsPanel)
    }

    /// Atoll cannot ship OpenDyslexic — committing a font binary is against the
    /// project's rules — so the choice must resolve gracefully when it is absent.
    func testOnlyOpenDyslexicRequiresAnInstalledFont() {
        XCTAssertNil(TeleprompterFontChoice.system.requiredFamilyName)
        XCTAssertNil(TeleprompterFontChoice.highLegibility.requiredFamilyName)
        XCTAssertEqual(TeleprompterFontChoice.openDyslexic.requiredFamilyName, "OpenDyslexic")
        XCTAssertTrue(TeleprompterFontChoice.system.isAvailable)
        XCTAssertTrue(TeleprompterFontChoice.highLegibility.isAvailable)
    }

    // MARK: - Token similarity

    /// Fuzzy-matching function words is where a naive matcher destroys itself:
    /// `the`, `then`, `they` and `there` are one or two edits apart and are the
    /// most frequent words in any script.
    func testShortWordsRequireAnExactMatch() {
        XCTAssertEqual(TokenSimilarity.compare("the", "the"), .exact)
        XCTAssertEqual(TokenSimilarity.compare("the", "then"), .none)
        XCTAssertEqual(TokenSimilarity.compare("they", "then"), .none)
        XCTAssertEqual(TokenSimilarity.compare("cat", "cut"), .none)
    }

    func testRecogniserSlipsAndSpellingVariantsAreAccepted() {
        XCTAssertEqual(TokenSimilarity.compare("recognise", "recognize"), .near)
        XCTAssertEqual(TokenSimilarity.compare("colour", "color"), .near)
        XCTAssertEqual(TokenSimilarity.compare("presentation", "presentaton"), .near)
    }

    func testUnrelatedWordsDoNotMatch() {
        XCTAssertEqual(TokenSimilarity.compare("engineering", "marketing"), .none)
        XCTAssertEqual(TokenSimilarity.compare("hello", "goodbye"), .none)
    }

    /// Turkish, Finnish and Hungarian stack suffixes onto a stable stem. Without
    /// prefix tolerance nearly every inflected word would read as a miss.
    func testAgglutinativeSuffixesStillMatchTheirStem() {
        XCTAssertEqual(TokenSimilarity.compare("kitaplar", "kitap"), .near)
        XCTAssertEqual(TokenSimilarity.compare("ogrenciler", "ogrenci"), .near)

        // A two-letter stem is not a stem. `evde` and `evlerde` share only `ev`,
        // which would match far too much to be safe.
        XCTAssertEqual(TokenSimilarity.compare("evlerde", "evde"), .none)
        // And a long suffix chain has drifted too far to be the same word here.
        XCTAssertEqual(TokenSimilarity.compare("kitaplarimizdan", "kitap"), .none)
    }

    /// `they`/`then` and `there`/`their` are the pairs that would quietly wreck
    /// the matcher, so they are pinned explicitly.
    func testTheMostDangerousFunctionWordPairsNeverMatch() {
        XCTAssertEqual(TokenSimilarity.compare("they", "then"), .none)
        XCTAssertEqual(TokenSimilarity.compare("there", "their"), .none)
        XCTAssertEqual(TokenSimilarity.compare("that", "than"), .none)
        XCTAssertEqual(TokenSimilarity.compare("were", "where"), .none)
        // Content words of the same length are still allowed to differ by one.
        XCTAssertEqual(TokenSimilarity.compare("color", "colour"), .near)
    }

    func testEditDistanceAbandonsEarlyBeyondTheLimit() {
        XCTAssertEqual(TokenSimilarity.editDistance(Array("abc"), Array("abc"), limit: 2), 0)
        XCTAssertEqual(TokenSimilarity.editDistance(Array("abc"), Array("abd"), limit: 2), 1)
        XCTAssertGreaterThan(TokenSimilarity.editDistance(Array("abc"), Array("xyz"), limit: 1), 1)
    }

    // MARK: - Following the reader

    private func follow(
        _ script: TeleprompterScript,
        saying words: [String],
        state: inout FollowState,
        at time: TimeInterval = 1
    ) -> [ScriptFollower.Event] {
        let index = ScriptFollowIndex(script: script)
        return ScriptFollower.advance(
            state: &state,
            spoken: words.map { TeleprompterTokenizer.normalize($0, locale: english) },
            script: script,
            index: index,
            now: time
        )
    }

    /// Speaking the script verbatim should track it exactly and report nothing
    /// unusual.
    func testReadingVerbatimTracksWordForWord() {
        let script = parse("## One\nthe quick brown fox jumps over the lazy dog")
        var state = FollowState()
        _ = follow(script, saying: ["the", "quick", "brown", "fox", "jumps", "over", "the", "lazy", "dog"], state: &state)

        XCTAssertEqual(state.confirmedCursor, script.tokens.count)
        XCTAssertEqual(state.mode, .following)
        XCTAssertTrue(state.skipped.isEmpty)
        XCTAssertTrue(state.offScriptRuns.isEmpty)
        XCTAssertEqual(state.matchedWordCount, 9)
    }

    /// The highlight must not move on a single ambiguous word.
    func testTheHighlightWaitsForCorroboration() {
        let script = parse("## One\nalpha beta gamma delta")
        var state = FollowState()
        _ = follow(script, saying: ["alpha"], state: &state)
        XCTAssertEqual(state.cursor, 1)
        XCTAssertEqual(state.confirmedCursor, 0, "One word is not enough to move the display.")

        _ = follow(script, saying: ["beta"], state: &state)
        XCTAssertEqual(state.confirmedCursor, 2)
    }

    /// A pause must leave the position exactly where it was.
    func testSilenceDoesNotAdvanceOrPenalise() {
        let script = parse("## One\nalpha beta gamma delta epsilon")
        var state = FollowState()
        _ = follow(script, saying: ["alpha", "beta"], state: &state, at: 1)
        let position = state.confirmedCursor

        _ = follow(script, saying: [], state: &state, at: 30)
        XCTAssertEqual(state.confirmedCursor, position)
        XCTAssertEqual(state.mode, .waiting)
        XCTAssertTrue(state.offScriptRuns.isEmpty)

        _ = follow(script, saying: ["gamma"], state: &state, at: 31)
        XCTAssertEqual(state.mode, .following)
    }

    /// Skipping a clause is ordinary; it should be absorbed and recorded.
    func testASkippedClauseIsAbsorbedAndRecorded() {
        let script = parse("## One\nalpha beta gamma delta epsilon zeta eta theta")
        var state = FollowState()
        _ = follow(script, saying: ["alpha", "epsilon", "zeta"], state: &state)

        XCTAssertEqual(state.mode, .following)
        XCTAssertEqual(state.skipped.count, 1)
        XCTAssertEqual(state.skipped[0].range, 1..<4, "beta gamma delta were skipped.")
        XCTAssertGreaterThanOrEqual(state.confirmedCursor, 6)
    }

    /// The regression that matters most: one coincidental common word far away
    /// must not move the reader.
    func testASingleFarAwayMatchDoesNotTeleportTheReader() {
        let body = Array(repeating: "filler", count: 60).joined(separator: " ")
        let script = parse("## One\nalpha beta \(body) alpha omega")
        var state = FollowState()

        _ = follow(script, saying: ["alpha", "beta"], state: &state)
        let before = state.confirmedCursor

        // "omega" only appears at the very end. One hit must not commit.
        _ = follow(script, saying: ["omega"], state: &state)
        XCTAssertEqual(state.confirmedCursor, before, "A lone distant match must stay a candidate.")
    }

    /// Jumping to another section is something presenters do constantly, and it
    /// looks like this: several distinctive words from somewhere else, together.
    func testJumpingToAnotherSectionIsFollowed() {
        let body = Array(repeating: "filler", count: 40).joined(separator: " ")
        let script = parse("""
        ## One
        alpha beta \(body)

        ## Two
        quarterly revenue forecast improved substantially
        """)
        var state = FollowState()
        _ = follow(script, saying: ["alpha", "beta"], state: &state)

        _ = follow(script, saying: ["quarterly", "revenue", "forecast", "improved"], state: &state)
        XCTAssertGreaterThan(state.confirmedCursor, 40, "Four agreeing distinctive words should commit the jump.")
        XCTAssertEqual(state.mode, .following)
    }

    /// A common word repeated cannot name a place, however often it is said.
    func testRepeatingACommonWordNeverCausesAJump() {
        let body = Array(repeating: "filler", count: 40).joined(separator: " ")
        let script = parse("## One\nalpha beta \(body) filler filler filler")
        var state = FollowState()
        _ = follow(script, saying: ["alpha", "beta"], state: &state)
        let before = state.confirmedCursor

        _ = follow(script, saying: ["filler", "filler", "filler", "filler"], state: &state)
        XCTAssertLessThanOrEqual(
            state.confirmedCursor, before + 12,
            "A word that occurs everywhere identifies nowhere."
        )
    }

    /// Repeating yourself is not going off script, and must never rewind the
    /// highlight.
    func testRepeatingAPhraseDoesNotRewindOrCountAsOffScript() {
        let script = parse("## One\nalpha beta gamma delta epsilon")
        var state = FollowState()
        _ = follow(script, saying: ["alpha", "beta", "gamma"], state: &state)
        let position = state.confirmedCursor

        _ = follow(script, saying: ["beta", "gamma"], state: &state)
        XCTAssertGreaterThanOrEqual(state.confirmedCursor, position, "The highlight must not go backwards.")
        XCTAssertEqual(state.mode, .following)
        XCTAssertTrue(state.offScriptRuns.isEmpty)
    }

    /// Ad-libbing should freeze the prompter rather than send it guessing, and
    /// the first real word should pick it back up.
    func testAdLibbingFreezesTheCursorAndResumesCleanly() {
        let script = parse("## One\nalpha beta gamma delta epsilon zeta")
        var state = FollowState()
        _ = follow(script, saying: ["alpha", "beta"], state: &state)
        let frozen = state.confirmedCursor

        let improvised = ["incidentally", "something", "completely", "different", "happened", "yesterday", "morning"]
        _ = follow(script, saying: improvised, state: &state, at: 5)

        XCTAssertEqual(state.mode, .offScript)
        XCTAssertEqual(state.confirmedCursor, frozen, "The cursor must not guess while off script.")
        XCTAssertFalse(state.offScriptRuns.isEmpty)

        _ = follow(script, saying: ["gamma", "delta"], state: &state, at: 6)
        XCTAssertEqual(state.mode, .following)
        XCTAssertGreaterThan(state.confirmedCursor, frozen)
    }

    /// Partial results arrive cumulatively and get revised, so replaying the same
    /// words in smaller pieces must land in the same place.
    func testFeedingWordsOneAtATimeMatchesFeedingThemTogether() {
        let script = parse("## One\nalpha beta gamma delta epsilon zeta eta")
        let words = ["alpha", "beta", "gamma", "delta", "epsilon"]

        var bulk = FollowState()
        _ = follow(script, saying: words, state: &bulk)

        var incremental = FollowState()
        for word in words {
            _ = follow(script, saying: [word], state: &incremental)
        }
        XCTAssertEqual(bulk.confirmedCursor, incremental.confirmedCursor)
        XCTAssertEqual(bulk.matchedWordCount, incremental.matchedWordCount)
    }

    /// A recognition task is torn down and restarted about once a minute. The
    /// position lives in this state, not in any transcript, so a few words lost
    /// at the seam must barely register.
    func testLosingAFewWordsAtATaskBoundaryBarelyMoves() {
        let script = parse("## One\n" + (1...30).map { "word\($0)" }.joined(separator: " "))
        let all = (1...30).map { "word\($0)" }

        var uninterrupted = FollowState()
        _ = follow(script, saying: all, state: &uninterrupted)

        var interrupted = FollowState()
        _ = follow(script, saying: Array(all[0..<12]), state: &interrupted)
        // Two words vanish at the seam.
        _ = follow(script, saying: Array(all[14...]), state: &interrupted)

        XCTAssertEqual(interrupted.mode, .following)
        XCTAssertEqual(
            interrupted.confirmedCursor, uninterrupted.confirmedCursor,
            "A short dropout should be absorbed as an ordinary skip."
        )
    }

    /// Numbers are written as digits and spoken as words.
    func testASpokenNumberMatchesItsWrittenDigits() {
        let script = parse("## One\nwe shipped 25 features")
        var state = FollowState()
        _ = follow(script, saying: ["we", "shipped", "twenty", "features"], state: &state)
        XCTAssertGreaterThanOrEqual(state.matchedWordCount, 3)
        XCTAssertEqual(state.mode, .following)
    }

    // MARK: - Key phrases and coverage

    /// The point of a key phrase: making the argument differently still counts.
    func testAParaphraseCreditsAKeyPhrase() {
        let script = parse("""
        ## ! Close
        > key: ship the release on Friday
        Some other words entirely here.
        """)
        var state = FollowState()
        _ = follow(script, saying: ["we", "will", "ship", "the", "release", "friday"], state: &state)

        XCTAssertEqual(state.creditedKeyPhraseIDs.count, 1)
    }

    func testAnUnrelatedRambleCreditsNothing() {
        let script = parse("""
        ## ! Close
        > key: ship the release on Friday
        Some other words entirely here.
        """)
        var state = FollowState()
        _ = follow(script, saying: ["the", "weather", "today", "is", "quite", "pleasant"], state: &state)
        XCTAssertTrue(state.creditedKeyPhraseIDs.isEmpty)
    }

    /// Reading most of a section covers it.
    func testReadingASectionMarksItCovered() {
        let script = parse("## ! Intro\nalpha beta gamma delta epsilon zeta eta theta")
        var state = FollowState()
        _ = follow(script, saying: ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta"], state: &state)
        XCTAssertTrue(state.coveredSectionIndices.contains(0))
    }

    func testSkippingASectionLeavesItUncovered() {
        let script = parse("""
        ## ! One
        alpha beta gamma delta epsilon zeta eta theta iota kappa

        ## Two
        omega
        """)
        var state = FollowState()
        _ = follow(script, saying: ["omega"], state: &state)
        XCTAssertFalse(state.coveredSectionIndices.contains(0), "An unread must-cover section stays uncovered.")
    }

    // MARK: - Cost

    /// The claim that this is cheap enough to run on every partial result.
    /// A dynamic-programming pass over the script would fail this loudly.
    func testFollowingALongScriptIsFast() {
        let script = parse("## One\n" + (1...6_000).map { "word\($0)" }.joined(separator: " "))
        let index = ScriptFollowIndex(script: script)
        let spoken = (1...1_500).map { TeleprompterTokenizer.normalize("word\($0)", locale: english) }

        measure {
            var state = FollowState()
            ScriptFollower.advance(
                state: &state, spoken: spoken, script: script, index: index, now: 1
            )
        }
    }

    // MARK: - Whole-script properties

    func testEmptyMarkdownProducesAnEmptyButValidScript() {
        let script = parse("")
        XCTAssertTrue(script.sections.isEmpty)
        XCTAssertTrue(script.tokens.isEmpty)
        XCTAssertEqual(script.wordCount, 0)
        XCTAssertEqual(script.estimatedDuration(wordsPerMinute: 140), 0)
    }

    func testEstimatedDurationScalesWithPace() {
        let script = parse("## One\n" + Array(repeating: "word", count: 280).joined(separator: " "))
        XCTAssertEqual(script.wordCount, 280)
        XCTAssertEqual(script.estimatedDuration(wordsPerMinute: 140), 120, accuracy: 0.01)
        XCTAssertEqual(script.estimatedDuration(wordsPerMinute: 0), 0, "A zero pace must not divide by zero.")
    }

    /// The markdown is kept verbatim so a re-parse after an edit is always
    /// possible and nothing is silently lost.
    func testTheOriginalMarkdownIsPreserved() {
        let source = "## ! Intro (1:00)\n> key: land the point\nHello."
        XCTAssertEqual(parse(source).markdown, source)
    }
}
