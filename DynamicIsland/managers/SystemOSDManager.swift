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
import os
import Darwin

class SystemOSDManager {
    private init() {}

    // Tracks the PID we most recently suspended. macOS jetsam-exits OSDUIHelper
    // when idle and launchd respawns it on the next media-key press as a fresh
    // process, so we need to re-SIGSTOP every new incarnation.
    private struct SuppressionState {
        var task: Task<Void, Never>?
        var lastSuspendedPID: Int32 = -1
    }
    private static let suppressionState = OSAllocatedUnfairLock(initialState: SuppressionState())

    /// Re-enables the system HUD by restarting OSDUIHelper
    public static func enableSystemHUD() {
        stopSuppressionWatcher()
        Task.detached(priority: .background) {
            await enableSystemHUDAsync()
        }
    }
    
    private static func enableSystemHUDAsync() async {
        do {
            // First, stop any existing OSDUIHelper process
            let stopTask = Process()
            stopTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            stopTask.arguments = ["-9", "OSDUIHelper"]
            try stopTask.run()
            stopTask.waitUntilExit()
            
            // Small delay to ensure process is fully stopped
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            
            // Then kickstart it again to ensure it's running properly
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            kickstart.arguments = ["kickstart", "gui/\(getuid())/com.apple.OSDUIHelper"]
            try kickstart.run()
            kickstart.waitUntilExit()
            
            // Additional delay to ensure service is fully started
            try await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            await MainActor.run {
                print("✅ System HUD re-enabled")
            }
        } catch {
            await MainActor.run {
                NSLog("❌ Error while trying to re-enable OSDUIHelper: \(error)")
            }
            
            // Fallback: Try to restart the service using launchctl load
            do {
                let fallbackTask = Process()
                fallbackTask.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                fallbackTask.arguments = ["load", "-w", "/System/Library/LaunchAgents/com.apple.OSDUIHelper.plist"]
                try fallbackTask.run()
                fallbackTask.waitUntilExit()
                
                await MainActor.run {
                    print("✅ System HUD re-enabled via fallback method")
                }
            } catch {
                await MainActor.run {
                    NSLog("❌ Fallback method also failed: \(error)")
                }
            }
        }
    }

    /// Disables the system HUD by stopping OSDUIHelper, and starts a
    /// background watcher that re-suspends any future incarnation launchd
    /// spawns (macOS auto-exits OSDUIHelper on idle).
    public static func disableSystemHUD() {
        Task.detached(priority: .background) {
            await disableSystemHUDAsync()
        }
        startSuppressionWatcher()
    }
    
    private static func disableSystemHUDAsync() async {
        do {
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            // When macOS boots, OSDUIHelper does not start until a volume button is pressed. We can workaround this by kickstarting it.
            kickstart.arguments = ["kickstart", "gui/\(getuid())/com.apple.OSDUIHelper"]
            try kickstart.run()
            kickstart.waitUntilExit()

            // launchctl kickstart returns once the request is queued, not after
            // OSDUIHelper has actually forked. At cold boot the helper can take
            // a while to appear — a fixed sleep races and the SIGSTOP misses,
            // letting the native OSD render on the first volume/brightness key.
            // Poll for the PID up to ~5s, then suspend, and retry if launchd
            // respawned a fresh copy between kickstart and SIGSTOP.
            var attempts = 0
            while attempts < 3 {
                let appeared = await waitForOSDUIHelper(timeoutMillis: 5000)
                if !appeared {
                    await MainActor.run {
                        NSLog("⚠️ OSDUIHelper did not appear within timeout; retrying SIGSTOP anyway")
                    }
                }

                suspendOSDUIHelper()

                // Settle, then confirm a process is actually present (and thus
                // suspended). If none is running, launchd hasn't spawned it yet
                // or the prior STOP raced — loop and try again.
                try await Task.sleep(nanoseconds: 250_000_000) // 250ms
                if let pid = osduiHelperPID() {
                    suppressionState.withLock { $0.lastSuspendedPID = pid }
                    break
                }
                attempts += 1
            }

            await MainActor.run {
                print("✅ System HUD disabled")
            }
        } catch {
            await MainActor.run {
                NSLog("❌ Error while trying to hide OSDUIHelper: \(error)")
            }
        }
    }

