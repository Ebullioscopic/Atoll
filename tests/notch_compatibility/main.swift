import Foundation
import CoreGraphics

// From Atoll:
// swiftc DynamicIsland/models/NotchCompatibilityPolicy.swift tests/notch_compatibility/main.swift -o /tmp/atoll-notch-policy-tests
// /tmp/atoll-notch-policy-tests
// Pure geometry/metadata only: no NSApplication, CG window-list calls or UI.
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    checks += 1
    guard condition() else { fatalError("Line \(line): \(message)") }
}
typealias Policy = NotchCompatibilityPolicy
let screen = CGRect(x: 0, y: 0, width: 1280, height: 832)
let notch = CGRect(x: 390, y: -2, width: 500, height: 302)
func overlay(pid: Int32 = 42, name: String? = "iBarmenu", frame: CGRect = CGRect(x: 0, y: 0, width: 1280, height: 34),
             level: Int = 30, alpha: Double = 1, onscreen: Bool = true) -> Policy.Window {
    .init(id: 1, ownerPID: pid, name: name, frame: frame, level: level, alpha: alpha, isOnscreen: onscreen)
}
func level(_ windows: [Policy.Window]?, pids: Set<Int32> = [42], on display: CGRect = screen,
           target: CGRect = notch, height: CGFloat = 34, popup: Int = 101) -> Int {
    Policy.recommendedLevel(screenFrame: display, menuBarHeight: height, notchFrame: target,
                            iBarPIDs: pids, windows: windows, popupMenuLevel: popup)
}

expect(level(nil) == 27, "Unavailable API never guesses a level")
expect(level([]) == 27, "No overlay returns baseline")
expect(level([overlay()], pids: []) == 27, "Quit clears a stale overlay")
expect(level([overlay(pid: 999)]) == 27, "Unrelated PID cannot raise the notch")
expect(level([overlay()], pids: [43]) == 27, "A relaunched iBar cannot inherit old PID windows")
expect(level([overlay(level: 26)]) == 27, "Already below notch")
expect(level([overlay(level: 27)]) == 28, "Same-level decoration requires one level above")
expect(level([overlay(level: 30)]) == 31, "1280x34 iBarmenu at lower layer")
expect(level([overlay(level: 99)]) == 100, "One below native popup level")
expect(level([overlay(level: 100)]) == 100, "Ceiling-level decoration never starts a level escalation")
let actualDecoration = overlay(name: "iBarmenu", frame: CGRect(x: 0, y: -1, width: 1280, height: 34), level: 101, alpha: 1)
let actualStatusItem = overlay(name: "iBarStatusItem", frame: CGRect(x: 1100, y: 0, width: 31, height: 33), level: 25)
expect(level([actualDecoration]) == 102, "Actual CG title iBarmenu, 1280x34 at (0,-1), layer101 requires level102")
expect(level([actualStatusItem]) == 27, "Actual iBarStatusItem at layer25 does not raise the notch")
expect(level([actualStatusItem, actualDecoration]) == 102, "Actual status item does not mask eligible decoration")
expect(level([overlay(name: "Menu", level: 101)]) == 27, "Native popup name cannot use layer101 exception")
expect(level([overlay(pid: 999, level: 101)]) == 27, "Full-width popup from another PID excluded")
expect(level([overlay(name: nil, frame: CGRect(x: 300, y: -1, width: 600, height: 34), level: 101)]) == 27,
       "Redacted popup still must meet full-width rule")
expect(level([overlay(frame: CGRect(x: 0, y: -1, width: 1280, height: 65), level: 101)]) == 27,
       "Full-width dialog above thickness limit excluded")
expect(level([overlay(frame: CGRect(x: 0, y: -1, width: 1280, height: 64), level: 101)]) == 102,
       "Full-width top decoration at allowed 64pt thickness")
expect(level([overlay(frame: CGRect(x: 0, y: 80, width: 1280, height: 34), level: 101)]) == 27,
       "Layer101 surface must be at screen top")
expect(level([overlay(frame: CGRect(x: 300, y: -1, width: 600, height: 34), level: 101)]) == 27,
       "Narrow popup-like layer101 surface is excluded")
expect(level([overlay(frame: CGRect(x: 0, y: -1, width: 1024, height: 34), level: 101)]) == 102,
       "At least 80 percent display width permits confirmed decoration")
expect(level([overlay(frame: CGRect(x: 0, y: -1, width: 1023, height: 34), level: 101)]) == 27,
       "Below 80 percent never crosses popup level")
