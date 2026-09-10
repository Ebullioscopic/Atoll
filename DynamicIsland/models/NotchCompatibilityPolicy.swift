import Foundation
import CoreGraphics

/// Pure policy. All rectangles use the same global, top-left-origin coordinates
/// as CGWindowListCopyWindowInfo. No process discovery, window ordering, or UI.
enum NotchCompatibilityPolicy {
    static let baselineLevel = 27
    static let maximumLevel = 102
    static let iBarBundleIdentifier = "com.better365.iBarPro"

    struct Window: Equatable {
        let id: UInt32
        let ownerPID: Int32
        let name: String?
        let frame: CGRect
        let level: Int
        let alpha: Double
        let isOnscreen: Bool
        /// Position in the full CG list, used only for cache change detection.
        var zOrder: Int = 0
    }

    /// An unavailable list means baseline, never a guessed compatibility level.
    /// The caller identifies iBar by bundle ID and supplies its current PID(s).
    static func recommendedLevel(
        screenFrame: CGRect,
        menuBarHeight: CGFloat,
        notchFrame: CGRect,
        iBarPIDs: Set<Int32>,
        windows: [Window]?,
        popupMenuLevel: Int
    ) -> Int {
        guard popupMenuLevel > baselineLevel, popupMenuLevel < maximumLevel,
              valid(screenFrame), valid(notchFrame),
              menuBarHeight.isFinite, menuBarHeight > 0,
              !iBarPIDs.isEmpty, let windows else { return baselineLevel }
        let strip = CGRect(x: screenFrame.minX, y: screenFrame.minY,
                           width: screenFrame.width, height: min(menuBarHeight, 64))
        let target = strip.intersection(notchFrame)
        guard valid(target) else { return baselineLevel }
        let ceiling = popupMenuLevel - 1
        var result = baselineLevel
        for window in windows {
            guard iBarPIDs.contains(window.ownerPID), window.isOnscreen,
                  window.alpha.isFinite, window.alpha > 0,
                  window.level >= baselineLevel, window.level <= popupMenuLevel,
                  valid(window.frame) else { continue }
            // Window names may be redacted without screen-recording permission.
            // CG's observed title is "iBarmenu". "MenuBarWindow" is an AX
            // identifier, not the title supplied by CGWindowListCopyWindowInfo.
            if let name = window.name, !name.isEmpty, name != "iBarmenu" { continue }
            // A broad, thin surface at this display's top edge, not an iBar
            // preferences window, dropdown, tooltip, or fullscreen shield.
            let frame = window.frame
            guard frame.height >= 8, frame.height <= 64,
                  frame.width >= max(240, frame.height * 8),
                  abs(frame.minY - strip.minY) <= 8,
                  valid(frame.intersection(target)) else { continue }
            if window.level == popupMenuLevel {
                // Confirmed iBar decoration: 1280x34 at (0,-1), layer 101.
                // Only this full-width top-bar shape may cross the popup level;
                // never chase a future layer 102+ overlay or a popup/dialog.
                guard frame.intersection(screenFrame).width >= screenFrame.width * 0.8 else { continue }
                result = max(result, popupMenuLevel + 1)
            } else {
                result = max(result, min(ceiling, window.level + 1))
            }
        }
        // The parent decides whether lock/fullscreen/Spaces rules permit applying
        // this recommendation. No window other than the notch should use it.
        return result
    }

    /// Convert an AppKit global frame using the PRIMARY display's top edge,
    /// not the height of the target display (important for stacked displays).
    static func windowServerFrame(fromAppKit frame: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenTop - frame.maxY,
               width: frame.width, height: frame.height)
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite && rect.width > 0 && rect.height > 0
    }
}
