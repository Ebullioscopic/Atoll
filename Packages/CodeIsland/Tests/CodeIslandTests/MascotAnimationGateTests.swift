import XCTest
@testable import CodeIsland

@MainActor
final class MascotAnimationGateTests: XCTestCase {
    func testShouldAnimateOnlyWhenVisibleAndAwake() {
        XCTAssertTrue(MascotAnimationGate.shouldAnimate(isVisible: true, isAwake: true))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(isVisible: false, isAwake: true))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(isVisible: true, isAwake: false))
        XCTAssertFalse(MascotAnimationGate.shouldAnimate(isVisible: false, isAwake: false))
    }

    func testHidingPanelStopsAnimationsWithoutBumpingEpoch() {
        let gate = MascotAnimationGate.shared
        gate.setPanelVisible(true)
        let baseEpoch = gate.epoch

        gate.setPanelVisible(false)
        XCTAssertFalse(gate.animationsActive)
        // Hiding must not re-anchor — only re-showing/waking does.
        XCTAssertEqual(gate.epoch, baseEpoch)
    }

    func testReShowingPanelBumpsEpochToReAnchorSchedules() {
        let gate = MascotAnimationGate.shared
        gate.setPanelVisible(false)
        let hiddenEpoch = gate.epoch

        gate.setPanelVisible(true)
        XCTAssertTrue(gate.animationsActive)
        XCTAssertEqual(gate.epoch, hiddenEpoch + 1)
    }

    func testRepeatedSameVisibilityIsIdempotent() {
        let gate = MascotAnimationGate.shared
        gate.setPanelVisible(true)
        let epoch = gate.epoch
        gate.setPanelVisible(true)
        XCTAssertEqual(gate.epoch, epoch)
    }
}
