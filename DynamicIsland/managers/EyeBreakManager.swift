/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import AVFoundation
import AppKit
import Combine
import Defaults
import Foundation

/// Drives the 20-20-20 rule: after every work interval, remind the user to look
/// at something twenty feet away for twenty seconds.
///
/// All the cycle logic lives in `EyeBreakSchedule`; this class only supplies the
/// clock, the system state the schedule needs, and the published values the notch
/// binds to.
@MainActor
final class EyeBreakManager: ObservableObject {
    static let shared = EyeBreakManager()

    /// True while the notch should be showing the break.
    @Published private(set) var isBreakVisible: Bool = false
    /// Seconds left in the visible break, or nil when nothing is counting down.
    @Published private(set) var remainingSeconds: Int?

    /// The settings steppers already bound these, but `Defaults` is writable from
    /// outside the app (`defaults write`, a synced plist), and a zero or negative
    /// duration produces an already-expired deadline: the schedule would then fire
    /// a break on every tick and each break would end the moment it appeared.
    /// Both construction sites go through these so the bound cannot be enforced in
    /// one place and forgotten in the other.
    private static func clampedWorkInterval() -> TimeInterval {
        TimeInterval(min(max(Defaults[.eyeBreakWorkInterval], 5), 120)) * 60
    }

    private static func clampedRestDuration() -> TimeInterval {
        TimeInterval(min(max(Defaults[.eyeBreakRestDuration], 10), 120))
    }

    private var schedule = EyeBreakSchedule(
        workInterval: EyeBreakManager.clampedWorkInterval(),
        restDuration: EyeBreakManager.clampedRestDuration()
    )

    private var ticker: Timer?
    /// Interval the running ticker was scheduled with, so it is only rebuilt when
    /// the cadence actually needs to change.
    private var tickerInterval: TimeInterval?
    private var cancellables = Set<AnyCancellable>()
    private var soundPlayer: AVAudioPlayer?
    private var areScreensAsleep = false

    /// While resting, the countdown is on screen and needs a second-by-second
    /// tick. While working there is nothing to draw, so a coarse tick is enough
    /// to notice the deadline — the deadline itself is absolute, so a late tick
    /// costs accuracy in when the break appears, not in when it was due.
    private static let restingTickInterval: TimeInterval = 0.5
    private static let workingTickInterval: TimeInterval = 15

    /// Deliberately empty. ContentView touches `shared` while building its body,
    /// which happens before `applicationDidFinishLaunching`; reaching for other
    /// managers or Defaults publishers from here would wire the app together in
    /// an order it does not expect. `start()` does that work instead, following
    /// the same configure-at-launch pattern as LockScreenManager and
    /// SystemHUDManager.
    private init() {}

    private var hasStarted = false

    /// Called once from `applicationDidFinishLaunching`.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        observeSettings()
        observeSystemState()
        applyEnabledState()
    }

    // MARK: - Public actions

    /// Ends the break early and starts the next work interval.
    func skipBreak() {
        schedule.skipBreak(at: Date())
        stopSound()
        publish()
    }

    // MARK: - Settings

    private func observeSettings() {
        Defaults.publisher(.enableEyeBreak, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyEnabledState() }
            }
            .store(in: &cancellables)

        Defaults.publisher(.eyeBreakWorkInterval, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyDurations() }
            }
            .store(in: &cancellables)

        Defaults.publisher(.eyeBreakRestDuration, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyDurations() }
            }
            .store(in: &cancellables)

        Defaults.publisher(.eyeBreakPauseWhenLocked, options: [])
            .sink { [weak self] _ in
                Task { @MainActor in self?.evaluatePause() }
            }
            .store(in: &cancellables)
    }

    private func applyEnabledState() {
        if Defaults[.enableEyeBreak] {
            guard !schedule.isRunning else { return }
            schedule.start(at: Date())
            evaluatePause()
        } else {
            schedule.stop()
            stopSound()
        }
        publish()
    }

    private func applyDurations() {
        schedule.updateDurations(
            workInterval: Self.clampedWorkInterval(),
            restDuration: Self.clampedRestDuration(),
            at: Date()
        )
        publish()
    }

    // MARK: - System state

    private func observeSystemState() {
        LockScreenManager.shared.$isLocked
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.evaluatePause() }
            }
            .store(in: &cancellables)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.areScreensAsleep = true
                    self?.evaluatePause()
                }
            }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.areScreensAsleep = false
                    // A single re-evaluation after any sleep gap. The schedule works
                    // from absolute deadlines, so hours away collapse into one
                    // transition rather than a pile of missed breaks.
                    self?.evaluatePause()
                }
            }
        }
    }

    /// True while a break may not be presented: the user is not looking at the
    /// screen, so counting down a break they cannot see would waste it.
    private var isUserAway: Bool {
        areScreensAsleep || (Defaults[.eyeBreakPauseWhenLocked] && LockScreenManager.shared.isLocked)
    }

    private func evaluatePause() {
        let now = Date()
        if isUserAway {
            schedule.pause(at: now)
            stopSound()
        } else {
            schedule.resume(at: now)
        }
        publish()
    }

    // MARK: - Ticking

    private func tick() {
        let wasResting = schedule.isBreakVisible
        schedule.advance(to: Date(), canPresent: !isUserAway)
        if schedule.isBreakVisible && !wasResting {
            playBreakSound()
        } else if !schedule.isBreakVisible && wasResting {
            stopSound()
        }
        publish()
    }

    private func publish() {
        let now = Date()
        isBreakVisible = schedule.isBreakVisible
        remainingSeconds = schedule.isBreakVisible ? schedule.remainingSeconds(at: now) : nil
        updateTicker()
    }

    private func updateTicker() {
        guard schedule.isRunning else {
            ticker?.invalidate()
            ticker = nil
            tickerInterval = nil
            return
        }

        let interval = schedule.isBreakVisible ? Self.restingTickInterval : Self.workingTickInterval
        guard tickerInterval != interval else { return }

        ticker?.invalidate()
        tickerInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // A relaxed tolerance lets the system coalesce these wake-ups with others;
        // the deadline is absolute, so drift only shifts when the notch notices.
        timer.tolerance = interval / 2
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    // MARK: - Sound

    private func playBreakSound() {
        guard Defaults[.eyeBreakPlaySound] else { return }
        guard let url = Bundle.main.url(forResource: "timer", withExtension: "mp3") else {
            NSSound.beep()
            return
        }
        do {
            soundPlayer = try AVAudioPlayer(contentsOf: url)
            soundPlayer?.play()
        } catch {
            Logger.log("Could not play the eye break chime: \(error.localizedDescription)", category: .warning)
            NSSound.beep()
        }
    }

    private func stopSound() {
        soundPlayer?.stop()
        soundPlayer = nil
    }
}