    /// Polls for an OSDUIHelper process, returning true as soon as one appears
    /// or false if `timeoutMillis` elapses with no match.
    private static func waitForOSDUIHelper(timeoutMillis: Int) async -> Bool {
        let pollIntervalNanos: UInt64 = 200_000_000 // 200ms
        let maxAttempts = max(1, timeoutMillis / 200)
        for _ in 0..<maxAttempts {
            if isOSDUIHelperRunning() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanos)
        }
        return isOSDUIHelperRunning()
    }

    /// Background loop that catches OSDUIHelper respawns. macOS exits the
    /// helper after a short idle period (JETSAM_REASON_MEMORY_IDLE_EXIT) and
    /// launchd spins up a brand-new process on the next volume/brightness
    /// keypress — that fresh PID renders the native OSD before any one-shot
    /// SIGSTOP can hit it. Polling every 150ms is cheap (a single pgrep per
    /// tick when nothing changed) and shrinks the visible-OSD window enough
    /// to feel instant.
    private static func startSuppressionWatcher() {
        let newTask = Task.detached(priority: .background) {
            while !Task.isCancelled {
                let currentPID = osduiHelperPID()
                let lastPID = suppressionState.withLock { $0.lastSuspendedPID }

                if let pid = currentPID, pid != lastPID {
                    suspendOSDUIHelper()
                    suppressionState.withLock { $0.lastSuspendedPID = pid }
                }
                try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
            }
        }

        let previous = suppressionState.withLock { state -> Task<Void, Never>? in
            let prior = state.task
            state.task = newTask
            return prior
        }
        previous?.cancel()
    }

    private static func stopSuppressionWatcher() {
        let previous = suppressionState.withLock { state -> Task<Void, Never>? in
            let prior = state.task
            state.task = nil
            state.lastSuspendedPID = -1
            return prior
        }
        previous?.cancel()
    }

    /// Returns the PIDs of all processes named `name`, using libproc entirely
    /// in-process.
    ///
    /// The suppression watcher calls this every 150ms; the previous
    /// implementation forked `/usr/bin/pgrep` on every tick (~6-7 process
    /// spawns per second, indefinitely), which dominated the app's idle CPU and
    /// energy use. Enumerating PIDs via `proc_listallpids` avoids the fork
    /// entirely.
    private static func pids(named name: String) -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }

        // Over-allocate to absorb processes that spawn between the count and the
        // fill; proc_listallpids returns the number actually written.
        var buffer = [pid_t](repeating: 0, count: Int(estimate) + 32)
        let byteCount = Int32(buffer.count * MemoryLayout<pid_t>.size)
        let written = buffer.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, byteCount)
        }
        guard written > 0 else { return [] }

        var matches: [pid_t] = []
        var nameBuffer = [CChar](repeating: 0, count: 256)
        for index in 0..<Int(written) {
            let pid = buffer[index]
            guard pid > 0 else { continue }
            let length = nameBuffer.withUnsafeMutableBufferPointer {
                proc_name(pid, $0.baseAddress, UInt32($0.count))
            }
            guard length > 0 else { continue }
            if String(cString: nameBuffer) == name {
                matches.append(pid)
            }
        }
        return matches
    }

    /// Returns the newest OSDUIHelper PID, or nil if none.
    private static func osduiHelperPID() -> Int32? {
        // launchd respawns the helper as a fresh, higher PID; the highest PID is
        // the newest incarnation (matching the old `pgrep -n` behaviour).
        pids(named: "OSDUIHelper").max()
    }

    /// Sends SIGSTOP to all OSDUIHelper processes. Idempotent.
    private static func suspendOSDUIHelper() {
        let stop = Process()
        stop.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        stop.arguments = ["-STOP", "OSDUIHelper"]
        do {
            try stop.run()
            stop.waitUntilExit()
        } catch {
            NSLog("Suppression watcher: failed to SIGSTOP OSDUIHelper: \(error)")
        }
    }

    /// Check if OSDUIHelper is currently running
    public static func isOSDUIHelperRunning() -> Bool {
        !pids(named: "OSDUIHelper").isEmpty
    }
    
    /// Async version of status checking to avoid main thread blocking
    public static func isOSDUIHelperRunningAsync() async -> Bool {
        return await withCheckedContinuation { continuation in
            Task.detached(priority: .background) {
                let result = isOSDUIHelperRunning()
                continuation.resume(returning: result)
            }
        }
    }
}