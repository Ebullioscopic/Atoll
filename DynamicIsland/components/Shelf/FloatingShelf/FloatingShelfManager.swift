/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Licensed under GNU GPLv3.
 */

import AppKit
import Defaults

@MainActor
final class FloatingShelfManager {
    static let shared = FloatingShelfManager()

    private var panel: FloatingShelfPanel?
    private let shakeDetector = FloatingShakeDetector()
    private(set) var isMonitoring = false

    private init() {
        shakeDetector.onShake = { [weak self] point in
            guard Defaults[.enableShakeToSummon] else { return }
            self?.show(at: point)
        }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        shakeDetector.start()
        isMonitoring = true
        print("🌊 [FloatingShelfManager] Shake-to-summon gesture monitoring started")
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        shakeDetector.stop()
        isMonitoring = false
        print("🌊 [FloatingShelfManager] Shake-to-summon gesture monitoring stopped")
    }

    func show(at point: NSPoint? = nil) {
        let location = point ?? NSEvent.mouseLocation
        if panel == nil {
            panel = FloatingShelfPanel()
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        panel?.show(at: location)
    }

    func hide() {
        panel?.hideAnimated()
    }

    func toggle(at point: NSPoint? = nil) {
        if let p = panel, p.isVisible {
            hide()
        } else {
            show(at: point)
        }
    }
}
