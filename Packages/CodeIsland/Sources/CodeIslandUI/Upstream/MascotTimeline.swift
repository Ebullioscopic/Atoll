import SwiftUI

/// Shared frame driver for every pixel mascot (#225 → all mascots).
///
/// Wraps `TimelineView(.periodic)` with the MascotAnimationGate plumbing that
/// PixelCharacterView pioneered, so ALL mascots — not just Clawd — stop their
/// per-frame Canvas redraws when the panel is hidden/occluded or the machine
/// is asleep, and re-anchor their schedules on wake instead of replaying every
/// missed tick in a catch-up burst.
///
/// `content` receives the mascot-local time `t` (already scaled by the user's
/// animation-speed setting), exactly like the raw pattern it replaces:
///
///     MascotTimeline(interval: 0.05) { t in workCanvas(t: t) }
///
/// The effective interval is clamped to `minInterval` (20 fps): a menu-bar-
/// sized pixel sprite gains nothing perceivable above that, and the wasted
/// wakeups were a real contributor to "CodeIsland makes my Mac warm" (#14).
struct MascotTimeline<Content: View>: View {
    /// Floor for all mascot frame intervals — 20 fps.
    static var minInterval: TimeInterval { 0.05 }

    let interval: TimeInterval
    /// Time handed to `content` for the single static frame rendered while
    /// animations are gated off.
    var staticTime: Double = 0
    @ViewBuilder let content: (Double) -> Content

    @Environment(\.mascotSpeed) private var speed
    @Environment(\.mascotAnimationsActive) private var animationsActive
    @Environment(\.mascotAnimationEpoch) private var animationEpoch
    @Environment(\.mascotStaticTime) private var staticTimeOverride

    var body: some View {
        if animationsActive {
            TimelineView(.periodic(from: .now, by: max(interval, Self.minInterval))) { ctx in
                content(ctx.date.timeIntervalSinceReferenceDate * speed)
            }
            .id(animationEpoch)
        } else {
            content(staticTimeOverride ?? staticTime)
        }
    }
}

// MARK: - Static-frame override (render harness)

private struct MascotStaticTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// When set (and animations are gated off), MascotTimeline renders its
    /// single static frame at this timeline instant instead of `staticTime`.
    /// Used by the offscreen contact-sheet harness to inspect specific frames.
    var mascotStaticTime: Double? {
        get { self[MascotStaticTimeKey.self] }
        set { self[MascotStaticTimeKey.self] = newValue }
    }
}
