/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */
import AppKit
import ApplicationServices

/// Read-only identity checks by default. --chrome-multiple creates and closes
/// two blank fixture windows; --activate-other-space also verifies selection.
/// Titles/images are never logged or saved.
@main
struct DockPreviewIdentityRegression {
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, key as CFString, &value)
        return value
    }
    @MainActor static func multipleChromeWindows() async throws {
        guard let chrome = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else {
            throw NSError(domain: "Multiple-window test requires running Chrome", code: 1)
        }
        let previous = NSWorkspace.shared.frontmostApplication
        func script(_ source: String) throws -> String {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw NSError(domain: "Chrome fixture Automation unavailable", code: 1) }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        func serverIDs() -> Set<CGWindowID> {
            let entries = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
            return Set(entries.filter {
                $0[kCGWindowOwnerPID as String] as? pid_t == chrome.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0
                    && !($0[kCGWindowName as String] as? String ?? "").isEmpty
            }.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        }
        let originalIDs = serverIDs()
        var fixtureScriptIDs: [Int] = []
        defer {
            for id in fixtureScriptIDs { _ = try? script("tell application \"Google Chrome\" to close (first window whose id is \(id))") }
            previous?.activate()
        }
        for _ in 0..<2 {
            let value = try script("tell application \"Google Chrome\" to get id of (make new window)")
            guard let id = Int(value) else { throw NSError(domain: "Invalid Chrome fixture ID", code: 1) }
            fixtureScriptIDs.append(id)
            try await Task.sleep(for: .milliseconds(700))
        }
        let expected = serverIDs()
        guard expected.subtracting(originalIDs).count == 2 else { throw NSError(domain: "Could not identify two separate Chrome fixture windows", code: 1) }
        let service = DockPreviewService()
        let previews = await service.windows(for: chrome.processIdentifier, includeMinimized: true, limit: 12, allowCapture: true)
        let actual = Set(previews.compactMap(\.captureID))
        guard expected.isSubset(of: actual) else { throw NSError(domain: "Missing separate Chrome windows: expected \(expected.count), displayed \(previews.count), missing native IDs \(expected.subtracting(actual))", code: 1) }
        guard actual.count == previews.count else { throw NSError(domain: "Duplicate Chrome preview IDs", code: 1) }
        if CommandLine.arguments.contains("--installed-multiple") {
            let smoke = Process()
            smoke.executableURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/dock-preview-verification/installed-smoke")
            smoke.arguments = ["--preview", "--chrome"]
            try smoke.run(); smoke.waitUntilExit()
            guard smoke.terminationStatus == 0 else { throw NSError(domain: "Installed multiwindow Chrome cards failed", code: 1) }
        }
        let chromeRoot = AXUIElementCreateApplication(chrome.processIdentifier)
        let accessible = attribute(chromeRoot, kAXWindowsAttribute) as? [AXUIElement] ?? []
        let accessibleIDs = Set(accessible.compactMap { DockPreviewNativeWindowIdentity.windowID(for: $0) })
        if CommandLine.arguments.contains("--activate-other-space") {
            let hidden = previews.filter { !accessibleIDs.contains(CGWindowID($0.id)) }
            guard !hidden.isEmpty else { throw NSError(domain: "No other-Space Chrome window exercised", code: 1) }
            for window in hidden {
                guard await service.perform(.activate, windowID: window.id, pid: chrome.processIdentifier) else {
                    throw NSError(domain: "Other-Space Chrome preview activation failed", code: 1)
                }
                try await Task.sleep(for: .milliseconds(500))
                guard let focused = attribute(chromeRoot, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID(),
                      DockPreviewNativeWindowIdentity.windowID(for: focused as! AXUIElement) == CGWindowID(window.id) else {
                    throw NSError(domain: "Other-Space Chrome activated the wrong window", code: 1)
                }
            }
            print("PASS \(hidden.count) other-Space Chrome previews activate their exact native windows")
        }
        for window in previews {
            guard await service.thumbnail(for: CGWindowID(window.id), width: 320) != nil else { throw NSError(domain: "Missing multiwindow Chrome snapshot", code: 1) }
        }
        print("PASS separate Chrome windows: \(expected.count) real windows, \(previews.count) distinct previews and snapshots")
        let fixtureNativeIDs = expected.subtracting(originalIDs)
        for id in fixtureScriptIDs { _ = try script("tell application \"Google Chrome\" to close (first window whose id is \(id))") }
        fixtureScriptIDs.removeAll()
        var remaining: [DockPreviewWindow] = []
        for _ in 0..<30 {
            remaining = await service.windows(for: chrome.processIdentifier, includeMinimized: true, limit: 12, allowCapture: true)
            if Set(remaining.map { CGWindowID($0.id) }).isDisjoint(with: fixtureNativeIDs) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard Set(remaining.map { CGWindowID($0.id) }).isDisjoint(with: fixtureNativeIDs) else { throw NSError(domain: "Closed Chrome fixture remains in previews", code: 1) }
        print("PASS closed fixture windows disappear from previews")
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else { throw NSError(domain: "Identity test requires Accessibility and Screen Recording", code: 1) }
        if CommandLine.arguments.contains("--chrome-multiple") {
            try await multipleChromeWindows()
            try await Task.sleep(for: .milliseconds(600))
        }
        let service = DockPreviewService()
        let apps = NSWorkspace.shared.runningApplications.filter { ["com.google.Chrome", "com.apple.finder", "com.openai.chat", "com.openai.codex"].contains($0.bundleIdentifier ?? "") }
        var snapshots = 0
        for app in apps {
            let windows = await service.windows(for: app.processIdentifier, includeMinimized: true, limit: 12, allowCapture: true)
            guard Set(windows.map(\.id)).count == windows.count else { throw NSError(domain: "Duplicate native preview IDs", code: 1) }
            for window in windows {
                guard window.captureID == CGWindowID(window.id) else { throw NSError(domain: "Snapshot/action native identity mismatch", code: 1) }
                guard let image = await service.thumbnail(for: CGWindowID(window.id), width: 320), image.width > 1 else { throw NSError(domain: "Native preview snapshot missing for \(app.localizedName ?? "Application") ID \(window.id)", code: 1) }
                snapshots += 1
            }
            print("PASS \(app.localizedName ?? "Application"): \(windows.count) distinct native windows and exact snapshots")
        }
        guard snapshots > 0 else { throw NSError(domain: "No real window snapshots exercised", code: 1) }
        print("PASS \(snapshots) real snapshots verified without app activation or window changes")
    }
}
