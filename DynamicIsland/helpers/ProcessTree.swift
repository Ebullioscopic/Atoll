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

import AppKit
import Darwin
import Foundation

/// Reads the running process table through `sysctl`.
///
/// Used to answer two questions about an agent whose pid Atoll knows: *which
/// terminal device is it attached to*, and *which application is it running
/// inside*. Both come straight from the kernel, so no subprocess is spawned —
/// this repo has no `ps` or `osascript` shelling out and should keep it that way.
///
/// Everything here degrades to `nil`: a process can exit between two calls, and
/// none of this is worth failing a feature over.
enum ProcessTree {
    /// The parent of `pid`, or `nil` if it cannot be read.
    static func parent(of pid: pid_t) -> pid_t? {
        guard let info = processInfo(for: pid) else { return nil }
        let parent = info.kp_eproc.e_ppid
        return parent > 0 ? parent : nil
    }

    /// `pid` and its ancestors, closest first, stopping at `launchd`.
    ///
    /// Depth-capped: a corrupted table with a parent cycle would otherwise spin.
    static func ancestors(of pid: pid_t, limit: Int = 24) -> [pid_t] {
        var result: [pid_t] = []
        var current = pid
        var seen = Set<pid_t>()
        while result.count < limit, current > 1, seen.insert(current).inserted {
            result.append(current)
            guard let next = parent(of: current) else { break }
            current = next
        }
        return result
    }

    /// Path of the controlling terminal for `pid`, e.g. `/dev/ttys004`.
    ///
    /// This is the join key for finding an agent's tab: both Terminal.app and
    /// iTerm2 expose a `tty` on their tabs and sessions, so matching on it is
    /// exact rather than a guess from a window title.
    static func ttyPath(for pid: pid_t) -> String? {
        guard let info = processInfo(for: pid) else { return nil }
        let device = info.kp_eproc.e_tdev
        // `NODEV` means the process has no controlling terminal.
        guard device != dev_t(bitPattern: UInt32.max), device != 0 else { return nil }
        guard let name = devname(device, S_IFCHR) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// The running application `pid` lives inside, found by walking up until an
    /// ancestor is a GUI app.
    ///
    /// This is what makes the fallback work for every terminal: even with no
    /// AppleScript support and no CLI, the right app can still be brought
    /// forward, and it needs no automation consent at all.
    /// Only a `.regular` application is accepted. `NSRunningApplication` can be
    /// constructed for a command-line process too — with an activation policy that
    /// makes `activate()` a no-op — so taking the first non-nil result would
    /// report success while nothing came forward.
    static func hostApplication(for pid: pid_t) -> NSRunningApplication? {
        for candidate in ancestors(of: pid) {
            guard let app = NSRunningApplication(processIdentifier: candidate) else { continue }
            guard app.activationPolicy == .regular else { continue }
            return app
        }
        return nil
    }

    /// Raw `kinfo_proc` for one pid.
    private static func processInfo(for pid: pid_t) -> kinfo_proc? {
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&name, u_int(name.count), &info, &size, nil, 0)
        // `size == 0` means the pid is gone even though sysctl succeeded.
        guard result == 0, size > 0 else { return nil }
        return info
    }
}
