import Foundation

/// Bounded, persistent text zoom shared by message rendering and the composer.
enum ChatPresentation {
    static let minimumScale = 0.8
    static let maximumScale = 1.6
    static func clamp(_ scale: Double) -> Double {
        guard scale.isFinite else { return 1 }
        return min(maximumScale, max(minimumScale, scale))
    }
    static func zoom(_ scale: Double, steps: Int) -> Double {
        clamp((clamp(scale) * 10 + Double(steps)).rounded() / 10)
    }
}
