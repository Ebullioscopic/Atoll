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
import SwiftUI
import SkyLightWindow
import Defaults
import QuartzCore
import Combine

@MainActor
final class LockScreenWeatherPanelManager {
    static let shared = LockScreenWeatherPanelManager()

    private var window: NSWindow?
    private var hostingView: NSHostingView<LockScreenWeatherWidget>?
    private var hasDelegated = false
    private(set) var latestFrame: NSRect?
    private var lastSnapshot: LockScreenWeatherSnapshot?
    private var lastContentSize: CGSize?
    private var lastInlineBaselineHeight: CGFloat = 0
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        registerScreenChangeObservers()
    }

    func show(with snapshot: LockScreenWeatherSnapshot) {
        render(snapshot: snapshot, makeVisible: true)
    }

    func update(with snapshot: LockScreenWeatherSnapshot) {
        render(snapshot: snapshot, makeVisible: false)
    }

    func hide() {
        guard let window else { return }
        window.alphaValue = 0
        window.orderOut(nil)
        window.contentView = nil
        window.alphaValue = 1
        latestFrame = nil
        lastSnapshot = nil
        lastContentSize = nil
    }

    private func render(snapshot: LockScreenWeatherSnapshot, makeVisible: Bool) {
        guard let screen = currentScreen() else { return }
        if !makeVisible, window == nil {
            return
        }

        let window = ensureWindow()

        // Reuse a single cached hosting view and only swap its rootView. Recreating
        // the NSHostingView on every update remounted the SwiftUI tree, re-firing
        // `.onAppear` (timer/observer re-setup + forced calendar reload). Assigning
        // `rootView` performs a lightweight diff instead.
        let hosting = ensureHostingView(in: window, snapshot: snapshot)
        hosting.rootView = LockScreenWeatherWidget(snapshot: snapshot)

        // `fittingSize` forces a synchronous layout pass. The window frame is only
        // ever driven by snapshot changes here (internal widget ticks relayout
        // within the existing bounds), so only re-measure when the snapshot changes.
        let fittingSize: CGSize
        if let cachedSize = lastContentSize, snapshot == lastSnapshot {
            fittingSize = cachedSize
        } else {
            fittingSize = hosting.fittingSize
            if snapshot.widgetStyle == .inline {
                lastInlineBaselineHeight = max(lastInlineBaselineHeight, fittingSize.height)
            }
        }
        hosting.frame = NSRect(origin: .zero, size: fittingSize)

        let targetFrame = frame(for: fittingSize, snapshot: snapshot, on: screen)
        window.setFrame(targetFrame, display: true)
        latestFrame = targetFrame
        lastSnapshot = snapshot
        lastContentSize = fittingSize

        if makeVisible {
            window.orderFrontRegardless()
        }
    }

    private func ensureHostingView(in window: NSWindow, snapshot: LockScreenWeatherSnapshot) -> NSHostingView<LockScreenWeatherWidget> {
        if let hostingView {
            if window.contentView !== hostingView {
                window.contentView = hostingView
            }
            return hostingView
        }

        let view = NSHostingView(rootView: LockScreenWeatherWidget(snapshot: snapshot))
        hostingView = view
        window.contentView = view
        return view
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let frame = NSRect(origin: .zero, size: CGSize(width: 110, height: 40))
        let newWindow = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newWindow.isReleasedWhenClosed = false
        newWindow.isOpaque = false
        newWindow.backgroundColor = .clear
        newWindow.hasShadow = false
        newWindow.ignoresMouseEvents = true
        newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)

        window = newWindow
        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(newWindow)
            hasDelegated = true
        }
        
        SiriVisibilityMonitor.shared.autohide(newWindow, cancellables: &cancellables)
        
        return newWindow
    }

    private func frame(for size: CGSize, snapshot: LockScreenWeatherSnapshot, on screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let originX = screenFrame.midX - (size.width / 2)
        let verticalOffset = screenFrame.height * 0.15
        let isCircular = snapshot.widgetStyle == .circular
        let topMargin: CGFloat = isCircular ? 120 : 48
        let inlineBaselineHeight: CGFloat = max(lastInlineBaselineHeight, 80)
        let positionHeight = snapshot.widgetStyle == .inline
            ? max(size.height, inlineBaselineHeight)
            : size.height
        let maxY = screenFrame.maxY - positionHeight - topMargin
        let baseY = min(maxY, screenFrame.midY + verticalOffset)
        let loweredY = baseY - 36

        let inlineLift: CGFloat = snapshot.widgetStyle == .inline ? 44 : 0
        let circularDrop: CGFloat = isCircular ? 28 : 0
        let sizeDropHeight = positionHeight
        let sizeDrop = max(0, sizeDropHeight - 80) * 0.35
        let userOffset = CGFloat(Defaults[.lockScreenWeatherVerticalOffset])
        let clampedOffset = min(max(userOffset, -160), 160)
        let adjustedY = loweredY + inlineLift + clampedOffset - circularDrop - sizeDrop
        let upperClampedY = min(maxY, adjustedY)
        let clampedY = max(screenFrame.minY + 80, upperClampedY)
        return NSRect(x: originX, y: clampedY, width: size.width, height: size.height)
    }

    func refreshPositionForOffsets(animated: Bool = true) {
        guard let window, let snapshot = lastSnapshot else { return }
        guard let screen = currentScreen() else { return }
        let size = lastContentSize ?? window.frame.size
        let targetFrame = frame(for: size, snapshot: snapshot, on: screen)
        latestFrame = targetFrame

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }
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
        guard window?.isVisible == true else { return }
        refreshPositionForOffsets(animated: false)
        print("LockScreenWeatherPanelManager: realigned window due to \(reason)")
    }

    private func currentScreen() -> NSScreen? {
        LockScreenDisplayContextProvider.shared.contextSnapshot()?.screen ?? NSScreen.main
    }
}
