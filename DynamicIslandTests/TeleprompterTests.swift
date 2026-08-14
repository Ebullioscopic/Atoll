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
