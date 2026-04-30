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

class SystemOSDManager {
    private init() {}

    /// Re-enables the system HUD by restarting OSDUIHelper
    public static func enableSystemHUD() {
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

    /// Disables the system HUD by stopping OSDUIHelper
    public static func disableSystemHUD() {
        Task.detached(priority: .background) {
            await disableSystemHUDAsync()
        }
    }
    
    private static func disableSystemHUDAsync() async {
        do {
            let kickstart = Process()
            kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            // -k forces launchd to kill any existing OSDUIHelper instance and respawn it
            // cleanly. Without -k, kickstart is a no-op when the service is already running,
            // and the subsequent SIGSTOP can land on a lingering instance that macOS then
            // replaces when a media key is pressed — leaving the native HUD visible on
            // first launch until the user toggles the setting off and on again.
            kickstart.arguments = ["kickstart", "-k", "gui/\(getuid())/com.apple.OSDUIHelper"]
            try kickstart.run()
            kickstart.waitUntilExit()

            try await Task.sleep(nanoseconds: 500_000_000) // 500ms - async wait instead of usleep
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            task.arguments = ["-STOP", "OSDUIHelper"]
            try task.run()
            task.waitUntilExit()
            
            await MainActor.run {
                print("✅ System HUD disabled")
            }
        } catch {
            await MainActor.run {
                NSLog("❌ Error while trying to hide OSDUIHelper: \(error)")
            }
        }
    }
    
    /// Check if OSDUIHelper is currently running
    public static func isOSDUIHelperRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["OSDUIHelper"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            return task.terminationStatus == 0 && !output!.isEmpty
        } catch {
            return false
        }
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