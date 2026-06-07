// FineTune/Models/VolumeMapping.swift
import Foundation

/// Perceptual volume mapping for **per-app software gain** sliders only.
///
/// Per-app gain is a linear PCM amplitude multiplier (0.0–1.0). Without a curve,
/// slider movement at low volumes produces barely perceptible change while movement
/// at high volumes changes loudness drastically. The x² curve redistributes control
/// to the perceptually important low-gain region.
///
/// **Do NOT use for device hardware volume (DeviceRow, InputDeviceRow).**
/// CoreAudio's HAL scalar (kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
/// is already audio-tapered by the driver — IOAudioLevelControl applies a dB curve
/// by default (see `setLinearScale()` in IOAudioLevelControl.h). Applying x² on top
/// creates a "double taper" that kills the bottom 10% of slider range.
///
/// Evidence: empirical measurement of built-in output shows scalar maps linearly to dB:
///   scalar 0.50 → -50 dB, scalar 0.10 → -90 dB (100 dB range, linear-in-dB taper).
///   Square-law on top: slider 10% → scalar 0.01 → -99 dB (effective silence).
///
/// References:
/// - IOAudioLevelControl.h `setLinearScale(bool)`: "FALSE instructs CoreAudio to apply
///   a curve, which is CoreAudio's default behavior."
/// - dr-lex.be/info-stuff/volumecontrols.html: x⁴ recommended for linear-amplitude
///   controls; unnecessary when the backend is already perceptually mapped.
/// - Microsoft "Audio-Tapered Volume Controls": Windows scalar volume is also pre-tapered;
///   applications should NOT apply additional curves on the scalar endpoint API.
/// - Discord perceptual (github.com/discord/perceptual): 50 dB exponential mapping for
///   linear PCM gain — similar purpose to our x² curve for per-app volume.
enum VolumeMapping {
    /// Convert per-app slider position to linear PCM gain using square-law curve.
    /// Slider 50% → gain 0.25 (−12 dB). Provides perceptual linearity for software gain.
    static func sliderToGain(_ slider: Double) -> Float {
        if slider <= 0 { return 0 }
        let t = min(slider, 1.0)
        return Float(t * t)
    }

    /// Convert linear PCM gain to per-app slider position using inverse square-law (sqrt).
    /// Gain 0.25 → slider 50%. Inverse of `sliderToGain`.
    static func gainToSlider(_ gain: Float) -> Double {
        if gain <= 0 { return 0 }
        return Double(sqrt(min(gain, 1.0)))
    }

    /// `.software` is linear PCM; `.hardware` / `.ddc` scalars are already audio-tapered
    /// by the driver/firmware (see the top-level docstring on this enum).
    static func sliderFraction(forSystemGain gain: Float, tier: VolumeControlTier) -> Double {
        switch tier {
        case .software:
            return gainToSlider(gain)
        case .hardware, .ddc:
            return Double(max(0, min(1, gain)))
        }
    }

    static func systemGain(forSliderFraction fraction: Double, tier: VolumeControlTier) -> Float {
        switch tier {
        case .software:
            return sliderToGain(fraction)
        case .hardware, .ddc:
            return Float(max(0, min(1, fraction)))
        }
    }
}
