/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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

@MainActor
final class MediaChecker {
    enum MediaCheckerError: Error {
        case missingResources
        case processExecutionFailed
        case timeout
    }

    func checkDeprecationStatus() async throws -> Bool {
        guard let scriptURL = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworkPath =
                    Bundle.main.resourceURL?
                        .appendingPathComponent("MediaRemoteAdapter.framework")
                        .path
        else {
            throw MediaCheckerError.missingResources
        }

        let nowPlayingTestClientPath =
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers/NowPlayingTestClient")
                .path

        guard FileManager.default.isExecutableFile(atPath: nowPlayingTestClientPath) else {
            throw MediaCheckerError.missingResources
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptURL.path, frameworkPath, nowPlayingTestClientPath, "test"]

        // Capture stderr to distinguish script errors from genuine deprecation.
        // The perl script's fail() and the framework's test function both exit
        // with status 1, but only script-level failures write to stderr.
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw MediaCheckerError.processExecutionFailed
        }

        // Timeout after 10 seconds
        let didExit: Bool = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                process.waitUntilExit()
                return true
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                if process.isRunning {
                    process.terminate()
                }
                return false
            }
            for try await exited in group {
                if exited {
                    group.cancelAll()
                    return true
                }
            }
            throw MediaCheckerError.timeout
        }

        if !didExit {
            throw MediaCheckerError.timeout
        }

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrOutput = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // If the process exited with a non-zero status AND stderr contains
        // output, a script-level error occurred (e.g. framework failed to load,
        // symbol not found). Treat this as an execution failure rather than
        // reporting deprecated, since perl's fail() also uses exit(1).
        if process.terminationStatus != 0, !stderrOutput.isEmpty {
            print("MediaChecker: script error (exit \(process.terminationStatus)): \(stderrOutput)")
            throw MediaCheckerError.processExecutionFailed
        }

        let isDeprecated = process.terminationStatus == 1
        return isDeprecated
    }
}
