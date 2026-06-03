import Foundation
import CoreGraphics

// MARK: - Brightness emission throttle + user-initiated HUD gate
//
// MIRRORS: DynamicIsland/managers/SystemMediaControllers.swift
//   `final class SystemBrightnessController` — the emission-throttling and
//   baseline-sync logic (properties: lastEmittedBrightness, lastEmissionDate,
//   minimumEmissionInterval = 0.04; methods: emitBrightnessChange(value:force:),
//   syncWithSystemBrightnessIfNeeded(), markUserInitiated()).
//
// The app class drives real CoreBrightness/IODisplay hardware and an animation
// Timer; this kernel isolates the *decisions* (when does an emission fire? does
// an auto-brightness sync emit or only move the baseline? is a change gated as
// user-initiated?) so they can be tested deterministically with an injected clock.
public final class BrightnessEmissionKernel {

    /// ~25 fps cap. MIRRORS `minimumEmissionInterval: TimeInterval = 0.04`.
    public static let minimumEmissionInterval: TimeInterval = 0.04

    /// MIRRORS `userInitiatedWindow: TimeInterval = 1.5`.
    public static let userInitiatedWindow: TimeInterval = 1.5

    /// MIRRORS `syncWithSystemBrightnessIfNeeded` baseline-delta guard (0.001).
    public static let baselineSyncThreshold: Float = 0.001

    public private(set) var lastEmittedBrightness: Float
    public private(set) var lastEmissionDate: Date
    public private(set) var userInitiatedBrightnessChange = false
    private var userInitiatedDeadline: Date?

    /// Records emissions actually delivered to observers (the HUD-visible path).
    public private(set) var emittedValues: [Float] = []

    public init(initialBrightness: Float = 0.5, now: Date = .distantPast) {
        self.lastEmittedBrightness = initialBrightness
        self.lastEmissionDate = now
    }

    /// MIRRORS `emitBrightnessChange(value:force:)`.
    /// Returns true when the change is emitted to observers (HUD fires),
    /// false when throttled. `force` bypasses the throttle (final animation step).
    @discardableResult
    public func emitBrightnessChange(value: Float, force: Bool = false, now: Date) -> Bool {
        let clamped = max(0, min(1, value))
        lastEmittedBrightness = clamped
        if !force {
            guard now.timeIntervalSince(lastEmissionDate) >= Self.minimumEmissionInterval else {
                return false
            }
        }
        lastEmissionDate = now
        emittedValues.append(clamped)
        return true
    }

    /// MIRRORS `syncWithSystemBrightnessIfNeeded()`.
    /// Auto-brightness adjustments update the internal baseline but must NOT emit
    /// (no HUD flash). Returns true if the baseline moved.
    @discardableResult
    public func syncWithSystemBrightness(_ systemLevel: Float) -> Bool {
        if abs(systemLevel - lastEmittedBrightness) > Self.baselineSyncThreshold {
            lastEmittedBrightness = systemLevel   // baseline only — deliberately no emit
            return true
        }
        return false
    }

    /// MIRRORS `markUserInitiated()` — opens the gate, auto-resets after the window.
    public func markUserInitiated(now: Date) {
        userInitiatedBrightnessChange = true
        userInitiatedDeadline = now.addingTimeInterval(Self.userInitiatedWindow)
    }

    /// Evaluates the auto-reset that the app performs via a 1.5s Timer.
    public func isUserInitiated(at now: Date) -> Bool {
        if let deadline = userInitiatedDeadline, now >= deadline {
            userInitiatedBrightnessChange = false
            userInitiatedDeadline = nil
        }
        return userInitiatedBrightnessChange
    }
}

// MARK: - CoreBrightness candidate-class resolution
//
// MIRRORS: DynamicIsland/helpers/CoreBrightnessDisplayClient.swift
//   `private static let candidateClassNames` + the `private init()` resolver
//   loop that walks the list newest-first and binds the first class that exists.
//
// Tests pass a stub `classLookup` (stand-in for NSClassFromString) representing
// what's present on a given macOS version, verifying the resolver picks the
// correct (newest available) class and degrades gracefully when none exist.
public enum CoreBrightnessClassResolver {

    /// MIRRORS `candidateClassNames` — ordered newest-first.
    public static let candidateClassNames: [String] = [
        "CBBrightnessProxy",
        "CBDisplayBrightnessClient",
        "BrightnessSystemClient",
        "DisplayBrightnessClient"
    ]

    /// Returns the first candidate the platform exposes, or nil (→ polling fallback).
    /// MIRRORS the `for name in candidateClassNames { if NSClassFromString(name) … }`
    /// loop including its newest-first short-circuit.
    public static func resolve(classExists: (String) -> Bool) -> String? {
        for name in candidateClassNames where classExists(name) {
            return name
        }
        return nil
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
public enum StickyTerminalClickKernel {

    /// MIRRORS `isPointInsideNotchWindow(_:)` — point is inside if ANY notch
    /// window frame contains it (covers the showOnAllDisplays multi-window case).
    public static func isPointInsideNotchWindow(_ point: CGPoint, windowFrames: [CGRect]) -> Bool {
        windowFrames.contains { $0.contains(point) }
    }

    /// MIRRORS the monitor-install guard:
    /// `vm.notchState == .open && terminalStickyMode && currentView == .terminal`.
    public static func shouldMonitorOutsideClicks(notchOpen: Bool, stickyMode: Bool, currentViewIsTerminal: Bool) -> Bool {
        notchOpen && stickyMode && currentViewIsTerminal
    }

    /// MIRRORS the handler body: while open, a click outside all notch windows
    /// closes the notch; a click inside (or notch already closed) does nothing.
    /// Returns true when the notch should close.
    public static func shouldCloseOnClick(notchOpen: Bool, clickLocation: CGPoint, windowFrames: [CGRect]) -> Bool {
        guard notchOpen else { return false }
        return !isPointInsideNotchWindow(clickLocation, windowFrames: windowFrames)
    }
}
