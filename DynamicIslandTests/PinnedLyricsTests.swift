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

    func testParallelTextUsesOneSlotForEitherPlaybackIndex() {
        let parallel = LRCParser.parse("""
        [00:01]Before
        [00:04.85]響めき 煌めきと君も
        [00:04.85]kyoumeki koumekitokunmo
        [00:08]After
        [00:08]译文
        [00:12]Last
        """)
        for index in [1, 2] {
            XCTAssertEqual(PinnedLyricsContextRows.slots(lines: parallel, duration: 20,
                currentIndex: index, context: .three).map(\.text),
                ["Before", "響めき 煌めきと君も", "After"])
            XCTAssertEqual(PinnedLyricsContextRows.slots(lines: parallel, duration: 20,
                currentIndex: index, context: .five).map(\.text),
                ["", "Before", "響めき 煌めきと君も", "After", "Last"])
        }
        XCTAssertEqual(parallel.count, 6)
        XCTAssertEqual(SyncedLyricsRows.rows(for: parallel, duration: 20).count, 6)
    }

    func testParallelTextDoesNotPreferAnyLanguage() {
        let parallel = LRCParser.parse("[00:01]English first\n[00:01]中文译文\n[00:03]Next")
        XCTAssertEqual(PinnedLyricsContextRows.slots(lines: parallel, duration: 10,
            currentIndex: 1, context: .current).map(\.text), ["English first"])
    }

    func testCreditsAndBlanksDoNotClaimTimestampGroup() {
        let parallel = LRCParser.parse("[00:01]作曲：A\n[00:01]\n[00:01]Words\n[00:03]Next")
        XCTAssertEqual(PinnedLyricsContextRows.slots(lines: parallel, duration: 10,
            currentIndex: 2, context: .three).map(\.text), ["", "Words", "Next"])
    }

    func testDifferentTimestampsRemainSeparateEvenWithIdenticalText() {
        let repeated = LRCParser.parse("[00:01]Words\n[00:01.01]Words\n[00:03]Next")
        XCTAssertEqual(PinnedLyricsContextRows.slots(lines: repeated, duration: 10,
            currentIndex: 1, context: .three).map(\.text), ["Words", "Words", "Next"])
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

@MainActor
final class LyricsRecordingIdentityTests: XCTestCase {
    private func key(_ duration: Double, id: String? = nil, source: String = "test.player") -> LyricsLookupKey {
        LyricsLookupKey(title: "song", artist: "artist", album: "album", source: source,
                        contentIdentifier: id, duration: duration)
    }

    func testRecordingIDsTakePrecedenceOverDurationAndAreSourceScoped() {
        XCTAssertEqual(key(100, id: "track:a"), key(101, id: "track:a"))
        XCTAssertNotEqual(key(100, id: "track:a"), key(100, id: "track:b"))
        XCTAssertNotEqual(key(100, id: "1"), key(100, id: "1", source: "other.player"))
    }

    func testDurationFallbackNormalizesPrecisionAndMissingValues() {
        XCTAssertEqual(key(214.01), key(214.1, id: "  "))
        XCTAssertNotEqual(key(76), key(214))
        XCTAssertEqual(key(.nan), key(0))
        XCTAssertEqual(key(.infinity), key(-1))
        XCTAssertNotEqual(key(0), key(214))
    }

    func testDurationOnlyChangeDoesNotReuseInstrumentalCache() {
        assertRecordingChange(firstDuration: 76, secondDuration: 214)
    }

    func testDurationArrivalReplacesUnknownDurationCache() {
        assertRecordingChange(firstDuration: 0, secondDuration: 214)
    }

    func testIdentifierOnlyChangeDoesNotReuseInstrumentalCache() {
        assertRecordingChange(firstDuration: 214, secondDuration: 214,
                              firstID: "track:a", secondID: "track:b")
    }

    private func assertRecordingChange(firstDuration: Double, secondDuration: Double,
                                       firstID: String? = nil, secondID: String? = nil) {
        let wasEnabled = Defaults[.enableLyrics]
        Defaults[.enableLyrics] = true
        let manager = MusicManager(startsControllerSetup: false)
        defer {
            manager.destroy()
            Defaults[.enableLyrics] = wasEnabled
        }
        manager.storeLyricsInCache(LyricsResolution(instrumental: true),
                                   for: key(firstDuration, id: firstID))
        manager.storeLyricsInCache(LyricsResolution(lines: [LyricLine(timestamp: 1, text: "Words")]),
                                   for: key(secondDuration, id: secondID))
        var state = PlaybackState(bundleIdentifier: "test.player", title: "Song", artist: "Artist",
                                  album: "Album", contentIdentifier: firstID, duration: firstDuration)
        manager.updateFromPlaybackState(state)
        XCTAssertEqual(manager.lyricsAvailability, .instrumental)
        state.duration = secondDuration
        state.contentIdentifier = secondID
        manager.updateFromPlaybackState(state)
        XCTAssertEqual(manager.songDuration, secondDuration)
        XCTAssertEqual(manager.lyricsAvailability, .timed)
        XCTAssertEqual(manager.syncedLyrics.map(\.text), ["Words"])
        var updates = 0
        let observation = manager.$lyricsAvailability.dropFirst().sink { _ in updates += 1 }
        state.duration += 0.01
        manager.updateFromPlaybackState(state)
        XCTAssertEqual(updates, 0, "Subsecond duration noise must not reset the lyric display")
        withExtendedLifetime(observation) {}
        state.duration = firstDuration
        state.contentIdentifier = firstID
        manager.updateFromPlaybackState(state)
        XCTAssertEqual(manager.lyricsAvailability, .instrumental)
        XCTAssertTrue(manager.syncedLyrics.isEmpty)
    }

    func testDurationOnlyAdvertisementStartDiscardsLyricsAndReservation() {
        let wasEnabled = Defaults[.enableLyrics]
        Defaults[.enableLyrics] = true
        let manager = MusicManager(startsControllerSetup: false)
        defer {
            manager.destroy()
            Defaults[.enableLyrics] = wasEnabled
        }
        var state = PlaybackState(bundleIdentifier: "com.spotify.client", title: "Promotion",
                                  artist: "", album: "", duration: 0)
        manager.updateFromPlaybackState(state)
        manager.applyLyricsToDisplay(LyricsResolution(lines: [LyricLine(timestamp: 1, text: "Old words")]))
        XCTAssertEqual(manager.lyricsAvailability, .timed)
        state.duration = 30
        manager.updateFromPlaybackState(state)
        XCTAssertTrue(manager.isAdvertisement)
        XCTAssertTrue(manager.syncedLyrics.isEmpty)
        XCTAssertEqual(manager.currentLyricIndex, -1)
        XCTAssertEqual(PinnedLyricsView.reservedHeight(isEligible: true,
            availability: manager.lyricsAvailability, context: .three), 0)
    }

    func testDurationOnlyAdvertisementEndPreparesLyricsAgain() {
        let wasEnabled = Defaults[.enableLyrics]
        Defaults[.enableLyrics] = true
        let manager = MusicManager(startsControllerSetup: false)
        defer {
            manager.destroy()
            Defaults[.enableLyrics] = wasEnabled
        }
        var state = PlaybackState(bundleIdentifier: "com.spotify.client", title: "Promotion",
                                  artist: "", album: "", duration: 30)
        manager.updateFromPlaybackState(state)
        XCTAssertTrue(manager.isAdvertisement)
        var updates: [LyricsAvailability] = []
        let observation = manager.$lyricsAvailability.dropFirst().sink { updates.append($0) }
        state.duration = 180
        manager.updateFromPlaybackState(state)
        XCTAssertFalse(manager.isAdvertisement)
        // Preparation must run even though all content metadata is unchanged.
        // This incomplete metadata is rejected locally without a network lookup.
        XCTAssertEqual(updates, [.unavailable])
        withExtendedLifetime(observation) {}
    }
}
