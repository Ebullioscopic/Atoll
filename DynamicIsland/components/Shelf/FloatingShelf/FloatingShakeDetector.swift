/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Licensed under GNU GPLv3.
 */

import AppKit
import QuartzCore

/// Detects a horizontal "shake" gesture while dragging mouse/files anywhere on macOS.
/// Inspired by Dropover's shake-to-summon mechanism.
@MainActor
final class FloatingShakeDetector {
    var onShake: ((NSPoint) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollingTimer: Timer?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private struct Sample {
        let time: CFTimeInterval
        let point: NSPoint
    }

    private var samples: [Sample] = []
    private var lastShakeTime: CFTimeInterval = 0

    // Configuration tunables
    private let timeWindow: CFTimeInterval = 0.45
    private let minReversals = 3           // At least 3 rapid horizontal direction changes
    private let minTravelPerLeg: CGFloat = 12
    private let cooldown: CFTimeInterval = 1.0

    func start() {
        stop()

        // 1. Install Global/Local monitors for mouse drag events
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
            return event
        }

        // 2. High-precision CGEventTap (active if Accessibility is granted)
        installEventTap()

        // 3. Fallback tracking timer: macOS suppresses .leftMouseDragged to event monitors
        // during modal AppKit file dragging sessions from Finder. Polling mouse location
        // while the left mouse button is pressed guarantees shake detection during Finder drags.
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollMousePosition()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil

        pollingTimer?.invalidate()
        pollingTimer = nil

        removeEventTap()
        samples.removeAll()
    }

    private func installEventTap() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.leftMouseDragged.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
            let detector = Unmanaged<FloatingShakeDetector>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .leftMouseDragged {
                let location = cgEvent.location
                DispatchQueue.main.async {
                    detector.record(point: NSPoint(x: location.x, y: location.y))
                }
            } else if type == .leftMouseUp {
                DispatchQueue.main.async {
                    detector.samples.removeAll()
                }
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        if let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) {
            eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func removeEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func pollMousePosition() {
        let isLeftMouseDown = (NSEvent.pressedMouseButtons & 1) != 0
        guard isLeftMouseDown else {
            if !samples.isEmpty {
                samples.removeAll()
            }
            return
        }
        record(point: NSEvent.mouseLocation)
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseUp:
            samples.removeAll()
        case .leftMouseDragged:
            record(point: NSEvent.mouseLocation)
        default:
            break
        }
    }

    private func record(point: NSPoint) {
        // Suppress if user is interacting with an open Notch window
        if let keyWindow = NSApp.keyWindow, keyWindow.frame.contains(point), keyWindow.isVisible {
            if keyWindow.className.contains("DynamicIsland") || keyWindow.title.contains("DynamicIsland") {
                return
            }
        }

        let now = CACurrentMediaTime()
        samples.append(Sample(time: now, point: point))
        samples.removeAll { now - $0.time > timeWindow }

        if detectShake() {
            guard now - lastShakeTime > cooldown else { return }
            lastShakeTime = now
            let triggerPoint = point
            samples.removeAll()
            onShake?(triggerPoint)
        }
    }

    private func detectShake() -> Bool {
        guard samples.count >= 4 else { return false }

        var reversals = 0
        var legTravelX: CGFloat = 0
        var totalTravelX: CGFloat = 0
        var totalTravelY: CGFloat = 0
        var lastDir: Int = 0

        for i in 1..<samples.count {
            let dx = samples[i].point.x - samples[i - 1].point.x
            let dy = samples[i].point.y - samples[i - 1].point.y
            totalTravelX += abs(dx)
            totalTravelY += abs(dy)

            let dir = dx > 1.5 ? 1 : (dx < -1.5 ? -1 : 0)
            if dir == 0 { continue }

            if dir == lastDir {
                legTravelX += abs(dx)
            } else {
                if lastDir != 0 && legTravelX >= minTravelPerLeg {
                    reversals += 1
                }
                legTravelX = abs(dx)
                lastDir = dir
            }
        }

        // Must be predominantly horizontal shaking, not vertical dragging or diagonal scrolling
        guard totalTravelX > totalTravelY * 1.1 else { return false }

        return reversals >= minReversals
    }
}
