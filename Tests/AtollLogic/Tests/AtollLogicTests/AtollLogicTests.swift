import XCTest
@testable import AtollLogic

// Coverage for the test scenarios Codacy proposed on arbitraged-life/atoll PR #3
// ("Prompt proposal for missing tests"). Each scenario maps to a kernel that
// mirrors the canonical app logic — see AtollLogic.swift `// MIRRORS:` refs.
//
// Codacy proposed 5 scenarios. Four map to real logic and are covered below.
// The 5th ("custom terminal scroll knob reflects the underlying SwiftTerm view")
// targets code that does not exist: Atoll's terminal uses SwiftTerm's built-in
// scrolling and has NO custom scroll knob/scroller (verified — no NSScroller /
// knob / scrollOffset code in TerminalManager, NotchTerminalView, or
// TerminalFloatingPanel). It is documented as not-applicable in
// testScrollKnob_notApplicable_swiftTermOwnsScrolling below rather than faked.

final class BrightnessEmissionTests: XCTestCase {

    // Codacy #2: brightness emissions are throttled to >= 0.04s apart.
    func testEmissionThrottledToMinimumInterval() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let k = BrightnessEmissionKernel(initialBrightness: 0.5, now: t0)

        XCTAssertTrue(k.emitBrightnessChange(value: 0.60, now: t0.addingTimeInterval(0.04)),
                      "first change past the interval should emit")
        // 20ms later — inside the 40ms window — must be throttled.
        XCTAssertFalse(k.emitBrightnessChange(value: 0.65, now: t0.addingTimeInterval(0.06)),
                       "change inside the 0.04s window must be throttled (no HUD spam)")
        // 40ms after the last *emission* — boundary is inclusive, should emit.
        XCTAssertTrue(k.emitBrightnessChange(value: 0.70, now: t0.addingTimeInterval(0.10)),
                      "change at exactly the interval boundary should emit")

        XCTAssertEqual(k.emittedValues.count, 2, "only the two non-throttled values reach observers")
        XCTAssertEqual(k.emittedValues.first ?? .nan, 0.60, accuracy: 0.0001)
        XCTAssertEqual(k.emittedValues.last ?? .nan, 0.70, accuracy: 0.0001)
        // Latest internal value still tracks the throttled write.
        XCTAssertEqual(k.lastEmittedBrightness, 0.70, accuracy: 0.0001)
    }

    func testForcedEmissionBypassesThrottle() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let k = BrightnessEmissionKernel(initialBrightness: 0.5, now: t0)
        XCTAssertTrue(k.emitBrightnessChange(value: 0.60, now: t0.addingTimeInterval(0.04)))
        // Final animation step fires immediately despite being inside the window.
        XCTAssertTrue(k.emitBrightnessChange(value: 0.61, force: true, now: t0.addingTimeInterval(0.05)),
                      "force=true (final animation tick) must bypass the throttle")
    }

    func testEmissionClampsToUnitRange() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let k = BrightnessEmissionKernel(initialBrightness: 0.5, now: t0)
        k.emitBrightnessChange(value: 1.8, now: t0.addingTimeInterval(1))
        XCTAssertEqual(k.lastEmittedBrightness, 1.0, accuracy: 0.0001)
        k.emitBrightnessChange(value: -0.3, now: t0.addingTimeInterval(2))
        XCTAssertEqual(k.lastEmittedBrightness, 0.0, accuracy: 0.0001)
    }

    // Codacy #1: auto-brightness updates the baseline WITHOUT showing the HUD.
    func testAutoBrightnessUpdatesBaselineWithoutEmitting() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let k = BrightnessEmissionKernel(initialBrightness: 0.50, now: t0)

        let moved = k.syncWithSystemBrightness(0.42) // ambient sensor drift
        XCTAssertTrue(moved, "a meaningful system delta should move the baseline")
        XCTAssertEqual(k.lastEmittedBrightness, 0.42, accuracy: 0.0001,
                       "baseline tracks the system level")
        XCTAssertTrue(k.emittedValues.isEmpty,
                      "auto-brightness sync must NOT emit — no HUD flash on ambient changes")
    }

    func testAutoBrightnessIgnoresSubThresholdJitter() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let k = BrightnessEmissionKernel(initialBrightness: 0.50, now: t0)
        let moved = k.syncWithSystemBrightness(0.5005) // < 0.001 threshold
        XCTAssertFalse(moved, "sub-threshold sensor jitter must not move the baseline")
        XCTAssertEqual(k.lastEmittedBrightness, 0.50, accuracy: 0.0001)
    }

    func testUserInitiatedGateOpensThenAutoResets() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let k = BrightnessEmissionKernel(initialBrightness: 0.5, now: t0)
        XCTAssertFalse(k.isUserInitiated(at: t0), "gate starts closed")

        k.markUserInitiated(now: t0)
        XCTAssertTrue(k.isUserInitiated(at: t0.addingTimeInterval(0.5)),
                      "within the 1.5s window the change is user-initiated (HUD allowed)")
        XCTAssertFalse(k.isUserInitiated(at: t0.addingTimeInterval(1.5)),
                       "at/after the window the gate auto-resets")
    }
}

