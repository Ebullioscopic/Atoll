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

import Combine
import Foundation
import IOKit
import IOKit.pwr_mgt

/// Power management: keep screen awake + stay awake with the lid closed.
///
/// The two features work through completely different mechanisms — don't conflate them:
///
/// - **Keep screen awake** uses `IOPMAssertionCreateWithName` + `PreventUserIdleDisplaySleep`.
///   A standard idle assertion: it only blocks "idle-triggered display sleep" and **cannot
///   block lid-close sleep**. The assertion lives inside the process and is released
///   automatically once the process exits.
///
/// - **Stay awake with the lid closed** obtains the `IOPMrootDomain` user-client connection
///   via `IOPMFindPowerManagement`, then calls **selector 12** (set clamshell sleep state)
///   through `IOConnectCallScalarMethod`, passing `1` to disable lid-close sleep and `0` to
///   restore the default. No privileges, pure user space, works inside the sandbox too.
///
/// ## Dead ends already explored (don't redo them)
///
/// The first attempt assumed `IORegisterForSystemPower` + `IOCancelPowerChange` could catch
/// it. Three rounds of real-world testing all failed; the log (`Diagnostics.logURL`) showed:
///
/// 1. Lid close **only sends** `kIOMessageSystemWillSleep` (0xE0000280) and never the
///    documented "vetoable" `kIOMessageCanSystemSleep` (0xE0000270);
/// 2. Calling `IOCancelPowerChange` on `kIOMessageSystemWillSleep` **does nothing** — the
///    call goes through and the system sleeps 5 seconds later regardless. Apple's docs are
///    correct on this point.
///
/// The correct solution came from disassembling State.app (its `IOPMFindPowerManagement` →
/// `IOConnectCallScalarMethod(conn, 12, [!enabled], 1, NULL, 0)` → `IOServiceClose`).
///
/// ⚠️ **This switch is global kernel state and is NOT restored automatically when the process
/// exits** (same nature as `pmset disablesleep`, except a reboot clears it). So
/// `applicationWillTerminate` must call `shutdown()` to restore it; otherwise a crash of Atoll
/// leaves behind a system that "never sleeps on lid close".
final class PowerManagementManager: ObservableObject {
    static let shared = PowerManagementManager()

    /// Selector for "set clamshell sleep state" in the `IOPMrootDomain` user client.
    ///
    /// The value **12** comes from the actual call in disassembled State.app (`mov w1, #0xc`),
    /// not from the widely-circulated `kPMSetClamshellSleepState = 11` — that enum doesn't match
    /// this machine. It's a private interface that may change in future OS versions, so failures
    /// are never swallowed silently.
    private static let clamshellSleepStateSelector: UInt32 = 12

    /// Whether keep-screen-awake is active.
    @Published private(set) var isKeepingScreenAwake = false

    /// Whether stay-awake-with-lid-closed is active.
    @Published private(set) var isPreventingLidSleep = false

    private var displayAssertionID = IOPMAssertionID(0)

    private init() {}

    // MARK: - Public interface

    func toggleKeepScreenAwake() {
        setKeepScreenAwake(!isKeepingScreenAwake)
    }

    func togglePreventLidSleep() {
        setPreventLidSleep(!isPreventingLidSleep)
    }

    /// Call before quitting: release the assertion and **restore lid-close sleep**. The latter
    /// especially must not be skipped.
    func shutdown() {
        setKeepScreenAwake(false)
        setPreventLidSleep(false)
    }

    /// Unconditionally reset clamshell sleep to the system default at launch.
    ///
    /// Stay-awake-with-lid-closed changes **global kernel state** that is not restored
    /// automatically when the process exits. A normal quit restores it via `shutdown()`, but on
    /// a crash or force-kill `applicationWillTerminate` never runs, leaving the user with a
    /// machine that "never sleeps on lid close". This switch is not meant to persist across
    /// launches anyway, so reset it at launch to clear any leftover from last time.
    func resetClamshellStateOnLaunch() {
        // Log the actual result; never report success unconditionally — the whole point of this
        // diagnostic line is to capture failures when there is no other visible indication. A
        // failed kernel call that logs "restored" would wipe out that one signal.
        let succeeded = setClamshellSleepDisabled(false)
        Diagnostics.setActive(false)
        Diagnostics.log(succeeded
            ? "Launch reset: clamshell sleep restored to system default"
            : "Launch reset failed: clamshell sleep-state reset call did not succeed")
    }

    // MARK: - Keep screen awake

