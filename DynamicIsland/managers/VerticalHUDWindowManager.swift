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
final class VerticalHUDWindowManager {
    static let shared = VerticalHUDWindowManager()
    
    // Properties
    private var windows: [NSScreen: OSDWindow] = [:]
    private var hideWorkItem: DispatchWorkItem?
    private let displayDuration: TimeInterval = 2.0
    private let animationDuration: TimeInterval = 0.2
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupPositionObserver()
    }
    
    // Helper Struct
    private struct OSDWindow {
        let nsWindow: NSWindow
        let hostingView: NSHostingView<VerticalHUDView>
        let state: VerticalHUDState
    }
    
    private func setupPositionObserver() {
        // Observe layout keys individually
        let updateBlock: (Any) -> Void = { [weak self] _ in
             Task { @MainActor [weak self] in
                 self?.updateWindowLayout()
             }
        }

        Defaults.publisher(.verticalHUDPosition, options: []).sink(receiveValue: updateBlock).store(in: &cancellables)
        Defaults.publisher(.verticalHUDHeight, options: []).sink(receiveValue: updateBlock).store(in: &cancellables)
        Defaults.publisher(.verticalHUDWidth, options: []).sink(receiveValue: updateBlock).store(in: &cancellables)
        Defaults.publisher(.verticalHUDPadding, options: []).sink(receiveValue: updateBlock).store(in: &cancellables)
        Defaults.publisher(.verticalHUDInteractive, options: []).sink(receiveValue: updateBlock).store(in: &cancellables)

        Defaults.publisher(.enableVerticalHUD, options: []).sink { [weak self] change in
            Task { @MainActor [weak self] in
                self?.handleEnablementChange(change.newValue)
            }
        }.store(in: &cancellables)
    }
    
    private func updateWindowLayout() {
        guard !windows.isEmpty else { return }
        
        for (screen, window) in windows {
            let screenFrame = screen.frame
            let position = Defaults[.verticalHUDPosition]
            let width = Defaults[.verticalHUDWidth]
            let height = Defaults[.verticalHUDHeight]
            let padding = Defaults[.verticalHUDPadding]
            
            // Add padding for shadow and elastic stretch
            // We use 120px total padding (60px per side) to absolutely guarantee no clipping.
            let shadowPadding: CGFloat = 120
            let totalWidth = width + shadowPadding
            let totalHeight = height + shadowPadding
            
            let x: CGFloat
            if position == "left" {
                // Left edge of HUD is at (minX + padding).
                // Window edge = HUD Edge - half shadow padding
                x = screenFrame.minX + padding - (shadowPadding / 2)
            } else {
                // Right edge of HUD is at (maxX - padding).
                // Left edge of HUD = maxX - padding - width.
                // Window edge = HUD Edge - half shadow padding
                x = screenFrame.maxX - width - padding - (shadowPadding / 2)
            }
            
            let y = screenFrame.midY - (totalHeight / 2)
            let newFrame = NSRect(x: x, y: y, width: totalWidth, height: totalHeight)
            
            window.nsWindow.setFrame(newFrame, display: true, animate: true)
            applyInteractivity(window)
        }
    }

    private func handleEnablementChange(_ isEnabled: Bool) {
        if isEnabled {
            updateWindowLayout()
        } else {
            teardownWindows()
        }
    }

    private func applyInteractivity(_ window: OSDWindow, visibleOverride: Bool? = nil) {
        let isVisible = visibleOverride ?? (window.nsWindow.alphaValue > 0.01)
        let shouldAllowInteraction = Defaults[.enableVerticalHUD] && Defaults[.verticalHUDInteractive] && isVisible
        window.nsWindow.ignoresMouseEvents = !shouldAllowInteraction
    }

    private func teardownWindows() {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        for window in windows.values {
            window.nsWindow.orderOut(nil)
            window.nsWindow.ignoresMouseEvents = true
        }

        windows.removeAll()
    }
    
    func show(type: SneakContentType, value: CGFloat, icon: String = "", onScreen targetScreen: NSScreen? = nil) {
        guard Defaults[.enableVerticalHUD] else { return }
        
        let screens = targetScreen.map { [$0] } ?? NSScreen.screens
        guard !screens.isEmpty else { return }
        
        // Show on target screen(s)
        for screen in screens {
            let windowContext = ensureWindow(for: type, screen: screen)
            updateContent(window: windowContext, type: type, value: value, icon: icon)
            
            // Ensure visible
            windowContext.nsWindow.orderFrontRegardless()
            applyInteractivity(windowContext, visibleOverride: true)
            
            NSAnimationContext.runAnimationGroup { context in
                context.duration = animationDuration
                windowContext.nsWindow.animator().alphaValue = 1
            }
        }
        
        scheduleHide()
    }
    
    func triggerBump(direction: Int) {
        guard Defaults[.enableVerticalHUD] else { return }
        Task { @MainActor in
            for window in windows.values {
                window.state.bumpEvent = BumpEvent(direction: direction, timestamp: Date())
            }
        }
    }
    
    private func ensureWindow(for type: SneakContentType, screen: NSScreen) -> OSDWindow {
        if let existing = windows[screen] {
            return existing
        }
        
        let state = VerticalHUDState(type: type, value: 0, icon: "")
        let osdView = VerticalHUDView(state: state)
        let hostingView = NSHostingView(rootView: osdView)
        
        // Calculate frame
        let screenFrame = screen.frame
        let position = Defaults[.verticalHUDPosition]
        let width = Defaults[.verticalHUDWidth]
        let height = Defaults[.verticalHUDHeight]
        let padding = Defaults[.verticalHUDPadding]
        
        // Add padding for shadow and elastic stretch
        // We use 120px total padding (60px per side) to absolutely guarantee no clipping.
        let shadowPadding: CGFloat = 120
        let totalWidth = width + shadowPadding
        let totalHeight = height + shadowPadding
        
        let x: CGFloat
        if position == "left" {
            x = screenFrame.minX + padding - (shadowPadding / 2)
        } else {
            x = screenFrame.maxX - width - padding - (shadowPadding / 2)
        }
        
        // Center vertically
        let y = screenFrame.midY - (totalHeight / 2)
        let frame = NSRect(x: x, y: y, width: totalWidth, height: totalHeight)
        
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        win.isOpaque = false
        win.backgroundColor = NSColor.clear
        win.level = NSWindow.Level.screenSaver
        win.collectionBehavior = [NSWindow.CollectionBehavior.canJoinAllSpaces, NSWindow.CollectionBehavior.stationary, NSWindow.CollectionBehavior.ignoresCycle, NSWindow.CollectionBehavior.fullScreenAuxiliary]
        win.hasShadow = false
        win.contentView = hostingView
        win.alphaValue = 0
        
        // Default to ignoring events until explicitly shown
        win.ignoresMouseEvents = true
        
        SkyLightOperator.shared.delegateWindow(win)
        
        let windowStruct = OSDWindow(nsWindow: win, hostingView: hostingView, state: state)
        windows[screen] = windowStruct
        return windowStruct
    }
    
    private func updateContent(window: OSDWindow, type: SneakContentType, value: CGFloat, icon: String) {
        // Update state instead of replacing view
        window.state.type = type
        window.state.value = value
        window.state.icon = icon
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
            } completionHandler: { [weak self] in
                self?.applyInteractivity(window, visibleOverride: false)
            }
        }
    }
}
#endif