final class CoreBrightnessClassResolverTests: XCTestCase {

    // Codacy #4: CoreBrightness client init resolves the right class per macOS version.
    func testResolvesNewestAvailableClass() {
        // Newest two present → newest wins.
        let picked = CoreBrightnessClassResolver.resolve { name in
            name == "CBBrightnessProxy" || name == "CBDisplayBrightnessClient"
        }
        XCTAssertEqual(picked, "CBBrightnessProxy",
                       "resolver must prefer the newest available candidate")
    }

    func testFallsBackToOlderClassWhenNewestAbsent() {
        // Simulate an older OS where only a legacy class exists.
        let picked = CoreBrightnessClassResolver.resolve { name in
            name == "BrightnessSystemClient"
        }
        XCTAssertEqual(picked, "BrightnessSystemClient",
                       "resolver must fall back to an older present class")
    }

    func testReturnsNilWhenNoCandidateExists() {
        let picked = CoreBrightnessClassResolver.resolve { _ in false }
        XCTAssertNil(picked,
                     "no candidate present → nil so the app uses its polling fallback")
    }

    func testCandidateOrderIsNewestFirst() {
        XCTAssertEqual(CoreBrightnessClassResolver.candidateClassNames.first, "CBBrightnessProxy",
                       "candidate list must stay ordered newest-first for correct resolution")
    }
}

final class StickyTerminalClickTests: XCTestCase {

    private let notchFrame = CGRect(x: 600, y: 1000, width: 200, height: 40)

    // Codacy #3: clicking the desktop (outside the notch) closes the terminal.
    func testDesktopClickOutsideNotchClosesTerminal() {
        let desktopClick = CGPoint(x: 100, y: 100) // far from the notch
        XCTAssertTrue(
            StickyTerminalClickKernel.shouldCloseOnClick(
                notchOpen: true, clickLocation: desktopClick, windowFrames: [notchFrame]),
            "a click on the desktop outside the notch must close the sticky terminal")
    }

    func testClickInsideNotchDoesNotClose() {
        let insideClick = CGPoint(x: 650, y: 1010)
        XCTAssertFalse(
            StickyTerminalClickKernel.shouldCloseOnClick(
                notchOpen: true, clickLocation: insideClick, windowFrames: [notchFrame]),
            "a click inside the notch window must NOT close the terminal")
    }

    func testClickIgnoredWhenNotchAlreadyClosed() {
        let desktopClick = CGPoint(x: 100, y: 100)
        XCTAssertFalse(
            StickyTerminalClickKernel.shouldCloseOnClick(
                notchOpen: false, clickLocation: desktopClick, windowFrames: [notchFrame]),
            "if the notch is already closed there is nothing to close")
    }

    func testMultiDisplayClickInsideSecondaryNotchDoesNotClose() {
        // showOnAllDisplays: a click inside ANY notch window counts as inside.
        let secondaryNotch = CGRect(x: 2000, y: 1000, width: 200, height: 40)
        let clickOnSecondary = CGPoint(x: 2050, y: 1010)
        XCTAssertFalse(
            StickyTerminalClickKernel.shouldCloseOnClick(
                notchOpen: true, clickLocation: clickOnSecondary,
                windowFrames: [notchFrame, secondaryNotch]),
            "with multiple notch windows, a click inside any one must not close")
    }

    func testMonitorOnlyActiveForOpenStickyTerminal() {
        XCTAssertTrue(StickyTerminalClickKernel.shouldMonitorOutsideClicks(
            notchOpen: true, stickyMode: true, currentViewIsTerminal: true))
        // Each precondition off → no monitor.
        XCTAssertFalse(StickyTerminalClickKernel.shouldMonitorOutsideClicks(
            notchOpen: false, stickyMode: true, currentViewIsTerminal: true))
        XCTAssertFalse(StickyTerminalClickKernel.shouldMonitorOutsideClicks(
            notchOpen: true, stickyMode: false, currentViewIsTerminal: true))
        XCTAssertFalse(StickyTerminalClickKernel.shouldMonitorOutsideClicks(
            notchOpen: true, stickyMode: true, currentViewIsTerminal: false))
    }

    // Codacy #5 — documented as not-applicable (no custom scroll knob exists).
    func testScrollKnob_notApplicable_swiftTermOwnsScrolling() throws {
        throw XCTSkip("""
            Codacy proposed testing that a custom terminal scroll knob reflects the \
            underlying SwiftTerm view. Atoll has no custom scroll knob — scrolling is \
            handled entirely inside SwiftTerm's NSView (verified: no NSScroller/knob/\
            scrollOffset code in TerminalManager, NotchTerminalView, or \
            TerminalFloatingPanel). There is no app-owned logic to test, so this \
            scenario is intentionally skipped rather than asserting against a fake.
            """)
    }
}
