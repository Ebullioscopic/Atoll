import AppKit
import Foundation
import CodeIslandCore

/// One-click diagnostics export for bug reports.
/// Collects app metadata, settings, session state, CLI configs, and recent logs into a zip.
struct DiagnosticsExporter {

    static func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CodeIsland-Diagnostics-\(timestamp()).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let zipURL = try buildArchive(saveTo: url)
                DispatchQueue.main.async {
                    NSWorkspace.shared.activateFileViewerSelecting([zipURL])
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Archive Builder

    private static func buildArchive(saveTo destination: URL) throws -> URL {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("CodeIsland-Diag-\(UUID().uuidString)", isDirectory: true)
        let root = tmp.appendingPathComponent("CodeIsland-Diagnostics-\(timestamp())", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        // 1. Metadata
        writeJSON(metadata(), to: root.appendingPathComponent("metadata.json"))

        // 2. Session snapshots (from AppState)
        let sessionsJSON = DispatchQueue.main.sync { sessionSnapshots() }
        writeJSON(sessionsJSON, to: root.appendingPathComponent("state/sessions.json"))

        // 2b. Recent hook events ring buffer (#103). Helps reproduce
        // session-routing / source-inference issues that only show up at
        // runtime — bug reports can ship with the actual event stream.
        let hookEventsJSON = DispatchQueue.main.sync { recentHookEvents() }
        writeJSON(hookEventsJSON, to: root.appendingPathComponent("state/hook-events.json"))

        // 3. CLI config files
        let home = fm.homeDirectoryForCurrentUser.path
        let configs: [(source: String, dest: String)] = [
            (ClaudeConfigPaths.settingsPath(), "configs/claude-settings.json"),
            ("\(home)/.codex/hooks.json", "configs/codex-hooks.json"),
            ("\(home)/.gemini/settings.json", "configs/gemini-settings.json"),
            ("\(home)/.cursor/hooks.json", "configs/cursor-hooks.json"),
            ("\(home)/.qoder/settings.json", "configs/qoder-settings.json"),
            ("\(home)/.factory/settings.json", "configs/factory-settings.json"),
            ("\(home)/.codebuddy/settings.json", "configs/codebuddy-settings.json"),
            ("\(home)/.codeisland/sessions.json", "configs/persisted-sessions.json"),
        ]
        for item in configs {
            copyIfExists(from: item.source, to: root.appendingPathComponent(item.dest))
        }

        // 4. Socket status
        let socketPath = SocketPath.path
        let socketExists = fm.fileExists(atPath: socketPath)
        let socketInfo = "path: \(socketPath)\nexists: \(socketExists)\n"
        try? socketInfo.write(to: root.appendingPathComponent("state/socket.txt"), atomically: true, encoding: .utf8)

        // 5. Unified system logs (last 2 hours)
        let logOutput = runCommand("/usr/bin/log", args: [
            "show", "--style", "compact", "--info", "--debug",
            "--last", "2h", "--predicate", "subsystem == \"com.codeisland\""
        ])
        try? logOutput.write(to: root.appendingPathComponent("logs/unified.log"), atomically: true, encoding: .utf8)

        // 6. sw_vers
        let swVers = runCommand("/usr/bin/sw_vers", args: [])
        try? swVers.write(to: root.appendingPathComponent("logs/sw_vers.txt"), atomically: true, encoding: .utf8)

        // 7. Recent crash reports
        copyCrashReports(to: root.appendingPathComponent("logs/crash-reports", isDirectory: true))

        // Zip
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        proc.arguments = ["-c", "-k", "--keepParent", root.path, destination.path]
        try proc.run()
        proc.waitUntilExit()
        try? fm.removeItem(at: tmp)

        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "DiagnosticsExporter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ditto failed with exit code \(proc.terminationStatus)"
            ])
        }
        return destination
    }

    // MARK: - Data Collectors

    private static func metadata() -> [String: Any] {
        [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "appVersion": AppVersion.current,
            "macOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "locale": Locale.current.identifier,
            "timeZone": TimeZone.current.identifier,
            "socketPath": SocketPath.path,
            "settings": [
                "hideInFullscreen": UserDefaults.standard.bool(forKey: SettingsKey.hideInFullscreen),
                "hideWhenNoSession": UserDefaults.standard.bool(forKey: SettingsKey.hideWhenNoSession),
                "collapseOnMouseLeave": UserDefaults.standard.bool(forKey: SettingsKey.collapseOnMouseLeave),
                "smartSuppress": UserDefaults.standard.bool(forKey: SettingsKey.smartSuppress),
                "sessionTimeout": UserDefaults.standard.integer(forKey: SettingsKey.sessionTimeout),
                "maxVisibleSessions": UserDefaults.standard.integer(forKey: SettingsKey.maxVisibleSessions),
                "mascotSpeed": UserDefaults.standard.integer(forKey: SettingsKey.mascotSpeed),
                "displayChoice": UserDefaults.standard.string(forKey: SettingsKey.displayChoice) ?? "auto",
            ],
        ]
    }

    @MainActor
    private static func recentHookEvents() -> [[String: Any]] {
        guard let appState = (NSApp.delegate as? AppDelegate)?.appState else { return [] }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return appState.recentHookEvents.map { event in
            var dict: [String: Any] = [
                "timestamp": isoFormatter.string(from: event.timestamp),
                "eventName": event.eventName,
                "viaPlugin": event.viaPlugin,
                "payloadKeys": event.payloadKeys,
            ]
            if let source = event.source { dict["source"] = source }
            if let sessionId = event.sessionId { dict["sessionId"] = String(sessionId.prefix(12)) }
            if let toolName = event.toolName { dict["toolName"] = toolName }
            if let preview = event.promptPreview { dict["promptPreview"] = preview }
            return dict
        }
    }

    @MainActor
    private static func sessionSnapshots() -> [[String: Any]] {
        guard let appState = (NSApp.delegate as? AppDelegate)?.appState else { return [] }
        return appState.sessions.map { id, s in
            var dict: [String: Any] = [
                "id": String(id.prefix(8)),
                "status": "\(s.status)",
                "source": s.source,
                "lastActivity": ISO8601DateFormatter().string(from: s.lastActivity),
            ]
            if let cwd = s.cwd { dict["cwd"] = cwd }
            if let tool = s.currentTool { dict["currentTool"] = tool }
            if let model = s.model { dict["model"] = model }
            if let term = s.terminalName { dict["terminal"] = term }
            if let pid = s.cliPid { dict["pid"] = pid }
            dict["subagentCount"] = s.subagents.count
            dict["toolHistoryCount"] = s.toolHistory.count
            return dict
        }
    }

    // MARK: - Helpers

    private static func writeJSON(_ obj: Any, to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func copyIfExists(from path: String, to url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(atPath: path, toPath: url.path)
    }

    private static func runCommand(_ executable: String, args: [String]) -> String {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = args
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    private static func copyCrashReports(to dir: URL) {
        let fm = FileManager.default
        let diagDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")
        guard let files = try? fm.contentsOfDirectory(at: diagDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let recent = files
            .filter { $0.lastPathComponent.lowercased().contains("codeisland") }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d1 > d2
            }
            .prefix(5)
        guard !recent.isEmpty else { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in recent {
            try? fm.copyItem(at: file, to: dir.appendingPathComponent(file.lastPathComponent))
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
