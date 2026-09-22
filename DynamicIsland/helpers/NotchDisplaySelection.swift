// ToolIsle display-selection fix, 2026-09-22.
// SPDX-License-Identifier: GPL-3.0-or-later
// Kept independent of AppKit so the same selection policy can be regression-tested.

struct NotchDisplayCandidate {
    let name: String
    let isBuiltIn: Bool
    let hasNotch: Bool
}

enum NotchDisplaySelection {
    /// Empty preference means automatic, not the screen with keyboard focus.
    /// An explicit available selection always wins. An unavailable explicit
    /// selection is retained by the caller and only falls back when enabled.
    static func index(
        in displays: [NotchDisplayCandidate],
        preferredName: String = "",
        allowsFallback: Bool = true
    ) -> Int? {
        guard !displays.isEmpty else { return nil }
        if !preferredName.isEmpty && preferredName != "Unknown" {
            if let selected = displays.firstIndex(where: { $0.name == preferredName }) {
                return selected
            }
            if !allowsFallback { return nil }
        }
        return displays.firstIndex(where: { $0.isBuiltIn && $0.hasNotch })
            ?? displays.firstIndex(where: { $0.isBuiltIn })
            ?? displays.startIndex
    }
}

#if canImport(AppKit)
import AppKit
import CoreGraphics

extension NotchDisplaySelection {
    /// NSScreen.screens lists currently available screens, so clamshell mode
    /// falls back to the primary external display and reopening the lid returns
    /// automatic mode to the built-in screen. No default is saved as a user choice.
    static func screen(
        preferredName: String = "",
        allowsFallback: Bool = true
    ) -> NSScreen? {
        let screens = NSScreen.screens
        let candidates = screens.map { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let builtIn = number.map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
            return NotchDisplayCandidate(
                name: screen.localizedName,
                isBuiltIn: builtIn,
                hasNotch: screen.safeAreaInsets.top > 0
            )
        }
        guard let selected = index(
            in: candidates, preferredName: preferredName, allowsFallback: allowsFallback
        ) else { return nil }
        return screens[selected]
    }
}
#endif
