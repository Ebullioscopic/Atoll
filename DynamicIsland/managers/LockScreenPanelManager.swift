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

import SwiftUI
import AppKit
import SkyLightWindow
import Defaults
import QuartzCore
import Combine

@MainActor
final class LockScreenPanelAnimator: ObservableObject {
    @Published var isPresented: Bool = false
}

@MainActor
class LockScreenPanelManager {
    static let shared = LockScreenPanelManager()

    private var panelWindow: NSWindow?
    private var hasDelegated = false
    private var collapsedFrame: NSRect?
    private var isPanelExpanded = false
    private var currentAdditionalHeight: CGFloat = 0
    private let collapsedPanelCornerRadius: CGFloat = 28
    private let expandedPanelCornerRadius: CGFloat = 52
    private(set) var latestFrame: NSRect?
    private let panelAnimator = LockScreenPanelAnimator()
    private var hideTask: Task<Void, Never>?
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {
        print("[\(timestamp())] LockScreenPanelManager: initialized")
        registerScreenChangeObservers()
        observeDefaultChanges()
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    private func publishPanelFrame(_ frame: NSRect?) {
        latestFrame = frame

        var userInfo: [AnyHashable: Any] = [:]
        if let frame {
            userInfo["frame"] = NSValue(rect: frame)
        }

        NotificationCenter.default.post(
            name: .atollLockScreenPanelFrameDidChange,
            object: self,
            userInfo: userInfo
        )
    }

    private func registerScreenChangeObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenGeometryChange(reason: "screen-parameters")
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleScreenGeometryChange(reason: "screens-did-wake")
            }
        }

        workspaceObservers = [wakeObserver]
    }

    func showPanel() {
        print("[\(timestamp())] LockScreenPanelManager: showPanel")

        guard Defaults[.enableLockScreenMediaWidget] else {
            print("[\(timestamp())] LockScreenPanelManager: widget disabled")
            hidePanel()
            return
        }

        guard let screen = currentScreen() else {
            print("[\(timestamp())] LockScreenPanelManager: no main screen available")
            return
        }

        let screenFrame = screen.frame
        let defaultCollapsedFrame = collapsedFrame(for: screenFrame)
        let targetFrame = targetFrame(for: screenFrame, panelSize: LockScreenMusicPanel.collapsedSize)
        collapsedFrame = defaultCollapsedFrame
        isPanelExpanded = false
        currentAdditionalHeight = 0

        let window: NSWindow

        if let existingWindow = panelWindow {
            window = existingWindow
        } else {
            let newWindow = NSWindow(
                contentRect: targetFrame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            newWindow.isReleasedWhenClosed = false
            newWindow.isOpaque = false
            newWindow.backgroundColor = .clear
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            newWindow.isMovable = false
            newWindow.hasShadow = false

            ScreenCaptureVisibilityManager.shared.register(newWindow, scope: .entireInterface)

            panelWindow = newWindow
            window = newWindow
            hasDelegated = false
        }

        window.setFrame(targetFrame, display: true)
        publishPanelFrame(targetFrame)
        hideTask?.cancel()
        panelAnimator.isPresented = false
        LockScreenTimerWidgetManager.shared.notifyMusicPanelFrameChanged(animated: false)

        let hosting = NSHostingView(rootView: LockScreenMusicPanel(animator: panelAnimator))
        hosting.frame = NSRect(origin: .zero, size: targetFrame.size)
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting

        // Ensure the underlying window content is clipped to rounded corners
        if let content = window.contentView {
            content.wantsLayer = true
            content.layer?.masksToBounds = true
            content.layer?.cornerRadius = collapsedPanelCornerRadius
            content.layer?.backgroundColor = NSColor.clear.cgColor
        }

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        // Keep the window alive and simply order it out on unlock to avoid SkyLight crashes.
        window.orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panelAnimator.isPresented = true
        }

        print("[\(timestamp())] LockScreenPanelManager: panel visible")
    }

    func updatePanelSize(expanded: Bool, additionalHeight: CGFloat = 0, animated: Bool = true) {
        guard let window = panelWindow, let screen = currentScreen() else {
            return
        }

        let resizeDuration: CFTimeInterval = 0.28

        let baseSize = expanded ? LockScreenMusicPanel.expandedSize : LockScreenMusicPanel.collapsedSize
        let targetFrame = targetFrame(
            for: screen.frame,
            panelSize: CGSize(width: baseSize.width, height: baseSize.height + additionalHeight)
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = resizeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }

        publishPanelFrame(targetFrame)

        LockScreenTimerWidgetManager.shared.notifyMusicPanelFrameChanged(animated: animated)

        // Update corner radius to match the SwiftUI panel's style
        let targetRadius = expanded ? expandedPanelCornerRadius : collapsedPanelCornerRadius
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(resizeDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            window.contentView?.layer?.cornerRadius = targetRadius
            CATransaction.commit()
        } else {
            window.contentView?.layer?.cornerRadius = targetRadius
        }

        isPanelExpanded = expanded
        currentAdditionalHeight = additionalHeight
    }

    func notifyTimerWidgetFrameChanged(animated: Bool) {
        guard panelWindow?.isVisible == true || panelAnimator.isPresented else { return }
        applyOffsetAdjustment(animated: animated)
    }

    func applyOffsetAdjustment(animated: Bool = true) {
        guard let screen = currentScreen() else { return }
        let screenFrame = screen.frame
        let newCollapsed = collapsedFrame(for: screenFrame)
        collapsedFrame = newCollapsed

        guard panelWindow != nil else { return }
        updatePanelSize(expanded: isPanelExpanded, additionalHeight: currentAdditionalHeight, animated: animated)
        LockScreenTimerWidgetManager.shared.notifyMusicPanelFrameChanged(animated: animated)
    }

    func hidePanel() {
        print("[\(timestamp())] LockScreenPanelManager: hidePanel")

        panelAnimator.isPresented = false
        hideTask?.cancel()

        guard let window = panelWindow else {
            print("LockScreenPanelManager: no panel to hide")
            publishPanelFrame(nil)
            return
        }

        hideTask = Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(360))
            guard let self else { return }
            await MainActor.run {
                window?.orderOut(nil)
                window?.contentView = nil
                self.publishPanelFrame(nil)
                print("[\(self.timestamp())] LockScreenPanelManager: panel hidden")
            }
        }
    }

    private func handleScreenGeometryChange(reason: String) {
        guard let window = panelWindow else { return }
        guard window.isVisible || panelAnimator.isPresented else { return }
        guard let screen = currentScreen() else { return }

        let screenFrame = screen.frame
        collapsedFrame = collapsedFrame(for: screenFrame)
        updatePanelSize(expanded: isPanelExpanded, additionalHeight: currentAdditionalHeight, animated: false)
        LockScreenTimerWidgetManager.shared.notifyMusicPanelFrameChanged(animated: false)

        print("[\(timestamp())] LockScreenPanelManager: realigned window due to \(reason)")
    }

    private func observeDefaultChanges() {
        Defaults.publisher(.lockScreenMusicPanelWidth)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyOffsetAdjustment(animated: true)
            }
            .store(in: &cancellables)
    }

    private func targetFrame(for screenFrame: NSRect, panelSize: CGSize) -> NSRect {
        let defaultCollapsedFrame = collapsedFrame(for: screenFrame)

        if FullScreenArtworkWindowManager.shared.isShowingSpotifyCanvasFallback {
            return spotifyCanvasFallbackPanelFrame(
                screenFrame: screenFrame,
                defaultCollapsedFrame: defaultCollapsedFrame,
                panelSize: panelSize
            )
        }

        let originX = defaultCollapsedFrame.midX - (panelSize.width / 2)
        return NSRect(
            x: originX,
            y: defaultCollapsedFrame.origin.y,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func spotifyCanvasFallbackPanelFrame(
        screenFrame: NSRect,
        defaultCollapsedFrame: NSRect,
        panelSize: CGSize
    ) -> NSRect {
        let fullscreenArtworkManager = FullScreenArtworkWindowManager.shared
        let spacing = fullscreenArtworkManager.spotifyCanvasFallbackInterItemSpacing(screenFrame: screenFrame)
        let artworkSide = fullscreenArtworkManager.spotifyCanvasFallbackArtworkSideLength(
            screenFrame: screenFrame,
            panelSize: panelSize
        )
        let totalWidth = artworkSide + spacing + panelSize.width
        let horizontalMargin: CGFloat = 48
        let minGroupOriginX = screenFrame.minX + horizontalMargin
        let maxGroupOriginX = max(screenFrame.maxX - horizontalMargin - totalWidth, minGroupOriginX)
        let groupOriginX = min(
            max(screenFrame.midX - (totalWidth / 2), minGroupOriginX),
            maxGroupOriginX
        )

        let baseCenterY = screenFrame.midY
        let largestHalfHeight = max(artworkSide, panelSize.height) / 2
        let minCenterY = screenFrame.minY + largestHalfHeight + 56
        var maxCenterY = screenFrame.maxY - largestHalfHeight - 84

        let widgetClearance: CGFloat = 20
        if let weatherFrame = LockScreenWeatherPanelManager.shared.latestFrame,
           !weatherFrame.isEmpty {
            let weatherTopConstrainedCenterY = weatherFrame.minY - widgetClearance - largestHalfHeight
            maxCenterY = min(maxCenterY, weatherTopConstrainedCenterY)
        }
        if let timerFrame = LockScreenTimerWidgetPanelManager.shared.latestFrame,
           !timerFrame.isEmpty {
            let timerTopConstrainedCenterY = timerFrame.minY - widgetClearance - largestHalfHeight
            maxCenterY = min(maxCenterY, timerTopConstrainedCenterY)
        }

        let resolvedMaxCenterY = max(maxCenterY, minCenterY)
        let centerY = min(max(baseCenterY, minCenterY), resolvedMaxCenterY)

        return NSRect(
            x: groupOriginX + artworkSide + spacing,
            y: centerY - (panelSize.height / 2),
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func collapsedFrame(for screenFrame: NSRect) -> NSRect {
        let collapsedSize = LockScreenMusicPanel.collapsedSize
        let originX = screenFrame.midX - (collapsedSize.width / 2)
        let baseOriginY = screenFrame.origin.y + (screenFrame.height / 2) - collapsedSize.height - 32
        let defaultLowering: CGFloat = -28
        let userOffset = CGFloat(Defaults[.lockScreenMusicVerticalOffset])
        let clampedOffset = min(max(userOffset, -160), 160)
        var originY = baseOriginY + defaultLowering + clampedOffset

        if let timerFrame = LockScreenTimerWidgetPanelManager.shared.latestFrame {
            let maxAllowedTop = timerFrame.minY - 12
            let maxOriginY = maxAllowedTop - collapsedSize.height
            originY = min(originY, maxOriginY)
        }

        return NSRect(x: originX, y: originY, width: collapsedSize.width, height: collapsedSize.height)
    }

    private func currentScreen() -> NSScreen? {
        LockScreenDisplayContextProvider.shared.contextSnapshot()?.screen ?? NSScreen.main
    }
}

extension Notification.Name {
    static let atollLockScreenPanelFrameDidChange = Notification.Name("atollLockScreenPanelFrameDidChange")
}
