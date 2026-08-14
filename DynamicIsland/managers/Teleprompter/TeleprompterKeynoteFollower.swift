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

import Foundation

/// Keeps the prompter on the slide Keynote is actually showing.
///
/// ## Why polling, and why it is cheap enough
/// Keynote posts no notification when the slide changes; the only way to know is
/// to ask. The cost is bounded by only ever asking while a take is running and
/// Keynote is already open — never at launch, never idle, and never at all if
/// the current script did not come from a deck.
///
/// ## Failing quietly, once
/// If automation permission is refused, asking again every second would achieve
/// nothing but a log full of the same refusal. The first failure stops the
/// follower and hands the reason back, exactly once.
@MainActor
final class TeleprompterKeynoteFollower {
    /// Called when Keynote moves to a different slide.
    var onSlideChange: ((Int) -> Void)?
    /// Called once, when following has given up and why.
    var onFailure: ((KeynoteBridgeError) -> Void)?

    private(set) var isFollowing = false
    private var task: Task<Void, Never>?
    private var lastSlide: Int?

    /// Fast enough that a slide change is not visibly late, slow enough that the
    /// Apple event costs nothing measurable.
    private static let interval: Duration = .milliseconds(900)

    func start() {
        guard !isFollowing, KeynoteBridge.isInstalled else { return }
        isFollowing = true
        lastSlide = nil

        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled, let self, self.isFollowing else { return }
                await self.poll()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isFollowing = false
        lastSlide = nil
    }

    private func poll() async {
        // Keynote not being open is the ordinary case, not a failure: someone
        // may start the deck halfway through a take.
        guard KeynoteBridge.isRunning else { return }

        do {
            guard let slide = try await KeynoteBridge.playingSlideNumber() else { return }
            guard slide != lastSlide else { return }
            lastSlide = slide
            onSlideChange?(slide)
        } catch let error as KeynoteBridgeError {
            // A show that ended between the check and the event is not worth
            // reporting; a refusal is, and it ends the attempt.
            if error == .notRunning { return }
            stop()
            onFailure?(error)
        } catch {
            stop()
            onFailure?(.failed(error.localizedDescription))
        }
    }
}
