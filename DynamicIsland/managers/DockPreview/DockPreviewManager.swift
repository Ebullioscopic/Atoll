/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */

import AppKit
import ApplicationServices
import Combine
import Defaults
import SwiftUI

@MainActor
final class DockPreviewManager: ObservableObject {
    static let shared = DockPreviewManager()
    @Published private(set) var session: DockPreviewSession?
    @Published private(set) var thumbnails: [UInt: CGImage] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var actionError: String?
    @Published private(set) var hasScreenRecording = CGPreflightScreenCaptureAccess()

    @Published private(set) var applications: [DockPreviewApplication] = []
    @Published private(set) var isKeyboardSwitching = false
    @Published private(set) var keyboardAvailable = false
    private let keyboard = DockPreviewKeyboardMonitor()
    private var selection: DockPreviewSwitchSelection?
    private var recentPIDs: [pid_t] = []
    private var cooldownUntil: TimeInterval = 0

    var resolveScreen: ((NSScreen) -> String?)?
    var previewFrame: ((String) -> CGRect?)?
    var onPresent: ((String) -> Void)?
    var onDismiss: ((Bool) -> Void)?

    private let service = DockPreviewService()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var observations: [NSObjectProtocol] = []
    private var hover = DockPreviewHoverState()
    private var pointerTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var lastInside: TimeInterval = 0
    private var lastRefresh: TimeInterval = 0
    private var dismissedURL: URL?
    private var pointerGeneration = UUID()
    private var isRunning = false
    private var actionInFlight = false

