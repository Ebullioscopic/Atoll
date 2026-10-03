import AppKit
import ApplicationServices
import Foundation

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func classes(_ element: AXUIElement) -> [String] {
    attribute(element, "AXDOMClassList") as? [String] ?? []
}
func find(_ root: AXUIElement, _ predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(3)
    repeat {
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var budget = 6000
        while let (element, depth) = stack.popLast(), budget > 0, Date() < deadline {
            budget -= 1
            if predicate(element) { return element }
            if depth < 40 {
                for child in (attribute(element, "AXChildren") as? [AXUIElement] ?? []) {
                    stack.append((child, depth + 1))
                }
            }
        }
        usleep(100000)
    } while Date() < deadline
    return nil
}
func press(_ element: AXUIElement) -> Bool {
    AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Qobuz controls: " + message + "\n").utf8))
    exit(1)
}
guard CommandLine.arguments.count >= 3 else { fail("expected seek, shuffle or repeat and a value") }
let action = CommandLine.arguments[1]
let value = CommandLine.arguments[2]
if action == "seek" { fail("timeline seeking is unavailable without a verified background gesture") }
guard AXIsProcessTrusted() else { fail("Accessibility permission is required") }
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.qobuz.desktop" }) else { fail("Qobuz is not running") }
let application = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(application, 0.5)
AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
guard let window = (attribute(application, "AXWindows") as? [AXUIElement])?.first else { fail("Qobuz has no accessible window") }
usleep(200000)
if action == "shuffle" {
    guard let control = find(window, { classes($0).contains("player__action-shuffle") }) else { fail("shuffle unavailable") }
    let active = classes(control).contains("player__action-shuffle--active")
    if active != (value != "1") && !press(control) { fail("shuffle command rejected") }
} else if action == "repeat" {
    guard let wanted = Int(value), (1...3).contains(wanted) else { fail("invalid repeat mode") }
    guard let control = find(window, { classes($0).contains("player__action-repeat") }) else { fail("repeat unavailable") }
    var matched = false
    for _ in 0..<4 {
        let c = classes(control)
        let current = c.contains("pct-repeat-once") ? 2 : c.contains("player__action-repeat--active") ? 3 : 1
        if current == wanted { matched = true; break }
        guard press(control) else { fail("repeat command rejected") }
        usleep(150000)
    }
    if !matched { fail("repeat mode did not converge") }
} else { fail("unsupported action") }
print("{\"accepted\":true,\"action\":\"" + action + "\"}")
