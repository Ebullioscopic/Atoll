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

import Combine
import Defaults
import Foundation
import IOKit.pwr_mgt
import SwiftUI

/// Keeps the Mac awake for as long as the user asks, the way `caffeinate(8)`
/// does, by holding an IOKit power assertion.
///
/// The assertion is held by this process, so it is released automatically if
/// Atoll exits for any reason -- there is no way to leave the Mac permanently
/// caffeinated by crashing.
@MainActor
final class CaffeinateManager: ObservableObject {
    static let shared = CaffeinateManager()

    /// Whether an assertion is currently held.
    @Published private(set) var isActive: Bool = false

    /// When the current session ends, or `nil` for an indefinite session.
    @Published private(set) var expiresAt: Date?

    /// Seconds left in a timed session, republished once a second so views can
    /// count down. `nil` while idle or during an indefinite session.
    @Published private(set) var remainingTime: TimeInterval?

    /// The duration the running session was started with. Kept so the UI can
    /// show what is running without inferring it back out of `expiresAt`.
    @Published private(set) var activeDuration: CaffeinateDuration?

    private var assertionID: IOPMAssertionID = IOPMAssertionID(0)
    private var ticker: AnyCancellable?
    private var featureCancellable: AnyCancellable?

    private init() {
        // Turning the feature off in Settings must also drop a session that is
        // already running, otherwise the Mac stays awake with no visible
        // control left to stop it.
        featureCancellable = Defaults.publisher(.enableCaffeinate, options: [])
            .sink { [weak self] change in
                guard !change.newValue else { return }
                Task { @MainActor in self?.deactivate() }
            }
    }

    deinit {
        // `deinit` cannot hop to the main actor, and the assertion ID is a
        // plain integer, so release it directly.
        if assertionID != IOPMAssertionID(0) {
            IOPMAssertionRelease(assertionID)
        }
    }

    // MARK: - Control

    /// Starts a session, replacing any session already running.
    ///
    /// Re-asserting is how a duration change is applied: the old assertion is
    /// released first so the two never stack.
    func activate(for duration: CaffeinateDuration) {
        deactivate()

        guard Defaults[.enableCaffeinate] else { return }

        let type = Defaults[.caffeinateKeepsDisplayAwake]
            ? kIOPMAssertionTypeNoDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep

        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.assertionReason as CFString,
            &id
        )

        guard result == kIOReturnSuccess else {
            NSLog("[Caffeinate] IOPMAssertionCreateWithName failed: \(result)")
            return
        }

        assertionID = id
        isActive = true
        activeDuration = duration
        expiresAt = Self.expiry(from: Date(), duration: duration)
        startTicking()
    }

    /// Releases the assertion, if one is held. Safe to call when idle.
    func deactivate() {
        if assertionID != IOPMAssertionID(0) {
            IOPMAssertionRelease(assertionID)
            assertionID = IOPMAssertionID(0)
        }

        ticker?.cancel()
        ticker = nil
        isActive = false
        expiresAt = nil
        remainingTime = nil
        activeDuration = nil
    }

    /// Starts the configured default duration, or stops a running session.
    func toggle() {
        if isActive {
            deactivate()
        } else {
            activate(for: Defaults[.caffeinateDefaultDuration])
        }
    }

    // MARK: - Countdown

    private func startTicking() {
        guard let expiry = expiresAt else {
            // Indefinite: nothing to count down, and no timer to burn wakeups on.
            remainingTime = nil
            return
        }

        remainingTime = max(0, expiry.timeIntervalSinceNow)
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                let left = max(0, expiry.timeIntervalSinceNow)
                self.remainingTime = left
                if left <= 0 {
                    self.deactivate()
                }
            }
    }

    // MARK: - Pure helpers

    private static let assertionReason = "Atoll is keeping this Mac awake"

    /// The moment a session started at `start` should end, or `nil` when the
    /// session never expires on its own.
    nonisolated static func expiry(from start: Date, duration: CaffeinateDuration) -> Date? {
        guard let seconds = duration.seconds else { return nil }
        return start.addingTimeInterval(seconds)
    }

    /// A countdown label: `M:SS` under an hour, `H:MM:SS` at or above it.
    ///
    /// Rounds up, so a session with 0.4s left still reads "0:01" rather than
    /// showing "0:00" for most of its final second.
    nonisolated static func remainingLabel(_ interval: TimeInterval) -> String {
        let total = Int(ceil(max(0, interval)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
