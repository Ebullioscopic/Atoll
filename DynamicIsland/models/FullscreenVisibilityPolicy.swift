import Foundation

/// All rectangles use WindowServer coordinates (origin at the primary display's
/// top left). Inputs contain metadata only; no accessibility or workspace calls.
enum FullscreenVisibilityPolicy {
    enum HideMode { case always, nowPlayingOnly, never }

    struct Screen {
        let name: String
        let frame: CGRect
        let safeFrame: CGRect
    }

    struct Window {
        let id: UInt32
        let pid: Int32
        let bundleIdentifier: String?
        let frame: CGRect
        let layer: Int
        let alpha: Double
        let isOnscreen: Bool
    }

    struct NativeWindow {
        let id: UInt32
        let pid: Int32
        let isFullscreen: Bool
    }

    /// Input order is CG's front-to-back order. A foreground screen-filling
    /// ordinary window must not inherit fullscreen from a window behind it.
    static func candidate(on screen: Screen, windows: [Window]) -> Window? {
        windows.first {
            $0.isOnscreen && $0.layer == 0 && $0.alpha.isFinite && $0.alpha > 0
                && $0.bundleIdentifier != "com.apple.finder"
                && $0.bundleIdentifier != "com.apple.dock"
                && (fills($0.frame, screen.frame) || fills($0.frame, screen.safeFrame))
        }
    }

    static func statuses(screens: [Screen], windows: [Window], nativeWindows: [NativeWindow],
                         accessibilityTrusted: Bool, enabled: Bool, mode: HideMode,
                         mediaBundleIdentifier: String?) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for screen in screens {
            var hidden = false
            if enabled, mode != .never, let window = candidate(on: screen, windows: windows),
               mode == .always || (mediaBundleIdentifier != nil
                    && window.bundleIdentifier == mediaBundleIdentifier) {
                // No AX permission retains the previous geometric fallback. It
                // cannot distinguish a maximized window from native fullscreen.
                // With AX permission, missing/failed identity is NOT evidence.
                hidden = !accessibilityTrusted || nativeWindows.contains {
                    $0.pid == window.pid && $0.id == window.id && $0.isFullscreen
                }
            }
            // localizedName is the existing public contract. Duplicate display
            // names cannot be represented independently; avoid a dictionary trap.
            result[screen.name] = (result[screen.name] ?? false) || hidden
        }
        return result
    }

    private static func fills(_ window: CGRect, _ screen: CGRect) -> Bool {
        guard [window.origin.x, window.origin.y, window.size.width, window.size.height,
               screen.origin.x, screen.origin.y, screen.size.width, screen.size.height].allSatisfy(\.isFinite),
              window.size.width > 0, window.size.height > 0,
              screen.size.width > 0, screen.size.height > 0 else { return false }
        return abs(window.origin.x - screen.origin.x) <= 5 && abs(window.origin.y - screen.origin.y) <= 5
            && abs(window.size.width - screen.size.width) <= screen.size.width * 0.02
            && abs(window.size.height - screen.size.height) <= screen.size.height * 0.02
    }
}
