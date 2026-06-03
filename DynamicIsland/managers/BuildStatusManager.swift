/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import Defaults
import Combine

@MainActor
final class BuildStatusManager: ObservableObject {
    static let shared = BuildStatusManager()

    @Published private(set) var isBuildActive: Bool = false

    private var timer: Timer?
    // Fix #2: guard against overlapping refresh executions
    private var isRefreshing = false

    private init() {
        startPolling()
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refresh()
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard Defaults[.enableLockScreenBuildStatusWidget] else {
            isBuildActive = false
            return
        }
        // Fix #2: skip if a refresh is already in progress
        guard !isRefreshing else { return }
        isRefreshing = true

        // Fix #1: run Process off the main thread, publish results back on MainActor
        Task.detached { [weak self] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            process.arguments = ["-f", "xcodebuild"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            var active = false
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                active = !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } catch {
                active = false
            }

            await MainActor.run { [weak self] in
                self?.isBuildActive = active
                self?.isRefreshing = false
            }
        }
    }
}