    @discardableResult
    func setKeepScreenAwake(_ enabled: Bool) -> Bool {
        guard enabled != isKeepingScreenAwake else { return true }

        if enabled {
            var assertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                // The assertion name shows up in system diagnostics like `pmset -g assertions`,
                // which handle non-ASCII unreliably (an em dash renders as garbage), so ASCII only.
                "Atoll: keep screen awake" as CFString,
                &assertionID
            )

            guard result == kIOReturnSuccess else {
                Diagnostics.log("Failed to create keep-screen-awake assertion: \(result)")
                return false
            }

            displayAssertionID = assertionID
            isKeepingScreenAwake = true
            Diagnostics.log("Keep screen awake enabled")
            return true
        } else {
            // The release can fail (stale ID, etc.); return the real result so the caller (e.g.
            // the icon-hiding onChange) can tell whether the system assertion was actually
            // dropped, instead of only seeing isKeepingScreenAwake forced to false.
            var released = true
            if displayAssertionID != IOPMAssertionID(0) {
                let result = IOPMAssertionRelease(displayAssertionID)
                released = (result == kIOReturnSuccess)
                if !released { Diagnostics.log("Failed to release keep-screen-awake assertion: \(result)") }
                displayAssertionID = IOPMAssertionID(0)
            }
            isKeepingScreenAwake = false
            Diagnostics.log("Keep screen awake disabled")
            return released
        }
    }

    // MARK: - Stay awake with lid closed

    @discardableResult
    func setPreventLidSleep(_ enabled: Bool) -> Bool {
        guard enabled != isPreventingLidSleep else { return true }

        guard setClamshellSleepDisabled(enabled) else {
            Diagnostics.log("Failed to set clamshell sleep state; stay-awake-with-lid-closed not applied")
            return false
        }

        isPreventingLidSleep = enabled
        Diagnostics.setActive(enabled)
        Diagnostics.log("Stay awake with lid closed \(enabled ? "enabled" : "disabled")")
        return true
    }

    /// Set the kernel's clamshell sleep switch directly.
    ///
    /// - Parameter disabled: `true` = **disable** lid-close sleep (stay-awake-with-lid-closed
    ///   takes effect), `false` = restore the system default (lid close sleeps as usual).
    ///
    /// Don't invert the direction — a flipped value manifests as "turning it on does nothing",
    /// which is very hard to spot. This semantic is cross-confirmed by two independent lines of
    /// reasoning: ① State's `-[… setClamshellCausingSleep:]` XORs the argument with 1 before
    /// passing it to the kernel (`eor w8, w20, #0x1`), i.e. `causingSleep=NO` → `input=1`;
    /// ② the selector maps to `setClamShellSleepDisable(bool)` on the kernel side, which is a
    /// "disable" semantic.
    @discardableResult
    private func setClamshellSleepDisabled(_ disabled: Bool) -> Bool {
        let connection = IOPMFindPowerManagement(0)
        guard connection != 0 else {
            Diagnostics.log("IOPMFindPowerManagement returned 0")
            return false
        }
        defer { IOServiceClose(connection) }

        var input: UInt64 = disabled ? 1 : 0
        let result = IOConnectCallScalarMethod(
            connection,
            Self.clamshellSleepStateSelector,
            &input,
            1,
            nil,
            nil
        )

        Diagnostics.log(
            "IOConnectCallScalarMethod(selector=\(Self.clamshellSleepStateSelector), "
            + "input=\(input)) -> 0x\(String(result, radix: 16))"
        )
        return result == kIOReturnSuccess
    }

}

// MARK: - Diagnostics

extension PowerManagementManager {
    /// Stay-awake-with-lid-closed produces no IOPM assertion, so `pmset -g assertions` can't see
    /// it; and during lid close the screen is invisible while NSLog can't be captured from a GUI
    /// process launched via `open`. So write a dedicated log to have something to grab onto when
    /// things go wrong.
    enum Diagnostics {
        static let logURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Atoll-power.log")

        private static let activeKey = "atollDiagLidPreventionActive"

        private static let formatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return f
        }()

        static func setActive(_ active: Bool) {
            UserDefaults.standard.set(active, forKey: activeKey)
        }

        static func log(_ message: String) {
            let line = "\(formatter.string(from: Date())) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            let fm = FileManager.default
            if !fm.fileExists(atPath: logURL.path) {
                try? fm.createDirectory(
                    at: logURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                fm.createFile(atPath: logURL.path, contents: nil)
            }

            guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}
