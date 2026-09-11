import AppKit
import CoreGraphics

/// Metadata-only observer. It never launches/activates apps, prompts for screen
/// recording permission, changes a window level, or orders a window front.
/// Parent owns lock/fullscreen/Spaces gates and applies levels ONLY to its notch
/// windows. Call start once, stop at teardown, and apply the cached recommendation
/// on creation/positioning as well as in onChange.
@MainActor
final class NotchCompatibilityMonitor {
    static let shared = NotchCompatibilityMonitor()

    /// Synchronous main-actor notification after the cache changes (including
    /// the iBar windows' positions in CG's front-to-back window list). Reading
    /// recommendedLevel here does not perform another CG window-list query.
    var onChange: (() -> Void)?
    private(set) var isIBarRunning = false
    private(set) var windowInfoAvailable = false

    private var started = false
    private var iBarPIDs: Set<Int32> = []
    private var cachedWindows: [NotchCompatibilityPolicy.Window]?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var pollTimer: Timer?

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(forceNotification: true) }
        }
        refresh(forceNotification: true)
    }

    func stop() {
        guard started else { return }
        started = false
        pollTimer?.invalidate()
        pollTimer = nil
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        let changed = isIBarRunning || cachedWindows != nil
        iBarPIDs = []
        cachedWindows = nil
        isIBarRunning = false
        windowInfoAvailable = false
        if changed { onChange?() }
    }

    /// The frame must be the positioned notch window's AppKit global frame.
    /// Pass the intended screen explicitly during creation; window.screen can
    /// briefly refer to the wrong display until positioning has completed.
    func recommendedLevel(for notchWindowFrame: CGRect, on screen: NSScreen) -> NSWindow.Level {
        guard let primary = NSScreen.screens.first else {
            return NSWindow.Level(rawValue: NotchCompatibilityPolicy.baselineLevel)
        }
        let screenFrame = NotchCompatibilityPolicy.windowServerFrame(
            fromAppKit: screen.frame, primaryScreenTop: primary.frame.maxY)
        let notchFrame = NotchCompatibilityPolicy.windowServerFrame(
            fromAppKit: notchWindowFrame, primaryScreenTop: primary.frame.maxY)
        let visibleInset = screen.frame.maxY - screen.visibleFrame.maxY
        let menuBarHeight = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness,
                                (0...64).contains(visibleInset) ? visibleInset : 0)
        return NSWindow.Level(rawValue: NotchCompatibilityPolicy.recommendedLevel(
            screenFrame: screenFrame, menuBarHeight: menuBarHeight, notchFrame: notchFrame,
            iBarPIDs: iBarPIDs, windows: cachedWindows,
            popupMenuLevel: NSWindow.Level.popUpMenu.rawValue))
    }

    /// Explicit metadata refresh for parent lifecycle events. No CG calls while
    /// iBar is absent; no polling timer is installed until it is running.
    func refresh() { refresh(forceNotification: false) }

    private func refresh(forceNotification: Bool) {
        guard started else { return }
        let pids = Set(NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleIdentifier == NotchCompatibilityPolicy.iBarBundleIdentifier
        }.map(\.processIdentifier))
        if pids.isEmpty {
            pollTimer?.invalidate()
            pollTimer = nil
        } else if pollTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            timer.tolerance = 0.25
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        }
        // Exactly one full visible-window metadata query per refresh, shared
        // by all notch screens. Do not depend on window titles being available.
        let windows: [NotchCompatibilityPolicy.Window]?
        if pids.isEmpty {
            windows = nil
        } else if let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            windows = info.enumerated().compactMap { zOrder, value in
                guard let pid = value[kCGWindowOwnerPID as String] as? NSNumber,
                      pids.contains(pid.int32Value),
                      let id = value[kCGWindowNumber as String] as? NSNumber,
                      let layer = value[kCGWindowLayer as String] as? NSNumber,
                      let bounds = value[kCGWindowBounds as String] as? [String: Any],
                      let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                      let alpha = value[kCGWindowAlpha as String] as? NSNumber,
                      let onscreen = value[kCGWindowIsOnscreen as String] as? NSNumber else { return nil }
                return NotchCompatibilityPolicy.Window(id: id.uint32Value, ownerPID: pid.int32Value,
                    name: value[kCGWindowName as String] as? String, frame: frame, level: layer.intValue,
                    alpha: alpha.doubleValue, isOnscreen: onscreen.boolValue, zOrder: zOrder)
            }.sorted { $0.id < $1.id }
        } else {
            windows = nil
        }
        let changed = pids != iBarPIDs || windows != cachedWindows
        iBarPIDs = pids
        cachedWindows = windows
        isIBarRunning = !pids.isEmpty
        windowInfoAvailable = windows != nil
        if changed || forceNotification { onChange?() }
    }
}
