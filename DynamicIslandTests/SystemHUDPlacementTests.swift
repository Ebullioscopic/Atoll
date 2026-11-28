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

/// Which HUD can be drawn depends on whether the Mac is locked, and getting it
/// wrong is silent: the keys simply do nothing, because this app has already
/// suppressed the system HUD.
final class SystemHUDPlacementTests: XCTestCase {
    /// This app's HUDs cannot be seen over the lock screen at all, so they stand
    /// down there rather than drawing where nobody can see them — which also
    /// stops them re-suppressing the system HUD on every keypress.
    func testAppHUDStandsDownOnlyWhileLocked() {
        XCTAssertTrue(SystemHUDPlacement.suppressesAppHUD(isLocked: true))
        XCTAssertFalse(SystemHUDPlacement.suppressesAppHUD(isLocked: false))
    }

    /// Locked, macOS draws its own HUD again.
    func testYieldsToNativeHUDWhileLocked() {
        XCTAssertTrue(SystemHUDPlacement.yieldsToNativeHUD(isLocked: true))
    }

    /// Unlocked, this app owns the HUD.
    func testNeverYieldsWhileUnlocked() {
        XCTAssertFalse(SystemHUDPlacement.yieldsToNativeHUD(isLocked: false))
    }

    /// The two decisions have to agree about who is drawing.
    ///
    /// `suppressesAppHUD` stands this app down for *every* channel while
    /// locked — volume, brightness and keyboard backlight alike. If yielding
    /// were ever withheld while locked, those channels would have no indicator
    /// from either side, and the keys would appear dead. The lock screen music
    /// panel used to withhold it, on the grounds that its capsule already shows
    /// volume; that left brightness silent whenever music was playing.
    func testNoChannelIsEverLeftWithoutAHUD() {
        for isLocked in [true, false] {
            let appStandsDown = SystemHUDPlacement.suppressesAppHUD(isLocked: isLocked)
            let nativeDraws = SystemHUDPlacement.yieldsToNativeHUD(isLocked: isLocked)
            XCTAssertFalse(
                appStandsDown && !nativeDraws,
                "locked=\(isLocked): neither this app nor macOS would draw a HUD"
            )
        }
    }
}