for highLevel in [102, 103, 1000, 1500, Int.max] {
    expect(level([overlay(level: highLevel)]) == 27, "Popup, shield and extreme levels excluded: \(highLevel)")
}
expect(level([overlay(level: 30), overlay(level: 90)]) == 91, "Highest eligible decoration wins")
expect(level([overlay(level: 90), overlay(level: 30)]) == 91, "List ordering does not change policy")
expect(level([overlay(name: nil)]) == 31, "Redacted title uses PID plus geometry")
expect(level([overlay(name: "")]) == 31, "Empty title uses PID plus geometry")
for name in ["Preferences", "Dialog", "Menu", "Screen Saver"] {
    expect(level([overlay(name: name)]) == 27, "Named unrelated surface excluded: \(name)")
}
expect(level([overlay(alpha: 0)]) == 27, "Transparent surface excluded")
expect(level([overlay(alpha: .nan)]) == 27, "Invalid opacity excluded")
expect(level([overlay(onscreen: false)]) == 27, "Offscreen surface excluded")
expect(level([overlay(frame: CGRect(x: 0, y: 0, width: 1280, height: 832))]) == 27, "Fullscreen window excluded")
expect(level([overlay(frame: CGRect(x: 400, y: 0, width: 400, height: 300))]) == 27, "Top-anchored dialog excluded")
expect(level([overlay(frame: CGRect(x: 600, y: 0, width: 80, height: 34))]) == 27, "Status item or tooltip excluded")
expect(level([overlay(frame: CGRect(x: 0, y: 80, width: 1280, height: 34))]) == 27, "Floating toolbar below strip excluded")
expect(level([overlay(frame: CGRect(x: 0, y: 0, width: 300, height: 34))]) == 27, "Decoration must overlap notch, not just menu strip")
expect(level([overlay()], target: CGRect(x: 390, y: 100, width: 500, height: 300)) == 27, "Window away from menu strip excluded")
expect(level([overlay()], height: 0) == 27, "No menu strip")
expect(level([overlay()], height: .nan) == 27, "Non-finite strip rejected")
expect(level([overlay()], target: .null) == 27, "Null target rejected")
expect(level([overlay()], popup: 27) == 27, "Invalid level boundary does not underflow")
expect(level([overlay()], popup: Int.max) == 27, "Unknown future popup level cannot exceed fixed maximum or overflow")

// WindowServer/AppKit conversion must use the same primary top for every screen.
let primaryTop: CGFloat = 832
let left = Policy.windowServerFrame(fromAppKit: CGRect(x: -1920, y: 0, width: 1920, height: 1080), primaryScreenTop: primaryTop)
expect(left == CGRect(x: -1920, y: -248, width: 1920, height: 1080), "Left display preserves negative global coordinates")
let above = Policy.windowServerFrame(fromAppKit: CGRect(x: 0, y: 832, width: 1280, height: 800), primaryScreenTop: primaryTop)
expect(above == CGRect(x: 0, y: -800, width: 1280, height: 800), "Stacked display uses primary origin")
let aboveNotch = CGRect(x: 390, y: -802, width: 500, height: 302)
expect(level([overlay()], on: above, target: aboveNotch) == 27, "Same X on another display cannot match")
expect(level([overlay(level: 101)], on: above, target: aboveNotch) == 27, "Other-display layer101 cannot raise this notch")
expect(level([overlay(frame: CGRect(x: 0, y: -800, width: 1280, height: 34))], on: above, target: aboveNotch) == 31,
       "Matching stacked-display overlay")
expect(level([overlay(frame: CGRect(x: 0, y: -801, width: 1280, height: 34), level: 101)], on: above, target: aboveNotch) == 102,
       "Actual layer101 decoration on stacked display")
expect(level([overlay(frame: CGRect(x: -1920, y: -248, width: 1920, height: 34))], on: left,
             target: CGRect(x: -1210, y: -250, width: 500, height: 302)) == 31, "Matching left-display overlay")
expect(level([overlay()], on: CGRect(x: 1280, y: 0, width: 1920, height: 1080),
             target: CGRect(x: 1990, y: -2, width: 500, height: 302)) == 27, "Other display cannot affect recommendation")

// Bounds invariant across normal, popup, and screensaver-level inputs.
for value in -10...1100 {
    let result = level([overlay(level: value)])
    expect((27...102).contains(result), "Bounded level for \(value)")
}
var reordered = overlay()
reordered.zOrder = 4
expect(reordered != overlay(), "Same layer/frame reordering changes cached snapshot")
print("Notch compatibility policy passed: \(checks) checks; no UI or live window queries")
