import Foundation
import CoreGraphics

/// Shared motion vocabulary for the pixel mascots (#15 polish pass).
///
/// Everything here is a PURE function of the timeline time `t` (plus constant
/// seeds), because mascot frames are re-rendered from scratch by
/// `MascotTimeline` — there is no retained animation state, so "randomness"
/// must be deterministic. All curves are cheap (a few transcendentals per
/// frame) and look right at the 8 fps idle / 20 fps active budget.
enum MascotMotion {

    // MARK: - Deterministic pseudo-randomness

    /// Stable hash of an integer slot → [0, 1). Used to vary blink gaps,
    /// quirk picks, etc. without any stored state.
    static func hash01(_ n: Int, seed: UInt64 = 0) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &+ 0x9E3779B97F4A7C15 &+ seed &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x = x ^ (x >> 31)
        return Double(x % 1_000_000) / 1_000_000
    }

    // MARK: - Breathing

    /// Asymmetric breath: quicker inhale, slower exhale, and a soft pause at
    /// the bottom — reads as "alive" instead of a metronome. Returns 0…1
    /// (0 = rest, 1 = full inhale).
    static func breathe(_ t: Double, period: Double = 4.5) -> CGFloat {
        let phase = (t / period).truncatingRemainder(dividingBy: 1)
        // 35% inhale, 45% exhale, 20% rest.
        if phase < 0.35 {
            let p = phase / 0.35
            return CGFloat(0.5 - 0.5 * cos(p * .pi))            // ease-in-out up
        } else if phase < 0.80 {
            let p = (phase - 0.35) / 0.45
            return CGFloat(0.5 + 0.5 * cos(p * .pi))            // ease-in-out down
        } else {
            return 0
        }
    }

    // MARK: - Blinking

    /// Natural blink signal: 1 = eyes open, 0 = eyes shut, with eased lids.
    /// Blinks land at irregular gaps (2.4–5.6 s) and ~1 in 6 is a double
    /// blink — the biggest single "it's alive" tell on a tiny sprite.
    static func blink(_ t: Double, seed: UInt64 = 0) -> CGFloat {
        let slotLength = 4.0
        let slot = Int(floor(t / slotLength))
        let r = hash01(slot, seed: seed)
        // Blink start jitters inside the slot; keep clear of the slot edges.
        let start = slotLength * (0.15 + 0.6 * r)
        let local = t - Double(slot) * slotLength

        let blinkDuration = 0.14
        func lid(_ dt: Double) -> CGFloat {
            guard dt >= 0, dt < blinkDuration else { return 1 }
            // Close fast, open slightly slower.
            let p = dt / blinkDuration
            return CGFloat(p < 0.4 ? 1 - (p / 0.4) : (p - 0.4) / 0.6)
        }

        var openness = lid(local - start)
        // Occasional double blink right after the first.
        if hash01(slot, seed: seed ^ 0xB11) < 0.18 {
            openness = min(openness, lid(local - start - 0.22))
        }
        return openness
    }

    // MARK: - Idle quirks

    /// Low-frequency "quirk" window for idle micro-actions (ear twitch, tail
    /// flick, head tilt, stretch…). Returns the 0→1→0 envelope of the quirk
    /// when inside its window, else 0. At most one quirk per `cycle` seconds,
    /// and ~30% of cycles skip theirs so the rhythm never feels scheduled.
    static func quirk(_ t: Double, cycle: Double = 7.0, duration: Double = 0.9, seed: UInt64 = 0) -> CGFloat {
        let slot = Int(floor(t / cycle))
        guard hash01(slot, seed: seed ^ 0x9D2C) > 0.30 else { return 0 }
        let start = cycle * (0.2 + 0.55 * hash01(slot, seed: seed))
        let local = t - Double(slot) * cycle - start
        guard local >= 0, local < duration else { return 0 }
        let p = local / duration
        // Smooth in-out envelope.
        return CGFloat(sin(p * .pi))
    }

    /// Picks a variant index (0..<count) for the quirk in the current cycle,
    /// so a mascot can rotate between e.g. ear-twitch / tail-flick / look-around.
    static func quirkVariant(_ t: Double, cycle: Double = 7.0, count: Int, seed: UInt64 = 0) -> Int {
        guard count > 0 else { return 0 }
        let slot = Int(floor(t / cycle))
        return Int(hash01(slot, seed: seed ^ 0x51DE) * Double(count)) % count
    }

    // MARK: - Easing

    /// Overshooting ease-out — snappy arrivals for hop/startle motions.
    static func easeOutBack(_ p: CGFloat, overshoot: CGFloat = 1.70158) -> CGFloat {
        let x = p - 1
        return 1 + x * x * ((overshoot + 1) * x + overshoot)
    }

    /// Standard smooth step for gentle attacks.
    static func easeInOut(_ p: CGFloat) -> CGFloat {
        p < 0.5 ? 2 * p * p : 1 - pow(-2 * p + 2, 2) / 2
    }

    /// Humanized typing beat: a base cadence with deterministic micro-jitter
    /// per keystroke slot, so hands don't hammer like a metronome.
    static func typingStroke(_ t: Double, cadence: Double = 0.16, seed: UInt64 = 0) -> (active: Bool, slot: Int) {
        let slot = Int(floor(t / cadence))
        // ~18% of strokes are skipped — bursts and pauses, like real typing.
        let active = hash01(slot, seed: seed) > 0.18
        return (active, slot)
    }
}
