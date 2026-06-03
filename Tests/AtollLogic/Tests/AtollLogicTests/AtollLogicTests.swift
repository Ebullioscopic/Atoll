import XCTest
@testable import AtollLogic

// Coverage for the test scenarios Codacy proposed on arbitraged-life/atoll PR #3
// ("Prompt proposal for missing tests"). Each scenario maps to a kernel that
// mirrors the canonical app logic — see AtollLogic.swift `// MIRRORS:` refs.
//
// Codacy proposed 5 scenarios. They are reconciled against the ACTUAL app code:
//
//   #1 "auto-brightness updates the baseline WITHOUT showing the HUD" — the app
//      does NOT do this. `syncWithSystemBrightnessIfNeeded()` re-emits (and the
//      app posts `.systemBrightnessDidChange`) when the system level differs by
//      > 0.001. We test that real contract rather than a fabricated silent sync.
//   #2 "emissions throttled to >= 0.04s apart" — the app has NO emission
//      throttle. The real rate-limiting lives in the poll loop's 0.005 change
//      threshold, which we test instead.
//   #3 desktop click outside the notch closes the sticky terminal — real, tested.
//   #4 "CoreBrightness client resolves the right class per macOS version" — the
//      app does NOT resolve among candidate classes; CoreBrightnessDisplayClient
//      loads a single `DisplayBrightnessClient` directly. There is no resolver
//      logic to test, so this proposal is documented as not-applicable rather
//      than asserted against a fabricated resolver.
//   #5 "custom terminal scroll knob reflects the SwiftTerm view" — Atoll has no
//      custom scroll knob (SwiftTerm owns scrolling). Documented not-applicable.

final class BrightnessEmissionTests: XCTestCase {

    func testEmissionClampsToUnitRange() {
        let kernel = BrightnessEmissionKernel(initialBrightness: 0.5)
        XCTAssertEqual(kernel.emitBrightnessChange(value: 1.8), 1.0, accuracy: 0.0001)
        XCTAssertEqual(kernel.lastEmittedBrightness, 1.0, accuracy: 0.0001)
        XCTAssertEqual(kernel.emitBrightnessChange(value: -0.3), 0.0, accuracy: 0.0001)
        XCTAssertEqual(kernel.lastEmittedBrightness, 0.0, accuracy: 0.0001)
    }

    func testEmissionDeliversEveryValueToObservers() {
        // The app's emitBrightnessChange has no throttle — every call reaches
        // observers (the animation Timer relies on this to stream interpolated
        // steps to the HUD).
        let kernel = BrightnessEmissionKernel(initialBrightness: 0.5)
        kernel.emitBrightnessChange(value: 0.60)
        kernel.emitBrightnessChange(value: 0.65)
        kernel.emitBrightnessChange(value: 0.70)
        XCTAssertEqual(kernel.emittedValues.count, 3, "every emission reaches observers; no throttle")
        XCTAssertEqual(kernel.emittedValues.last ?? .nan, 0.70, accuracy: 0.0001)
    }

    // Codacy #1 (reconciled): auto-brightness sync re-emits when the system level
    // diverges from the baseline by more than 0.001 — the app's real behaviour.
    func testSyncEmitsWhenSystemDivergesAboveThreshold() {
        let kernel = BrightnessEmissionKernel(initialBrightness: 0.50)
        let didEmit = kernel.syncWithSystemBrightnessIfNeeded(systemLevel: 0.42)
        XCTAssertTrue(didEmit, "an above-threshold system delta re-emits at the system level")
        XCTAssertEqual(kernel.lastEmittedBrightness, 0.42, accuracy: 0.0001)
        XCTAssertEqual(kernel.emittedValues, [0.42], "the sync emission reaches observers")
    }

    func testSyncIgnoresSubThresholdJitter() {
        let kernel = BrightnessEmissionKernel(initialBrightness: 0.50)
        let didEmit = kernel.syncWithSystemBrightnessIfNeeded(systemLevel: 0.5005) // < 0.001 delta
        XCTAssertFalse(didEmit, "sub-threshold sensor jitter must not re-emit")
        XCTAssertEqual(kernel.lastEmittedBrightness, 0.50, accuracy: 0.0001)
        XCTAssertTrue(kernel.emittedValues.isEmpty)
    }

