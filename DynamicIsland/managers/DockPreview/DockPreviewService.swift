/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */

import AppKit
import ApplicationServices
import ScreenCaptureKit

/// All potentially slow Accessibility IPC and image capture stay off the main actor.
actor DockPreviewService {
    private var elements: [UInt: AXUIElement] = [:]
    private var captureWindows: [CGWindowID: SCWindow] = [:]
    private var cachedImages: [CGWindowID: (Date, CGImage)] = [:]
    private var knownTitles: [UInt: String] = [:]
    private var processID: pid_t?

    func target(at point: CGPoint, dockProcessID: pid_t) -> DockPreviewTarget? {
        let dock = AXUIElementCreateApplication(dockProcessID)
        AXUIElementSetMessagingTimeout(dock, 0.15)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dock, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }
        for _ in 0..<5 {
            if string(element, kAXRoleAttribute) == "AXDockItem" { break }
            guard let parent = attribute(element, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            element = parent as! AXUIElement
        }
        guard string(element, kAXRoleAttribute) == "AXDockItem",
              string(element, kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = attribute(element, kAXURLAttribute) as? URL, url.isFileURL,
              url.pathExtension.lowercased() == "app", let frame = rect(element), frame.contains(point) else { return nil }
        return DockPreviewTarget(applicationURL: url.standardizedFileURL, frame: frame)
    }

    func windows(for pid: pid_t, includeMinimized: Bool, limit: Int, allowCapture: Bool) async -> [DockPreviewWindow] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var raw: CFTypeRef?
        let enumeration = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
        var all = raw as? [AXUIElement] ?? []
        if enumeration != .success {
            all += (attribute(app, kAXChildrenAttribute) as? [AXUIElement] ?? []).filter { string($0, kAXRoleAttribute) == kAXWindowRole }
        }
        // Full-screen/other-Space apps can expose an empty AXWindows list
        // while retaining their main or focused window. Merge, then deduplicate.
        for key in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            if let window = attribute(app, key), CFGetTypeID(window) == AXUIElementGetTypeID() {
                let element = window as! AXUIElement
                if !all.contains(where: { CFEqual($0, element) }) { all.append(element) }
            }
        }
        let serverWindows = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).filter {
            $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0
        }
        let serverByID = Dictionary(serverWindows.compactMap { entry -> (CGWindowID, [String: Any])? in
            guard let id = entry[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return (id, entry)
        }, uniquingKeysWith: { first, _ in first })
        let runningApplication = NSRunningApplication(processIdentifier: pid)
        let applicationName = runningApplication?.localizedName ?? "Application window"
        let chromium = ["com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser"].contains(runningApplication?.bundleIdentifier ?? "")
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(16, &displayIDs, &displayCount)
        let displayBounds = displayIDs.prefix(Int(displayCount)).map { CGDisplayBounds($0) }
        var shareable: [SCWindow] = []
        if allowCapture, let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) {
            shareable = content.windows.filter { serverByID[$0.windowID] != nil && $0.windowLayer == 0 }
        }
        guard !Task.isCancelled else { return [] }
        elements.removeAll()
        if processID != pid { knownTitles.removeAll(); cachedImages.removeAll() }
        processID = pid
        let previousWindows = captureWindows
        cachedImages = cachedImages.filter { id, _ in
            guard let next = shareable.first(where: { $0.windowID == id }), let previous = previousWindows[id] else { return false }
            return next.frame == previous.frame && next.title == previous.title && previous.owningApplication?.processID == pid
        }
        captureWindows = Dictionary(shareable.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        // Prefer the actionable standard proxy when an app exposes several
        // AX objects for the same native window.
        func rank(_ element: AXUIElement) -> Int {
            (string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole ? 8 : 0)
                + ((string(element, kAXTitleAttribute) ?? "").isEmpty ? 0 : 4)
                + (attribute(element, kAXCloseButtonAttribute) == nil ? 0 : 2)
        }
        all.sort { rank($0) > rank($1) }
        var result: [DockPreviewWindow] = []
        var seen = Set<CGWindowID>()
        for element in all {
            guard !Task.isCancelled else { return [] }
            AXUIElementSetMessagingTimeout(element, 0.15)
            guard string(element, kAXRoleAttribute) == kAXWindowRole,
                  !["AXSystemDialog", "AXNotificationCenterWindow"].contains(string(element, kAXSubroleAttribute) ?? ""),
                  let accessibleFrame = rect(element) else { continue }
            let title = (string(element, kAXTitleAttribute) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let nativeID = DockPreviewNativeWindowIdentity.windowID(for: element)
            // If the native resolver is present, a failed lookup means this is
            // a stale/helper AX proxy, not a window to guess a snapshot for.
            if DockPreviewNativeWindowIdentity.isAvailable && nativeID == nil { continue }
            let fallbackMatches = nativeID == nil ? serverWindows.filter { entry in
                guard !title.isEmpty, let raw = entry[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: raw) else { return false }
                return DockPreviewGeometry.captureMatchScore(title: title, frame: accessibleFrame,
                    candidateTitle: entry[kCGWindowName as String] as? String, candidateFrame: bounds) < 20
            } : []
            guard let windowID = nativeID ?? (fallbackMatches.count == 1 ? fallbackMatches[0][kCGWindowNumber as String] as? CGWindowID : nil),
                  let metadata = serverByID[windowID], let bounds = metadata[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width >= 120, frame.height >= 80 else { continue }
            let minimized = attribute(element, kAXMinimizedAttribute) as? Bool ?? false
            guard minimized || (metadata[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            if minimized && !includeMinimized { continue }
            guard seen.insert(windowID).inserted else { continue }
            let id = UInt(windowID)
            let fullScreen = (attribute(element, "AXFullScreen") as? Bool ?? false) || DockPreviewGeometry.matchesFullScreen(frame, displays: displayBounds)
            guard !chromium || DockPreviewWindowInclusion.includes(subrole: string(element, kAXSubroleAttribute), accessibilityTitle: title,
                serverTitle: metadata[kCGWindowName as String] as? String, fullScreen: fullScreen) else { continue }
            let capture = allowCapture ? windowID : nil
            let captureTitle = [captureWindows[windowID]?.title, metadata[kCGWindowName as String] as? String].compactMap { $0 }.first { !$0.isEmpty }
            let document = (attribute(element, kAXDocumentAttribute) as? String).flatMap { URL(string: $0)?.lastPathComponent }
            let resolvedTitle = DockPreviewWindowTitle.resolve(accessibility: title, capture: captureTitle, document: document,
                previous: knownTitles[id], application: applicationName)
            knownTitles[id] = resolvedTitle
            elements[id] = element
            var settable = DarwinBoolean(false)
            let canMinimize = AXUIElementIsAttributeSettable(element, kAXMinimizedAttribute as CFString, &settable) == .success && settable.boolValue
            result.append(DockPreviewWindow(id: id, title: resolvedTitle, frame: frame,
                isMinimized: minimized, canClose: attribute(element, kAXCloseButtonAttribute) != nil,
                canMinimize: canMinimize, captureID: capture, isFullScreen: fullScreen))
            if result.count >= max(1, min(12, limit)) { break }
        }
        cachedImages = cachedImages.filter { captureWindows[$0.key] != nil }
        knownTitles = knownTitles.filter { elements[$0.key] != nil }
        return result
    }

    func thumbnail(for id: CGWindowID, width: Int) async -> CGImage? {
        guard elements[UInt(id)] != nil, !Task.isCancelled, CGPreflightScreenCaptureAccess() else { return nil }
        if let cached = cachedImages[id], Date().timeIntervalSince(cached.0) < 60 { return cached.1 }
        var image: CGImage?
        if let window = captureWindows[id] {
            let configuration = SCStreamConfiguration()
            configuration.width = max(160, min(640, width))
            configuration.height = max(80, min(420, Int(CGFloat(configuration.width) * window.frame.height / max(1, window.frame.width))))
            configuration.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: window)
            image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        }
        guard !Task.isCancelled else { return nil }
        if image == nil { image = DockPreviewNativeWindowIdentity.snapshot(windowID: id, width: width) }
        guard let image else { return nil }
        cachedImages[id] = (Date(), image)
        return image
    }

    func perform(_ action: DockPreviewAction, windowID: UInt, pid: pid_t) async -> Bool {
        guard processID == pid, let window = elements[windowID] else { return false }
        switch action {
        case .activate:
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            _ = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            _ = AXUIElementSetAttributeValue(app, kAXMainWindowAttribute as CFString, window)
            _ = AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window)
            if attribute(window, kAXMinimizedAttribute) as? Bool == true {
                guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success else { return false }
            }
            // Restoring a minimized window is asynchronous in WindowServer.
            for _ in 0..<4 {
                guard !Task.isCancelled, processID == pid, elements[windowID] != nil else { return false }
                if AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success { return true }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return false
        case .minimize:
            let minimized = attribute(window, kAXMinimizedAttribute) as? Bool ?? false
            return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, minimized ? kCFBooleanFalse : kCFBooleanTrue) == .success
        case .move(let destination):
            if attribute(window, "AXFullScreen") as? Bool == true {
                guard AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse) == .success else { return false }
                for _ in 0..<20 {
                    if attribute(window, "AXFullScreen") as? Bool != true { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                guard attribute(window, "AXFullScreen") as? Bool != true else { return false }
            }
            if attribute(window, kAXMinimizedAttribute) as? Bool == true {
                _ = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            guard let current = rect(window) else { return false }
            var size = CGSize(width: min(current.width, destination.width), height: min(current.height, destination.height))
            var point = CGPoint(x: destination.midX - size.width / 2, y: destination.midY - size.height / 2)
            guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return false }
            let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
            return moved == .success
        case .close:
            guard let close = attribute(window, kAXCloseButtonAttribute), CFGetTypeID(close) == AXUIElementGetTypeID() else { return false }
            return AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) == .success
        }
    }

    func invalidateThumbnails() { cachedImages.removeAll() }

    func clear() {
        elements.removeAll(); captureWindows.removeAll(); cachedImages.removeAll(); knownTitles.removeAll(); processID = nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }
    private func rect(_ element: AXUIElement) -> CGRect? {
        guard let origin = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute),
              CFGetTypeID(origin) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(origin as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
