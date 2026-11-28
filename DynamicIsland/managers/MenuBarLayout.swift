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
import SwiftUI

/// Where a closed live activity sits relative to the frontmost app's menus.
enum ClosedActivityPlacement: Equatable {
    /// Wings on both sides of the notch, as designed.
    case centered
    /// Both wings drawn to the right of the notch.
    case trailing
    /// Both wings drawn to the left of the notch.
    case leading
    /// Wings folded away: only the notch itself is drawn.
    case retracted
}

/// Raised by a closed live activity that can draw both its wings on one side
/// of the notch (see `ClosedActivityPlacement.trailing` / `.leading`).
struct ClosedWingsGatherableKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// A zero-spacing row for the closed music activity's three sections, given in
/// the order artwork wing, middle, trailing wing, and placed in the order that
/// `placement` calls for.
///
/// Each section is declared once and reordered here rather than repeated in a
/// `switch`: repeating the same opaque-typed sections in several branches makes
/// the Release (whole-module) build reject `ContentView.body` as an opaque type
/// defined in terms of itself.
struct ClosedMusicSectionsLayout: Layout {
    var placement: ClosedActivityPlacement

    /// Indices of the sections from leading to trailing edge.
    static func order(for placement: ClosedActivityPlacement) -> [Int] {
        switch placement {
        case .trailing: return [1, 0, 2]
        case .leading: return [0, 2, 1]
        case .centered, .retracted: return [0, 1, 2]
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return CGSize(
            width: sizes.reduce(0) { $0 + $1.width },
            height: sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let order = subviews.count == 3 ? Self.order(for: placement) : Array(subviews.indices)
        var x = bounds.minX
        for index in order {
            let size = subviews[index].sizeThatFits(.unspecified)
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(size)
            )
            x += size.width
        }
    }
}

/// The frontmost app's menus as read from one display's menu bar.
struct AppMenuBar: Equatable {
    /// Horizontal extent of each menu, in global screen coordinates.
    var spans: [ClosedRange<CGFloat>]
    /// Top-left corner of the first menu in accessibility coordinates (global,
    /// top-left origin). It places the menu bar on its display, which `spans`
    /// alone cannot do when displays are stacked vertically.
    var origin: CGPoint

    /// The spans that constrain an activity on the display with frame
    /// `screenFrame` (Cocoa coordinates). Each display has its own menu bar, and
    /// the accessibility API reports only the one the menus were read from, so
    /// menus measured on another display must not move this display's
    /// activity.
    func spans(onScreen screenFrame: CGRect, primaryScreenMaxY: CGFloat) -> [ClosedRange<CGFloat>] {
        let cocoaPoint = CGPoint(x: origin.x + 1, y: primaryScreenMaxY - origin.y - 1)
        return screenFrame.contains(cocoaPoint) ? spans : []
    }
}

/// Tracks where the frontmost application's menu bar items are.
///
/// A live activity draws into the strips of menu bar on either side of the
/// notch, which is where the app's own menus live. When an app has more menus
/// than fit on the left, macOS carries the rest over to the right of the notch,
/// so both strips can be taken. macOS lays those menus out inside
/// `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` and offers no way
/// to tell it that something else is using part of that space -- both areas
/// are read-only and derived from the display hardware. So rather than
/// reserving room, Atoll measures what is already there and steps aside.
///
/// The measurement is the accessibility API's view of the menu bar, which is
/// how the geometry is available at all: every menu reports its own position
/// and size.
@MainActor
final class MenuBarLayout: ObservableObject {
    static let shared = MenuBarLayout()

    /// The frontmost app's menus. `nil` when they cannot be known -- no
    /// accessibility permission, an app that exposes no menu bar, a full-screen
    /// window (see `constraint(menus:isFullScreen:)`), or a process that did
    /// not answer in time. Callers treat that as "no constraint" rather than
    /// guessing.
    @Published private(set) var appMenuBar: AppMenuBar?

    /// Menus change with the frontmost app, and within an app as its windows
    /// change, so a slow poll backs up the activation notice. It runs only
    /// while something actually needs the measurement.
    private static let pollInterval: TimeInterval = 3

    private var observer: NSObjectProtocol?
    private var pollTimer: Timer?
    private var trackers = 0
    private var inFlight = false

    private init() {}

