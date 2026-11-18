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

/// The decisions behind "Hide DynamicIsland" in fullscreen, kept free of
/// window-server and Accessibility calls so they can be tested directly.
enum FullscreenHidePolicy {

    /// Whether one fullscreen app should hide the closed notch on its screen.
    ///
    /// For `.nowPlayingOnly`, `nowPlayingBundleID` is the app macOS reports as
    /// Now Playing — not the media source chosen in Atoll — so a video player
    /// or browser hides the notch even when Apple Music or Spotify is the
    /// selected source.
    static func shouldHide(option: HideNotchOption,
                           fullscreenBundleID: String?,
                           nowPlayingBundleID: String?,
                           isNativeFullscreen: Bool) -> Bool {
        switch option {
        case .always:
            return isNativeFullscreen
        case .nowPlayingOnly:
            guard let fullscreenBundleID, fullscreenBundleID == nowPlayingBundleID else { return false }
            return isNativeFullscreen
        case .never:
            return false
        }
    }

    /// How many follow-up checks one Space, screen or Now Playing change may
    /// trigger: at a 2 s interval, about 30 s to start playback after going
    /// fullscreen. Bounded so a fullscreen app that never plays anything does
    /// not cost a Now Playing query every two seconds for as long as it is open.
    static let maxRechecksPerChange = 15

    /// Whether the detector should look again shortly: a native-fullscreen app
    /// is on screen but has not (yet) become the Now Playing app, e.g. the
    /// window went fullscreen before playback started.
    static func shouldKeepRechecking(option: HideNotchOption,
                                     detectionEnabled: Bool,
                                     hasFullscreenCandidate: Bool,
                                     isHidden: Bool,
                                     rechecksDone: Int) -> Bool {
        option == .nowPlayingOnly
            && detectionEnabled
            && hasFullscreenCandidate
            && !isHidden
            && rechecksDone < maxRechecksPerChange
    }
}
