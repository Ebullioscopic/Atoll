import AppKit
import CoreGraphics

/// #219 — on external screens the simulated notch sits centered in the menu
/// bar, which can overlap third-party status items (Bartender's bar, iStat
/// menus, …). This helper reads the geometry of visible status-bar windows
/// (bounds/layer/owner only — no Screen Recording permission needed) and
/// nudges the island into the nearest clear gap.
enum MenuBarIconAvoidance {

    /// NSStatusItem windows live on this CGWindow layer.
    private static let statusBarWindowLayer = 25

    /// Never move the island further than this fraction of the screen width
    /// away from its preferred position — a packed menu bar shouldn't shove
    /// the island into a corner.
    static let maxShiftFraction: CGFloat = 0.25

    /// Breathing room kept between the island and the nearest status icon.
    static let margin: CGFloat = 8

    /// X-intervals (AppKit coordinates, in `screen`'s space) of visible
    /// status-bar windows on `screen`'s menu bar, excluding our own windows.
    @MainActor
    static func occupiedMenuBarRanges(on screen: NSScreen) -> [ClosedRange<CGFloat>] {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] else { return [] }

        // CGWindowList uses a global top-left origin anchored at the primary
        // screen; AppKit uses bottom-left. Convert via the primary screen height.
        guard let primary = NSScreen.screens.first else { return [] }
        let primaryHeightCG = primary.frame.maxY

        let menuBarHeight = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
        let menuBarTopY = screen.frame.maxY
        let ownPid = Int32(ProcessInfo.processInfo.processIdentifier)

        var ranges: [ClosedRange<CGFloat>] = []
        for info in windowInfo {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == statusBarWindowLayer,
                  let ownerPid = info[kCGWindowOwnerPID as String] as? Int32,
                  ownerPid != ownPid,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }

            guard let x = boundsDict["X"], let y = boundsDict["Y"],
                  let width = boundsDict["Width"], let height = boundsDict["Height"],
                  width > 0, height > 0 else { continue }

            // Convert the window's CG top-left Y to AppKit bottom-left.
            let appKitMaxY = primaryHeightCG - y
            // Keep only windows whose top edge sits in this screen's menu bar band.
            guard appKitMaxY <= menuBarTopY + 1,
                  appKitMaxY >= menuBarTopY - menuBarHeight - 1 else { continue }
            // And which horizontally belong to this screen.
            let minX = x
            let maxX = x + width
            guard maxX > screen.frame.minX, minX < screen.frame.maxX else { continue }

            ranges.append(max(minX, screen.frame.minX)...min(maxX, screen.frame.maxX))
        }
        return ranges
    }

    /// Pure placement: returns the X for `panelWidth` that avoids `occupied`
    /// ranges while staying as close to `preferredX` as possible. Falls back to
    /// `preferredX` when there is no clear gap within the allowed shift.
    static func resolvedX(
        preferredX: CGFloat,
        panelWidth: CGFloat,
        occupied: [ClosedRange<CGFloat>],
        screenMinX: CGFloat,
        screenMaxX: CGFloat,
        maxShift: CGFloat
    ) -> CGFloat {
        let merged = mergeRanges(occupied)
        guard overlaps(x: preferredX, width: panelWidth, ranges: merged) else { return preferredX }

        var candidates: [CGFloat] = []
        for range in merged {
            candidates.append(range.lowerBound - margin - panelWidth) // slide in on the left
            candidates.append(range.upperBound + margin)              // slide in on the right
        }

        let viable = candidates.filter { x in
            x >= screenMinX
                && x + panelWidth <= screenMaxX
                && abs(x - preferredX) <= maxShift
                && !overlaps(x: x, width: panelWidth, ranges: merged)
        }

        return viable.min(by: { abs($0 - preferredX) < abs($1 - preferredX) }) ?? preferredX
    }

    static func mergeRanges(_ ranges: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        guard !ranges.isEmpty else { return [] }
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<CGFloat>] = [sorted[0]]
        for range in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if range.lowerBound <= last.upperBound + margin {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func overlaps(x: CGFloat, width: CGFloat, ranges: [ClosedRange<CGFloat>]) -> Bool {
        let panelRange = x...(x + width)
        return ranges.contains { $0.overlaps(panelRange) }
    }
}