    /// Where a closed activity can go without covering a menu.
    ///
    /// The surface is `coreWidth` (the part that sits on the notch, always
    /// drawn centred on it) plus `wingsWidth` of content that normally splits
    /// evenly to both sides. Sliding the whole surface sideways is not an
    /// option: the notch is a hole in the panel, so whatever slides over it is
    /// lost. The wings can only be kept where they are, gathered on the one
    /// side that has room (when the activity can be laid out that way), or
    /// folded away.
    ///
    /// Menus are split by which side of the notch they sit on; each side's
    /// free room runs from its nearest menu, less `gap`, to the notch.
    nonisolated static func placement(
        notch: ClosedRange<CGFloat>,
        coreWidth: CGFloat,
        wingsWidth: CGFloat,
        menuSpans: [ClosedRange<CGFloat>],
        canGatherWings: Bool,
        gap: CGFloat
    ) -> ClosedActivityPlacement {
        guard wingsWidth > 0 || coreWidth > notch.upperBound - notch.lowerBound else { return .centered }
        let split = (notch.lowerBound + notch.upperBound) / 2
        let leftLimit = menuSpans.filter { ($0.lowerBound + $0.upperBound) / 2 < split }
            .map(\.upperBound).max().map { $0 + gap } ?? -.infinity
        let rightLimit = menuSpans.filter { ($0.lowerBound + $0.upperBound) / 2 >= split }
            .map(\.lowerBound).min().map { $0 - gap } ?? .infinity
        let leftRoom = notch.lowerBound - leftLimit
        let rightRoom = rightLimit - notch.upperBound

        // How far the core alone reaches past each edge of the notch.
        let coreReach = max(0, (coreWidth - (notch.upperBound - notch.lowerBound)) / 2)
        let centredReach = coreReach + wingsWidth / 2
        if centredReach <= leftRoom && centredReach <= rightRoom { return .centered }

        if canGatherWings {
            let gatheredReach = coreReach + wingsWidth
            if coreReach <= leftRoom && gatheredReach <= rightRoom { return .trailing }
            if coreReach <= rightRoom && gatheredReach <= leftRoom { return .leading }
        }
        return .retracted
    }

    /// Whether a closed activity should make way for the menus at all.
    ///
    /// Only a settled, closed live activity does. Sneak peeks and HUDs (volume,
    /// brightness, a track change) come and go in a moment and are what the
    /// user is looking at, so they keep their full width even over a menu. A
    /// connectivity HUD must also remain centred on the physical notch: its
    /// middle transparent lane is what keeps both wings visible, and moving or
    /// folding it would put that lane underneath the camera housing and clip
    /// one of the two content areas. The floating island is not in the menu
    /// bar's way.
    nonisolated static func yieldsToMenus(
        isNotchClosed: Bool,
        isHiddenOnClosed: Bool,
        isIslandMode: Bool,
        isConnectivityHUDVisible: Bool,
        isSneakPeekVisible: Bool,
        isExpansionVisible: Bool
    ) -> Bool {
        isNotchClosed
            && !isHiddenOnClosed
            && !isIslandMode
            && !isConnectivityHUDVisible
            && !isSneakPeekVisible
            && !isExpansionVisible
    }

    /// What a menu-bar reading means for placement: `nil` (no constraint) when
    /// the focused window is full screen -- the menu bar is hidden there, yet
    /// the accessibility API still reports the old positions -- or when no menu
    /// with a width was measured.
    nonisolated static func constraint(menus: AppMenuBar?, isFullScreen: Bool) -> AppMenuBar? {
        guard !isFullScreen, var menus else { return nil }
        menus.spans.removeAll { $0.upperBound <= $0.lowerBound }
        return menus.spans.isEmpty ? nil : menus
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
        appMenuBar = nil
    }

    func refresh() {
        guard !inFlight else { return }
        guard AXIsProcessTrusted() else {
            appMenuBar = nil
            return
        }
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            appMenuBar = nil
            return
        }

        // Off the main actor: these are cross-process calls, and an app that has
        // stopped answering would otherwise take the notch's UI down with it.
        inFlight = true
        Task.detached(priority: .utility) {
            let menus = Self.appMenuBar(pid: pid)
            await MainActor.run {
                self.inFlight = false
                guard self.trackers > 0 else { return }
                if self.appMenuBar != menus { self.appMenuBar = menus }
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

    /// Whether the app's focused window is full screen, where the menu bar is
    /// hidden but the accessibility API keeps reporting its old geometry.
    nonisolated private static func isFullScreen(_ app: AXUIElement) -> Bool {
        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else { return false }
        let window = unsafeBitCast(windowValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, elementTimeout)
        var fullScreenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreenValue) == .success
        else { return false }
        return (fullScreenValue as? Bool) ?? false
    }

    /// The app's menus as a placement constraint; see `constraint(menus:isFullScreen:)`.
    nonisolated private static func appMenuBar(pid: pid_t) -> AppMenuBar? {
        let app = AXUIElementCreateApplication(pid)
        // A hung app must not hold this up; the measurement is an optimisation,
        // never something worth waiting on.
        AXUIElementSetMessagingTimeout(app, elementTimeout)
        // Full screen needs no scan: whatever it found would be discarded.
        let fullScreen = isFullScreen(app)
        return constraint(menus: fullScreen ? nil : readMenus(of: app), isFullScreen: fullScreen)
    }

    /// Each menu's extent, or `nil` if the menu bar cannot be read.
    nonisolated private static func readMenus(of app: AXUIElement) -> AppMenuBar? {
        let startedAt = Date()

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

        var spans: [ClosedRange<CGFloat>] = []
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

            if firstOrigin == nil { firstOrigin = origin }
            spans.append(origin.x...(origin.x + max(0, size.width)))
        }
        guard let firstOrigin else { return nil }
        return AppMenuBar(spans: spans, origin: firstOrigin)
    }
}
