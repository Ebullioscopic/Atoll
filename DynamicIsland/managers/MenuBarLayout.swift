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

    /// Right edge of the last menu of the frontmost app, measured from the left
    /// edge of the display whose menu bar it was read on.
    /// `nil` when it cannot be known -- no accessibility permission, an app that
    /// exposes no menu bar, or a process that did not answer in time. Callers
    /// treat that as "no constraint" rather than guessing.
    ///
    /// Relative, not global: with several displays the frontmost app's menus are
    /// drawn in every display's menu bar at the same offset, but the
    /// accessibility API reports only one of them. Comparing a global x against
    /// another display's frame made that display's island shove its content
    /// hundreds of points sideways, out of the notch shape -- the background
    /// animated with nothing visible on top.
    @Published private(set) var appMenusRightInset: CGFloat?

    /// Right edge of the frontmost app's menus in the menu bar of the display
    /// with frame `screenFrame` (Cocoa coordinates), or `nil` when unknown.
    func appMenusRightEdge(in screenFrame: CGRect) -> CGFloat? {
        appMenusRightInset.map { screenFrame.minX + $0 }
    }

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
        appMenusRightInset = nil
    }

    func refresh() {
        guard !inFlight else { return }
        guard AXIsProcessTrusted() else {
            appMenusRightInset = nil
            return
        }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            appMenusRightInset = nil
            return
        }
        // Display frames are read here, on the main actor, and handed to the scan.
        let screenFrames = NSScreen.screens.map(\.frame)
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0

        // Off the main actor: these are cross-process calls, and an app that has
        // stopped answering would otherwise take the notch's UI down with it.
        inFlight = true
        Task.detached(priority: .utility) {
            let inset = Self.menusRightInset(pid: pid, screenFrames: screenFrames, primaryMaxY: primaryMaxY)
            await MainActor.run {
                self.inFlight = false
                guard self.trackers > 0 else { return }
                if self.appMenusRightInset != inset { self.appMenusRightInset = inset }
            }
        }
    }

    /// Longest the whole scan may take. A menu bar with many items could
    /// otherwise reach minutes at the per-element timeout, and until it returns
    /// no further measurement is taken.
    nonisolated private static let scanDeadline: TimeInterval = 1

    /// Per-element messaging timeout. `AXUIElementSetMessagingTimeout` applies
    /// only to the element it is called on -- it does not carry to the children
    /// that element hands back -- so every element messaged here is given its
    /// own, or a hung app would still block on the ones that inherited nothing.
    nonisolated private static let elementTimeout: Float = 0.25

    /// The right edge of the last menu relative to the left edge of the display it
    /// sits on, or `nil` if the menu bar cannot be read.
    nonisolated private static func menusRightInset(pid: pid_t, screenFrames: [CGRect], primaryMaxY: CGFloat) -> CGFloat? {
        let startedAt = Date()
        let app = AXUIElementCreateApplication(pid)
        // A hung app must not hold this up; the measurement is an optimisation,
        // never something worth waiting on.
        AXUIElementSetMessagingTimeout(app, elementTimeout)

        var menuBarValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              CFGetTypeID(menuBarValue) == AXUIElementGetTypeID()
        else { return nil }
        let menuBar = unsafeBitCast(menuBarValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(menuBar, elementTimeout)

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let items = childrenValue as? [AXUIElement], !items.isEmpty
        else { return nil }

        var rightEdge: CGFloat?
        var firstOrigin: CGPoint?
        for item in items {
            // Whatever has been measured so far is still usable; a scan that has
            // run long is one where the app is not answering, and waiting out
            // every remaining item only delays the next attempt.
            guard Date().timeIntervalSince(startedAt) < scanDeadline else { break }
            AXUIElementSetMessagingTimeout(item, elementTimeout)

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
            if firstOrigin == nil { firstOrigin = origin }
        }
        guard let rightEdge, let firstOrigin else { return nil }
        return relativeInset(
            rightEdge: rightEdge,
            menuOrigin: firstOrigin,
            screenFrames: screenFrames,
            primaryMaxY: primaryMaxY
        )
    }

    /// Converts a menu bar right edge read through accessibility (global,
    /// top-left origin) into an offset from the left edge of the display whose
    /// menu bar holds the menu at `menuOrigin`.
    nonisolated static func relativeInset(
        rightEdge: CGFloat,
        menuOrigin: CGPoint,
        screenFrames: [CGRect],
        primaryMaxY: CGFloat
    ) -> CGFloat {
        // Accessibility uses a top-left origin; NSScreen frames a bottom-left one.
        let cocoaPoint = CGPoint(x: menuOrigin.x + 1, y: primaryMaxY - menuOrigin.y - 1)
        let screen = screenFrames.first { $0.contains(cocoaPoint) }
            ?? screenFrames.first { menuOrigin.x >= $0.minX && menuOrigin.x < $0.maxX }
        return rightEdge - (screen?.minX ?? 0)
    }
}
