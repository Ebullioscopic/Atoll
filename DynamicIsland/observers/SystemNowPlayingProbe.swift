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

/// Asks macOS once which app is Now Playing, independent of the media source
/// selected in Atoll. Used by the fullscreen detector when that source is not
/// "Now Playing" — then `MusicManager` only knows about the chosen player.
enum SystemNowPlayingProbe {

    /// Longest the adapter may run before it is terminated and the probe gives up.
    private static let timeout: TimeInterval = 2

    /// The Now Playing app named by one `mediaremote-adapter.pl … get` output,
    /// read the way `NowPlayingController` reads it: the parent application
    /// wins over the reporting process. Nil when the output is unusable.
    static func bundleIdentifier(fromAdapterOutput data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(NowPlayingPayload.self, from: data) else { return nil }
        let candidates = [payload.parentApplicationBundleIdentifier, payload.bundleIdentifier]
        return candidates.compactMap { $0 }.first { !$0.isEmpty }
    }

    /// Runs the bundled adapter's `get` off the main thread. Nil on any failure
    /// (missing resources, launch error, non-zero exit, timeout, bad output).
    static func currentBundleIdentifier() async -> String? {
        guard
            let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
            let frameworkPath = Bundle.main.resourceURL?
                .appendingPathComponent("MediaRemoteAdapter.framework")
                .path
        else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
                process.arguments = [scriptURL.path, frameworkPath, "get"]
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { process.terminate() }
                }

                // Read until EOF before waiting: artwork can exceed the pipe buffer.
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: bundleIdentifier(fromAdapterOutput: data))
            }
        }
    }
}
