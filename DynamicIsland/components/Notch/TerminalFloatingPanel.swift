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
import SwiftTerm
import Defaults

// MARK: - Floating Terminal Panel

/// A detachable floating NSPanel that hosts its own terminal session.
/// Uses the same pattern as ClipboardPanel — borderless, floating, draggable.
class TerminalFloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        setupWindow()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private func setupWindow() {
        backgroundColor = NSColor(white: 0.1, alpha: 0.95)
        isOpaque = false
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isFloatingPanel = true
        minSize = NSSize(width: 300, height: 200)

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]

        acceptsMouseMovedEvents = true
    }
}

// MARK: - Controller

/// Singleton controller that manages the floating terminal panel lifecycle.
/// The floating panel gets its own independent terminal session (separate from
/// the notch terminal) so both can be used simultaneously.
@MainActor
class TerminalFloatingPanelController: NSObject, ObservableObject, LocalProcessTerminalViewDelegate {
    static let shared = TerminalFloatingPanelController()

    private var panel: TerminalFloatingPanel?
    private var terminalView: LocalProcessTerminalView?
    private var isProcessRunning = false

    private override init() {
        super.init()
    }

    /// Shows the floating terminal panel, creating it if needed.
    func showPanel() {
        if let panel = panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            focusTerminal()
            return
        }

        let width = CGFloat(Defaults[.terminalCustomWidth])
        let height: CGFloat = 400
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = NSPoint(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2
        )
        let contentRect = NSRect(origin: origin, size: NSSize(width: width, height: height))

        let newPanel = TerminalFloatingPanel(contentRect: contentRect)
        panel = newPanel

        // Create terminal view
        let tv = LocalProcessTerminalView(frame: NSRect(origin: .zero, size: contentRect.size))
        tv.autoresizingMask = [.width, .height]
        tv.processDelegate = self
        tv.optionAsMetaKey = Defaults[.terminalOptionAsMeta]
        tv.allowMouseReporting = Defaults[.terminalMouseReporting]

        // Font
        let fontSize = CGFloat(Defaults[.terminalFontSize])
        let fontFamily = Defaults[.terminalFontFamily]
        if !fontFamily.isEmpty, let font = NSFont(name: fontFamily, size: fontSize) {
            tv.font = font
        } else {
            tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }

        // Colors
        tv.nativeBackgroundColor = NSColor(Defaults[.terminalBackgroundColor])
        tv.nativeForegroundColor = NSColor(Defaults[.terminalForegroundColor])
        tv.caretColor = NSColor(Defaults[.terminalCursorColor])

        terminalView = tv

        let hostView = NSView(frame: NSRect(origin: .zero, size: contentRect.size))
        hostView.autoresizingMask = [.width, .height]
        hostView.addSubview(tv)
        newPanel.contentView = hostView

        // Start shell
        let shell = Defaults[.terminalShellPath]
        let execName = "-" + (shell as NSString).lastPathComponent
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env.removeValue(forKey: "TERM_PROGRAM")
        tv.startProcess(
            executable: shell,
            args: [],
            environment: env.map { "\($0.key)=\($0.value)" },
            execName: execName
        )
        isProcessRunning = true

        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Auto-focus
        if Defaults[.terminalAutoFocus] {
            focusTerminal()
        }
    }

    /// Closes and destroys the floating panel.
    func hidePanel() {
        terminalView?.terminate()
        terminalView = nil
        panel?.close()
        panel = nil
        isProcessRunning = false
    }

    private func focusTerminal() {
        guard let tv = terminalView, let window = tv.window else { return }
        window.makeFirstResponder(tv)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor in
            self.panel?.title = title
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor in
            self.isProcessRunning = false
            // Auto-close panel when shell exits
            self.hidePanel()
        }
    }
}
