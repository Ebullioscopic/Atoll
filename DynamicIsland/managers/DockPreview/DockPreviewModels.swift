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
}

struct DockPreviewSession: Identifiable {
    let id: UUID
    let applicationURL: URL
    let applicationName: String
    let processID: pid_t?
    let screenName: String
    var windows: [DockPreviewWindow]
}

enum DockPreviewAction: Sendable { case activate, minimize, close }

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
        return distance + (candidateTitle == title ? 0 : 1000)
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
