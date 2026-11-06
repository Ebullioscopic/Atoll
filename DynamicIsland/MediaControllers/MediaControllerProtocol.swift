/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import AppKit
import Combine

protocol MediaControllerProtocol: ObservableObject {
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> { get }
    var isWorking: Bool { get }
    func play() async
    func pause() async
    func seek(to time: Double) async
    func nextTrack() async
    func previousTrack() async
    func togglePlay() async
    func toggleShuffle() async
    func toggleRepeat() async
    func isActive() -> Bool
    func updatePlaybackInfo() async

    // MARK: - Favouriting

    /// Whether favouriting applies to this source at all.
    ///
    /// Deliberately not the same question as ``supportsFavoriting``. This one
    /// decides whether the control is offered in settings, and it has to hold
    /// still: a user configuring their slots should not find the option gone
    /// because the music happens to be stopped, or because they have not
    /// connected an account *yet*. It answers "could this source ever do it",
    /// so the control can be placed now and work later.
    @MainActor var canEverFavorite: Bool { get }

    /// Whether favouriting would work right now. Drives the enabled state, not
    /// whether the control exists.
    @MainActor var supportsFavoriting: Bool { get }

    /// Whether this source will report the favourited state but refuse to
    /// change it. The control still shows the truth -- worth having on its own
    /// -- and simply does not take a click.
    @MainActor var favoritingIsReadOnly: Bool { get }

    /// Whether the playing track is favourited, or `nil` while that is not yet
    /// known -- nothing is playing, the answer is still being fetched, or the
    /// source cannot say.
    func isCurrentTrackFavorited() async -> Bool?

    /// Favourites or unfavourites the playing track. Returns whether it worked,
    /// so the caller can put an optimistic toggle back if it did not.
    @discardableResult
    func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool
}

extension MediaControllerProtocol {
    @MainActor var canEverFavorite: Bool { false }
    @MainActor var supportsFavoriting: Bool { false }

    @MainActor var favoritingIsReadOnly: Bool { false }
    func isCurrentTrackFavorited() async -> Bool? { nil }
    @discardableResult
    func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool { false }
}
