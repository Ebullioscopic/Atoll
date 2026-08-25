//
//  ActivityGate.swift
//  DynamicIsland
//
//  Central "activity gate" for energy-aware background work (Perf Phase 2).
//
//  Purpose: a single source of truth that lets optional background jobs
//  (polling loops, periodic refreshes) suspend themselves while the screen
//  is asleep, and stretch their intervals under low-power / thermal pressure.
//
//  Usage from a poller:
//    - Skip a tick when `ActivityGate.shared.shouldSuspendBackgroundWork` is true.
//    - Multiply the base interval by `ActivityGate.shared.pollingIntervalScale`.
//    - Optionally observe the @Published properties to react to changes.
//

import AppKit
import Combine

@MainActor
final class ActivityGate: ObservableObject {
    static let shared = ActivityGate()

    /// True while the screen (or system) is asleep → optional background work
    /// (polling) should be skipped to save energy.
    @Published private(set) var shouldSuspendBackgroundWork: Bool = false

    /// Multiplier applied to polling intervals: normally 1.0; larger under
    /// low-power mode or serious/critical thermal pressure (e.g. 3.0), 1.5 for
    /// a "fair" thermal state. Pollers multiply their base interval by this.
    @Published private(set) var pollingIntervalScale: Double = 1.0

    private init() {
        // Observe screen/system sleep on the AppKit workspace notification center.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for (name, sleeping) in [
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.screensDidWakeNotification, false),
            (NSWorkspace.willSleepNotification, true),   // system sleep
            (NSWorkspace.didWakeNotification, false)     // system wake
        ] {
            workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Notification is delivered on .main; hop to the actor to mutate state.
                MainActor.assumeIsolated {
                    self?.shouldSuspendBackgroundWork = sleeping
                }
            }
        }

        // Observe low-power-mode and thermal-state changes on the default center.
        let defaultCenter = NotificationCenter.default
        for name in [
            NSNotification.Name.NSProcessInfoPowerStateDidChange, // low power mode toggled
            ProcessInfo.thermalStateDidChangeNotification         // thermal state changed
        ] {
            defaultCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.recomputePollingScale()
                }
            }
        }

        // Seed initial values so state is correct before any notification fires.
        recomputePollingScale()
    }

    /// Recompute `pollingIntervalScale` from current power + thermal conditions.
    private func recomputePollingScale() {
        let info = ProcessInfo.processInfo
        let scale: Double

        switch info.thermalState {
        case .serious, .critical:
            scale = 3.0
        case .fair:
            // Low power always wins with the heaviest throttle.
            scale = info.isLowPowerModeEnabled ? 3.0 : 1.5
        case .nominal:
            scale = info.isLowPowerModeEnabled ? 3.0 : 1.0
        @unknown default:
            scale = info.isLowPowerModeEnabled ? 3.0 : 1.0
        }

        if scale != pollingIntervalScale {
            pollingIntervalScale = scale
        }
    }
}
