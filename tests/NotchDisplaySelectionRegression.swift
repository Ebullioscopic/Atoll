// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main
struct NotchDisplaySelectionRegression {
    static func main() {
        let external = NotchDisplayCandidate(name: "External", isBuiltIn: false, hasNotch: false)
        let laptop = NotchDisplayCandidate(name: "Built-in Retina", isBuiltIn: true, hasNotch: true)
        let plain = NotchDisplayCandidate(name: "Built-in LCD", isBuiltIn: true, hasNotch: false)
        let secondary = NotchDisplayCandidate(name: "Secondary", isBuiltIn: false, hasNotch: false)
        var checks = 0
        func check(_ displays: [NotchDisplayCandidate], _ preference: String = "", _ fallback: Bool = true, _ expected: Int?, _ name: String) {
            let actual = NotchDisplaySelection.index(in: displays, preferredName: preference, allowsFallback: fallback)
            precondition(actual == expected, "\(name): expected \(String(describing: expected)), got \(String(describing: actual))")
            checks += 1
            print("PASS: \(name)")
        }
        check([external, laptop], "", true, 1, "external primary at first launch")
        check([laptop, external], "", true, 0, "screen order does not move automatic mode")
        check([external, laptop], "", false, 1, "automatic works with fallback toggle off")
        check([laptop], "", true, 0, "laptop only")
        check([external], "", true, 0, "closed lid external only")
        check([external, laptop], "", true, 1, "reopen lid returns to laptop")
        check([external, laptop], "External", true, 0, "explicit external selection respected")
        check([external, laptop], "External", false, 0, "explicit external without fallback")
        check([external, laptop], "Built-in Retina", false, 1, "explicit laptop respected")
        check([external], "Built-in Retina", true, 0, "temporarily absent preference falls back")
        check([external], "Built-in Retina", false, nil, "absent preference without fallback hides")
        check([external, laptop], "Missing", true, 1, "fallback prefers built-in")
        check([external, laptop], "Unknown", false, 1, "legacy unknown preference treated as automatic")
        check([external, plain], "", true, 1, "non-notched built-in supported")
        check([external, plain, laptop], "", true, 2, "notched built-in first")
        check([external, secondary], "", true, 0, "desktop defaults to primary screen")
        check([external, secondary], "Secondary", true, 1, "manual secondary on desktop")
        check([], "", true, nil, "transient empty list does not crash")
        check([], "External", false, nil, "empty list with saved preference")
        print("\(checks) display-selection cases passed")
    }
}
