import XCTest
@testable import CodeIslandCore

/// #246 — the shipped iPhone/Watch companion apps (App Store) decode these enums
/// with a fixed known set. Since the 1.0.0(5) companion build they degrade unknown
/// values gracefully, but builds in the wild before that CRASH-LOOP when a decode
/// fails on the persisted application context. Never rename or repurpose existing
/// raw values; when adding a new one, remember old companion builds will render it
/// as idle/assistant until users update.
final class AppleCompanionPayloadCompatTests: XCTestCase {
    func testStatusRawValuesStayKnownToShippedCompanions() {
        let shipped: Set<String> = ["idle", "processing", "running", "waitingApproval", "waitingQuestion"]
        for status in [AppleCompanionStatus.idle, .processing, .running, .waitingApproval, .waitingQuestion] {
            XCTAssertTrue(
                shipped.contains(status.rawValue),
                "\(status.rawValue) is unknown to shipped companion apps — old Watch builds decode it as .idle; make sure that degradation is acceptable before shipping"
            )
        }
    }

    func testPendingActionRawValuesStayKnownToShippedCompanions() {
        let shipped: Set<String> = ["approval", "question"]
        for action in [AppleCompanionPendingAction.approval, .question] {
            XCTAssertTrue(shipped.contains(action.rawValue))
        }
    }

    func testMessageRoleRawValuesStayKnownToShippedCompanions() {
        let shipped: Set<String> = ["user", "assistant"]
        for role in [AppleCompanionMessageRole.user, .assistant] {
            XCTAssertTrue(shipped.contains(role.rawValue))
        }
    }
}
