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

/// The 20-20-20 cycle is pure state driven by an injected `now`, so the whole
/// state machine — including the sleep behaviour that is otherwise painful to
/// reproduce — is testable without timers, hardware, or waiting.
final class EyeBreakScheduleTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func makeSchedule(work: TimeInterval = 20 * 60, rest: TimeInterval = 20) -> EyeBreakSchedule {
        EyeBreakSchedule(workInterval: work, restDuration: rest)
    }

    // MARK: - Basic cycle

    func testStartBeginsTheWorkCountdown() {
        var schedule = makeSchedule()

        schedule.start(at: start)

        XCTAssertEqual(schedule.phase, .working(deadline: start.addingTimeInterval(20 * 60)))
        XCTAssertEqual(schedule.remainingSeconds(at: start), 20 * 60)
        XCTAssertFalse(schedule.isBreakVisible)
    }

    func testWorkIntervalElapsingStartsTheRest() {
        var schedule = makeSchedule()
        schedule.start(at: start)

        schedule.advance(to: start.addingTimeInterval(20 * 60))

        XCTAssertTrue(schedule.isBreakVisible)
        XCTAssertEqual(schedule.remainingSeconds(at: start.addingTimeInterval(20 * 60)), 20)
    }

    func testWorkIntervalNotYetElapsedKeepsWorking() {
        var schedule = makeSchedule()
        schedule.start(at: start)

        schedule.advance(to: start.addingTimeInterval(20 * 60 - 1))

        XCTAssertFalse(schedule.isBreakVisible)
        XCTAssertEqual(schedule.remainingSeconds(at: start.addingTimeInterval(20 * 60 - 1)), 1)
    }

    func testRestElapsingReturnsToWork() {
        var schedule = makeSchedule()
        schedule.start(at: start)
        let breakStart = start.addingTimeInterval(20 * 60)
        schedule.advance(to: breakStart)

        let breakEnd = breakStart.addingTimeInterval(20)
        schedule.advance(to: breakEnd)

        XCTAssertFalse(schedule.isBreakVisible)
        XCTAssertEqual(schedule.phase, .working(deadline: breakEnd.addingTimeInterval(20 * 60)))
    }

    func testStopReturnsToIdle() {
        var schedule = makeSchedule()
        schedule.start(at: start)

        schedule.stop()

        XCTAssertEqual(schedule.phase, .idle)
        XCTAssertFalse(schedule.isRunning)
        XCTAssertNil(schedule.remainingSeconds(at: start))
    }

    // MARK: - Skip

    func testSkipDuringRestStartsAFullWorkInterval() {
        var schedule = makeSchedule()
        schedule.start(at: start)
        let breakStart = start.addingTimeInterval(20 * 60)
        schedule.advance(to: breakStart)

        let skipMoment = breakStart.addingTimeInterval(3)
        schedule.skipBreak(at: skipMoment)

        XCTAssertFalse(schedule.isBreakVisible)
        XCTAssertEqual(schedule.phase, .working(deadline: skipMoment.addingTimeInterval(20 * 60)))
    }

    /// A stray Skip while working must not shorten the work period.
    func testSkipWhileWorkingIsANoOp() {
        var schedule = makeSchedule()
        schedule.start(at: start)
        let before = schedule.phase

        schedule.skipBreak(at: start.addingTimeInterval(60))

        XCTAssertEqual(schedule.phase, before)
    }

    func testSkipWhileABreakIsPendingStartsWorkingAgain() {
        var schedule = makeSchedule()
        schedule.start(at: start)
        // Break falls due while the user is away, so it waits rather than resting.
        schedule.advance(to: start.addingTimeInterval(20 * 60), canPresent: false)
        XCTAssertEqual(schedule.phase, .breakDue)

        let skipMoment = start.addingTimeInterval(20 * 60 + 5)
        schedule.skipBreak(at: skipMoment)

        XCTAssertEqual(schedule.phase, .working(deadline: skipMoment.addingTimeInterval(20 * 60)))
    }

    // MARK: - Sleep and wake

    /// The regression this design exists to prevent: sleeping through several
    /// work intervals must produce exactly one break, not a stack of them.
    func testALongSleepGapProducesASingleBreak() {
        var schedule = makeSchedule()
        schedule.start(at: start)

        // Thirty minutes of sleep spans one and a half work intervals.
        let afterSleep = start.addingTimeInterval(30 * 60)
        schedule.advance(to: afterSleep)

        XCTAssertTrue(schedule.isBreakVisible)
        XCTAssertEqual(schedule.remainingSeconds(at: afterSleep), 20, "the rest must start from the wake moment, not from the missed deadline")

        // Finishing that break leaves a normal work interval — no queued extras.
        let breakEnd = afterSleep.addingTimeInterval(20)
        schedule.advance(to: breakEnd)
        XCTAssertEqual(schedule.phase, .working(deadline: breakEnd.addingTimeInterval(20 * 60)))

        // And advancing again right away does not immediately fire another break.
        schedule.advance(to: breakEnd.addingTimeInterval(1))
        XCTAssertFalse(schedule.isBreakVisible)
    }

    func testHoursAwayStillProduceOnlyOneBreak() {
        var schedule = makeSchedule()
        schedule.start(at: start)

        let afterSleep = start.addingTimeInterval(8 * 60 * 60)
        schedule.advance(to: afterSleep)
        XCTAssertTrue(schedule.isBreakVisible)

        let breakEnd = afterSleep.addingTimeInterval(20)
        schedule.advance(to: breakEnd)
        schedule.advance(to: breakEnd)
        XCTAssertFalse(schedule.isBreakVisible)
    }

    /// A break that falls due while the screen is locked waits instead of
    /// spending its twenty seconds unseen.
    func testABreakDueWhileAwayWaitsUntilItCanBeShown() {
        var schedule = makeSchedule()
        schedule.start(at: start)

        schedule.advance(to: start.addingTimeInterval(20 * 60), canPresent: false)
        XCTAssertEqual(schedule.phase, .breakDue)
        XCTAssertFalse(schedule.isBreakVisible)
        XCTAssertNil(schedule.remainingSeconds(at: start.addingTimeInterval(20 * 60)))

        let returnMoment = start.addingTimeInterval(60 * 60)
        schedule.advance(to: returnMoment, canPresent: true)

        XCTAssertTrue(schedule.isBreakVisible)
        XCTAssertEqual(schedule.remainingSeconds(at: returnMoment), 20)
    }

    // MARK: - Pause

    func testPauseHoldsTheRemainingWorkTime() {
        var schedule = makeSchedule()
        schedule.start(at: start)

        schedule.pause(at: start.addingTimeInterval(5 * 60))

        XCTAssertEqual(schedule.phase, .pausedWorking(remaining: 15 * 60))
        XCTAssertEqual(schedule.remainingSeconds(at: start.addingTimeInterval(60 * 60)), 15 * 60,
                       "a paused countdown must not drain while the user is away")
    }

    func testAPausedScheduleDoesNotFireABreak() {
        var schedule = makeSchedule()
        schedule.start(at: start)
        schedule.pause(at: start.addingTimeInterval(5 * 60))

        schedule.advance(to: start.addingTimeInterval(10 * 60 * 60))

        XCTAssertFalse(schedule.isBreakVisible)
        XCTAssertEqual(schedule.phase, .pausedWorking(remaining: 15 * 60))
    }

    func testResumeRebasesTheDeadlineOnTheReturnMoment() {
        var schedule = makeSchedule()
        schedule.start(at: start)
        schedule.pause(at: start.addingTimeInterval(5 * 60))

        let returnMoment = start.addingTimeInterval(3 * 60 * 60)
        schedule.resume(at: returnMoment)

        XCTAssertEqual(schedule.phase, .working(deadline: returnMoment.addingTimeInterval(15 * 60)))
    }

    /// Pause only affects the work countdown; a rest already on screen just runs
    /// out, and resume must not resurrect anything.
    func testPauseDuringARestLeavesTheRestRunning() {
        var schedule = makeSchedule()
        schedule.start(at: start)
        let breakStart = start.addingTimeInterval(20 * 60)
        schedule.advance(to: breakStart)

        schedule.pause(at: breakStart.addingTimeInterval(2))

        XCTAssertTrue(schedule.isBreakVisible)
    }

    func testResumeWhileWorkingIsANoOp() {
        var schedule = makeSchedule()
        schedule.start(at: start)
        let before = schedule.phase

        schedule.resume(at: start.addingTimeInterval(30))

        XCTAssertEqual(schedule.phase, before)
    }

    // MARK: - Duration edits

    func testChangingTheWorkIntervalRebasesTheCountdown() {
        var schedule = makeSchedule()
        schedule.start(at: start)

        let editMoment = start.addingTimeInterval(60)
        schedule.updateDurations(workInterval: 30 * 60, restDuration: 20, at: editMoment)

        XCTAssertEqual(schedule.phase, .working(deadline: editMoment.addingTimeInterval(30 * 60)))
    }

    func testChangingOnlyTheRestDurationLeavesTheWorkCountdownAlone() {
        var schedule = makeSchedule()
        schedule.start(at: start)
        let deadline = start.addingTimeInterval(20 * 60)

        schedule.updateDurations(workInterval: 20 * 60, restDuration: 45, at: start.addingTimeInterval(60))

        XCTAssertEqual(schedule.phase, .working(deadline: deadline))

        schedule.advance(to: deadline)
        XCTAssertEqual(schedule.remainingSeconds(at: deadline), 45)
    }

    func testRemainingSecondsRoundsUpSoACountdownNeverSkipsItsLastSecond() {
        var schedule = makeSchedule()
        schedule.start(at: start)
        let breakStart = start.addingTimeInterval(20 * 60)
        schedule.advance(to: breakStart)

        XCTAssertEqual(schedule.remainingSeconds(at: breakStart.addingTimeInterval(19.2)), 1)
        XCTAssertEqual(schedule.remainingSeconds(at: breakStart.addingTimeInterval(20)), 0)
    }
}
