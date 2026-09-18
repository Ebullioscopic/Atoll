/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Licensed under GNU GPLv3.
 */

import AppKit
import SwiftUI

@MainActor
final class FloatingShelfPanel: NSPanel {
    private var isHiding = false

    init() {
        let defaultRect = NSRect(x: 0, y: 0, width: 360, height: 180)
        super.init(
            contentRect: defaultRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
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

        let root = NSView(frame: defaultRect)
        root.wantsLayer = true
        root.layer?.cornerRadius = 20
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .vibrantDark)
        blur.translatesAutoresizingMaskIntoConstraints = false

        let swiftUIView = FloatingShelfView(
            onClose: { [weak self] in
                self?.hideAnimated()
            },
            onDockToNotch: { [weak self] in
                self?.hideAnimated()
                // Switch Atoll's main notch to shelf view and open the notch
                DispatchQueue.main.async {
                    DynamicIslandViewCoordinator.shared.currentView = .shelf
                    AppDelegate.shared?.vm.open()
                }
            }
        )

        let hosting = FirstMouseHostingView(rootView: swiftUIView)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(blur)
        root.addSubview(hosting)

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: root.topAnchor),
            blur.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            hosting.topAnchor.constraint(equalTo: root.topAnchor),
            hosting.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        contentView = root
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(at point: NSPoint) {
        isHiding = false
        let size = NSSize(width: 360, height: 180)
        let screen = NSScreen.screens.first(where: { NSPointInRect(point, $0.frame) }) ?? NSScreen.main ?? NSScreen.screens[0]
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
