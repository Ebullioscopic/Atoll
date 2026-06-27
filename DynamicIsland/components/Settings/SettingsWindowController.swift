/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import Sparkle

private final class SettingsWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var updaterController: SPUStandardUpdaterController?
    private var focusRetryWorkItem: DispatchWorkItem?
    
    private init() {
        super.init(window: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUpdaterController(_ controller: SPUStandardUpdaterController) {
        self.updaterController = controller
        if let window {
            installContent(in: window)
        }
    }
    
    private func makeWindow() -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        setupWindow(window)
        ScreenCaptureVisibilityManager.shared.register(window, scope: .panelsOnly)
        return window
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = makeWindow()
        self.window = window
        return window
    }

    private func setupWindow(_ window: NSWindow) {
        window.title = "Atoll Settings"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.isReleasedWhenClosed = false
        
        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle, .moveToActiveSpace]
        
        // Ensure proper window behavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        
        // Configure window to be a standard document-style window
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("DynamicIslandSettingsWindow")
        
        installContent(in: window)
        window.delegate = self
    }

    private func installContent(in window: NSWindow) {
        let settingsView = SettingsView(updaterController: updaterController)
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView
    }
    
    func showWindow() {
        focusRetryWorkItem?.cancel()

        // The app normally runs as an accessory app. Switch to regular before
        // requesting focus so AppKit can make the settings window key/main.
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async { [weak self] in
            self?.presentSettingsWindow()
        }
    }

    private func presentSettingsWindow() {
        let window = ensureWindow()

        // Reassert regular window semantics in case any prior state mutated this window.
        window.level = .normal
        window.collectionBehavior = [.managed, .participatesInCycle, .moveToActiveSpace]

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        if !window.isVisible {
            window.center()
        }

        focus(window)

        let retry = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window, window.isVisible else { return }
            self.focus(window)
        }
        focusRetryWorkItem = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: retry)
    }

    private func focus(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
    }
    
    override func close() {
        focusRetryWorkItem?.cancel()
        super.close()
        relinquishFocus()
    }
    
    private func relinquishFocus() {
        focusRetryWorkItem?.cancel()
        window?.orderOut(nil)
        
        // Set app back to accessory mode immediately
        NSApp.setActivationPolicy(.accessory)
    }
    
    deinit {
        if let window = window {
            ScreenCaptureVisibilityManager.shared.unregister(window)
        }
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        relinquishFocus()
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Ensure app is in regular mode when window becomes key
        NSApp.setActivationPolicy(.regular)
    }
    
    func windowDidResignKey(_ notification: Notification) {
    }
    
}
