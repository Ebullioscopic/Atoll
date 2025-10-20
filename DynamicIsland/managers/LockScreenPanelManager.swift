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

@MainActor
class LockScreenPanelManager {
    static let shared = LockScreenPanelManager()

    private var panelWindow: NSWindow?
    private var hasDelegated = false
    private var collapsedFrame: NSRect?

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
            // Keep the music panel below system lock-screen UI. Use one level below CGShieldingWindowLevel.
            newWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) - 1)
            newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            newWindow.isMovable = false
            newWindow.hasShadow = false

            panelWindow = newWindow
            window = newWindow
            hasDelegated = false
        }

        window.setFrame(targetFrame, display: true)
        window.contentView = NSHostingView(rootView: LockScreenMusicPanel())

        if !hasDelegated {
            SkyLightOperator.shared.delegateWindow(window)
            hasDelegated = true
        }

        // Keep the window alive and simply order it out on unlock to avoid SkyLight crashes.
        window.orderFrontRegardless()

        print("[\(timestamp())] LockScreenPanelManager: panel visible")
    }

    func updatePanelSize(expanded: Bool, animated: Bool = true) {
        guard let window = panelWindow, let baseFrame = collapsedFrame else {
            return
        }

        // If expanded, expand the panel to cover the entire screen so the music view appears fullscreen.
        if expanded {
            let screenFrame: NSRect
            if let screen = window.screen {
                screenFrame = screen.frame
            } else if let main = NSScreen.main {
                screenFrame = main.frame
            } else {
                // Fallback to baseFrame sized expansion if no screen available
                let targetSize = LockScreenMusicPanel.expandedSize
                let originX = baseFrame.midX - (targetSize.width / 2)
                let originY = baseFrame.origin.y
                let fallback = NSRect(x: originX, y: originY, width: targetSize.width, height: targetSize.height)
                if animated {
                    window.animator().setFrame(fallback, display: true)
                } else {
                    window.setFrame(fallback, display: true)
                }
                return
            }

            if animated {
                window.animator().setFrame(screenFrame, display: true)
            } else {
                window.setFrame(screenFrame, display: true)
            }
        } else {
            // Collapse back to the stored collapsed frame
            if animated {
                window.animator().setFrame(baseFrame, display: true)
            } else {
                window.setFrame(baseFrame, display: true)
            }
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
