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
import Defaults
import Combine

@MainActor
final class CircularHUDWindowManager {
    static let shared = CircularHUDWindowManager()
    
    private var windows: [NSScreen: OSDWindow] = [:]
    private var hideWorkItem: DispatchWorkItem?
    private let displayDuration: TimeInterval = 2.0
    private let animationDuration: TimeInterval = 0.2
    
    private var cancellables = Set<AnyCancellable>()
    
    // Layout constants removed in favor of dynamic calculation
    
    private init() {
        setupSizeObserver()
    }
    
    private func setupSizeObserver() {
        Defaults.publisher(.circularHUDSize, options: []).sink { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateWindowLayout()
            }
        }.store(in: &cancellables)
    }
    
    private func updateWindowLayout() {
        guard !windows.isEmpty else { return }
        
        for (screen, window) in windows {
            window.nsWindow.setFrame(frame(for: screen), display: true, animate: true)
        }
    }

    private func frame(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let windowSize = Defaults[.circularHUDSize] + 80 // Padding
        let x = screenFrame.midX - (windowSize / 2)
        let y = screenFrame.midY - (windowSize / 2)
        return NSRect(x: x, y: y, width: windowSize, height: windowSize)
    }

    /// Drops windows whose display has gone. Their screens no longer get a
    /// HUD, so keeping them only leaks a window per reconnect.
    private func pruneDisconnectedScreens() {
        let current = NSScreen.screens
        for (screen, window) in windows where !current.contains(screen) {
            window.nsWindow.orderOut(nil)
            windows[screen] = nil
        }
    }
    
    func show(type: SneakContentType, value: CGFloat, icon: String = "", onScreen targetScreen: NSScreen? = nil) {
        guard Defaults[.enableCircularHUD] else { return }
        
        let screens = targetScreen.map { [$0] } ?? NSScreen.screens
        guard !screens.isEmpty else { return }
        
        pruneDisconnectedScreens()

        // Show on target screen(s)
        for screen in screens {
            let windowContext = ensureWindow(for: type, screen: screen)
            // Re-place on every show: an arrangement or main-display change
            // moves screens in global coordinates, and a window left at its old
            // frame lands on another display, doubling that display's HUD.
            let targetFrame = frame(for: screen)
            if windowContext.nsWindow.frame != targetFrame {
                windowContext.nsWindow.setFrame(targetFrame, display: false)
            }
            updateContent(window: windowContext, type: type, value: value, icon: icon)
            
            // Ensure visible
            windowContext.nsWindow.orderFrontRegardless()
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                windowContext.nsWindow.animator().alphaValue = 1
            }
        }
        
        scheduleHide()
    }
    
    private func ensureWindow(for type: SneakContentType, screen: NSScreen) -> OSDWindow {
        if let existing = windows[screen] {
            return existing
        }
        
        let osdView = CircularHUDView(type: .constant(type), value: .constant(0), icon: .constant(""))
        let hostingView = NSHostingView(rootView: osdView)
        
        // Position at center of screen
        let frame = frame(for: screen)
        
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        win.hasShadow = false
        win.contentView = hostingView
        win.alphaValue = 0
        
        SkyLightOperator.shared.delegateWindow(win)
        
        let windowStruct = OSDWindow(nsWindow: win, hostingView: hostingView, type: type)
        windows[screen] = windowStruct
        return windowStruct
    }
    
    private func updateContent(window: OSDWindow, type: SneakContentType, value: CGFloat, icon: String) {
        let osdView = CircularHUDView(type: .constant(type), value: .constant(value), icon: .constant(icon))
        window.hostingView.rootView = osdView
    }
    
    private func scheduleHide() {
        hideWorkItem?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.hideWindow()
            }
        }
        
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration, execute: workItem)
    }
    
    private func hideWindow() {
        for window in windows.values {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                window.nsWindow.animator().alphaValue = 0
            } completionHandler: {
                 // Keep window around but hidden for faster subsequent shows
            }
        }
    }
    
    // Helper struct
    private struct OSDWindow {
        let nsWindow: NSWindow
        let hostingView: NSHostingView<CircularHUDView>
        let type: SneakContentType
    }
}
#endif
