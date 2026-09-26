import XCTest
@testable import Atoll

final class ExtensionTabSelectionTests: XCTestCase {
    func testExtensionTabSelectionBackgroundCanBeDisabled() {
        XCTAssertFalse(shouldDisplayTabSelectionCapsule(
            isSelected: true,
            isExtensionTab: true,
            showExtensionBackground: false
        ))
    }

    func testExtensionCapsuleCanBeEnabled() {
        XCTAssertTrue(shouldDisplayTabSelectionCapsule(
            isSelected: true,
            isExtensionTab: true,
            showExtensionBackground: true
        ))
    }

    func testBuiltInTabSelectionRemainsUnchanged() {
        XCTAssertTrue(shouldDisplayTabSelectionCapsule(
            isSelected: true,
            isExtensionTab: false,
            showExtensionBackground: false
        ))
    }

    func testUnselectedTabNeverShowsCapsule() {
        XCTAssertFalse(shouldDisplayTabSelectionCapsule(
            isSelected: false,
            isExtensionTab: true,
            showExtensionBackground: true
        ))
    }
}
