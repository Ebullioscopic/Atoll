import Foundation

enum LoudnessEqualizerMath {
    static func dbToLinear(_ db: Float) -> Float {
        pow(10, db / 20)
    }

    static func linearToDb(_ linear: Float) -> Float {
        20 * log10(max(linear, 1e-9))
    }

    static func meanSquareToDb(_ meanSquare: Float) -> Float {
        10 * log10(max(meanSquare, 1e-12))
    }

    static func rmsFromMeanSquare(_ meanSquare: Float) -> Float {
        sqrt(max(meanSquare, 0))
    }

    static func clamp(_ value: Float, min: Float, max: Float) -> Float {
        Swift.min(Swift.max(value, min), max)
    }

    static func timeConstantCoefficient(timeMs: Float, stepMs: Float) -> Float {
        1 - exp(-stepMs / max(timeMs, 1e-6))
    }
}
