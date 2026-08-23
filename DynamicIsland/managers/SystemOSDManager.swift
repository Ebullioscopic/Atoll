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
import AppKit
import Darwin
import os

class SystemOSDManager {
    private init() {}

    // Tracks the PID we most recently suspended. macOS jetsam-exits OSDUIHelper
    // when idle and launchd respawns it on the next media-key press as a fresh
    // process, so we need to re-SIGSTOP every new incarnation.
    private struct SuppressionState {
        var task: Task<Void, Never>?
        var lastSuspendedPID: Int32 = -1
        // True while suppressing the native OSD (between disable/enableSystemHUD).
        var active = false
        // True while the Mac is asleep — watcher pauses, not cancelled.
        var systemSleeping = false
        // Invalidates asynchronous enable/disable work left over from an older
        // settings state. HUD style switches update several Defaults in quick
        // succession, so those transitions must not race each other.
        var transitionGeneration: UInt64 = 0
        // Coalesces immediate suppression requests from a key event and its
        // resulting system-value notification.
        var immediateSuppressionInFlight = false
    }
    private static let suppressionState = OSAllocatedUnfairLock(initialState: SuppressionState())

    /// Call once at startup to register sleep/wake observers.
    /// Safe to call multiple times — observers are registered only once.
    private static let sleepWakeSetupOnce: Void = {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            handleSystemSleep()
        }
        nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            handleSystemWake()
        }
    }()

    // MARK: - Sleep / Wake

    private static func handleSystemSleep() {
        // Mark as sleeping so the watcher loop exits its current poll immediately.
        suppressionState.withLock { $0.systemSleeping = true }
        // Stop the watcher task — no more pgrep spawns while sleeping.
        stopSuppressionWatcher()
    }

    private static func handleSystemWake() {
        suppressionState.withLock { $0.systemSleeping = false }
        // If suppression was still active when we went to sleep, restart the watcher.
        let active = suppressionState.withLock { $0.active }
        if active {
            // Reset the last-suspended PID so the watcher immediately re-suspends
            // the fresh OSDUIHelper that launchd may have spawned during wake.
            suppressionState.withLock { $0.lastSuspendedPID = -1 }
            startSuppressionWatcher()
        }
    }

    // MARK: - Public API

    /// Re-enables the system HUD by restarting OSDUIHelper
    public static func enableSystemHUD() {
        let generation = suppressionState.withLock { state -> UInt64 in
            state.active = false
            state.transitionGeneration &+= 1
            return state.transitionGeneration
        }
        stopSuppressionWatcher()
        Task.detached(priority: .background) {
            await enableSystemHUDAsync(generation: generation)
        }
    }
    
    private static func enableSystemHUDAsync(generation: UInt64) async {
        guard isCurrentTransition(generation, active: false) else { return }

        do {
            // First, stop any existing OSDUIHelper process
            let stopTask = Process()
            stopTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            stopTask.arguments = ["-9", "OSDUIHelper"]
            stopTask.standardError = Pipe() // silence "no such process" stderr
            try stopTask.run()
            stopTask.waitUntilExit()

            guard isCurrentTransition(generation, active: false) else { return }
            
            // Small delay to ensure process is fully stopped
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            guard isCurrentTransition(generation, active: false) else { return }
            
            // Then kickstart it again to ensure it's running properly
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            kickstart.arguments = ["kickstart", "gui/\(getuid())/com.apple.OSDUIHelper"]
            try kickstart.run()
            kickstart.waitUntilExit()

            // A replacement HUD may have been selected while launchctl was
            // running. In that case the current suppression transition owns the
            // helper; stop this stale restoration immediately.
            guard isCurrentTransition(generation, active: false) else {
                suppressNativeOSDNow()
                return
            }
            
            // Additional delay to ensure service is fully started
            try await Task.sleep(nanoseconds: 300_000_000) // 300ms
            guard isCurrentTransition(generation, active: false) else { return }
            
            await MainActor.run {
                print("✅ System HUD re-enabled")
            }
        } catch {
            guard isCurrentTransition(generation, active: false) else { return }
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

                guard isCurrentTransition(generation, active: false) else {
                    suppressNativeOSDNow()
                    return
                }
                
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

    /// Synchronously resumes OSDUIHelper for app termination.
    ///
    /// `enableSystemHUD()` restarts the helper on a detached background `Task`,
    /// which never runs to completion when the process is already terminating —
    /// so a SIGSTOP-frozen OSDUIHelper stays frozen after Atoll quits, breaking
    /// every native OSD Atoll does not replace (keyboard backlight,
    /// external-display brightness, …) and leaving a stuck HUD on screen. This
    /// sends SIGCONT inline and blocks until it lands, guaranteeing the helper
    /// is resumed before Atoll exits. Idempotent; safe to call from a
    /// termination handler.
    public static func resumeOSDUIHelperForTermination() {
        suppressionState.withLock { state in
            state.active = false
            state.transitionGeneration &+= 1
        }

        // Cancel the watcher and wait for it to fully exit before resuming. A
        // bare cancel is cooperative, so an in-flight suspendOSDUIHelper() could
        // otherwise land its SIGSTOP after our SIGCONT and re-freeze the helper.
        // Bridge the async drain to this synchronous path with a bounded wait.
        if let watcher = stopSuppressionWatcher() {
            let drained = DispatchSemaphore(value: 0)
            Task { await watcher.value; drained.signal() }
            _ = drained.wait(timeout: .now() + 1.0)
        }

        let resume = Process()
        resume.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        resume.arguments = ["-CONT", "OSDUIHelper"]
        resume.standardError = Pipe() // silence "no such process" stderr
        do {
            try resume.run()
            resume.waitUntilExit()
        } catch {
            NSLog("Failed to SIGCONT OSDUIHelper on termination: \(error)")
        }
    }

    /// Disables the system HUD by stopping OSDUIHelper, and starts a
    /// background watcher that re-suspends any future incarnation launchd
    /// spawns (macOS auto-exits OSDUIHelper on idle).
    public static func disableSystemHUD() {
        // Ensure sleep/wake observers are registered.
        _ = sleepWakeSetupOnce
        let generation = suppressionState.withLock { state -> UInt64 in
            state.active = true
            state.transitionGeneration &+= 1
            return state.transitionGeneration
        }
        Task.detached(priority: .background) {
            await disableSystemHUDAsync(generation: generation)
        }
        startSuppressionWatcher()
    }

    /// Immediately SIGSTOPs OSDUIHelper, bypassing the 150ms watcher poll. The
    /// CoreAudio volume write wakes/respawns the helper to draw the native OSD
    /// (brightness's private APIs never do), and the watcher can lose that race.
    /// No-op unless suppression is active.
    public static func suppressNativeOSDNow() {
        let generation = suppressionState.withLock { state -> UInt64? in
            guard state.active, !state.immediateSuppressionInFlight else { return nil }
            state.immediateSuppressionInFlight = true
            return state.transitionGeneration
        }
        guard let generation else { return }

        Task.detached(priority: .userInitiated) {
            defer {
                suppressionState.withLock { $0.immediateSuppressionInFlight = false }
            }

            guard isCurrentTransition(generation, active: true) else { return }
            if let pid = osduiHelperPID() {
                let lastPID = suppressionState.withLock { $0.lastSuspendedPID }
                if pid == lastPID {
                    return
                }
            }

            guard isCurrentTransition(generation, active: true) else { return }
            suspendOSDUIHelper()

            // If the user disabled Atoll's HUD replacement while SIGSTOP was in
            // flight, undo that stale suppression immediately. The current
            // restoration transition will still perform its clean restart.
            guard isCurrentTransition(generation, active: true) else {
                resumeOSDUIHelperProcess()
                return
            }

            if let pid = osduiHelperPID() {
                suppressionState.withLock { $0.lastSuspendedPID = pid }
            }
        }
    }
    
    private static func disableSystemHUDAsync(generation: UInt64) async {
        guard isCurrentTransition(generation, active: true) else { return }

        do {
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            // Force a clean helper instance. A plain kickstart is a no-op when
            // OSDUIHelper is already running, and macOS may replace that lingering
            // process on the first media key, briefly exposing the native HUD.
            kickstart.arguments = ["kickstart", "-k", "gui/\(getuid())/com.apple.OSDUIHelper"]
            try kickstart.run()
            kickstart.waitUntilExit()

            guard isCurrentTransition(generation, active: true) else { return }

            // launchctl kickstart returns once the request is queued, not after
            // OSDUIHelper has actually forked. At cold boot the helper can take
            // a while to appear — a fixed sleep races and the SIGSTOP misses,
            // letting the native OSD render on the first volume/brightness key.
            // Poll for the PID up to ~5s, then suspend, and retry if launchd
            // respawned a fresh copy between kickstart and SIGSTOP.
            var attempts = 0
            while attempts < 3 {
                guard isCurrentTransition(generation, active: true) else { return }
                let appeared = await waitForOSDUIHelper(timeoutMillis: 5000)
                guard isCurrentTransition(generation, active: true) else { return }
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
                guard isCurrentTransition(generation, active: true) else { return }
                if let pid = osduiHelperPID() {
                    suppressionState.withLock { $0.lastSuspendedPID = pid }
                    break
                }
                attempts += 1
            }

            if isCurrentTransition(generation, active: true) {
                await MainActor.run {
                    print("✅ System HUD disabled")
                }
            }
        } catch {
            guard isCurrentTransition(generation, active: true) else { return }
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

    private static func isCurrentTransition(_ generation: UInt64, active: Bool) -> Bool {
        suppressionState.withLock {
            $0.transitionGeneration == generation && $0.active == active
        }
    }

    /// Background loop that catches OSDUIHelper respawns. macOS exits the
    /// helper after a short idle period (JETSAM_REASON_MEMORY_IDLE_EXIT) and
    /// launchd spins up a brand-new process on the next volume/brightness
    /// keypress — that fresh PID renders the native OSD before any one-shot
    /// SIGSTOP can hit it. Polls at 150ms while catching a new PID, then backs
    /// off when the helper stays suspended.
    ///
    /// The loop exits immediately when the Mac sleeps (systemSleeping == true)
    /// and is restarted by handleSystemWake() when the machine wakes up again.
    /// This prevents the ~192,000 pgrep subprocess spawns that would otherwise
    /// accumulate over an 8-hour sleep and exhaust the process table / fd limits.
    private static func startSuppressionWatcher() {
        let newTask = Task.detached(priority: .background) {
            var stableChecks = 0
            while !Task.isCancelled {
                // Pause the watcher entirely while the system is asleep.
                // handleSystemWake() will cancel this task and spawn a fresh one.
                let sleeping = suppressionState.withLock { $0.systemSleeping }
                if sleeping {
                    // Sleep in larger chunks so we respond to cancellation promptly.
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                    continue
                }

                let currentPID = osduiHelperPID()
                let lastPID = suppressionState.withLock { $0.lastSuspendedPID }

                if let pid = currentPID, pid != lastPID {
                    suspendOSDUIHelper()
                    suppressionState.withLock { $0.lastSuspendedPID = pid }
                    stableChecks = 0
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
                    continue
                }

                stableChecks += 1
                let intervalNs: UInt64
                if currentPID == nil {
                    intervalNs = 1_000_000_000 // 1s — helper not running
                } else if stableChecks < 5 {
                    intervalNs = 150_000_000 // 150ms — confirm suspend stuck
                } else if stableChecks < 20 {
                    intervalNs = 500_000_000 // 500ms
                } else {
                    intervalNs = 1_000_000_000 // 1s — steady state
                }
                try? await Task.sleep(nanoseconds: intervalNs)
            }
        }

        let previous = suppressionState.withLock { state -> Task<Void, Never>? in
            let prior = state.task
            state.task = newTask
            return prior
        }
        previous?.cancel()
    }

    /// Cancels the suppression watcher. Returns the cancelled task so callers
    /// that must not race it (e.g. termination) can wait for it to fully exit.
    @discardableResult
    private static func stopSuppressionWatcher() -> Task<Void, Never>? {
        let previous = suppressionState.withLock { state -> Task<Void, Never>? in
            let prior = state.task
            state.task = nil
            state.lastSuspendedPID = -1
            return prior
        }
        previous?.cancel()
        return previous
    }

    /// Returns the newest OSDUIHelper PID, or nil if none.
    ///
    /// Asked once a second for as long as the app runs, so it is deliberately
    /// not `pgrep`. Shelling out costs a fork, an exec, a pipe and a process
    /// reap -- measured at 67ms of wall time and ~5ms of CPU per call, which is
    /// roughly half a percent of a core burned continuously, forever, to answer
    /// a question the kernel will answer directly in 0.6ms.
    private static func osduiHelperPID() -> Int32? {
        var byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard byteCount > 0 else { return nil }

        var pids = [pid_t](repeating: 0, count: Int(byteCount) / MemoryLayout<pid_t>.size)
        byteCount = proc_listpids(
            UInt32(PROC_ALL_PIDS),
            0,
            &pids,
            Int32(pids.count * MemoryLayout<pid_t>.size)
        )
        guard byteCount > 0 else { return nil }

        // `pgrep -n` means newest by start time, not highest PID. The two
        // usually agree and stop agreeing once PIDs wrap, so ask for the start
        // time rather than assume the ordering.
        var newestPID: pid_t?
        var newestStart: (sec: UInt64, usec: UInt64) = (0, 0)
        var name = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN) + 1)

        for pid in pids.prefix(Int(byteCount) / MemoryLayout<pid_t>.size) where pid > 0 {
            guard proc_name(pid, &name, UInt32(name.count)) > 0,
                  String(cString: name) == helperProcessName
            else { continue }

            var info = proc_bsdinfo()
            let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size))
            guard size == Int32(MemoryLayout<proc_bsdinfo>.size) else { continue }

            let start = (sec: UInt64(info.pbi_start_tvsec), usec: UInt64(info.pbi_start_tvusec))
            if newestPID == nil || start > newestStart {
                newestPID = pid
                newestStart = start
            }
        }

        return newestPID
    }

    private static let helperProcessName = "OSDUIHelper"

    /// Sends SIGSTOP to all OSDUIHelper processes. Idempotent.
    private static func suspendOSDUIHelper() {
        let stop = Process()
        stop.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        stop.arguments = ["-STOP", "OSDUIHelper"]
        stop.standardError = Pipe() // silence "no such process" stderr
        do {
            try stop.run()
            stop.waitUntilExit()
        } catch {
            NSLog("Suppression watcher: failed to SIGSTOP OSDUIHelper: \(error)")
        }
    }

    private static func resumeOSDUIHelperProcess() {
        let resume = Process()
        resume.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        resume.arguments = ["-CONT", "OSDUIHelper"]
        resume.standardError = Pipe()
        do {
            try resume.run()
            resume.waitUntilExit()
        } catch {
            NSLog("Failed to resume OSDUIHelper after stale suppression: \(error)")
        }
    }

    /// Check if OSDUIHelper is currently running
    public static func isOSDUIHelperRunning() -> Bool {
        osduiHelperPID() != nil
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
