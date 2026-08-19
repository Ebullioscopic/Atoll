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

struct MusicControlWindowMetrics: Equatable {
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let rightWingWidth: CGFloat
    let cornerRadius: CGFloat
    let spacing: CGFloat
    let contentRevision: AnyHashable
}

@MainActor
final class MusicControlWindowManager {
    static let shared = MusicControlWindowManager()

    private var window: NSPanel?
    private var hostingView: NSHostingView<MusicControlOverlay>?
    private var hasDelegated = false
    private var lastMetrics: MusicControlWindowMetrics?
    private var measuredContentSize: CGSize?
    private var measuredNotchHeight: CGFloat?
    private var measuredCornerRadius: CGFloat?
    private var measuredContentRevision: AnyHashable?
    private var frameUpdateGeneration: UInt = 0
    private var isHiding = false

    private init() {}

    @discardableResult
    func present(using viewModel: DynamicIslandViewModel, metrics: MusicControlWindowMetrics) -> Bool {
        guard let screen = resolveScreen(from: viewModel) else { return false }
        guard viewModel.effectiveClosedNotchHeight > 0, viewModel.closedNotchSize.width > 0 else {
            hide()
            return false
        }

        let overlay = MusicControlOverlay(
            notchHeight: metrics.notchHeight,
            cornerRadius: metrics.cornerRadius
        )
        let hosting = ensureHostingView(with: overlay)
        let fittingSize = measuredSize(for: hosting)
        hosting.frame = NSRect(origin: .zero, size: fittingSize)
        measuredContentSize = fittingSize
        measuredNotchHeight = metrics.notchHeight
        measuredCornerRadius = metrics.cornerRadius
        measuredContentRevision = metrics.contentRevision

        let window = ensureWindow(on: screen)
        if window.contentView !== hosting {
            window.contentView = hosting
        }

        let targetFrame = frame(for: fittingSize, screen: screen, metrics: metrics)

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        applyFrame(targetFrame, to: window, metrics: metrics, animated: true)
        return true
    }

    private func applyFrame(
        _ targetFrame: NSRect,
        to window: NSPanel,
        metrics: MusicControlWindowMetrics,
        animated: Bool
    ) {
        frameUpdateGeneration &+= 1
        let generation = frameUpdateGeneration
        isHiding = false
        lastMetrics = metrics

        if window.alphaValue > 0.01, window.frame == targetFrame {
            window.orderFrontRegardless()
            window.alphaValue = 1
            return
        }

        if !animated {
            updateFrameWithoutLayout(targetFrame, on: window)
            window.orderFrontRegardless()
            window.alphaValue = 1
            return
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
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard self?.frameUpdateGeneration == generation else { return }
                    window.setFrame(targetFrame, display: false)
                }
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            } completionHandler: { [weak self] in
                Task { @MainActor [weak self] in
                    guard self?.frameUpdateGeneration == generation else { return }
                    window.setFrame(targetFrame, display: false)
                }
            }
            window.orderFrontRegardless()
            window.alphaValue = 1
        }
    }

    /// Hover updates only move the panel. Updating the origin avoids asking
    /// AppKit to reconfigure the content size and its backing surface.
    private func updateFrameWithoutLayout(_ targetFrame: NSRect, on window: NSPanel) {
        guard window.frame != targetFrame else { return }
        if window.frame.size == targetFrame.size {
            window.setFrameOrigin(targetFrame.origin)
        } else {
            window.setFrame(targetFrame, display: true)
        }
    }

    @discardableResult
    func refresh(using viewModel: DynamicIslandViewModel, metrics: MusicControlWindowMetrics) -> Bool {
        guard let window else {
            return present(using: viewModel, metrics: metrics)
        }

        if let lastMetrics,
           lastMetrics == metrics,
           !isHiding,
           window.alphaValue > 0.01,
           window.isVisible,
           let hostingView,
           window.contentView === hostingView {
            return true
        }

        // Hover changes placement metrics, but not the overlay's intrinsic size.
        // Reuse the cached measurement to avoid rebuilding SwiftUI and fittingSize.
        if let measuredContentSize,
           measuredNotchHeight == metrics.notchHeight,
           measuredCornerRadius == metrics.cornerRadius,
           measuredContentRevision == metrics.contentRevision,
           let hostingView,
           window.contentView === hostingView,
           let screen = resolveScreen(from: viewModel) {
            let targetFrame = frame(for: measuredContentSize, screen: screen, metrics: metrics)
            applyFrame(targetFrame, to: window, metrics: metrics, animated: false)
            return true
        }

        return present(using: viewModel, metrics: metrics)
    }

    func hide(animated: Bool = true, tearDown: Bool = true) {
        guard let window else { return }

        frameUpdateGeneration &+= 1
        let generation = frameUpdateGeneration
        isHiding = animated && window.alphaValue > 0.01

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
            Task { @MainActor [weak self] in
                guard self?.frameUpdateGeneration == generation else { return }
                window.setFrame(originalFrame, display: false)
                window.orderOut(nil)
                window.alphaValue = 0
                if tearDown {
                    self?.tearDownWindowResources(using: window)
                }
            }
        }
    }

    private func tearDownWindowResources(using window: NSPanel? = nil) {
        frameUpdateGeneration &+= 1
        let targetWindow = window ?? self.window
        targetWindow?.contentView = nil
        targetWindow?.orderOut(nil)
        hostingView = nil
        lastMetrics = nil
        measuredContentSize = nil
        measuredNotchHeight = nil
        measuredCornerRadius = nil
        measuredContentRevision = nil
        isHiding = false
        self.window = nil
        hasDelegated = false
    }

    private func ensureHostingView(with overlay: MusicControlOverlay) -> NSHostingView<MusicControlOverlay> {
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
            contentRect: NSRect(x: screen.frame.midX, y: screen.frame.midY, width: 240, height: 68),
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

    private func measuredSize(for hosting: NSHostingView<MusicControlOverlay>) -> CGSize {
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

    private func frame(for size: CGSize, screen: NSScreen, metrics: MusicControlWindowMetrics) -> NSRect {
        FlyoutFrameCalculator.frame(
            for: size,
            screenFrame: screen.frame,
            notchWidth: metrics.notchWidth,
            rightWingWidth: metrics.rightWingWidth,
            spacing: metrics.spacing
        )
    }

    private func initialFrame(for targetFrame: NSRect, metrics: MusicControlWindowMetrics) -> NSRect {
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
