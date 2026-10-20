/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */
import AppKit
import ApplicationServices
import ImageIO

/// Opt-in installed-app smoke test. Opens Atoll Settings and leaves Dock Previews selected.
@main
struct DockPreviewInstalledSmoke {
    static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, key as CFString, &value)
        return value
    }
    static func find(_ root: AXUIElement, text: String, path: [AXUIElement] = []) -> [AXUIElement]? {
        guard path.count < 24 else { return nil }
        let path = path + [root]
        if [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].contains(where: { attribute(root, $0) as? String == text }) { return path }
        for child in attribute(root, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let result = find(child, text: text, path: path) { return result }
        }
        return nil
    }
    @MainActor static func checkAttachedFrames(pid: pid_t) async throws {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/dock-preview-verification/animation")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var checked = 0
        var centeredRows = 0
        var maximumDrift: CGFloat = 0
        for index in 0..<6 {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let notch = windows.first { item in
                guard item[kCGWindowOwnerPID as String] as? pid_t == pid,
                      item[kCGWindowLayer as String] as? Int != 0,
                      let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                      let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
                return frame.height > 50 && frame.minY < 60
            }
            guard let number = notch?[kCGWindowNumber as String] as? Int else { try fail("No notch window for animation capture"); return }
            let file = output.appendingPathComponent("opening-\(index).png")
            let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(number), file.path]
            try capture.run(); capture.waitUntilExit()
            guard capture.terminationStatus == 0, let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { try fail("Animation frame capture failed"); return }
            let width = image.width, height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let rows: [Int] = bytes.withUnsafeMutableBytes { storage in
                guard let context = CGContext(data: storage.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return (0..<height).filter { y in storage[y * width * 4 + (width / 2) * 4 + 3] > 160 }
            }
            // Check the animated shell, not just its final card positions. A
            // translated/clipped shell can remain attached while opening sideways.
            for y in stride(from: 8, to: max(9, height - 16), by: 12) {
                let opaque = (0..<width).filter { x in
                    let offset = (y * width + x) * 4
                    return bytes[offset + 3] > 245 && bytes[offset] < 25 && bytes[offset + 1] < 25 && bytes[offset + 2] < 25
                }
                if let left = opaque.first, let right = opaque.last, right - left > 100 {
                    let drift = abs(CGFloat(left + right) / 2 - CGFloat(width - 1) / 2)
                    centeredRows += 1
                    maximumDrift = max(maximumDrift, drift)
                    guard drift < 6 else { try fail("Sideways notch opening: shell center drift \(drift)px in frame \(index), row \(y)"); return }
                }
            }
            if let first = rows.first, let last = rows.last, last > first + 8 {
                let occupied = Set(rows)
                var gap = 0
                for row in first...last {
                    gap = occupied.contains(row) ? 0 : gap + 1
                    guard gap <= 4 else { try fail("Detached notch animation: transparent gap across the center in frame \(index)"); return }
                }
                checked += 1
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard centeredRows > 0 else { try fail("No opaque shell edges were checked for centered opening"); return }
        print("PASS opening shell stays centered: \(centeredRows) rows, maximum drift \(maximumDrift)px")
        guard checked > 0 else { try fail("No opaque notch animation frames were checked"); return }
        print("PASS \(checked) captured opening frames stay connected through the notch center")
    }
    static func fail(_ message: String) throws {
        throw NSError(domain: "DockPreviewInstalledSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        guard AXIsProcessTrusted() else { try fail("Test runner requires Accessibility"); return }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == "/Applications/Atoll.app" }) else { try fail("Installed Atoll is not running"); return }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        app.activate()
        if let menu = find(root, text: "Settings")?.last { _ = AXUIElementPerformAction(menu, kAXPressAction as CFString) }
        try await Task.sleep(for: .milliseconds(350))
        if find(root, text: "Dock Previews") == nil {
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 43, keyDown: true)!
            down.flags = .maskCommand; down.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 43, keyDown: false)!
            up.flags = .maskCommand; up.post(tap: .cghidEventTap)
            try await Task.sleep(for: .milliseconds(350))
        }
        for _ in 0..<10 {
            if find(root, text: "Dock Previews") != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let path = find(root, text: "Dock Previews"), let item = path.last else { try fail("Dock Previews is absent from installed Settings sidebar"); return }
        if let row = path.last(where: { attribute($0, kAXRoleAttribute) as? String == kAXRowRole }) {
            _ = AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)
            _ = AXUIElementPerformAction(row, kAXPressAction as CFString)
        } else { _ = AXUIElementPerformAction(item, kAXPressAction as CFString) }
        try await Task.sleep(for: .milliseconds(250))
        let labels = ["Enable Dock previews", "Use ⌘Tab in the notch", "Show unified app strip", "Move window to focused screen on click", "Show background process activity card", "Window snapshots", "Include minimized windows", "Re-check permissions"]
        for _ in 0..<20 {
            if labels.allSatisfy({ find(root, text: $0) != nil }) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        for label in labels {
            guard find(root, text: label) != nil else { try fail("Installed settings control missing: \(label)"); return }
        }
        print("PASS installed sidebar navigation and all \(labels.count) Dock Preview controls")
        print(find(root, text: "Accessibility access granted") == nil ? "Installed Atoll needs Accessibility access before live preview testing" : "Installed Atoll Accessibility granted")
        if CommandLine.arguments.contains("--preview") {
            for label in ["Enable Dock previews", "Use ⌘Tab in the notch"] {
                guard let path = find(root, text: label) else { try fail("Cannot find toggle label: \(label)"); return }
                guard let parent = path.dropLast().last, let labelElement = path.last else { try fail("Toggle label has no row"); return }
                let siblings = attribute(parent, kAXChildrenAttribute) as? [AXUIElement] ?? []
                guard let index = siblings.firstIndex(where: { CFEqual($0, labelElement) }),
                      let toggle = siblings.dropFirst(index + 1).first(where: { attribute($0, kAXRoleAttribute) as? String == kAXCheckBoxRole }) else { try fail("Cannot find toggle: \(label)"); return }
                if (attribute(toggle, kAXValueAttribute) as? NSNumber)?.intValue == 0 {
                    guard AXUIElementPerformAction(toggle, kAXPressAction as CFString) == .success else { try fail("Cannot enable \(label)"); return }
                }
            }
            try await Task.sleep(for: .milliseconds(300))
            guard find(root, text: "The keyboard monitor is unavailable. Check Accessibility access, then re-check permissions. macOS Command-Tab is still available.") == nil else { try fail("Installed keyboard monitor unavailable"); return }
            guard let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }) else { try fail("Finder unavailable"); return }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AtollPreviewSmoke-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
            defer {
                let finderRoot = AXUIElementCreateApplication(finder.processIdentifier)
                for window in attribute(finderRoot, kAXWindowsAttribute) as? [AXUIElement] ?? [] where attribute(window, kAXTitleAttribute) as? String == folder.lastPathComponent {
                    if let close = attribute(window, kAXCloseButtonAttribute), CFGetTypeID(close) == AXUIElementGetTypeID() { _ = AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) }
                }
                try? FileManager.default.removeItem(at: folder)
            }
            try await Task.sleep(for: .milliseconds(400))
            finder.activate()
            try await Task.sleep(for: .milliseconds(250))
            func post(_ key: CGKeyCode, flags: CGEventFlags = [], type: CGEventType = .keyDown) {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: type == .keyDown)!
                event.type = type; event.flags = flags; event.post(tap: .cghidEventTap)
            }
            post(48, flags: .maskCommand); post(48, flags: .maskCommand, type: .keyUp)
            if CommandLine.arguments.contains("--animation") { try await checkAttachedFrames(pid: app.processIdentifier) }
            try await Task.sleep(for: .milliseconds(200))
            post(48, flags: [.maskCommand, .maskShift]); post(48, flags: [.maskCommand, .maskShift], type: .keyUp)
            try await Task.sleep(for: .milliseconds(800))
            guard find(root, text: "Dismiss Dock preview") != nil else { try fail("Command-Tab did not open the installed notch preview"); return }
            let windows = attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []
            guard let notch = windows.first(where: { find($0, text: "Dismiss Dock preview") != nil }) else { try fail("Preview not in notch"); return }
            func frame(_ element: AXUIElement) -> CGRect? {
                guard let origin = attribute(element, kAXPositionAttribute), let dimensions = attribute(element, kAXSizeAttribute), CFGetTypeID(origin) == AXValueGetTypeID(), CFGetTypeID(dimensions) == AXValueGetTypeID() else { return nil }
                var p = CGPoint.zero, size = CGSize.zero
                AXValueGetValue(origin as! AXValue, .cgPoint, &p); AXValueGetValue(dimensions as! AXValue, .cgSize, &size)
                return CGRect(origin: p, size: size)
            }
            guard let notchFrame = frame(notch) else { try fail("No notch geometry"); return }
            var checkedCards = 0
            var cardBounds: CGRect?
            func checkCards(_ element: AXUIElement, depth: Int = 0) throws {
                guard depth < 20 else { return }
                let label = attribute(element, kAXTitleAttribute) as? String ?? attribute(element, kAXDescriptionAttribute) as? String ?? ""
                if label.hasPrefix("Activate "), let rect = frame(element), rect.width > 0 {
                    checkedCards += 1
                    cardBounds = cardBounds.map { $0.union(rect) } ?? rect
                    guard rect.minX >= notchFrame.minX + 4, rect.maxX <= notchFrame.maxX - 4 else { try fail("Installed preview card is clipped at the native window edge"); return }
                }
                for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { try checkCards(child, depth: depth + 1) }
            }
            try checkCards(notch)
            guard checkedCards > 0, let cardBounds else { try fail("No native preview card bounds were checked"); return }
            guard abs(cardBounds.midX - notchFrame.midX) < 3 else { try fail("Preview cards are not centered inside the native notch: offset \(cardBounds.midX - notchFrame.midX)"); return }
            guard let primary = NSScreen.screens.first else { try fail("No screen"); return }
            let topEdges = NSScreen.screens.map { primary.frame.maxY - $0.frame.maxY }
            guard topEdges.contains(where: { abs($0 - notchFrame.minY) < 1 }) else { try fail("Notch window is not anchored to its screen top"); return }
            for _ in 0..<5 {
                try await Task.sleep(for: .milliseconds(25))
                guard let current = frame(notch), abs(current.minY - notchFrame.minY) < 1 else { try fail("Notch top edge moves during presentation"); return }
            }
            post(53, flags: .maskCommand); post(53, flags: .maskCommand, type: .keyUp)
            post(55, type: .flagsChanged)
            try await Task.sleep(for: .milliseconds(500))
            guard find(root, text: "Dismiss Dock preview") == nil else { try fail("Escape did not dismiss installed preview"); return }
            finder.activate()
            try await Task.sleep(for: .milliseconds(250))
            post(48, flags: .maskCommand); post(48, flags: .maskCommand, type: .keyUp)
            try await Task.sleep(for: .milliseconds(200))
            post(48, flags: [.maskCommand, .maskShift]); post(48, flags: [.maskCommand, .maskShift], type: .keyUp)
            try await Task.sleep(for: .milliseconds(300))
            post(55, type: .flagsChanged)
            for _ in 0..<15 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier else { try fail("Command release did not activate selected Finder app; active: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")"); return }
            print("PASS installed Command-Tab preview, card bounds, Escape, reverse selection, and release activation")
            if CommandLine.arguments.contains("--chrome"), let chrome = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) {
                chrome.activate()
                try await Task.sleep(for: .milliseconds(300))
                post(48, flags: .maskCommand); post(48, flags: .maskCommand, type: .keyUp)
                try await Task.sleep(for: .milliseconds(150))
                post(48, flags: [.maskCommand, .maskShift]); post(48, flags: [.maskCommand, .maskShift], type: .keyUp)
                try await Task.sleep(for: .milliseconds(800))
                let entries = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                let expected = Set(entries.filter { entry in
                    guard entry[kCGWindowOwnerPID as String] as? pid_t == chrome.processIdentifier,
                          entry[kCGWindowLayer as String] as? Int == 0,
                          !(entry[kCGWindowName as String] as? String ?? "").isEmpty,
                          let raw = entry[kCGWindowBounds as String] as? NSDictionary,
                          let bounds = CGRect(dictionaryRepresentation: raw) else { return false }
                    return bounds.width >= 120 && bounds.height >= 120
                }.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
                guard !expected.isEmpty, let preview = (attribute(root, kAXWindowsAttribute) as? [AXUIElement] ?? []).first(where: { find($0, text: "Dismiss Dock preview") != nil }) else { try fail("Chrome preview not available"); return }
                var cards = 0
                func countCards(_ element: AXUIElement, depth: Int = 0) {
                    guard depth < 20 else { return }
                    let label = attribute(element, kAXTitleAttribute) as? String ?? attribute(element, kAXDescriptionAttribute) as? String ?? ""
                    if attribute(element, kAXRoleAttribute) as? String == kAXButtonRole, label.hasPrefix("Activate ") { cards += 1 }
                    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] { countCards(child, depth: depth + 1) }
                }
                countCards(preview)
                guard cards > 0, cards <= expected.count,
                      cards == expected.count || find(preview, text: "Next windows") != nil else {
                    try fail("Chrome omitted separate windows: \(cards) cards for \(expected.count) native windows without overflow paging"); return
                }
                post(53, flags: .maskCommand); post(53, flags: .maskCommand, type: .keyUp); post(55, type: .flagsChanged)
                print("PASS installed Chrome preview: \(cards) visible cards for \(expected.count) native browser windows")
            }
        }
        if let outputIndex = CommandLine.arguments.firstIndex(of: "--output"), CommandLine.arguments.count > outputIndex + 1,
           let settings = (attribute(root, kAXWindowsAttribute) as? [AXUIElement])?.first(where: { attribute($0, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole }) {
            let pid = app.processIdentifier
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            if let window = windows.first(where: { $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0 }), let number = window[kCGWindowNumber as String] as? Int {
                _ = settings
                let capture = Process(); capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-o", "-l", String(number), CommandLine.arguments[outputIndex + 1]]
                try capture.run(); capture.waitUntilExit()
            }
        }
    }
}
