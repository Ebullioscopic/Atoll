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

import AppKit
import Foundation

/// Represents a detected media source when using "All Music" multi-source mode.
/// Each source corresponds to a distinct app that is (or was recently) playing media.
struct MediaSource: Identifiable, Equatable {
    /// Unique identifier — the app's bundle identifier.
    let id: String

    /// The app's bundle identifier (same as `id`, kept for clarity).
    var bundleIdentifier: String

    /// The currently playing track title.
    var title: String

    /// The currently playing track artist.
    var artist: String

    /// Album artwork as raw data (optional; UI resolves to NSImage).
    var artworkData: Data?

    /// Whether this source is actively playing.
    var isPlaying: Bool

    /// The last time this source received a playback state update.
    var lastUpdated: Date

    static func == (lhs: MediaSource, rhs: MediaSource) -> Bool {
        return lhs.id == rhs.id
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.isPlaying == rhs.isPlaying
            && lhs.artworkData == rhs.artworkData
    }
}
