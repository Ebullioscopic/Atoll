import AppKit

struct ScreenDetector {
    struct Candidate {
        let frame: CGRect
        let hasNotch: Bool
        let isMain: Bool
    }

    /// Simulated notch width for non-notch screens — scales with screen width.
    /// User scaling is applied in NotchPanelView.effectiveNotchW (reactive via @AppStorage).
    private static func fakeNotchWidth(for screen: NSScreen) -> CGFloat {
        let screenW = screen.frame.width
        return min(max(screenW * 0.14, 160), 240)
    }

    static func autoPreferredIndex(candidates: [Candidate], activeWindowBounds: CGRect?) -> Int? {
        guard !candidates.isEmpty else { return nil }

        if let activeWindowBounds {
            let center = CGPoint(x: activeWindowBounds.midX, y: activeWindowBounds.midY)
            if let index = candidates.firstIndex(where: { $0.frame.contains(center) }) {
                return index
            }

            let bestOverlap = candidates.enumerated()
                .map { offset, candidate in
                    (offset, overlapArea(lhs: candidate.frame, rhs: activeWindowBounds))
                }
                .max { lhs, rhs in lhs.1 < rhs.1 }

            if let bestOverlap, bestOverlap.1 > 0 {
                return bestOverlap.0
            }
        }

        if let notchIndex = candidates.firstIndex(where: \.hasNotch) {
            return notchIndex
        }

        if let mainIndex = candidates.firstIndex(where: \.isMain) {
            return mainIndex
        }

        return candidates.indices.first
    }

    /// Preferred screen: active work screen first, then built-in (notch), then main
    static var preferredScreen: NSScreen {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return NSScreen.main ?? NSScreen()
        }

        let mainScreen = NSScreen.main
        let candidates = screens.map { screen in
            Candidate(
                frame: screen.frame,
                hasNotch: screenHasNotch(screen),
                isMain: mainScreen == screen
            )
        }

        if let index = autoPreferredIndex(
            candidates: candidates,
            activeWindowBounds: frontmostApplicationWindowBounds()
        ), index < screens.count {
            return screens[index]
        }

        return mainScreen ?? screens.first ?? NSScreen()
    }

    static var hasNotch: Bool {
        screenHasNotch(preferredScreen)
    }

    /// Check if a specific screen has a notch
    static func screenHasNotch(_ screen: NSScreen) -> Bool {
        if #available(macOS 12.0, *) {
            return screen.auxiliaryTopLeftArea != nil || screen.auxiliaryTopRightArea != nil
        }
        return false
    }

    /// Height of the notch/menu bar area for a specific screen
    static func topBarHeight(for screen: NSScreen) -> CGFloat {
        let realNotchHeight: CGFloat
        if #available(macOS 12.0, *) {
            realNotchHeight = screen.safeAreaInsets.top
        } else {
            realNotchHeight = 0
        }

        // Menu bar height — only present on the screen that has it
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY

        func resolvedMenuBarHeight() -> CGFloat {
            // On the primary screen, this is ~25pt (non-notch) or ~37pt (notch)
            // On secondary screens without menu bar, this is 0
            if menuBarHeight > 5 { return menuBarHeight }
            if let main = NSScreen.main {
                let mainMenuBar = main.frame.maxY - main.visibleFrame.maxY
                if mainMenuBar > 5 { return mainMenuBar }
            }
            return 25
        }

        let modeRaw = UserDefaults.standard.string(forKey: SettingsKey.notchHeightMode) ?? SettingsDefaults.notchHeightMode
        let mode = NotchHeightMode(rawValue: modeRaw) ?? .matchNotch

        switch mode {
        case .matchNotch:
            if realNotchHeight > 0 { return realNotchHeight }
            return resolvedMenuBarHeight()
        case .matchMenuBar:
            return resolvedMenuBarHeight()
        case .custom:
            let custom = UserDefaults.standard.double(forKey: SettingsKey.customNotchHeight)
            let fallback = SettingsDefaults.customNotchHeight
            return CGFloat(max(15, min(custom > 0 ? custom : fallback, 60)))
        }
    }

    /// Height of the notch area — returns menu bar height on non-notch screens
    static var notchHeight: CGFloat {
        topBarHeight(for: preferredScreen)
    }

    /// Width of the notch — returns simulated width on non-notch screens
    static var notchWidth: CGFloat {
        notchWidth(for: preferredScreen)
    }

    /// Width of the notch for a specific screen
    static func notchWidth(for screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *) {
            let leftWidth = screen.auxiliaryTopLeftArea?.width ?? 0
            let rightWidth = screen.auxiliaryTopRightArea?.width ?? 0
            if leftWidth > 0 || rightWidth > 0 {
                return screen.frame.width - leftWidth - rightWidth
            }
        }
        return fakeNotchWidth(for: screen)
    }

    static func signature(for screen: NSScreen) -> String {
        let frame = screen.frame.integral
        return "\(Int(frame.origin.x)):\(Int(frame.origin.y)):\(Int(frame.width)):\(Int(frame.height))"
    }

    private static func overlapArea(lhs: CGRect, rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }

    private static func frontmostApplicationWindowBounds() -> CGRect? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let preferredPID: pid_t? = frontApp.processIdentifier == ownPID ? nil : frontApp.processIdentifier

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 0,
                  rect.height > 0 else { continue }
            guard pid != ownPID else { continue }
            if let preferredPID, pid != preferredPID { continue }
            return rect
        }

        guard preferredPID != nil else { return nil }

        for window in windowList {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 0,
                  rect.height > 0 else { continue }
            return rect
        }

        return nil
    }
}