    var cardWidth: CGFloat { min(240, max(132, Defaults[.dockPreviewCardWidth])) }
    var contentSize: CGSize {
        let screen = NSScreen.screens.first { $0.localizedName == session?.screenName } ?? NSScreen.main
        let width = DockPreviewLayout.panelWidth(count: session?.windows.count ?? 0, cardWidth: cardWidth,
            maximum: min(760, (screen?.frame.width ?? 760) - 8))
        return CGSize(width: width, height: 380)
    }
    func isPresented(on screenName: String?) -> Bool { session != nil && session?.screenName == screenName }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        keyboard.canBegin = { [weak self] in
            guard let self, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return false }
            return !LockScreenManager.shared.isLocked && self.resolveScreen?(screen) != nil && NSWorkspace.shared.runningApplications.contains {
                $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            }
        }
        keyboard.onAction = { [weak self] action in
            Task { @MainActor in
                guard let self else { return }
                switch action {
                case .step(let forward): self.stepSwitcher(forward: forward)
                case .commit: self.commitSwitcher()
                case .cancel: self.dismiss()
                }
            }
        }
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            Task { @MainActor in
                guard let self else { return }
                self.recentPIDs.removeAll { $0 == pid }; self.recentPIDs.insert(pid, at: 0)
            }
        })
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.configure() }
            })
        }
        for name in [NSWorkspace.didTerminateApplicationNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            })
        }
        Defaults.publisher(.dockPreviewEnabled).sink { [weak self] _ in Task { @MainActor in self?.configure() } }.store(in: &cancellables)
        Defaults.publisher(.dockPreviewCardWidth).sink { [weak self] _ in Task { @MainActor in self?.configure() } }.store(in: &cancellables)
        Defaults.publisher(.dockPreviewIncludeMinimized).sink { [weak self] _ in Task { @MainActor in self?.refresh() } }.store(in: &cancellables)
        for key in [Defaults.Keys.dockPreviewCommandTab, .dockPreviewShowAppStrip, .dockPreviewShowBackgroundProcesses] {
            Defaults.publisher(key).sink { [weak self] _ in Task { @MainActor in self?.configure() } }.store(in: &cancellables)
        }
        Defaults.publisher(.dockPreviewThumbnails).sink { [weak self] _ in Task { @MainActor in self?.refresh() } }.store(in: &cancellables)
        configure()
    }

    func stop() {
        isRunning = false
        keyboard.stop()
        pointerGeneration = UUID()
        pointerTask?.cancel(); pointerTask = nil
        timer?.invalidate(); timer = nil
        for observer in observations {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observations.removeAll(); cancellables.removeAll()
        dismiss()
    }

    func configure() {
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        timer?.invalidate(); timer = nil
        pointerGeneration = UUID()
        pointerTask?.cancel(); pointerTask = nil
        dismiss()
        keyboard.stop(); keyboardAvailable = false
        guard isRunning, Defaults[.dockPreviewEnabled], AXIsProcessTrusted(), !AppRuntimeEnvironment.isUITesting else { return }
        if Defaults[.dockPreviewCommandTab] { keyboard.start(); keyboardAvailable = keyboard.isInstalled }
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func dismiss(keepNotchOpen: Bool = false) {
        let wasPresented = session != nil
        selection = nil; isKeyboardSwitching = false; keyboard.reset()
        dismissedURL = session?.applicationURL ?? dismissedURL
        session = nil; thumbnails.removeAll(); actionError = nil; isLoading = false
        loadTask?.cancel(); loadTask = nil
        hover.reset()
        if wasPresented { onDismiss?(!keepNotchOpen) }
        Task { [weak self] in
            guard let self, self.session == nil else { return }
            await self.service.clear()
        }
    }

    func refreshSnapshots() {
        Task { await service.invalidateThumbnails(); refresh() }
    }

    func refresh() {
        guard let session, !actionInFlight else { return }
        load(sessionID: session.id)
    }

    func activateApplication() {
        guard let session else { return }
        if let pid = session.processID, let app = NSRunningApplication(processIdentifier: pid) { app.activate() }
        else { NSWorkspace.shared.openApplication(at: session.applicationURL, configuration: NSWorkspace.OpenConfiguration()) }
        dismiss()
    }

    func perform(_ action: DockPreviewAction, window: DockPreviewWindow) {
        guard let session, let pid = session.processID, !actionInFlight else { return }
        actionInFlight = true
        if case .activate = action { NSRunningApplication(processIdentifier: pid)?.activate() }
        Task {
            if case .activate = action, Defaults[.dockPreviewMoveToActiveDisplay], let destination = destinationFrame() {
                _ = await service.perform(.move(destination), windowID: window.id, pid: pid)
            }
            let succeeded = await service.perform(action, windowID: window.id, pid: pid)
            actionInFlight = false
            guard self.session?.id == session.id else { return }
            if succeeded {
                if case .activate = action {
                    NSRunningApplication(processIdentifier: pid)?.activate()
                    dismiss()
                } else { refresh() }
            } else {
                actionError = String(localized: "The window is no longer available, or the app did not accept that action.")
                refresh()
            }
        }
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        refresh()
    }

    private func tick() {
        if LockScreenManager.shared.isLocked { if session != nil { dismiss() }; return }
        guard pointerTask == nil, !actionInFlight, !isKeyboardSwitching,
              ProcessInfo.processInfo.systemUptime > cooldownUntil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let point = NSEvent.mouseLocation
        if let session, previewFrame?(session.screenName)?.contains(point) == true {
            lastInside = now
            if now - lastRefresh > 3 && !isLoading { refresh() }
            return
        }
        if session != nil && now - lastInside > max(0.5, min(2, Defaults[.dockPreviewDismissDelay])) { dismiss() }
        guard let primary = NSScreen.screens.first, let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }),
              DockPreviewGeometry.isNearDock(point, screen: screen.frame, orientation: UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"),
              let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            hover.reset(); dismissedURL = nil
            return
        }
        let quartz = DockPreviewGeometry.quartzPoint(point, primaryScreen: primary.frame)
        let generation = UUID()
        pointerGeneration = generation
        pointerTask = Task { [weak self] in
            guard let self else { return }
            let target = await service.target(at: quartz, dockProcessID: dockPID)
            guard generation == self.pointerGeneration else { return }
            self.pointerTask = nil
            guard !Task.isCancelled, self.isRunning else { return }
            guard Defaults[.dockPreviewEnabled] else { return }
            let currentPoint = DockPreviewGeometry.quartzPoint(NSEvent.mouseLocation, primaryScreen: primary.frame)
            guard let target, target.frame.contains(currentPoint) else {
                hover.reset(); dismissedURL = nil
                return
            }
            lastInside = ProcessInfo.processInfo.systemUptime
            hover.update(target.applicationURL, now: now)
            guard let screenName = resolveScreen?(screen) else { return }
            if session?.applicationURL == target.applicationURL && session?.screenName == screenName {
                if now - lastRefresh > 3 && !isLoading { refresh() }
                return
            }
            guard dismissedURL != target.applicationURL,
                  hover.isReady(now: now, delay: Defaults[.dockPreviewHoverDelay]) else { return }
            if let existing = session, existing.screenName != screenName { dismiss() }
            let app = NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == target.applicationURL }
            present(url: target.applicationURL, name: app?.localizedName ?? target.applicationURL.deletingPathExtension().lastPathComponent,
                pid: app?.processIdentifier, screenName: screenName)
        }
    }

    private func runningApps() -> [DockPreviewApplication] {
        let info = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var counts: [pid_t: Int] = [:]
        for item in info where item[kCGWindowLayer as String] as? Int == 0 {
            if let pid = item[kCGWindowOwnerPID as String] as? pid_t { counts[pid, default: 0] += 1 }
        }
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }.compactMap { app in
            guard let url = app.bundleURL else { return nil }
            return DockPreviewApplication(id: app.processIdentifier, url: url, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                windowCount: counts[app.processIdentifier] ?? 0)
        }.sorted {
            let a = recentPIDs.firstIndex(of: $0.id) ?? Int.max, b = recentPIDs.firstIndex(of: $1.id) ?? Int.max
            return a == b ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : a < b
        }
    }

    private func present(url: URL, name: String, pid: pid_t?, screenName: String) {
        if let session, session.screenName != screenName { dismiss() }
        let first = session == nil
        loadTask?.cancel(); thumbnails.removeAll(); actionError = nil
        let next = DockPreviewSession(id: UUID(), applicationURL: url, applicationName: name, processID: pid, screenName: screenName, windows: [])
        session = next
        applications = runningApps()
        if first { onPresent?(screenName) }
        lastInside = ProcessInfo.processInfo.systemUptime
        load(sessionID: next.id)
    }

    func selectApplication(_ app: DockPreviewApplication) {
        guard let screen = session?.screenName else { return }
        present(url: app.url, name: app.name, pid: app.id, screenName: screen)
    }

    func hideApplication() {
        if let pid = session?.processID { NSRunningApplication(processIdentifier: pid)?.hide() }
        dismiss()
    }

    func quitApplication() {
        if let pid = session?.processID { NSRunningApplication(processIdentifier: pid)?.terminate() }
        dismiss()
    }

    func moveWindow(_ window: DockPreviewWindow) {
        guard let frame = destinationFrame() else { return }
        perform(.move(frame), window: window)
    }

    private func destinationFrame() -> CGRect? {
        guard let primary = NSScreen.screens.first, let screen = NSScreen.screens.first(where: { $0.localizedName == session?.screenName }) else { return nil }
        let visible = screen.visibleFrame
        return CGRect(x: visible.minX, y: primary.frame.maxY - visible.maxY, width: visible.width, height: visible.height)
    }

    private func stepSwitcher(forward: Bool) {
        guard Defaults[.dockPreviewEnabled], Defaults[.dockPreviewCommandTab] else { return }
        if selection == nil {
            let apps = runningApps()
            selection = DockPreviewSwitchSelection(pids: apps.map(\.id), frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier, forward: forward)
        } else { selection?.step(forward) }
        guard let selection else { return }
        for _ in selection.pids.indices {
            if let pid = self.selection?.selectedPID, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, let url = app.bundleURL,
               let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
               let name = resolveScreen?(screen) {
                isKeyboardSwitching = true
                present(url: url, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, pid: pid, screenName: name)
                return
            }
            self.selection?.step(forward)
        }
        dismiss()
    }

    private func commitSwitcher() {
        guard isKeyboardSwitching, selection != nil else { return }
        cooldownUntil = ProcessInfo.processInfo.systemUptime + 0.6
        if let window = session?.windows.first { perform(.activate, window: window) }
        else { activateApplication() }
    }

    private func load(sessionID: UUID) {
        loadTask?.cancel()
        guard let session, session.id == sessionID else { return }
        lastRefresh = ProcessInfo.processInfo.systemUptime
        guard let pid = session.processID else { isLoading = false; return }
        isLoading = true
        let includeMinimized = Defaults[.dockPreviewIncludeMinimized]
        let allowCapture = Defaults[.dockPreviewThumbnails] && CGPreflightScreenCaptureAccess()
        if !allowCapture { thumbnails.removeAll() }
        let width = Int(cardWidth * 2)
        loadTask = Task { [weak self] in
            guard let self else { return }
            let windows = await service.windows(for: pid, includeMinimized: includeMinimized, limit: 12, allowCapture: allowCapture)
            guard !Task.isCancelled, self.session?.id == sessionID else { return }
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            self.session?.windows = windows.map { window in
                var window = window
                let center = CGPoint(x: window.frame.midX, y: primaryTop - window.frame.midY)
                window.displayName = NSScreen.screens.first(where: { $0.frame.contains(center) })?.localizedName ?? ""
                return window
            }
            self.applications = self.runningApps()
            if let index = self.applications.firstIndex(where: { $0.id == pid }) { self.applications[index].windowCount = windows.count }
            self.thumbnails = self.thumbnails.filter { id, _ in windows.contains { $0.id == id } }
            self.isLoading = false
            for window in windows {
                guard !Task.isCancelled, self.session?.id == sessionID else { return }
                if let captureID = window.captureID, let image = await service.thumbnail(for: captureID, width: width) {
                    guard !Task.isCancelled, self.session?.id == sessionID else { return }
                    self.thumbnails[window.id] = image
                }
            }
        }
    }
}
