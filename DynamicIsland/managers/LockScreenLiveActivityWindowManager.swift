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

import AppKit
import Defaults
import SkyLightWindow
import SwiftUI
import QuartzCore

@MainActor
class LockScreenLiveActivityWindowManager {
    static let shared = LockScreenLiveActivityWindowManager()

    private var window: NSWindow?
    private var hasDelegated = false
    private var hideTask: Task<Void, Never>?
    private var hostingView: NSHostingView<LockScreenLiveActivityOverlay>?
    private let overlayModel = LockScreenLiveActivityOverlayModel()
    private let overlayAnimator = LockIconAnimator(initiallyLocked: LockScreenManager.shared.isLocked)
    private weak var viewModel: DynamicIslandViewModel?
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var currentNotchSize: CGSize?

    /// Whether the target screen uses Dynamic Island (pill) mode.
    private var isDynamicIslandMode: Bool {
        isDynamicIslandModeForScreen(lockContext()?.screen)
    }

    private func isDynamicIslandModeForScreen(_ screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return shouldUseDynamicIslandMode(for: screen.localizedName)
    }

    private init() {
        registerScreenChangeObservers()
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    private func windowSize(for notchSize: CGSize) -> CGSize {
        let indicatorWidth = max(0, notchSize.height - 12)
        let horizontalPadding = isDynamicIslandMode ? 8 : cornerRadiusInsets.closed.bottom
        let topOffset: CGFloat = isDynamicIslandMode ? dynamicIslandTopOffset : 0

        let totalWidth = notchSize.width + (indicatorWidth * 2) + (horizontalPadding * 2)

        return CGSize(width: totalWidth, height: notchSize.height + topOffset)
    }

    private func frame(for windowSize: CGSize, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let originX = screenFrame.origin.x + (screenFrame.width / 2) - (windowSize.width / 2)
        let originY = screenFrame.origin.y + screenFrame.height - windowSize.height

        return NSRect(x: originX, y: originY, width: windowSize.width, height: windowSize.height)
    }

    private func ensureWindow(windowSize: CGSize, screen: NSScreen) -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: frame(for: windowSize, on: screen),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = false
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.alphaValue = 0
        window.animationBehavior = .none

        ScreenCaptureVisibilityManager.shared.register(window, scope: .entireInterface)

        self.window = window
        self.hasDelegated = false
        return window
    }

    private func lockContext() -> (notchSize: CGSize, screen: NSScreen)? {
        guard let screen = LockScreenDisplayContextProvider.shared.contextSnapshot()?.screen ?? NSScreen.main else {
            print("[\(timestamp())] LockScreenLiveActivityWindowManager: no main screen available")
            return nil
        }

        guard let viewModel else {
            print("[\(timestamp())] LockScreenLiveActivityWindowManager: no view model configured")
            return nil
        }

        var notchSize = viewModel.closedNotchSize
        if notchSize.width <= 0 || notchSize.height <= 0 {
            notchSize = getClosedNotchSize(screen: screen.localizedName)
        }

        return (notchSize, screen)
    }

    private func registerScreenChangeObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenGeometryChange(reason: "screen-parameters")
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenGeometryChange(reason: "screens-did-wake")
        }
        workspaceObservers = [wakeObserver]
    }

    private func handleScreenGeometryChange(reason: String) {
        guard let window else { return }
        guard window.isVisible || window.alphaValue > 0.01 else { return }
        guard let context = lockContext() else { return }

        let windowSize = windowSize(for: context.notchSize)
        let targetFrame = frame(for: windowSize, on: context.screen)
        if window.frame != targetFrame {
            window.setFrame(targetFrame, display: true)
        }

        if let hostingView {
            hostingView.frame = CGRect(origin: .zero, size: targetFrame.size)
            hostingView.rootView = LockScreenLiveActivityOverlay(model: overlayModel, animator: overlayAnimator, notchSize: context.notchSize, isDynamicIslandMode: isDynamicIslandMode)
        }

        currentNotchSize = context.notchSize

        print("[\(timestamp())] LockScreenLiveActivityWindowManager: realigned window due to \(reason)")
    }

    private func present(notchSize: CGSize, on screen: NSScreen) {
        guard Defaults[.enableLockScreenLiveActivity] else {
            hideImmediately()
            return
        }

        let windowSize = windowSize(for: notchSize)
        let window = ensureWindow(windowSize: windowSize, screen: screen)
        let targetFrame = frame(for: windowSize, on: screen)
        window.setFrame(targetFrame, display: true)

        let overlayView = LockScreenLiveActivityOverlay(model: overlayModel, animator: overlayAnimator, notchSize: notchSize, isDynamicIslandMode: isDynamicIslandMode)

        if let hostingView {
            hostingView.rootView = overlayView
            hostingView.frame = CGRect(origin: .zero, size: targetFrame.size)
        } else {
            let view = NSHostingView(rootView: overlayView)
            view.frame = CGRect(origin: .zero, size: targetFrame.size)
            hostingView = view
            window.contentView = view
        }

        if window.contentView !== hostingView {
            window.contentView = hostingView
        }

        window.displayIfNeeded()

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        window.orderFrontRegardless()
        window.alphaValue = 1

        currentNotchSize = notchSize
    }

    func showLocked() {
        hideTask?.cancel()
        guard let context = lockContext() else { return }

        let collapsedScale = LockScreenLiveActivityOverlay.collapsedScale(for: context.notchSize, isDynamicIslandMode: isDynamicIslandMode)

        overlayAnimator.update(isLocked: true)
        overlayModel.scale = collapsedScale
        overlayModel.opacity = 0

        present(notchSize: context.notchSize, on: context.screen)

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                self.overlayModel.scale = 1
            }
            withAnimation(.easeOut(duration: 0.18)) {
                self.overlayModel.opacity = 1
            }
        }

        print("[\(timestamp())] LockScreenLiveActivityWindowManager: showing locked state")
    }

    func showUnlockAndScheduleHide() {
        hideTask?.cancel()
        guard let context = lockContext() else { return }

        overlayModel.scale = 1
        overlayModel.opacity = 1

        present(notchSize: context.notchSize, on: context.screen)

        overlayAnimator.update(isLocked: false)

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LockScreenAnimationTimings.unlockCollapse))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.hideWithAnimation()
            }
        }
    }

    func hideImmediately() {
        hideTask?.cancel()
        hideTask = nil

        hideWithAnimation()
    }

    private func hideWithAnimation() {
        guard let window else { return }

        let targetScale: CGFloat
        if let notchSize = currentNotchSize {
            targetScale = LockScreenLiveActivityOverlay.collapsedScale(for: notchSize, isDynamicIslandMode: isDynamicIslandMode)
        } else {
            targetScale = 0.7
        }

        withAnimation(.smooth(duration: LockScreenAnimationTimings.unlockCollapse)) {
            overlayModel.opacity = 0
            overlayModel.scale = targetScale
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = LockScreenAnimationTimings.unlockCollapse
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + LockScreenAnimationTimings.unlockCollapse + 0.02) {
            window.orderOut(nil)
            self.currentNotchSize = nil
        }

        print("[\(timestamp())] LockScreenLiveActivityWindowManager: HUD hidden")
    }

    func configure(viewModel: DynamicIslandViewModel) {
        self.viewModel = viewModel
    }
}
