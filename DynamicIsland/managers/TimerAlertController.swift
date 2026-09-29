/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import Foundation

/// Alternates bounded ringing with silence until the timer is dismissed.
/// Owned and called on the main thread, like TimerManager.
final class TimerAlertController {
    static let ringDurationRange = 1...3600
    static let repeatIntervalRange = 1...1440

    /// Each date marks the start of the current phase, not the original expiry.
    private enum Phase {
        case ringing(Date)
        case waiting(Date)
    }

    private var phase: Phase?
    private var timer: Timer?
    private let now: () -> Date
    private let ringDuration: () -> Int
    private let repeatIntervalMinutes: () -> Int
    private let playSound: () -> Void
    private let stopSound: () -> Void

    init(
        now: @escaping () -> Date = Date.init,
        ringDuration: @escaping () -> Int,
        repeatIntervalMinutes: @escaping () -> Int,
        playSound: @escaping () -> Void,
        stopSound: @escaping () -> Void
    ) {
        self.now = now
        self.ringDuration = ringDuration
        self.repeatIntervalMinutes = repeatIntervalMinutes
        self.playSound = playSound
        self.stopSound = stopSound
    }

    deinit {
        timer?.invalidate()
        stopSound()
    }

    func start() {
        stop()
        phase = .ringing(now())
        playSound()
        // Common mode keeps phase changes scheduled while the UI is being tracked.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.update()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        phase = nil
        stopSound()
    }

    /// Silence before sleep. On wake, at most one new reminder is played;
    /// missed reminders are never replayed in a burst.
    func prepareForSleep() {
        guard let phase else { return }
        if case .ringing = phase {
            self.phase = .waiting(now())
        }
        stopSound()
    }

    /// Read settings on each tick so edits also affect an ongoing alert.
    func update() {
        let date = now()
        switch phase {
        case .ringing(let started):
            let seconds = Self.clamp(ringDuration(), to: Self.ringDurationRange)
            guard date.timeIntervalSince(started) >= Double(seconds) else { return }
            stopSound()
            // Measure silence from when playback actually stops, even if the
            // run loop was delayed. Do not catch up through elapsed cycles.
            phase = .waiting(date)
        case .waiting(let started):
            let minutes = Self.clamp(repeatIntervalMinutes(), to: Self.repeatIntervalRange)
            guard date.timeIntervalSince(started) >= Double(minutes) * 60 else { return }
            phase = .ringing(date)
            playSound()
        case nil:
            break
        }
    }

    /// Keep persistence in seconds while the settings editor uses minutes and seconds.
    static func duration(minutes: Int, seconds: Int) -> Int {
        let total = clamp(minutes, to: 0...60) * 60 + clamp(seconds, to: 0...59)
        return clamp(total, to: ringDurationRange)
    }

    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
