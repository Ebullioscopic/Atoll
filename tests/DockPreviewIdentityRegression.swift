/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */
import AppKit
import ApplicationServices

/// Read-only checks against running apps. Titles/images are never logged or saved.
@main
struct DockPreviewIdentityRegression {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else { throw NSError(domain: "Identity test requires Accessibility and Screen Recording", code: 1) }
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
