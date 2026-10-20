/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */

import AppKit

struct DockPreviewTarget: Equatable, Sendable {
    let applicationURL: URL
    let frame: CGRect
}

struct DockPreviewWindow: Identifiable, Sendable {
    let id: UInt
    let title: String
    let frame: CGRect
    let isMinimized: Bool
    let canClose: Bool
    let canMinimize: Bool
    let captureID: CGWindowID?
    var isFullScreen = false
    var displayName = ""
}

struct DockPreviewSession: Identifiable {
    let id: UUID
    let applicationURL: URL
    let applicationName: String
    let processID: pid_t?
    let screenName: String
    var windows: [DockPreviewWindow]
}

enum DockPreviewAction: Sendable { case activate, minimize, close, move(CGRect) }

enum DockPreviewGeometry {
    /// Accessibility and ScreenCaptureKit use the primary screen's top-left origin.
    static func quartzPoint(_ point: CGPoint, primaryScreen: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreen.maxY - point.y)
    }

    static func isNearDock(_ point: CGPoint, screen: CGRect, orientation: String) -> Bool {
        guard screen.contains(point) else { return false }
        switch orientation {
        case "left": return point.x - screen.minX <= 180
        case "right": return screen.maxX - point.x <= 180
        default: return point.y - screen.minY <= 180
        }
    }

    static func captureMatchScore(title: String, frame: CGRect, candidateTitle: String?, candidateFrame: CGRect) -> CGFloat {
        let distance = abs(frame.minX - candidateFrame.minX) + abs(frame.minY - candidateFrame.minY)
            + abs(frame.width - candidateFrame.width) + abs(frame.height - candidateFrame.height)
        return distance + (title.isEmpty || candidateTitle?.isEmpty != false || candidateTitle == title ? 0 : 1000)
    }
}

/// Time-based rather than event-count-based, so fast pointer movement never opens a stale app.
struct DockPreviewHoverState {
    private(set) var applicationURL: URL?
    private(set) var enteredAt: TimeInterval = 0
    mutating func update(_ url: URL?, now: TimeInterval) {
        guard applicationURL != url else { return }
        applicationURL = url
        enteredAt = now
    }
    func isReady(now: TimeInterval, delay: TimeInterval) -> Bool {
        applicationURL != nil && now - enteredAt >= max(0.15, min(1.5, delay))
    }
    mutating func reset() { applicationURL = nil; enteredAt = 0 }
}

struct DockPreviewApplication: Identifiable {
    let id: pid_t
    let url: URL
    let name: String
    var windowCount: Int
}

/// Shared shell/card sizing. A page contains whole cards, never half windows.
enum DockPreviewLayout {
    static let gap: CGFloat = 10
    static let panelInset: CGFloat = 12
    static let shellInset: CGFloat = 44
    static func panelWidth(count: Int, cardWidth: CGFloat, maximum: CGFloat = 760) -> CGFloat {
        let visible = CGFloat(min(4, max(1, count)))
        return min(maximum, max(360, visible * cardWidth + max(0, visible - 1) * gap + 2 * (shellInset + panelInset)))
    }
    static func cardsPerPage(available: CGFloat, cardWidth: CGFloat) -> Int {
        max(1, min(4, Int((max(0, available) + gap) / (cardWidth + gap))))
    }
    static func fittedCardWidth(available: CGFloat, preferred: CGFloat) -> CGFloat { min(preferred, max(1, available)) }
}

/// Full-screen video surfaces often omit AXTitle during a Space transition.
enum DockPreviewWindowTitle {
    static func resolve(accessibility: String?, capture: String?, document: String?, previous: String?, application: String) -> String {
        for title in [accessibility, capture, document, previous] {
            if let value = title?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty, value != "Untitled window" { return value }
        }
        return application
    }
}
