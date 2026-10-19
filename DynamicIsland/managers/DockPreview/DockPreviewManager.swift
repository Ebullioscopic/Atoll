/* Atoll — Copyright (C) 2026 Atoll Contributors. GPL-3.0-or-later. */

import AppKit
import ApplicationServices
import Combine
import Defaults

@MainActor
final class DockPreviewManager: ObservableObject {
    static let shared = DockPreviewManager()
    @Published private(set) var session: DockPreviewSession?
    @Published private(set) var thumbnails: [UInt: CGImage] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var actionError: String?
    @Published private(set) var hasScreenRecording = CGPreflightScreenCaptureAccess()

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

    var cardWidth: CGFloat { min(260, max(160, Defaults[.dockPreviewCardWidth])) }
    var contentSize: CGSize { CGSize(width: min(760, max(360, cardWidth * CGFloat(min(3, max(1, session?.windows.count ?? 1))) + 48)), height: 290) }
    func isPresented(on screenName: String?) -> Bool { session != nil && session?.screenName == screenName }

    func start() {
        guard !isRunning else { return }
        isRunning = true
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
        configure()
    }

    func stop() {
        isRunning = false
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
        guard isRunning, Defaults[.dockPreviewEnabled], AXIsProcessTrusted(), !AppRuntimeEnvironment.isUITesting else { return }
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func dismiss(keepNotchOpen: Bool = false) {
        let wasPresented = session != nil
        dismissedURL = session?.applicationURL ?? dismissedURL
        session = nil; thumbnails.removeAll(); actionError = nil; isLoading = false
        loadTask?.cancel(); loadTask = nil
        hover.reset()
        if wasPresented { onDismiss?(!keepNotchOpen) }
        Task { await service.clear() }
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
        guard pointerTask == nil, !actionInFlight else { return }
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
            let name = app?.localizedName ?? target.applicationURL.deletingPathExtension().lastPathComponent
            let next = DockPreviewSession(id: UUID(), applicationURL: target.applicationURL, applicationName: name,
                processID: app?.processIdentifier, screenName: screenName, windows: [])
            let firstPresentation = session == nil
            loadTask?.cancel(); thumbnails.removeAll(); actionError = nil
            session = next
            if firstPresentation { onPresent?(screenName) }
            load(sessionID: next.id)
        }
    }

    private func load(sessionID: UUID) {
        loadTask?.cancel()
        guard let session, session.id == sessionID else { return }
        lastRefresh = ProcessInfo.processInfo.systemUptime
        guard let pid = session.processID else { isLoading = false; return }
        isLoading = true
        let includeMinimized = Defaults[.dockPreviewIncludeMinimized]
        let allowCapture = CGPreflightScreenCaptureAccess()
        let width = Int(cardWidth * 2)
        loadTask = Task { [weak self] in
            guard let self else { return }
            let windows = await service.windows(for: pid, includeMinimized: includeMinimized, limit: 12, allowCapture: allowCapture)
            guard !Task.isCancelled, self.session?.id == sessionID else { return }
            self.session?.windows = windows
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
