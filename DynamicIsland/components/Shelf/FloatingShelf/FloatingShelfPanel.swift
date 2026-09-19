/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Licensed under GNU GPLv3.
 */

import AppKit
import SwiftUI


/// Custom hosting view allowing first-mouse clicks and window dragging on background clicks.
final class FloatingShelfHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        true
    }
}

/// An NSPanel that displays the floating companion shelf near the cursor.
/// Styled with a dark continuous-corner visual effect backdrop and non-activating window level.
@MainActor
final class FloatingShelfPanel: NSPanel {
    /// Flag indicating whether an animated dismissal is in progress.
    private var isHiding = false

    /// The display on which the panel is currently presented.
    private weak var currentScreen: NSScreen?

    /// Initializes a new floating shelf panel with translucent backdrop and SwiftUI hosting view.
    init() {
        let defaultRect = NSRect(x: 0, y: 0, width: 360, height: 180)
        super.init(
            contentRect: defaultRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false

        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow

        let swiftUIView = FloatingShelfView(
            onClose: { [weak self] in
                self?.hideAnimated()
            },
            onDockToNotch: { [weak self] in
                guard let self = self else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                let targetScreen = self.currentScreen ?? NSScreen.main ?? NSScreen.screens[0]
                let targetVM = AppDelegate.shared?.viewModels[targetScreen] ?? AppDelegate.shared?.vm
                self.hideAnimated()

                DispatchQueue.main.async {
                    DynamicIslandViewCoordinator.shared.currentView = .shelf
                    targetVM?.open()
                }
            }
        )

        let hosting = FloatingShelfHostingView(rootView: swiftUIView)
        contentView = hosting
    }

    /// Allows the panel to become key so items can be focused and manipulated.
    override var canBecomeKey: Bool { true }

    /// Prevents the panel from taking over as the main application window.
    override var canBecomeMain: Bool { false }

    /// Presents the floating shelf positioned adjacent to the specified screen coordinate.
    /// - Parameter point: The mouse location in AppKit screen coordinates.
    func show(at point: NSPoint) {
        isHiding = false
        let size = NSSize(width: 360, height: 180)
        let screen = NSScreen.screens.first(where: { NSPointInRect(point, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
        currentScreen = screen
        let visibleFrame = screen.visibleFrame

        // Center slightly offset from cursor so user isn't directly clicking on edge
        var originX = point.x - (size.width / 2)
        var originY = point.y - (size.height / 2)

        // Clamp inside screen visibleFrame
        originX = max(visibleFrame.minX + 16, min(originX, visibleFrame.maxX - size.width - 16))
        originY = max(visibleFrame.minY + 16, min(originY, visibleFrame.maxY - size.height - 16))

        setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: size), display: true)

        if !isVisible || alphaValue < 0.2 {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1.0
            }
        } else {
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                animator().alphaValue = 1.0
            }
        }
    }

    /// Fades out and dismisses the panel with an ease-in animation.
    func hideAnimated() {
        guard !isHiding else { return }
        isHiding = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self, self.isHiding else { return }
            self.orderOut(nil)
            self.isHiding = false
        })
    }
}
