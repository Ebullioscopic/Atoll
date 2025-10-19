//
//  SettingsWindowController.swift
//  DynamicIsland
//
//  Created by Alexander on 2025-06-14.
//

import AppKit
import SwiftUI
import Defaults
import Sparkle

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var updaterController: SPUStandardUpdaterController?
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: window)
        
        setupWindow()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setUpdaterController(_ controller: SPUStandardUpdaterController) {
        self.updaterController = controller
        // Recreate the content view with the proper updater controller
        setupWindow()
    }
    
    private func setupWindow() {
        guard let window = window else { return }
        
        window.title = "Dynamic Island Settings"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        
        // Make it behave like a regular app window with proper Spaces support
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        
        // Ensure proper window behavior
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = false
        
        // Configure window to be a standard document-style window
        window.isRestorable = true
        window.identifier = NSUserInterfaceItemIdentifier("DynamicIslandSettingsWindow")
        
        // Create the SwiftUI content
        let settingsView = SettingsView(updaterController: updaterController)
        let hostingView = NSHostingView(rootView: settingsView)
        window.contentView = hostingView
        
        // Handle window closing
        window.delegate = self
        
        // Apply screen capture hiding setting
        updateScreenCaptureVisibility()
        setupScreenCaptureObserver()
    }
    
    func showWindow() {
        // Set app to regular mode first
        NSApp.setActivationPolicy(.regular)
        
        // If window is already visible, bring it to front properly
        if window?.isVisible == true {
            forceWindowToFront()
            return
        }
        
        // Show the window with proper ordering
        window?.center()
        forceWindowToFront()
    }
    
    private func forceWindowToFront() {
        // Multi-step approach to ensure window gets focus
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        
        // Activate the app with maximum priority
        NSApp.activate(ignoringOtherApps: true)
        
        // Double-check after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let window = self?.window else { return }
            if !window.isKeyWindow {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    override func close() {
        super.close()
        relinquishFocus()
    }
    
    private func relinquishFocus() {
        window?.orderOut(nil)
        
        // Set app back to accessory mode immediately
        NSApp.setActivationPolicy(.accessory)
    }
    
    private func setupScreenCaptureObserver() {
        // Observe changes to hidePanelsFromScreenCapture setting
        Defaults.observe(.hidePanelsFromScreenCapture) { [weak self] change in
            DispatchQueue.main.async {
                self?.updateScreenCaptureVisibility()
            }
        }
    }
    
    private func updateScreenCaptureVisibility() {
        let shouldHide = Defaults[.hidePanelsFromScreenCapture]
        
        if shouldHide {
            // Hide from screen capture and recording
            window?.sharingType = .none
            print("🙈 SettingsWindow: Hidden from screen capture and recordings")
        } else {
            // Allow normal screen capture
            window?.sharingType = .readOnly
            print("👁️ SettingsWindow: Visible in screen capture and recordings")
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
