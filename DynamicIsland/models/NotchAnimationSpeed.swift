import Foundation

enum NotchAnimationSpeed {
    static func resolved(_ value: Double, legacy: String) -> Double {
        if value.isFinite && (1...2).contains(value) { return value }
        switch legacy {
        case "fast": return 1.5
        case "faster": return 2
        default: return 1
        }
    }
}
