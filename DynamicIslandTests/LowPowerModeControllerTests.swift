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

/// Covers the pure pieces of turning Low Power Mode on from the low battery
/// HUD: which `pmset` key this Mac uses, the script that is handed to macOS,
/// and how long hovering holds the HUD. The change itself needs an
/// administrator password, so it is not exercised here.
final class LowPowerModeControllerTests: XCTestCase {

    // MARK: - pmsetKey

    func testMacWithHighPowerModeUsesPowermode() {
        let output = """
        Battery Power:
         Sleep On Power Button 1
         powermode            1
         powernap             1
        AC Power:
         Sleep On Power Button 1
         powermode            0
         powernap             1
        """

        XCTAssertEqual(LowPowerModeController.pmsetKey(inCustomSettings: output), "powermode")
    }

    func testMacWithoutHighPowerModeUsesLowpowermode() {
        let output = """
        Battery Power:
         lowpowermode         0
         standby              1
        AC Power:
         lowpowermode         0
         standby              1
        """

        XCTAssertEqual(LowPowerModeController.pmsetKey(inCustomSettings: output), "lowpowermode")
    }

    func testMacWithoutLowPowerModeHasNoKey() {
        let output = """
        AC Power:
         Sleep On Power Button 1
         standby              0
         womp                 1
        """

        XCTAssertNil(LowPowerModeController.pmsetKey(inCustomSettings: output))
        XCTAssertNil(LowPowerModeController.pmsetKey(inCustomSettings: ""))
    }

    func testKeyIsMatchedAsAWholeSettingName() {
        // `powermode` is a substring of `lowpowermode`, so a contains() check
        // on the raw output would pick the wrong key on older Macs.
        let output = " lowpowermode         1\n"

        XCTAssertEqual(LowPowerModeController.pmsetKey(inCustomSettings: output), "lowpowermode")
    }

    // MARK: - appleScriptSource

    func testScriptTurnsTheModeOnForBatteryPowerOnly() {
        let source = LowPowerModeController.appleScriptSource(pmsetKey: "powermode", prompt: "Prompt")

        XCTAssertEqual(
            source,
            "do shell script \"/usr/bin/pmset -b powermode 1\" with prompt \"Prompt\" with administrator privileges"
        )
    }

    func testPromptCannotBreakOutOfItsStringLiteral() {
        let source = LowPowerModeController.appleScriptSource(
            pmsetKey: "lowpowermode",
            prompt: "Say \"hi\" \\ bye"
        )

        XCTAssertTrue(source.contains("with prompt \"Say \\\"hi\\\" \\\\ bye\" with administrator privileges"))
    }

    // MARK: - lowBatteryHUDHoldDuration

    func testHoveringNeverShortensTheHUD() {
        XCTAssertEqual(BatteryStatusViewModel.lowBatteryHUDHoldDuration(configured: 1), 5)
        XCTAssertEqual(BatteryStatusViewModel.lowBatteryHUDHoldDuration(configured: 5), 5)
        XCTAssertEqual(BatteryStatusViewModel.lowBatteryHUDHoldDuration(configured: 10), 10)
    }
}
