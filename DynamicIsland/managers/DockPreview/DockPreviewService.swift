/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */

import AppKit
import ApplicationServices
import ScreenCaptureKit

/// All potentially slow Accessibility IPC and image capture stay off the main actor.
actor DockPreviewService {
    private var elements: [UInt: AXUIElement] = [:]
    private var captureWindows: [CGWindowID: SCWindow] = [:]
    private var cachedImages: [CGWindowID: (Date, CGImage)] = [:]
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
        let all = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        var shareable: [SCWindow] = []
        if allowCapture, let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) {
            shareable = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
        }
        guard !Task.isCancelled else { return [] }
        elements.removeAll()
        processID = pid
        captureWindows = Dictionary(shareable.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        var usedCaptures = Set<CGWindowID>()
        var result: [DockPreviewWindow] = []
        for element in all {
            guard !Task.isCancelled else { return [] }
            AXUIElementSetMessagingTimeout(element, 0.15)
            guard string(element, kAXRoleAttribute) == kAXWindowRole,
                  let frame = rect(element), frame.width > 40, frame.height > 30 else { continue }
            let minimized = attribute(element, kAXMinimizedAttribute) as? Bool ?? false
            if minimized && !includeMinimized { continue }
            let title = string(element, kAXTitleAttribute) ?? "Untitled window"
            let match = shareable.filter { !usedCaptures.contains($0.windowID) }.min {
                DockPreviewGeometry.captureMatchScore(title: title, frame: frame, candidateTitle: $0.title, candidateFrame: $0.frame)
                    < DockPreviewGeometry.captureMatchScore(title: title, frame: frame, candidateTitle: $1.title, candidateFrame: $1.frame)
            }
            let capture = match.flatMap { candidate -> CGWindowID? in
                let score = DockPreviewGeometry.captureMatchScore(title: title, frame: frame, candidateTitle: candidate.title, candidateFrame: candidate.frame)
                return score < 80 ? candidate.windowID : nil
            }
            if let capture { usedCaptures.insert(capture) }
            let id = UInt(CFHash(element))
            elements[id] = element
            var settable = DarwinBoolean(false)
            let canMinimize = AXUIElementIsAttributeSettable(element, kAXMinimizedAttribute as CFString, &settable) == .success && settable.boolValue
            result.append(DockPreviewWindow(id: id, title: title.isEmpty ? "Untitled window" : title, frame: frame,
                isMinimized: minimized, canClose: attribute(element, kAXCloseButtonAttribute) != nil,
                canMinimize: canMinimize, captureID: capture))
            if result.count >= max(1, min(12, limit)) { break }
        }
        cachedImages = cachedImages.filter { captureWindows[$0.key] != nil }
        return result
    }

    func thumbnail(for id: CGWindowID, width: Int) async -> CGImage? {
        guard let window = captureWindows[id], !Task.isCancelled else { return nil }
        if let cached = cachedImages[id], Date().timeIntervalSince(cached.0) < 2 { return cached.1 }
        let configuration = SCStreamConfiguration()
        configuration.width = max(160, min(640, width))
        configuration.height = max(80, min(420, Int(CGFloat(configuration.width) * window.frame.height / max(1, window.frame.width))))
        configuration.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration), !Task.isCancelled else { return nil }
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
        case .close:
            guard let close = attribute(window, kAXCloseButtonAttribute), CFGetTypeID(close) == AXUIElementGetTypeID() else { return false }
            return AXUIElementPerformAction(close as! AXUIElement, kAXPressAction as CFString) == .success
        }
    }

    func clear() {
        elements.removeAll(); captureWindows.removeAll(); cachedImages.removeAll(); processID = nil
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
