//
//  MenuBarLayout.swift
//  DynamicIsland
//
//  Where the frontmost app's menus end, so a live activity can stay out of
//  their way.
//

import AppKit
import ApplicationServices
import Combine

/// Tracks the right edge of the frontmost application's menu bar items.
///
/// A live activity draws into the strip of menu bar to the left of the notch,
/// which is the same strip the app's own menus occupy. macOS lays those menus
/// out inside `NSScreen.auxiliaryTopLeftArea` and offers no way to tell it that
/// something else is using part of that space -- both auxiliary areas are
/// read-only and derived from the display hardware. So rather than reserving
/// room, Atoll measures what is already there and moves aside.
///
/// The measurement is the accessibility API's view of the menu bar, which is
/// how the geometry is available at all: every menu reports its own position
/// and size.
@MainActor
final class MenuBarLayout: ObservableObject {
    static let shared = MenuBarLayout()

    /// Right edge of the last menu of the frontmost app, in screen coordinates.
    /// `nil` when it cannot be known -- no accessibility permission, an app that
    /// exposes no menu bar, or a process that did not answer in time. Callers
    /// treat that as "no constraint" rather than guessing.
    @Published private(set) var appMenusRightEdge: CGFloat?

    /// Menus change with the frontmost app, and within an app as its windows
    /// change, so a slow poll backs up the activation notice. It runs only
    /// while something actually needs the measurement.
    private static let pollInterval: TimeInterval = 3

    private var observer: NSObjectProtocol?
    private var pollTimer: Timer?
    private var trackers = 0
    private var inFlight = false

    private init() {}

    /// How far right content of `contentWidth`, centred in `screenFrame`, has to
    /// move so its left edge clears menus ending at `menusRightEdge`.
    ///
    /// Zero when nothing is covered. Capped at the room remaining on the right,
    /// because a shift that pushes the content off the far edge has traded one
    /// covered thing for another.
    nonisolated static func clearanceOffset(
        contentWidth: CGFloat,
        screenFrame: CGRect,
        menusRightEdge: CGFloat,
        gap: CGFloat
    ) -> CGFloat {
        guard contentWidth > 0 else { return 0 }
        let contentLeftEdge = screenFrame.midX - contentWidth / 2
        let overlap = (menusRightEdge + gap) - contentLeftEdge
        guard overlap > 0 else { return 0 }
        let rightHeadroom = max(0, screenFrame.maxX - (contentLeftEdge + contentWidth))
        return min(overlap, rightHeadroom)
    }

    /// Breathing room between the last menu and the notch content, so they do
    /// not end up flush against each other.
    nonisolated static let clearanceGap: CGFloat = 8

    /// Begin measuring. Balanced by `stopTracking()`; nested calls are counted,
    /// so several live activities can ask at once without one's disappearance
    /// stopping the others.
    func startTracking() {
        trackers += 1
        guard trackers == 1 else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        refresh()
    }

    func stopTracking() {
        guard trackers > 0 else { return }
        trackers -= 1
        guard trackers == 0 else { return }

        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        pollTimer?.invalidate()
        pollTimer = nil
        appMenusRightEdge = nil
    }

    func refresh() {
        guard !inFlight else { return }
        guard AXIsProcessTrusted() else {
            appMenusRightEdge = nil
            return
        }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            appMenusRightEdge = nil
            return
        }

        // Off the main actor: these are cross-process calls, and an app that has
        // stopped answering would otherwise take the notch's UI down with it.
        inFlight = true
        Task.detached(priority: .utility) {
            let edge = Self.menusRightEdge(pid: pid)
            await MainActor.run {
                self.inFlight = false
                guard self.trackers > 0 else { return }
                if self.appMenusRightEdge != edge { self.appMenusRightEdge = edge }
            }
        }
    }

    /// The right edge of the last menu, or `nil` if the menu bar cannot be read.
    nonisolated private static func menusRightEdge(pid: pid_t) -> CGFloat? {
        let app = AXUIElementCreateApplication(pid)
        // A hung app must not hold this up; the measurement is an optimisation,
        // never something worth waiting on.
        AXUIElementSetMessagingTimeout(app, 0.25)

        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              CFGetTypeID(menuBarValue) == AXUIElementGetTypeID()
        else { return nil }
        let menuBar = unsafeBitCast(menuBarValue, to: AXUIElement.self)

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let items = childrenValue as? [AXUIElement], !items.isEmpty
        else { return nil }

        var rightEdge: CGFloat?
        for item in items {
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue) == .success
            else { continue }

            var origin = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
                  AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            else { continue }

            rightEdge = max(rightEdge ?? 0, origin.x + size.width)
        }
        return rightEdge
    }
}
