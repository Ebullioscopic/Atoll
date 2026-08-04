import AppKit
import Carbon.HIToolbox
import XCTest
@testable import CodeIsland

final class GlobalHotKeyManagerTests: XCTestCase {
    func testCarbonModifiersMapsCommandShift() {
        let mods = GlobalHotKeyManager.carbonModifiers(from: [.command, .shift])
        XCTAssertEqual(mods, UInt32(cmdKey) | UInt32(shiftKey))
    }

    func testCarbonModifiersMapsAllFourFlags() {
        let mods = GlobalHotKeyManager.carbonModifiers(from: [.command, .shift, .option, .control])
        XCTAssertEqual(mods, UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey) | UInt32(controlKey))
    }

    func testCarbonModifiersEmptyForNoFlags() {
        XCTAssertEqual(GlobalHotKeyManager.carbonModifiers(from: []), 0)
    }

    func testCarbonModifiersIgnoresNonModifierFlags() {
        // Caps lock / numeric pad etc. must not contribute to the Carbon mask.
        let mods = GlobalHotKeyManager.carbonModifiers(from: [.command, .capsLock])
        XCTAssertEqual(mods, UInt32(cmdKey))
    }
}
