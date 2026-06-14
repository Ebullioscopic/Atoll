/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

#if os(macOS)
import AppKit
import SwiftUI
import SkyLightWindow
import QuartzCore

struct TimerControlWindowMetrics: Equatable {
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let rightWingWidth: CGFloat
    let cornerRadius: CGFloat
    let spacing: CGFloat
}

@MainActor
final class TimerControlWindowManager {
    static let shared = TimerControlWindowManager()

    private var window: NSPanel?
    private var hostingView: NSHostingView<TimerControlOverlay>?
    private var hasDelegated = false
    private var lastMetrics: TimerControlWindowMetrics?

    private init() {}

    @discardableResult
    func present(using viewModel: DynamicIslandViewModel, metrics: TimerControlWindowMetrics) -> Bool {
        guard !LockScreenManager.shared.currentLockStatus else {
            hide(animated: false)
            return false
        }
        guard let screen = resolveScreen(from: viewModel) else { return false }
        guard viewModel.effectiveClosedNotchHeight > 0, viewModel.closedNotchSize.width > 0 else {
            hide()
            return false
        }

        let overlay = TimerControlOverlay(
            notchHeight: metrics.notchHeight,
            cornerRadius: metrics.cornerRadius
        )
        let hosting = ensureHostingView(with: overlay)
        let fittingSize = measuredSize(for: hosting)
        hosting.frame = NSRect(origin: .zero, size: fittingSize)

        let window = ensureWindow(on: screen)
        if window.contentView !== hosting {
            window.contentView = hosting
        }

        let targetFrame = frame(for: fittingSize, viewModel: viewModel, screen: screen, metrics: metrics)
        lastMetrics = metrics

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        if window.alphaValue <= 0.01 {
            let startFrame = initialFrame(for: targetFrame, metrics: metrics)
            window.setFrame(startFrame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(targetFrame, display: true)
                window.animator().alphaValue = 1
            } completionHandler: {
                window.setFrame(targetFrame, display: false)
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            } completionHandler: {
                window.setFrame(targetFrame, display: false)
            }
            window.orderFrontRegardless()
            window.alphaValue = 1
        }

        return true
    }

    @discardableResult
    func refresh(using viewModel: DynamicIslandViewModel, metrics: TimerControlWindowMetrics) -> Bool {
        guard window != nil else {
            return present(using: viewModel, metrics: metrics)
        }

        if let lastMetrics, lastMetrics == metrics {
            return true
        }

        return present(using: viewModel, metrics: metrics)
    }

    func hide(animated: Bool = true, tearDown: Bool = true) {
        guard let window else { return }

        guard animated, window.alphaValue > 0.01 else {
            window.orderOut(nil)
            window.alphaValue = 0
            if tearDown {
                tearDownWindowResources(using: window)
            }
            return
        }

        let retreatFrame = notchRetreatFrame(from: window.frame)
        let originalFrame = window.frame

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(retreatFrame, display: true)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            window.setFrame(originalFrame, display: false)
            window.orderOut(nil)
            window.alphaValue = 0
            if tearDown {
                self?.tearDownWindowResources(using: window)
            }
        }
    }

    private func tearDownWindowResources(using window: NSPanel? = nil) {
        let targetWindow = window ?? self.window
        targetWindow?.contentView = nil
        targetWindow?.orderOut(nil)
        hostingView = nil
        lastMetrics = nil
        self.window = nil
        hasDelegated = false
    }

    private func ensureHostingView(with overlay: TimerControlOverlay) -> NSHostingView<TimerControlOverlay> {
        if let hostingView {
            hostingView.rootView = overlay
            return hostingView
        }
        let view = NSHostingView(rootView: overlay)
        hostingView = view
        return view
    }

    private func ensureWindow(on screen: NSScreen) -> NSPanel {
        if let window {
            return window
        }

        let window = NSPanel(
            contentRect: NSRect(x: screen.frame.midX, y: screen.frame.midY, width: 220, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.isMovable = false
        window.alphaValue = 0

        ScreenCaptureVisibilityManager.shared.register(window, scope: .entireInterface)

        self.window = window
        self.hasDelegated = false
        return window
    }

    private func measuredSize(for hosting: NSHostingView<TimerControlOverlay>) -> CGSize {
        let size = hosting.fittingSize
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func resolveScreen(from viewModel: DynamicIslandViewModel) -> NSScreen? {
        if let screenName = viewModel.screen,
           let targetScreen = NSScreen.screens.first(where: { $0.localizedName == screenName }) {
            return targetScreen
        }
        return NSScreen.main
    }

    private func frame(for size: CGSize, viewModel: DynamicIslandViewModel, screen: NSScreen, metrics: TimerControlWindowMetrics) -> NSRect {
        let screenFrame = screen.frame
        let notchOriginX = screenFrame.midX - (metrics.notchWidth / 2)
        let originY = screenFrame.maxY - size.height

        let rightEdge = notchOriginX + metrics.notchWidth + metrics.rightWingWidth
        let rawOriginX = rightEdge + metrics.spacing

        let clampedOriginX = max(screenFrame.minX + 8, min(rawOriginX, screenFrame.maxX - size.width - 8))

        return NSRect(
            x: clampedOriginX.rounded(),
            y: originY.rounded(),
            width: size.width.rounded(),
            height: size.height.rounded()
        )
    }

    private func initialFrame(for targetFrame: NSRect, metrics: TimerControlWindowMetrics) -> NSRect {
        var frame = targetFrame
        let notchRightEdge = targetFrame.minX - metrics.spacing
        frame.origin.x = notchRightEdge - targetFrame.width
        return frame
    }

    private func notchRetreatFrame(from currentFrame: NSRect) -> NSRect {
        guard let metrics = lastMetrics else {
            return currentFrame.offsetBy(dx: -currentFrame.width * 0.75, dy: 0)
        }

        let notchRightEdge = currentFrame.minX - metrics.spacing
        var frame = currentFrame
        frame.origin.x = notchRightEdge - currentFrame.width
        return frame
    }
}

#endif
