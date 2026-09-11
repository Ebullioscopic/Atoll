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
import Defaults
@testable import Atoll

final class PinnedLyricsContextTests: XCTestCase {
    private let lines = LRCParser.parse("""
    [00:00]作曲：A
    [00:02]编曲：B
    [00:10]One
    [00:15]Two
    [00:20]
    [00:40]Three
    [00:45]Four
    [00:50]Five
    [00:55]
    """)

    private func slots(_ index: Int, _ context: PinnedLyricContext) -> [PinnedLyricsContextRows.Slot] {
        PinnedLyricsContextRows.slots(lines: lines, duration: 100, currentIndex: index, context: context)
    }

    func testCurrentOnly() {
        XCTAssertEqual(slots(5, .current).map(\.text), ["Three"])
    }

    func testThreeSemanticLinesSkipEmptyMarkers() {
        XCTAssertEqual(slots(5, .three).map(\.text), ["Two", "Three", "Four"])
    }

    func testFiveSemanticLines() {
        XCTAssertEqual(slots(5, .five).map(\.text), ["One", "Two", "Three", "Four", "Five"])
    }

    func testBreakRetainsSungNeighbors() {
        XCTAssertEqual(slots(4, .five).map(\.text), ["One", "Two", "♪", "Three", "Four"])
    }

    func testCreditsAreNotContextOrCurrentText() {
        XCTAssertEqual(slots(0, .five).map(\.text), ["", "", "", "One", "Two"])
        XCTAssertEqual(lines[0].text, "作曲：A")
    }

    func testBeginningAndEndKeepEmptySlots() {
        XCTAssertEqual(slots(2, .five).map(\.text), ["", "", "One", "Two", "Three"])
        XCTAssertEqual(slots(7, .five).map(\.text), ["Three", "Four", "Five", "", ""])
        XCTAssertEqual(slots(8, .three).map(\.text), ["Five", "♪", ""])
    }

    func testBeforeFirstTimestampKeepsCenterBlankAndFutureContext() {
        XCTAssertEqual(slots(-1, .three).map(\.text), ["", "", "One"])
    }

    func testOnlyCenterClaimsCurrentStyling() {
        for context in PinnedLyricContext.allCases {
            for index in -1..<lines.count {
                let rows = slots(index, context)
                XCTAssertEqual(rows.count, context.rawValue)
                XCTAssertEqual(rows.indices.filter { rows[$0].isCurrent }, [context.rawValue / 2])
            }
        }
    }

    func testStaleIndexDoesNotSubscriptPastTheNewLyrics() {
        XCTAssertEqual(slots(99, .three).map(\.text), ["Five", "", ""])
    }

    func testShortGapDoesNotShowInstrumentalNote() {
        let short = LRCParser.parse("[00:10]One\n[00:15]\n[00:16]Two")
        let rows = PinnedLyricsContextRows.slots(lines: short, duration: 20, currentIndex: 1, context: .three)
        XCTAssertEqual(rows.map(\.text), ["One", "", "Two"])
    }

    func testLongIntroUsesExistingInstrumentalRow() {
        let intro = LRCParser.parse("[00:20]One")
        XCTAssertEqual(PinnedLyricsContextRows.slots(lines: intro, duration: 60, currentIndex: -1,
            context: .three).map(\.text), ["", "♪", "One"])
    }

    func testUntimedRowsAreNeverSelectedAsSungContext() {
        let plain = LyricLine.untimedLines(from: "One\nTwo")
        XCTAssertEqual(PinnedLyricsContextRows.slots(lines: plain, duration: 60, currentIndex: -1,
            context: .three).map(\.text), ["", "", ""])
    }

    func testHeightIsIdenticalAcrossEveryPositionAndContext() {
        let availability = LyricsResolution(lines: lines).availability
        XCTAssertEqual(availability, .timed)
        for context in PinnedLyricContext.allCases {
            let expected = PinnedLyricsView.rowHeight * CGFloat(context.rawValue) + PinnedLyricsView.gap
            for index in -1..<lines.count {
                XCTAssertEqual(slots(index, context).count, context.rawValue)
                XCTAssertEqual(PinnedLyricsView.reservedHeight(isEligible: true,
                    availability: availability, context: context), expected)
            }
        }
    }

