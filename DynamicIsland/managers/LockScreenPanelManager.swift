//
//  LockScreenPanelManager.swift
//  DynamicIsland
//
//  Manages the lock screen music panel window.
//

import SwiftUI
import AppKit
import SkyLightWindow
import Defaults
import QuartzCore

@MainActor
class LockScreenPanelManager {
    static let shared = LockScreenPanelManager()

    private var panelWindow: NSWindow?
    private var hasDelegated = false
    private var collapsedFrame: NSRect?
    private let collapsedPanelCornerRadius: CGFloat = 28
    private let expandedPanelCornerRadius: CGFloat = 52

    private init() {
        print("[\(timestamp())] LockScreenPanelManager: initialized")
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }

    func showPanel() {
        print("[\(timestamp())] LockScreenPanelManager: showPanel")

        guard Defaults[.enableLockScreenMediaWidget] else {
            print("[\(timestamp())] LockScreenPanelManager: widget disabled")
            hidePanel()
            return
        }

        guard let screen = NSScreen.main else {
            print("[\(timestamp())] LockScreenPanelManager: no main screen available")
            return
        }

        let collapsedSize = LockScreenMusicPanel.collapsedSize
        let screenFrame = screen.frame
        let centerX = screenFrame.origin.x + (screenFrame.width / 2)
        let originX = centerX - (collapsedSize.width / 2)
        let originY = screenFrame.origin.y + (screenFrame.height / 2) - collapsedSize.height - 32
        let targetFrame = NSRect(x: originX, y: originY, width: collapsedSize.width, height: collapsedSize.height)
        collapsedFrame = targetFrame

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

            panelWindow = newWindow
            window = newWindow
            hasDelegated = false
        }

        window.setFrame(targetFrame, display: true)
        let hosting = NSHostingView(rootView: LockScreenMusicPanel())
        hosting.frame = NSRect(origin: .zero, size: targetFrame.size)
        window.contentView = hosting

        // Ensure the underlying window content is clipped to rounded corners
        if let content = window.contentView {
            content.wantsLayer = true
            content.layer?.masksToBounds = true
            content.layer?.cornerRadius = collapsedPanelCornerRadius
        }

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        // Keep the window alive and simply order it out on unlock to avoid SkyLight crashes.
        window.orderFrontRegardless()

        print("[\(timestamp())] LockScreenPanelManager: panel visible")
    }

    func updatePanelSize(expanded: Bool, additionalHeight: CGFloat = 0, animated: Bool = true) {
        guard let window = panelWindow, let baseFrame = collapsedFrame else {
            return
        }

        let baseSize = expanded ? LockScreenMusicPanel.expandedSize : LockScreenMusicPanel.collapsedSize
        let targetWidth = baseSize.width
        let targetHeight = baseSize.height + additionalHeight
        let originX = baseFrame.midX - (targetWidth / 2)
        let originY = baseFrame.origin.y
        let targetFrame = NSRect(x: originX, y: originY, width: targetWidth, height: targetHeight)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.45
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(targetFrame, display: true)
            }
        } else {
            window.setFrame(targetFrame, display: true)
        }

        // Update corner radius to match the SwiftUI panel's style
        let targetRadius = expanded ? expandedPanelCornerRadius : collapsedPanelCornerRadius
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.28)
            window.contentView?.layer?.cornerRadius = targetRadius
            CATransaction.commit()
        } else {
            window.contentView?.layer?.cornerRadius = targetRadius
        }
    }

    func hidePanel() {
        print("[\(timestamp())] LockScreenPanelManager: hidePanel")

        guard let window = panelWindow else {
            print("LockScreenPanelManager: no panel to hide")
            return
        }

        window.orderOut(nil)
        window.contentView = nil

        print("[\(timestamp())] LockScreenPanelManager: panel hidden")
    }
}
