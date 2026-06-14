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
import Combine
import Defaults
import AppKit
import SkyLightWindow
import AtollExtensionKit

@MainActor
final class ExtensionLockScreenWidgetPresentationController {
    private unowned let manager: ExtensionLockScreenWidgetManager
    private var cancellables: Set<AnyCancellable> = []
    private let windowPool = ExtensionLockScreenWidgetWindowPool()
    private var cachedPayloads: [ExtensionLockScreenWidgetPayload] = []
    private var isLocked: Bool = false
    private var lastVisibilityState: VisibilityState?

    init(manager: ExtensionLockScreenWidgetManager) {
        self.manager = manager
    }

    func activate() {
        observeLockState()
        observePayloads()
        observeDefaults()
    }

    private func observeLockState() {
        LockScreenManager.shared.$isLocked
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] locked in
                guard let self else { return }
                self.isLocked = locked
                self.refreshPresentation()
            }
            .store(in: &cancellables)
    }

    private func observePayloads() {
        manager.$activeWidgets
            .receive(on: RunLoop.main)
            .sink { [weak self] payloads in
                guard let self else { return }
                self.cachedPayloads = payloads
                self.refreshPresentation()
            }
            .store(in: &cancellables)
    }

    private func observeDefaults() {
        Defaults.publisher(.enableExtensionLockScreenWidgets, options: [])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    self.refreshPresentation()
                } else {
                    self.windowPool.hideAll()
                    self.updateVisibilityLog(.hidden(reason: "feature-disabled"))
                }
            }
            .store(in: &cancellables)
    }

    private func refreshPresentation() {
        guard isLocked, LockScreenManager.shared.currentLockStatus, Defaults[.enableExtensionLockScreenWidgets] else {
            windowPool.hideAll()
            updateVisibilityLog(.hidden(reason: "lock-state"))
            return
        }
        guard cachedPayloads.isEmpty == false else {
            windowPool.hideAll()
            updateVisibilityLog(.hidden(reason: "no-payloads"))
            return
        }
        windowPool.sync(with: cachedPayloads)
        updateVisibilityLog(.showing(count: cachedPayloads.count))
    }

    private func updateVisibilityLog(_ state: VisibilityState) {
        guard state != lastVisibilityState else { return }
        lastVisibilityState = state
        switch state {
        case let .hidden(reason):
            logDiagnostics("Lock screen widgets hidden (reason: \(reason))")
        case let .showing(count):
            logDiagnostics("Presenting \(count) extension lock screen widget(s)")
        }
    }

    private func logDiagnostics(_ message: String) {
        guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
        Logger.log(message, category: .extensions)
    }

    private enum VisibilityState: Equatable {
        case hidden(reason: String)
        case showing(count: Int)
    }
}

@MainActor
private final class ExtensionLockScreenWidgetWindowPool {
    private struct WindowRecord {
        let window: NSWindow
    }

