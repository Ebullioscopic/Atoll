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
import QuartzCore
import SkyLightWindow
import SwiftUI

@MainActor
final class QuickTimerWindowManager {
    static let shared = QuickTimerWindowManager()

    private var window: NSPanel?
    private var hostingView: NSHostingView<QuickTimerOverlay>?
    private var hasDelegated = false
    private var lastMetrics: TimerControlWindowMetrics?
    private var autoHideTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var isPointerInside = false
    private(set) var isVisible = false

    private init() {}

    @discardableResult
    func present(
        using viewModel: DynamicIslandViewModel,
        metrics: TimerControlWindowMetrics,
        onStarted: (() -> Void)? = nil
    ) -> Bool {
        guard !LockScreenManager.shared.currentLockStatus else {
            hide(animated: false)
            return false
        }
        guard let screen = resolveScreen(from: viewModel) else { return false }
        guard viewModel.effectiveClosedNotchHeight > 0, viewModel.closedNotchSize.width > 0 else {
            hide()
            return false
        }

        collapseTask?.cancel()
        collapseTask = nil
        isPointerInside = false

        let presentation = QuickTimerPresentationState.shared
        presentation.reset()

        let overlay = QuickTimerOverlay(
            notchHeight: metrics.notchHeight,
            cornerRadius: metrics.cornerRadius,
            appearToken: UUID(),
            onStarted: { [weak self] in
                self?.isVisible = false
                onStarted?()
            }
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

        window.setFrame(targetFrame, display: true)
        window.alphaValue = 1
        window.orderFrontRegardless()

        isVisible = true
        scheduleAutoHide()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))
            guard self.isVisible else { return }
            presentation.expand()
        }

        return true
    }

    func hide(animated: Bool = true, tearDown: Bool = true) {
        cancelAutoHide()
        collapseTask?.cancel()
        collapseTask = nil
        isVisible = false
        isPointerInside = false

        guard let window else {
            QuickTimerPresentationState.shared.reset()
            return
        }

        guard animated, window.alphaValue > 0.01 else {
            QuickTimerPresentationState.shared.reset()
            window.orderOut(nil)
            window.alphaValue = 0
            if tearDown {
                tearDownWindowResources(using: window)
            }
            return
        }

        QuickTimerPresentationState.shared.collapse()

        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(ClosedNotchSatelliteChrome.morphDuration))
            guard !Task.isCancelled else { return }
            window.orderOut(nil)
            window.alphaValue = 0
            if tearDown {
                self.tearDownWindowResources(using: window)
            }
        }
    }

    func notePointerHover(_ hovering: Bool) {
        guard isVisible else { return }
        isPointerInside = hovering
        if hovering {
            cancelAutoHide()
        } else {
            scheduleAutoHide()
        }
    }

    private func scheduleAutoHide() {
        cancelAutoHide()
        autoHideTask = Task { @MainActor in
            // Wait for the open morph, then the idle delay.
            try? await Task.sleep(for: .seconds(ClosedNotchSatelliteChrome.morphDuration))
            guard !Task.isCancelled, self.isVisible, !self.isPointerInside else { return }
            try? await Task.sleep(for: .seconds(ClosedNotchSatelliteChrome.autoHideDelay))
            guard !Task.isCancelled, self.isVisible, !self.isPointerInside else { return }
            hide(animated: true)
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    private func tearDownWindowResources(using window: NSPanel? = nil) {
        QuickTimerPresentationState.shared.reset()
        let targetWindow = window ?? self.window
        targetWindow?.contentView = nil
        targetWindow?.orderOut(nil)
        hostingView = nil
        lastMetrics = nil
        self.window = nil
        hasDelegated = false
        isVisible = false
    }

    private func ensureHostingView(with overlay: QuickTimerOverlay) -> NSHostingView<QuickTimerOverlay> {
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

    private func measuredSize(for hosting: NSHostingView<QuickTimerOverlay>) -> CGSize {
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

    private func frame(
        for size: CGSize,
        viewModel: DynamicIslandViewModel,
        screen: NSScreen,
        metrics: TimerControlWindowMetrics
    ) -> NSRect {
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
}

#endif
