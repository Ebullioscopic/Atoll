import Foundation
import CoreGraphics

// MARK: - Brightness emission + baseline-sync decisions
//
// MIRRORS: DynamicIsland/managers/SystemMediaControllers.swift
//   `final class SystemBrightnessController` — the hardware-free *decision*
//   helpers embedded in that hardware-coupled singleton:
//     • emitBrightnessChange(value:)            (clamp + baseline update)
//     • syncWithSystemBrightnessIfNeeded()      (0.001 baseline-delta gate)
//     • adjust(by:)                             (base+delta target clamp)
//     • animationDuration(forDelta:)            (min/max duration scaling)
//     • ease(_:)                                (cubic ease-out)
//     • the poll loop's pollChangeThreshold     (0.005 emit gate)
//
// The app class drives real CoreBrightness/IODisplay hardware and an animation
// Timer; this kernel isolates only the value-math decisions so they run
// deterministically with no hardware. Each member is a verified copy of the
// canonical method — see the per-member `MIRRORS` note.
//
// NOTE on Codacy proposal #1 ("auto-brightness updates the baseline WITHOUT
// showing the HUD"): the real app does NOT behave that way. Its
// `syncWithSystemBrightnessIfNeeded()` calls `emitBrightnessChange(...)` (line
// ~558), so an above-threshold system change DOES emit (and the HUD does fire).
// There is likewise no emission throttle and no user-initiated gate in the app.
// Rather than fabricate those behaviours, this kernel mirrors the real logic and
// the tests assert the real contract: sync emits when, and only when, the system
// level differs from the baseline by more than 0.001.
final class BrightnessEmissionKernel {

    /// MIRRORS `syncWithSystemBrightnessIfNeeded()` baseline-delta guard (0.001).
    static let baselineSyncThreshold: Float = 0.001

    /// MIRRORS the poll loop's `pollChangeThreshold: Float = 0.005`.
    static let pollChangeThreshold: Float = 0.005

    /// MIRRORS `minimumBrightnessAnimationDuration` / `maximumBrightnessAnimationDuration`
    /// / `brightnessAnimationDurationScale`.
    static let minimumAnimationDuration: TimeInterval = 0.08
    static let maximumAnimationDuration: TimeInterval = 0.3
    static let animationDurationScale: TimeInterval = 1.6

    /// MIRRORS `private var lastEmittedBrightness: Float`.
    private(set) var lastEmittedBrightness: Float

    /// Records emissions actually delivered to observers (the HUD-visible path),
    /// so tests can assert exactly which changes reached `onBrightnessChange` /
    /// `.systemBrightnessDidChange`.
    private(set) var emittedValues: [Float] = []

    init(initialBrightness: Float = 0.5) {
        self.lastEmittedBrightness = max(0, min(1, initialBrightness))
    }

    /// MIRRORS `emitBrightnessChange(value:)`: clamp to [0, 1], update the
    /// baseline, and deliver to observers. There is no throttle in the app.
    @discardableResult
    func emitBrightnessChange(value: Float) -> Float {
        let clamped = max(0, min(1, value))
        lastEmittedBrightness = clamped
        emittedValues.append(clamped)
        return clamped
    }

    /// MIRRORS `syncWithSystemBrightnessIfNeeded()`: if the system level differs
    /// from the baseline by more than 0.001, re-emit at the system level (which,
    /// in the app, posts the notification). Returns true when it emitted.
    @discardableResult
    func syncWithSystemBrightnessIfNeeded(systemLevel: Float) -> Bool {
        guard abs(systemLevel - lastEmittedBrightness) > Self.baselineSyncThreshold else {
            return false
        }
        emitBrightnessChange(value: systemLevel)
        return true
    }

    /// MIRRORS `adjust(by:)` target computation:
    /// `target = clamp(base + delta)` where `base = pendingAdjustTarget ?? lastEmittedBrightness`.
    /// Coalescing successive deltas before the next runloop tick is what
    /// `pendingAdjustTarget` models.
    func adjustTarget(by delta: Float, pendingAdjustTarget: Float? = nil) -> Float {
        let base = pendingAdjustTarget ?? lastEmittedBrightness
        return max(0, min(1, base + delta))
    }

    /// MIRRORS `animationDuration(forDelta:)`: a larger jump animates longer,
    /// clamped to [min, max].
    func animationDuration(forDelta delta: Float) -> TimeInterval {
        let scaled = Self.minimumAnimationDuration + TimeInterval(delta) * Self.animationDurationScale
        return min(Self.maximumAnimationDuration, max(Self.minimumAnimationDuration, scaled))
    }

    /// MIRRORS `ease(_:)`: cubic ease-out, input clamped to [0, 1].
    func ease(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    /// MIRRORS the poll loop guard `abs(system - lastEmittedBrightness) > pollChangeThreshold`:
    /// background polling only emits when the system moved by more than 0.005.
    func pollShouldEmit(systemLevel: Float) -> Bool {
        abs(systemLevel - lastEmittedBrightness) > Self.pollChangeThreshold
    }
}

// MARK: - Sticky-terminal outside-click → close decision
//
// MIRRORS: DynamicIsland/ContentView.swift
//   `installStickyTerminalClickMonitor()` global .leftMouseDown handler +
//   `isPointInsideNotchWindow(_:)` + `syncStickyTerminalOutsideClickMonitor()`.
//
// When the terminal tab is opened via a global hotkey (sticky mode), a global
// left-click monitor closes the notch on any click that lands OUTSIDE every
// notch window frame. A click inside is ignored. This kernel isolates that
// frame-containment + gating decision (NSEvent/AppDelegate stripped out).
enum StickyTerminalClickKernel {

    /// MIRRORS `isPointInsideNotchWindow(_:)` — point is inside if ANY notch
    /// window frame contains it (covers the showOnAllDisplays multi-window case).
    static func isPointInsideNotchWindow(_ point: CGPoint, windowFrames: [CGRect]) -> Bool {
        windowFrames.contains { $0.contains(point) }
    }

    /// MIRRORS the monitor-install guard in `syncStickyTerminalOutsideClickMonitor()`:
    /// `vm.notchState == .open && terminalStickyMode && currentView == .terminal`.
    static func shouldMonitorOutsideClicks(
        notchOpen: Bool,
        stickyMode: Bool,
        currentViewIsTerminal: Bool
    ) -> Bool {
        notchOpen && stickyMode && currentViewIsTerminal
    }

    /// MIRRORS the handler body: while open, a click outside all notch windows
    /// closes the notch; a click inside (or notch already closed) does nothing.
    /// Returns true when the notch should close.
    static func shouldCloseOnClick(
        notchOpen: Bool,
        clickLocation: CGPoint,
        windowFrames: [CGRect]
    ) -> Bool {
        guard notchOpen else { return false }
        return !isPointInsideNotchWindow(clickLocation, windowFrames: windowFrames)
    }
}