    func testBothSettingsAndSurfaceEligibilityAreRequired() {
        for lyricsEnabled in [false, true] {
            for pinEnabled in [false, true] {
                for surfaceEligible in [false, true] {
                    XCTAssertEqual(PinnedLyricsView.shouldReserve(lyricsEnabled: lyricsEnabled,
                        pinEnabled: pinEnabled, surfaceEligible: surfaceEligible, availability: .timed),
                        lyricsEnabled && pinEnabled && surfaceEligible)
                }
            }
        }
    }

    func testDisabledOrIneligibleHasNoHeight() {
        // The host combines lyrics enabled, pin enabled, closed, unlocked and playing.
        for context in PinnedLyricContext.allCases {
            XCTAssertEqual(PinnedLyricsView.reservedHeight(isEligible: false, availability: .timed, context: context), 0)
        }
    }

    func testOnlyTimedLyricalTracksReserveHeight() {
        for state in [LyricsAvailability.loading, .unavailable, .instrumental, .untimed] {
            for context in PinnedLyricContext.allCases {
                XCTAssertEqual(PinnedLyricsView.reservedHeight(isEligible: true, availability: state, context: context), 0)
            }
        }
    }

    func testTrackChangesRemoveReservation() {
        let states: [LyricsAvailability] = [.timed, .loading, .unavailable, .timed, .instrumental]
        XCTAssertEqual(states.map {
            PinnedLyricsView.reservedHeight(isEligible: true, availability: $0, context: .three) > 0
        }, [true, false, false, true, false])
    }
}

final class LyricsResolutionTests: XCTestCase {
    func testLRCLIBExplicitInstrumentalWinsOverPlaceholderBody() {
        let result = LyricsResolution.lrclib(["instrumental": true, "syncedLyrics": "[00:00]Composer: A"])
        XCTAssertEqual(result.availability, .instrumental)
    }

