import Foundation
import CoreGraphics

typealias Policy = FullscreenVisibilityPolicy
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}
let primary = Policy.Screen(name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                            safeFrame: CGRect(x: 0, y: 32, width: 1512, height: 950))
let external = Policy.Screen(name: "External", frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                             safeFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1080))
func window(_ id: UInt32 = 1, pid: Int32 = 100, bundle: String? = "browser",
            frame: CGRect = primary.safeFrame, layer: Int = 0, alpha: Double = 1,
            onscreen: Bool = true) -> Policy.Window {
    Policy.Window(id: id, pid: pid, bundleIdentifier: bundle, frame: frame,
                  layer: layer, alpha: alpha, isOnscreen: onscreen)
}
func native(_ id: UInt32 = 1, pid: Int32 = 100, fullscreen: Bool = true) -> Policy.NativeWindow {
    Policy.NativeWindow(id: id, pid: pid, isFullscreen: fullscreen)
}
func status(_ windows: [Policy.Window], nativeWindows: [Policy.NativeWindow] = [native()],
            trusted: Bool = true, enabled: Bool = true, mode: Policy.HideMode = .always,
            media: String? = nil, screens: [Policy.Screen] = [primary, external]) -> [String: Bool] {
    Policy.statuses(screens: screens, windows: windows, nativeWindows: nativeWindows,
                    accessibilityTrusted: trusted, enabled: enabled, mode: mode, mediaBundleIdentifier: media)
}

expect(status([window()])[primary.name] == true, "Visible native fullscreen hides on its screen")
expect(status([window()])[external.name] == false, "Fullscreen does not leak to another screen")
expect(status([window()], nativeWindows: [native(2)])[primary.name] == false,
       "An identical-geometry AX fullscreen window in another Space must not match by PID alone")
expect(status([window()], nativeWindows: [native(pid: 200)])[primary.name] == false,
       "Window IDs from a different PID cannot confirm fullscreen")
expect(status([window()], nativeWindows: [native(fullscreen: false)])[primary.name] == false,
       "A maximized visible window is not native fullscreen")
expect(status([window()], nativeWindows: [])[primary.name] == false, "AX timeout/unavailable identity fails closed")
expect(status([window(2, frame: external.frame)], nativeWindows: [native(2)])[external.name] == true,
       "Negative display coordinates work")
let both = [window(), window(2, frame: external.frame)]
let oneFullscreen = status(both, nativeWindows: [native(2)])
expect(oneFullscreen[primary.name] == false && oneFullscreen[external.name] == true,
       "Same app maximized here and fullscreen on another display are independent")
expect(status([window(frame: primary.frame)])[primary.name] == true, "Full display native frame includes notch area")
expect(status([window(frame: primary.safeFrame)])[primary.name] == true, "Safe-area native frame works")
expect(status([window(onscreen: false)])[primary.name] == false, "Inactive Space is excluded")
expect(status([])[primary.name] == false, "Exiting fullscreen/closing last window restores notch")
expect(status([window(2), window()], nativeWindows: [native()])[primary.name] == false,
       "A foreground maximized window hides a fullscreen window behind it")
expect(status([window(2, frame: CGRect(x: 400, y: 200, width: 300, height: 200)), window()])[primary.name] == true,
       "A small dialog over fullscreen does not remove fullscreen state")
for layer in [-1, 1, 25, 101, 1000] {
    expect(status([window(layer: layer)])[primary.name] == false, "Non-normal layer \(layer) excluded")
}
for alpha in [0.0, -1, Double.nan, Double.infinity] {
    expect(status([window(alpha: alpha)])[primary.name] == false, "Invisible/invalid alpha excluded")
}
for frame in [CGRect.zero, CGRect(x: 0, y: 0, width: 1512, height: 34),
              CGRect(x: 600, y: 32, width: 1512, height: 950),
              CGRect(x: 0, y: 60, width: 1512, height: 922)] {
    expect(status([window(frame: frame)])[primary.name] == false, "Non-screen-filling geometry excluded")
}
for bundle in ["com.apple.finder", "com.apple.dock"] {
    expect(status([window(bundle: bundle)])[primary.name] == false, "Desktop/system host excluded")
}
expect(status([window(bundle: "com.apple.Safari")])[primary.name] == true, "System browser is eligible")
expect(status([window()], nativeWindows: [], trusted: false)[primary.name] == true,
       "No AX permission retains bounded visible-window geometric fallback")
expect(status([window(onscreen: false)], trusted: false)[primary.name] == false,
       "No AX fallback cannot revive other-Space windows")
expect(status([window()], mode: .never)[primary.name] == false, "Explicit never is respected")
expect(status([window()], enabled: false)[primary.name] == false, "Disabled detection clears state")
expect(status([window()], mode: .nowPlayingOnly, media: "browser")[primary.name] == true, "Current media match")
expect(status([window()], mode: .nowPlayingOnly, media: "music")[primary.name] == false, "Other app is not current media")
expect(status([window(bundle: nil)], mode: .nowPlayingOnly)[primary.name] == false, "Two missing bundle IDs do not match")
expect(status([window()], screens: [])[primary.name] == nil, "Disconnected displays are removed")
expect(status([window()], screens: [primary, primary])[primary.name] == true, "Duplicate display names never crash")
print("Fullscreen visibility tests passed: \(checks) checks")
