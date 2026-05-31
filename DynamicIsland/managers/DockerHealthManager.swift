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

struct DockerContainer: Identifiable {
    let id: String
    let name: String
    let status: String
    var isRunning: Bool { status.lowercased().contains("up") }
}

@MainActor
final class DockerHealthManager: ObservableObject {
    static let shared = DockerHealthManager()

    @Published private(set) var containers: [DockerContainer] = []
    @Published private(set) var lastError: String?

    private var timer: Timer?

    var runningCount: Int { containers.filter(\.isRunning).count }
    var stoppedCount: Int { containers.filter { !$0.isRunning }.count }

    private init() {
        startPolling()
    }

    func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
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
        guard Defaults[.enableLockScreenDockerHealthWidget] else { return }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/local/bin/docker")
        process.arguments = ["ps", "-a", "--format", "{{json .}}"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Try common docker paths
        let paths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/usr/bin/docker"]
        var found = false
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                process.executableURL = URL(fileURLWithPath: path)
                found = true
                break
            }
        }
        guard found else {
            lastError = "docker not found"
            containers = []
            return
        }

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return }

            var parsed: [DockerContainer] = []
            for line in output.components(separatedBy: "\n") where !line.isEmpty {
                if let jsonData = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let id = json["ID"] as? String,
                   let name = json["Names"] as? String,
                   let status = json["Status"] as? String {
                    parsed.append(DockerContainer(id: id, name: name, status: status))
                }
            }
            containers = parsed
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