    private var windows: [String: WindowRecord] = [:]
    private var payloadsByID: [String: ExtensionLockScreenWidgetPayload] = [:]
    private var screenChangeObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        registerScreenChangeObservers()
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
    }

    func sync(with payloads: [ExtensionLockScreenWidgetPayload]) {
        payloadsByID = Dictionary(uniqueKeysWithValues: payloads.map { ($0.id, $0) })
        let activeIDs = Set(payloadsByID.keys)
        let staleIDs = Set(windows.keys).subtracting(activeIDs)
        staleIDs.forEach { hideWindow(withID: $0) }
        payloads.forEach { renderWindow(for: $0) }
    }

    func hideAll() {
        payloadsByID.removeAll()
        windows.values.forEach { record in
            record.window.orderOut(nil)
            record.window.contentView = nil
        }
        windows.removeAll()
        logDiagnostics("Cleared all lock screen widget windows")
    }

    private func renderWindow(for payload: ExtensionLockScreenWidgetPayload) {
        guard let screen = currentScreen() else { return }
        let descriptor = payload.descriptor
        let isNewWindow = windows[payload.id] == nil
        let window = ensureWindow(for: payload.id)
        let hosting = NSHostingView(rootView: ExtensionLockScreenWidgetView(payload: payload))
        hosting.frame = NSRect(origin: .zero, size: descriptor.size)
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = true
        hosting.layer?.cornerRadius = descriptor.cornerRadius
        window.contentView = hosting
        window.setFrame(frame(for: descriptor, on: screen), display: true)
        window.alphaValue = 1
        window.orderFrontRegardless()
        if isNewWindow {
            logDiagnostics("Created lock screen widget window for \(payload.bundleIdentifier) id=\(payload.id) style=\(descriptor.layoutStyle)")
        } else {
            logDiagnostics("Updated lock screen widget window for \(payload.bundleIdentifier) id=\(payload.id)")
        }
    }

    private func ensureWindow(for id: String) -> NSWindow {
        if let record = windows[id] {
            return record.window
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: CGSize(width: 200, height: 80)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.isMovable = false

        ScreenCaptureVisibilityManager.shared.register(window, scope: .entireInterface)
        SkyLightOperator.shared.delegateWindow(window)

        let record = WindowRecord(window: window)
        windows[id] = record
        return window
    }

    private func hideWindow(withID id: String) {
        guard let record = windows[id] else { return }
        record.window.orderOut(nil)
        record.window.contentView = nil
        windows.removeValue(forKey: id)
        logDiagnostics("Removed lock screen widget window id=\(id)")
    }

    private func registerScreenChangeObservers() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenGeometryChange(reason: "screen-parameters")
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeObserver = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenGeometryChange(reason: "screens-did-wake")
        }

        workspaceObservers = [wakeObserver]
    }

    private func handleScreenGeometryChange(reason: String) {
        guard windows.isEmpty == false else { return }
        repositionAll(animated: false)
        logDiagnostics("Realigned lock screen widget windows due to \(reason)")
    }

    private func repositionAll(animated: Bool) {
        guard let screen = currentScreen() else { return }
        for (id, record) in windows {
            guard let payload = payloadsByID[id] else { continue }
            let targetFrame = frame(for: payload.descriptor, on: screen)
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    record.window.animator().setFrame(targetFrame, display: true)
                }
            } else {
                record.window.setFrame(targetFrame, display: true)
            }
        }
    }

    private func frame(for descriptor: AtollLockScreenWidgetDescriptor, on screen: NSScreen) -> NSRect {
        let size = descriptor.size
        let safeInsets = safeInsets(for: descriptor.position.clampMode)
        let screenFrame = screen.frame

        let minX = screenFrame.minX + safeInsets.left
        let maxX = screenFrame.maxX - safeInsets.right - size.width
        let minY = screenFrame.minY + safeInsets.bottom
        let maxY = screenFrame.maxY - safeInsets.top - size.height

        var originX: CGFloat
        switch descriptor.position.alignment {
        case .leading:
            originX = minX
        case .center:
            originX = screenFrame.midX - (size.width / 2)
        case .trailing:
            originX = maxX
        }

        originX += descriptor.position.horizontalOffset
        originX = clamp(originX, lower: min(minX, maxX), upper: max(minX, maxX))

        var originY = screenFrame.midY - (size.height / 2) + descriptor.position.verticalOffset
        originY = clamp(originY, lower: min(minY, maxY), upper: max(minY, maxY))

        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    private func safeInsets(for clampMode: AtollWidgetPosition.ClampMode) -> NSEdgeInsets {
        switch clampMode {
        case .safeRegion:
            return NSEdgeInsets(top: 140, left: 48, bottom: 100, right: 48)
        case .relaxed:
            return NSEdgeInsets(top: 96, left: 24, bottom: 72, right: 24)
        case .unconstrained:
            return NSEdgeInsets(top: 16, left: 0, bottom: 32, right: 0)
        }
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return value }
        return min(max(value, lower), upper)
    }

    private func currentScreen() -> NSScreen? {
        LockScreenDisplayContextProvider.shared.contextSnapshot()?.screen ?? NSScreen.main
    }
}

private func logDiagnostics(_ message: String) {
    guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
    Logger.log(message, category: .extensions)
}
