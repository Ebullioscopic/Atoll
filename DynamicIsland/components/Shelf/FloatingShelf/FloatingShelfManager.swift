/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Licensed under GNU GPLv3.
 */

import AppKit
import Defaults

/// Singleton manager responsible for the lifecycle and presentation of the Dropover-style Floating Shelf.
@MainActor
final class FloatingShelfManager {
    /// Shared singleton instance.
    static let shared = FloatingShelfManager()

    /// Lazily initialized floating panel instance.
    private var panel: FloatingShelfPanel?

    /// Shake gesture detector monitoring drag movement across the screen.
    private let shakeDetector = FloatingShakeDetector()

    /// Indicates whether shake gesture monitoring is currently running.
    private(set) var isMonitoring = false

    /// Private initializer setting up gesture callbacks.
    private init() {
        shakeDetector.onShake = { [weak self] point in
            guard Defaults[.enableShakeToSummon] else { return }
            self?.show(at: point)
        }
    }

    /// Starts monitoring for shake gestures if not already active.
    func startMonitoring() {
        guard !isMonitoring else { return }
        shakeDetector.start()
        isMonitoring = true
        print("🌊 [FloatingShelfManager] Shake-to-summon gesture monitoring started")
    }

    /// Stops monitoring for shake gestures.
    func stopMonitoring() {
        guard isMonitoring else { return }
        shakeDetector.stop()
        isMonitoring = false
        print("🌊 [FloatingShelfManager] Shake-to-summon gesture monitoring stopped")
    }

    /// Presents the floating shelf panel near the specified point or current mouse location.
    /// - Parameter point: Optional coordinate for positioning; defaults to `NSEvent.mouseLocation`.
    func show(at point: NSPoint? = nil) {
        let location = point ?? NSEvent.mouseLocation
        if panel == nil {
            panel = FloatingShelfPanel()
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        panel?.show(at: location)
    }

    /// Dismisses the floating shelf panel with an animation.
    func hide() {
        panel?.hideAnimated()
    }

    /// Toggles the floating shelf's visibility at the specified point or cursor location.
    /// - Parameter point: Optional target point for presentation.
    func toggle(at point: NSPoint? = nil) {
        if let p = panel, p.isVisible {
            hide()
        } else {
            show(at: point)
        }
    }
}
