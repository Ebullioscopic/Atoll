/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */
import AppKit
import ApplicationServices
import SwiftUI

@main
struct DockPreviewRegression {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw NSError(domain: "DockPreviewRegression", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            checks += 1
        }
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        try check(DockPreviewGeometry.quartzPoint(CGPoint(x: 10, y: 850), primaryScreen: primary) == CGPoint(x: 10, y: 50), "Primary coordinate conversion")
        try check(DockPreviewGeometry.quartzPoint(CGPoint(x: -400, y: 1100), primaryScreen: primary) == CGPoint(x: -400, y: -200), "Displays above and left retain global coordinates")
        for (orientation, point) in [("left", CGPoint(x: 5, y: 450)), ("right", CGPoint(x: 1435, y: 450)), ("bottom", CGPoint(x: 700, y: 5))] {
            try check(DockPreviewGeometry.isNearDock(point, screen: primary, orientation: orientation), "Dock edge \(orientation)")
            try check(!DockPreviewGeometry.isNearDock(CGPoint(x: 720, y: 450), screen: primary, orientation: orientation), "No AX work in the screen center")
        }
        let secondary = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        try check(DockPreviewGeometry.isNearDock(CGPoint(x: -1000, y: -195), screen: secondary, orientation: "bottom"), "Secondary-screen Dock")
        try check(!DockPreviewGeometry.isNearDock(CGPoint(x: 100, y: 5), screen: secondary, orientation: "bottom"), "Other screen is excluded")
        var hover = DockPreviewHoverState()
        let first = URL(fileURLWithPath: "/Applications/First.app"), second = URL(fileURLWithPath: "/Applications/Second.app")
        hover.update(first, now: 1)
        try check(!hover.isReady(now: 1.2, delay: 0.4), "No immediate hover activation")
        hover.update(first, now: 1.25)
        try check(hover.isReady(now: 1.41, delay: 0.4), "Dwell survives repeated events")
        hover.update(second, now: 1.42)
        try check(!hover.isReady(now: 1.5, delay: 0.4), "Rapid app switching restarts dwell")
        hover.reset()
        try check(!hover.isReady(now: 10, delay: 0.4), "Leaving the Dock cancels pending activation")
        let bounds = CGRect(x: 100, y: 100, width: 500, height: 300)
        try check(DockPreviewGeometry.captureMatchScore(title: "Same", frame: bounds, candidateTitle: "Same", candidateFrame: bounds) == 0, "Exact thumbnail identity")
        try check(DockPreviewGeometry.captureMatchScore(title: "Same", frame: bounds, candidateTitle: "Same", candidateFrame: bounds.offsetBy(dx: 50, dy: 0)) > 0, "Duplicate titles use geometry")
        try check(DockPreviewGeometry.captureMatchScore(title: "Same", frame: bounds, candidateTitle: "Other", candidateFrame: bounds) >= 1000, "Unrelated window rejected")
        for available in [CGFloat(220), 360, 480, 648, 760] {
            for preferred in [CGFloat(156), 200, 240] {
                let width = DockPreviewLayout.fittedCardWidth(available: available, preferred: preferred)
                let count = DockPreviewLayout.cardsPerPage(available: available, cardWidth: width)
                try check(CGFloat(count) * width + CGFloat(count - 1) * DockPreviewLayout.gap <= available, "Whole cards fit the actual shell viewport")
            }
        }
        let panelWidth = DockPreviewLayout.panelWidth(count: 3, cardWidth: 200)
        try check(panelWidth - 2 * (DockPreviewLayout.shellInset + DockPreviewLayout.panelInset) >= 620, "Panel width budgets shell flare and card gaps")
        let keyboard = DockPreviewKeyboardMonitor()
        var actions: [DockPreviewKeyboardMonitor.Action] = []
        keyboard.onAction = { actions.append($0) }
        func event(_ key: CGKeyCode, flags: CGEventFlags = [], type: CGEventType = .keyDown) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: type == .keyDown)!
            event.type = type; event.flags = flags; return event
        }
        try check(keyboard.process(type: .keyDown, event: event(48, flags: .maskCommand)) == nil, "Command-Tab intercepted")
        try check(keyboard.process(type: .keyUp, event: event(48, flags: .maskCommand, type: .keyUp)) == nil, "Consumed key-up does not leak to macOS switcher")
        _ = keyboard.process(type: .flagsChanged, event: event(56, flags: [.maskCommand, .maskShift], type: .flagsChanged))
        try check(actions == [.step(true)], "Shift release does not commit while Command is held")
        _ = keyboard.process(type: .flagsChanged, event: event(55, type: .flagsChanged))
        try check(actions == [.step(true), .commit], "Command release commits once")
        actions.removeAll()
        _ = keyboard.process(type: .keyDown, event: event(48, flags: [.maskCommand, .maskShift]))
        _ = keyboard.process(type: .keyDown, event: event(123, flags: .maskCommand))
        _ = keyboard.process(type: .keyDown, event: event(53, flags: .maskCommand))
        _ = keyboard.process(type: .flagsChanged, event: event(55, type: .flagsChanged))
        try check(actions == [.step(false), .step(false), .cancel], "Reverse, arrow navigation, Escape cancels without later commit")
        try check(keyboard.process(type: .keyDown, event: event(48, flags: [.maskCommand, .maskAlternate])) != nil, "Other shortcuts pass through")
        keyboard.canBegin = { false }
        try check(keyboard.process(type: .keyDown, event: event(48, flags: .maskCommand)) != nil, "System switcher retained if notch cannot present")
        for (front, forward, expected) in [(pid_t(10), true, pid_t(20)), (10, false, 30)] {
            try check(DockPreviewSwitchSelection(pids: [10, 20, 30], frontmost: front, forward: forward).selectedPID == expected, "Switcher starts relative to active app")
        }
        try check(DockPreviewSwitchSelection(pids: [10, 20], frontmost: nil, forward: true).selectedPID == 10, "Unknown front app selects first candidate")
        try check(DockPreviewSwitchSelection(pids: [], frontmost: nil, forward: true).selectedPID == nil, "Empty switcher is safe")
        try check(DockPreviewWindowTitle.resolve(accessibility: "", capture: "Playing video", document: nil, previous: nil, application: "Player") == "Playing video", "Full-screen video falls back to capture title")
        try check(DockPreviewWindowTitle.resolve(accessibility: nil, capture: nil, document: nil, previous: "Video.mp4", application: "Player") == "Video.mp4", "Title survives an empty full-screen transition")
        try check(DockPreviewWindowTitle.resolve(accessibility: " ", capture: "", document: nil, previous: nil, application: "Player") == "Player", "App name replaces Untitled window")
        try check(DockPreviewGeometry.captureMatchScore(title: "", frame: bounds, candidateTitle: "Video", candidateFrame: bounds) == 0, "Missing AX title still maps exact capture geometry")
        print("PASS \(checks) Dock preview policy checks")

        _ = NSApplication.shared
        if let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > index + 1 {
            try await renderPreviews(directory: CommandLine.arguments[index + 1])
        }
        guard CommandLine.arguments.contains("--live") else { return }
        try check(AXIsProcessTrusted(), "Accessibility is required for --live")
        keyboard.stop(); keyboard.canBegin = { true }; actions.removeAll(); keyboard.start()
        try check(keyboard.isInstalled, "Native Command-Tab event tap installed")
        event(48, flags: .maskCommand).post(tap: .cghidEventTap)
        event(48, flags: .maskCommand, type: .keyUp).post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(150))
        event(55, type: .flagsChanged).post(tap: .cghidEventTap)
        try await Task.sleep(for: .milliseconds(150))
        keyboard.stop()
        try check(actions == [.step(true), .commit], "Actual event tap consumes Command-Tab and commits on release")
        let previous = NSWorkspace.shared.frontmostApplication
        defer { previous?.activate() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AtollDockPreview-\(UUID().uuidString)")
        let firstFolder = root.appendingPathComponent("Preview A \(root.lastPathComponent.suffix(6))"), secondFolder = root.appendingPathComponent("Preview B \(root.lastPathComponent.suffix(6))")
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(firstFolder)
        try await Task.sleep(for: .milliseconds(500))
        NSWorkspace.shared.open(secondFolder)
        try await Task.sleep(for: .milliseconds(500))
        guard let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) else { throw NSError(domain: "DockPreviewRegression", code: 2) }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        func elements() -> [AXUIElement] {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
            return value as? [AXUIElement] ?? []
        }
        func title(_ element: AXUIElement) -> String? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value)
            return value as? String
        }
        func isMinimized(_ name: String) -> Bool? {
            guard let element = elements().first(where: { title($0) == name }) else { return nil }
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value)
            return value as? Bool
        }
        defer {
            for element in elements() where [firstFolder.lastPathComponent, secondFolder.lastPathComponent].contains(title(element) ?? "") {
                var button: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success, let button {
                    AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
                }
            }
            try? FileManager.default.removeItem(at: root)
        }
        let service = DockPreviewService(), pid = finder.processIdentifier
        if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            func finderDockFrame(_ element: AXUIElement, depth: Int = 0) -> CGRect? {
                guard depth < 4 else { return nil }
                func value(_ key: String) -> CFTypeRef? {
                    var result: CFTypeRef?
                    AXUIElementCopyAttributeValue(element, key as CFString, &result)
                    return result
                }
                if let url = value(kAXURLAttribute) as? URL, url.lastPathComponent == "Finder.app",
                   let position = value(kAXPositionAttribute), let dimensions = value(kAXSizeAttribute),
                   CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(dimensions) == AXValueGetTypeID() {
                    var point = CGPoint.zero, size = CGSize.zero
                    AXValueGetValue(position as! AXValue, .cgPoint, &point)
                    AXValueGetValue(dimensions as! AXValue, .cgSize, &size)
                    return CGRect(origin: point, size: size)
                }
                for child in value(kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                    if let frame = finderDockFrame(child, depth: depth + 1) { return frame }
                }
                return nil
            }
            if let frame = finderDockFrame(AXUIElementCreateApplication(dock.processIdentifier)) {
                let target = await service.target(at: CGPoint(x: frame.midX, y: frame.midY), dockProcessID: dock.processIdentifier)
                if let target {
                    try check(target.applicationURL.lastPathComponent == "Finder.app", "Actual Dock AX hit resolves the correct application")
                    print("PASS visible Dock hit identity")
                } else { print("SKIP visible Dock hit: Dock is hidden or occluded") }
            }
            let emptyTarget = await service.target(at: CGPoint(x: -100000, y: -100000), dockProcessID: dock.processIdentifier)
            try check(emptyTarget == nil, "No target outside actual Dock item geometry")
        }
        if CommandLine.arguments.contains("--fullscreen"), let fixture = elements().first(where: { title($0) == firstFolder.lastPathComponent }) {
            defer { _ = AXUIElementSetAttributeValue(fixture, "AXFullScreen" as CFString, kCFBooleanFalse) }
            let entered = AXUIElementSetAttributeValue(fixture, "AXFullScreen" as CFString, kCFBooleanTrue)
            try check(entered == .success, "Finder fixture accepts native full screen")
            try await Task.sleep(for: .milliseconds(1200))
            let fullScreenWindows = await service.windows(for: pid, includeMinimized: true, limit: 12, allowCapture: CGPreflightScreenCaptureAccess())
            try check(fullScreenWindows.contains { $0.title == firstFolder.lastPathComponent && $0.isFullScreen }, "Native full-screen window remains discoverable with a Full Screen badge")
            try check(Set(fullScreenWindows.map(\.id)).count == fullScreenWindows.count, "Main/focused fallback does not duplicate windows")
            if CGPreflightScreenCaptureAccess(), let window = fullScreenWindows.first(where: { $0.title == firstFolder.lastPathComponent }), let id = window.captureID {
                let snapshot = await service.thumbnail(for: id, width: 400)
                try check(snapshot != nil, "Native full-screen window snapshot is available")
                previous?.activate()
                try await Task.sleep(for: .milliseconds(700))
                let otherSpace = await service.windows(for: pid, includeMinimized: true, limit: 12, allowCapture: true)
                try check(otherSpace.contains { $0.title == firstFolder.lastPathComponent && $0.isFullScreen }, "Full-screen title persists from another Space")
                if let id = otherSpace.first(where: { $0.title == firstFolder.lastPathComponent })?.captureID {
                    let snapshot = await service.thumbnail(for: id, width: 400)
                    try check(snapshot != nil, "Full-screen snapshot available from another Space")
                } else { try check(false, "Full-screen capture identity missing on another Space") }
            } else if CGPreflightScreenCaptureAccess() { try check(false, "Full-screen capture identity missing") }

            _ = AXUIElementSetAttributeValue(fixture, "AXFullScreen" as CFString, kCFBooleanFalse)
            try await Task.sleep(for: .milliseconds(1200))
            print("PASS full-screen Finder discovery and deduplication")
        }
        let windows = await service.windows(for: pid, includeMinimized: true, limit: 12, allowCapture: CGPreflightScreenCaptureAccess())
        guard let a = windows.first(where: { $0.title == firstFolder.lastPathComponent }), let b = windows.first(where: { $0.title == secondFolder.lastPathComponent }) else { throw NSError(domain: "DockPreviewRegression", code: 3, userInfo: [NSLocalizedDescriptionKey: "AX fixture enumeration: \(windows.map(\.title))"]) }
        try check(a.id != b.id, "Separate action identities")
        try check(a.canClose && a.canMinimize, "Supported window actions exposed")
        let minimized = await service.perform(.minimize, windowID: a.id, pid: pid)
        try check(minimized, "Native minimize action")
        try await Task.sleep(for: .milliseconds(200))
        try check((isMinimized(firstFolder.lastPathComponent) == true), "Actual window is minimized")
        let visible = await service.windows(for: pid, includeMinimized: false, limit: 12, allowCapture: false)
        try check(!visible.contains { $0.title == firstFolder.lastPathComponent }, "Minimized filter")
        let all = await service.windows(for: pid, includeMinimized: true, limit: 12, allowCapture: CGPreflightScreenCaptureAccess())
        guard let minimizedWindow = all.first(where: { $0.title == firstFolder.lastPathComponent }) else { throw NSError(domain: "DockPreviewRegression", code: 4) }
        try check(minimizedWindow.isMinimized, "Minimized state is accurate")
        let raised = await service.perform(.activate, windowID: minimizedWindow.id, pid: pid)
        try check(raised, "Native restore and raise")
        try await Task.sleep(for: .milliseconds(200))
        try check(isMinimized(firstFolder.lastPathComponent) == false, "Actual window is restored")
        let destination = CGRect(x: 180, y: 180, width: 700, height: 480)
        let moved = await service.perform(.move(destination), windowID: minimizedWindow.id, pid: pid)
        try check(moved, "Native move-to-display position accepted")
        try await Task.sleep(for: .milliseconds(150))
        let refreshed = await service.windows(for: pid, includeMinimized: true, limit: 12, allowCapture: CGPreflightScreenCaptureAccess())
        guard let closeTarget = refreshed.first(where: { $0.title == secondFolder.lastPathComponent }) else { throw NSError(domain: "DockPreviewRegression", code: 5) }
        let closed = await service.perform(.close, windowID: closeTarget.id, pid: pid)
        try check(closed, "Native close action")
        try await Task.sleep(for: .milliseconds(150))
        try check(!elements().contains { title($0) == secondFolder.lastPathComponent } && elements().contains { title($0) == firstFolder.lastPathComponent }, "Close only affects the selected window")
        let wrongProcess = await service.perform(.close, windowID: a.id, pid: pid + 1)
        try check(!wrongProcess, "Cross-process stale action rejected")
        if CGPreflightScreenCaptureAccess(), let item = refreshed.first(where: { $0.title == firstFolder.lastPathComponent }), let capture = item.captureID {
            let image = await service.thumbnail(for: capture, width: 400)
            try check(image != nil && image!.width <= 640, "Bounded native thumbnail capture")
            print("PASS ScreenCaptureKit thumbnail capture")
        } else { print("SKIP ScreenCaptureKit capture: grant Screen Recording to this test executable") }
        await service.clear()
        let stale = await service.perform(.close, windowID: a.id, pid: pid)
        try check(!stale, "Cleared session cannot act on a stale window")
        print("PASS native window enumerate/minimize/restore/close; \(checks) total checks")
    }

    @MainActor private static func renderPreviews(directory: String) async throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
        let windows = [DockPreviewWindow(id: 1, title: "Project files", frame: .zero, isMinimized: false, canClose: true, canMinimize: true, captureID: nil),
                       DockPreviewWindow(id: 2, title: "Documentation — a longer window title", frame: .zero, isMinimized: true, canClose: true, canMinimize: true, captureID: nil)]
        let extra = (3...8).map { DockPreviewWindow(id: UInt($0), title: "Window \($0)", frame: .zero, isMinimized: false, canClose: true, canMinimize: true, captureID: nil) }
        let apps = (1...12).map { DockPreviewApplication(id: pid_t($0), url: url, name: "Application \($0)", windowCount: $0 % 4) }
        for width in [CGFloat(320), 360, 680] {
          for background in [false, true] {
            let session = DockPreviewSession(id: UUID(), applicationURL: url, applicationName: "Finder", processID: 42, screenName: "Preview", windows: background ? [] : windows + extra)
            let view = DockPreviewContent(session: session, thumbnails: [:], isLoading: false, actionError: nil, hasScreenRecording: false,
                cardWidth: 200, refresh: {}, dismiss: {}, activateApplication: {}, perform: { _, _ in }, applications: apps, isKeyboardSwitching: true)
                .padding(.horizontal, DockPreviewLayout.shellInset).padding(.top, 32).frame(width: width, height: 300, alignment: .top).background(Color.black).preferredColorScheme(.dark)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(x: 80, y: 150, width: width, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(180)); host.layoutSubtreeIfNeeded()
            let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), "\(directory)/dock-preview-\(background ? "background-" : "")\(Int(width)).png"]
            try capture.run(); capture.waitUntilExit(); window.close()
            guard capture.terminationStatus == 0 else { fatalError("FAIL: Native preview render") }
        }
          }
        print("PASS compact, wide, and background preview renders")
    }
}