    // Codacy #2 (reconciled): the real rate gate is the poll loop's 0.005 threshold.
    func testPollEmitsOnlyOnAboveThresholdSystemChange() {
        let kernel = BrightnessEmissionKernel(initialBrightness: 0.50)
        XCTAssertFalse(kernel.pollShouldEmit(systemLevel: 0.503), "0.003 delta is below the 0.005 poll gate")
        XCTAssertTrue(kernel.pollShouldEmit(systemLevel: 0.510), "0.010 delta exceeds the 0.005 poll gate")
    }

    func testAdjustTargetClampsBasePlusDelta() {
        let kernel = BrightnessEmissionKernel(initialBrightness: 0.90)
        XCTAssertEqual(kernel.adjustTarget(by: 0.20), 1.0, accuracy: 0.0001, "base+delta clamps at 1.0")
        XCTAssertEqual(kernel.adjustTarget(by: -1.5), 0.0, accuracy: 0.0001, "base+delta clamps at 0.0")
        // A pending (coalesced) target is the base for the next delta.
        XCTAssertEqual(kernel.adjustTarget(by: 0.05, pendingAdjustTarget: 0.30), 0.35, accuracy: 0.0001)
    }

    func testAnimationDurationScalesWithDeltaAndClamps() {
        let kernel = BrightnessEmissionKernel()
        let minDuration = BrightnessEmissionKernel.minimumAnimationDuration
        let maxDuration = BrightnessEmissionKernel.maximumAnimationDuration
        XCTAssertEqual(kernel.animationDuration(forDelta: 0), minDuration, accuracy: 0.0001)
        XCTAssertEqual(kernel.animationDuration(forDelta: 1.0), maxDuration, accuracy: 0.0001,
                       "a full-range jump clamps to the maximum duration")
        let mid = kernel.animationDuration(forDelta: 0.05)
        XCTAssertGreaterThan(mid, minDuration)
        XCTAssertLessThan(mid, maxDuration)
    }

    func testEaseIsCubicEaseOutAndClamps() {
        let kernel = BrightnessEmissionKernel()
        XCTAssertEqual(kernel.ease(0), 0, accuracy: 0.0001)
        XCTAssertEqual(kernel.ease(1), 1, accuracy: 0.0001)
        XCTAssertEqual(kernel.ease(0.5), 0.875, accuracy: 0.0001, "1 - (1-0.5)^3 = 0.875")
        XCTAssertEqual(kernel.ease(1.4), 1, accuracy: 0.0001, "input above 1 clamps")
        XCTAssertEqual(kernel.ease(-0.2), 0, accuracy: 0.0001, "input below 0 clamps")
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
}

// MARK: - Codacy proposals documented as not-applicable
//
// #4 "CoreBrightness client resolves the right class per macOS version" — the app
//    (CoreBrightnessDisplayClient) loads a single `DisplayBrightnessClient` class
//    directly; there is no candidate-class resolver to test.
// #5 "custom terminal scroll knob reflects the SwiftTerm view" — Atoll has no
//    custom scroll knob; SwiftTerm owns scrolling (verified: no NSScroller/knob/
//    scrollOffset code in TerminalManager, NotchTerminalView, TerminalFloatingPanel).
//
// Both are intentionally NOT faked. They are recorded here (and skipped) so the
// coverage map stays honest rather than asserting against logic the app lacks.
final class NotApplicableProposalsTests: XCTestCase {

    func testCoreBrightnessClassResolution_notApplicable_appLoadsSingleClass() throws {
        throw XCTSkip("""
            Codacy proposed testing that the CoreBrightness client resolves the right \
            class per macOS version. The app's CoreBrightnessDisplayClient loads a single \
            `DisplayBrightnessClient` class directly (no candidateClassNames, no resolver \
            loop), so there is no app-owned resolution logic to test. Skipped rather than \
            asserting against a fabricated resolver.
            """)
    }

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