    func testNetEasePreservesInstrumentalVersusUncollected() {
        XCTAssertEqual(NetEaseLyrics.parseResolution(Data(#"{"nolyric":true}"#.utf8)).availability, .instrumental)
        XCTAssertEqual(NetEaseLyrics.parseResolution(Data(#"{"uncollected":true}"#.utf8)).availability, .unavailable)
    }

    func testCreditsAndPlaceholderOnlyAreInstrumental() {
        let result = LyricsResolution(lines: LRCParser.parse("[00:00]作曲：A\n[00:01]编曲：B\n[00:02]纯音乐，请欣赏"))
        XCTAssertEqual(result.availability, .instrumental)
    }

    func testCreditsOnlyAreUnavailableAndRawRowsSurvive() {
        let result = LyricsResolution(lines: LRCParser.parse("[00:00]Composer: A\n[00:01]Arranger: B"))
        XCTAssertEqual(result.availability, .unavailable)
        XCTAssertEqual(result.lines.count, 2)
    }

    func testCreditMatchingRequiresAnExactLabelAndColon() {
        for text in [" 作词 : 方文山 ", "Composer：A", "Lyrics by: A", "Mixing: A", "Mastering: A"] {
            XCTAssertFalse(LyricTextSemantics.isLyric(text))
        }
        for text in ["The composer: a friend of mine", "Composer of dreams", "My lyrics by the sea"] {
            XCTAssertTrue(LyricTextSemantics.isLyric(text))
        }
    }

    func testWholeLinePlaceholders() {
        for text in ["纯音乐，请欣赏", "纯音乐 请欣赏", "此歌曲为没有填词的纯音乐，请您欣赏",
                     "该歌曲为纯音乐，请欣赏", "Instrumental", "Instrumental track", "No lyrics"] {
            XCTAssertEqual(LyricsResolution(lines: [LyricLine(timestamp: 0, text: text)]).availability, .instrumental)
        }
    }

    func testWordsInsideRealLyricsAreNotPlaceholders() {
        for text in ["我喜欢听着纯音乐", "今晚什么都不想说", "You were instrumental in my life", "Instrumental dreams"] {
            XCTAssertEqual(LyricsResolution(lines: [LyricLine(timestamp: 10, text: text)]).availability, .timed)
        }
    }

    func testVocalLyricsWinOverBoilerplateAndCredits() {
        let result = LyricsResolution(lines: LRCParser.parse("[00:00]作词：A\n[00:02]Instrumental\n[00:10]Sung words\n[00:20]"))
        XCTAssertEqual(result.availability, .timed)
    }

    func testEmptyAndUntimedResults() {
        XCTAssertEqual(LyricsResolution().availability, .unavailable)
        XCTAssertEqual(LyricsResolution.lrclib(["plainLyrics": "One\nTwo"]).availability, .untimed)
    }

    func testProvidersProduceTheSameSemanticRows() {
        let lrc = "[00:10]One\n[00:20]\n[00:40]Two"
        let lrclib = LyricsResolution.lrclib(["syncedLyrics": lrc])
        let data = try! JSONSerialization.data(withJSONObject: ["lrc": ["lyric": lrc]])
        let netease = NetEaseLyrics.parseResolution(data)
        XCTAssertEqual(lrclib.availability, netease.availability)
        XCTAssertEqual(lrclib.lines, netease.lines)
        XCTAssertEqual(PinnedLyricsContextRows.slots(lines: lrclib.lines, duration: 60, currentIndex: 1, context: .three),
                       PinnedLyricsContextRows.slots(lines: netease.lines, duration: 60, currentIndex: 1, context: .three))
    }
}

final class LyricsProviderFallbackTests: XCTestCase {
    private struct Transport: Error {}

    private let sung = LyricsResolution(lines: [LyricLine(timestamp: 1, text: "a")])

    func testPrimaryHitDoesNotAskFallback() async {
        var asked = false
        let result = await LyricsProviderFallback.resolve(
            primary: { self.sung },
            fallback: {
                asked = true
                return LyricsResolution()
            }
        )
        XCTAssertEqual(result.availability, .timed)
        XCTAssertFalse(asked)
    }

    func testInstrumentalPrimaryDoesNotAskFallback() async {
        var asked = false
        let result = await LyricsProviderFallback.resolve(
            primary: { LyricsResolution(instrumental: true) },
            fallback: {
                asked = true
                return self.sung
            }
        )
        XCTAssertEqual(result.availability, .instrumental)
        XCTAssertFalse(asked)
    }

    func testEmptyPrimaryUsesFallback() async {
        let result = await LyricsProviderFallback.resolve(
            primary: { LyricsResolution() },
            fallback: { self.sung }
        )
        XCTAssertEqual(result.availability, .timed)
        XCTAssertEqual(result.lines.map(\.text), ["a"])
    }

    func testPrimaryTransportFailureStillAsksFallback() async {
        let result = await LyricsProviderFallback.resolve(
            primary: { throw Transport() },
            fallback: { self.sung }
        )
        XCTAssertEqual(result.availability, .timed)
        XCTAssertEqual(result.lines.map(\.text), ["a"])
    }

    func testBothTransportFailuresAreUnavailable() async {
        let result = await LyricsProviderFallback.resolve(
            primary: { throw Transport() },
            fallback: { throw Transport() }
        )
        XCTAssertEqual(result.availability, .unavailable)
        XCTAssertTrue(result.lines.isEmpty)
    }
}


final class PinnedLyricsSettingsTests: XCTestCase {
    func testExistingUsersDefaultToCurrentLine() {
        XCTAssertEqual(Defaults.Keys.pinnedLyricContext.defaultValue, .current)
        XCTAssertEqual(PinnedLyricContext.allCases.map(\.rawValue), [1, 3, 5])
    }

    func testContextRoundTripsThroughDefaultsWithoutTouchingUserPreferences() {
        let name = "Atoll.PinnedLyricsTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }
        let key = Defaults.Key<PinnedLyricContext>("pinnedLyricContext", default: .current, suite: suite)
        XCTAssertEqual(Defaults[key], .current)
        for context in PinnedLyricContext.allCases {
            Defaults[key] = context
            let reloaded = Defaults.Key<PinnedLyricContext>("pinnedLyricContext", default: .current,
                suite: UserDefaults(suiteName: name)!)
            XCTAssertEqual(Defaults[reloaded], context)
        }
    }
}
