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

import Foundation

private let pmsetPath = "/usr/bin/pmset"
/// What AppleScript reports when the password prompt is cancelled.
private let userCancelledErrorNumber = -128

/// Turns Low Power Mode on from the low battery HUD, the way tapping the low
/// battery alert does on an iPhone.
///
/// macOS has no public API for this. The switch in System Settings writes a
/// power management preference that belongs to root, so the only supported
/// route from an app is `pmset` run with administrator rights. That is why
/// macOS asks for a password before the mode changes.
///
/// Nothing is published here when the change lands: `BatteryActivityManager`
/// already listens for `NSProcessInfoPowerStateDidChange`, so the yellow
/// "Low Power Mode enabled" HUD follows on its own.
@MainActor
final class LowPowerModeController: ObservableObject {
    static let shared = LowPowerModeController()

    /// True from the click until macOS has answered the password prompt. A
    /// click reaches the closed notch through both the SwiftUI tap gesture and
    /// the hover click monitor, so this also keeps one click from asking twice.
    @Published private(set) var isRequestInFlight = false

    private init() {}

    /// Asks macOS to turn Low Power Mode on while the Mac runs on battery.
    ///
    /// Battery only on purpose. An iPhone drops Low Power Mode again once it
    /// has charged; a Mac keeps the setting until someone changes it, so
    /// scoping it to battery power is what stops a click made at 20% from
    /// slowing the Mac down at the desk for good.
    func enableLowPowerMode() {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true

        Task { [weak self] in
            defer { self?.isRequestInFlight = false }

            guard let key = await Self.resolvePmsetKey() else {
                print("⚡ [LowPowerModeController] This Mac does not report a Low Power Mode setting")
                return
            }

            let source = Self.appleScriptSource(
                pmsetKey: key,
                prompt: String(localized: "Atoll wants to turn on Low Power Mode.")
            )

            do {
                try await AppleScriptHelper.executeVoid(source)
            } catch {
                let number = (error as NSError).userInfo[NSAppleScript.errorNumber] as? Int
                guard number != userCancelledErrorNumber else { return }
                print("⚡ [LowPowerModeController] Could not turn on Low Power Mode: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - pmset

    /// The name `pmset` uses for Low Power Mode on this Mac, or `nil` when it
    /// has no such setting.
    ///
    /// Macs that also offer High Power Mode replaced the boolean
    /// `lowpowermode` with a three-way `powermode` (0 automatic, 1 low,
    /// 2 high). Writing the wrong one is refused, so the key is read back from
    /// what `pmset -g custom` lists rather than guessed from the model.
    nonisolated static func pmsetKey(inCustomSettings output: String) -> String? {
        let keys = Set(
            output
                .split(whereSeparator: \.isNewline)
                .compactMap { $0.split(whereSeparator: \.isWhitespace).first.map(String.init) }
        )

        if keys.contains("powermode") { return "powermode" }
        if keys.contains("lowpowermode") { return "lowpowermode" }
        return nil
    }

    /// The AppleScript that runs `pmset` as root. `1` means "on" for
    /// `lowpowermode` and "low" for `powermode`, so the value is the same
    /// whichever key the Mac uses.
    nonisolated static func appleScriptSource(pmsetKey: String, prompt: String) -> String {
        let command = "\(pmsetPath) -b \(pmsetKey) 1"
        return "do shell script \"\(appleScriptEscaped(command))\" "
            + "with prompt \"\(appleScriptEscaped(prompt))\" "
            + "with administrator privileges"
    }

    /// Escapes text for an AppleScript string literal. The prompt is
    /// localized, so it cannot be trusted to stay free of quotes.
    nonisolated static func appleScriptEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private nonisolated static func resolvePmsetKey() async -> String? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pmsetPath)
            process.arguments = ["-g", "custom"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return nil
            }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let output = String(data: data, encoding: .utf8) else { return nil }
            return pmsetKey(inCustomSettings: output)
        }.value
    }
}
