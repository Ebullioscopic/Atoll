import Foundation

/// ITU-R BS.1770 K-weighting pre-filter for loudness measurement.
///
/// Two biquad stages in series:
///   Stage 1 — High-shelf pre-emphasis (+4 dB at ~1.5 kHz)
///   Stage 2 — High-pass RLB weighting (2nd-order Butterworth, ~38 Hz)
///
/// Implemented as transposed direct-form II with scalar state fields for RT-safety.
/// No allocations occur in `processSample`.
final class KWeightingFilter: @unchecked Sendable {

    // MARK: - Coefficient storage (Double precision for accuracy)

    // Stage 1: high-shelf  [b0, b1, b2, a1, a2]
    private var s1_b0: Float = 1
    private var s1_b1: Float = 0
    private var s1_b2: Float = 0
    private var s1_a1: Float = 0
    private var s1_a2: Float = 0

    // Stage 2: high-pass   [b0, b1, b2, a1, a2]
    private var s2_b0: Float = 1
    private var s2_b1: Float = 0
    private var s2_b2: Float = 0
    private var s2_a1: Float = 0
    private var s2_a2: Float = 0

    // MARK: - State (transposed direct-form II delay elements)

    private var s1_z1: Float = 0
    private var s1_z2: Float = 0

    private var s2_z1: Float = 0
    private var s2_z2: Float = 0

    // MARK: - Initialisation

    init(sampleRate: Float) {
        computeCoefficients(sampleRate: Double(sampleRate))
    }

    // MARK: - Public API

    /// Process a single sample through both K-weighting stages.
    /// Allocation-free, side-effect-free.
    @inline(__always)
    func processSample(_ sample: Float) -> Float {
        // Stage 1 — high-shelf
        let y1 = s1_b0 * sample + s1_z1
        let nextS1Z1 = s1_b1 * sample - s1_a1 * y1 + s1_z2
        let nextS1Z2 = s1_b2 * sample - s1_a2 * y1
        s1_z1 = nextS1Z1
        s1_z2 = nextS1Z2

        // Stage 2 — high-pass
        let y2 = s2_b0 * y1 + s2_z1
        let nextS2Z1 = s2_b1 * y1 - s2_a1 * y2 + s2_z2
        let nextS2Z2 = s2_b2 * y1 - s2_a2 * y2
        s2_z1 = nextS2Z1
        s2_z2 = nextS2Z2

        return y2
    }

    /// Reset all filter state to zero.
    func reset() {
        s1_z1 = 0; s1_z2 = 0
        s2_z1 = 0; s2_z2 = 0
    }

    // MARK: - Private helpers

    private func computeCoefficients(sampleRate: Double) {
        // Stage 1: high-shelf  +4 dB at 1500 Hz, Q = 1/√2
        let shelfCoeffs = BiquadMath.highShelfCoefficients(
            frequency: 1500.0,
            gainDB: 4.0,
            q: 1.0 / sqrt(2.0),
            sampleRate: sampleRate
        )
        s1_b0 = Float(shelfCoeffs[0])
        s1_b1 = Float(shelfCoeffs[1])
        s1_b2 = Float(shelfCoeffs[2])
        s1_a1 = Float(shelfCoeffs[3])
        s1_a2 = Float(shelfCoeffs[4])

        // Stage 2: high-pass  38 Hz, Q = 1/√2 (Butterworth)
        let hpCoeffs = BiquadMath.highPassCoefficients(
            frequency: 38.0,
            q: 1.0 / sqrt(2.0),
            sampleRate: sampleRate
        )
        s2_b0 = Float(hpCoeffs[0])
        s2_b1 = Float(hpCoeffs[1])
        s2_b2 = Float(hpCoeffs[2])
        s2_a1 = Float(hpCoeffs[3])
        s2_a2 = Float(hpCoeffs[4])
    }
}
