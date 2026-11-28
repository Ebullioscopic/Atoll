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

import CoreGraphics
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

    /// Whether the detector should look again later. Either a fullscreen app is
    /// on screen but has not (yet) become the Now Playing app — the window went
    /// fullscreen before playback started — or the island is hidden while the
    /// active media controller does not observe system Now Playing
    /// (`nowPlayingIsObserved == false`), so nothing else would notice playback
    /// moving to another app.
    static func shouldKeepRechecking(option: HideNotchOption,
                                     detectionEnabled: Bool,
                                     hasFullscreenCandidate: Bool,
                                     isHidden: Bool,
                                     nowPlayingIsObserved: Bool) -> Bool {
        option == .nowPlayingOnly
            && detectionEnabled
            && hasFullscreenCandidate
            && (!isHidden || !nowPlayingIsObserved)
    }

    /// How an on-screen window covers its display.
    enum WindowFit: Equatable {
        /// Not the shape of a fullscreen window.
        case none
        /// The whole safe area, like a fullscreen window (or a maximized one).
        case whole
        /// The full height of the safe area but only part of its width, like
        /// one side of a fullscreen Split View.
        case tile
    }

    /// Classifies a window frame against its display's safe area (both in the
    /// same coordinate space). Sizes may be off by `sizeTolerance` of the safe
    /// area and edges by `edgeTolerance` points. A tile must be at least
    /// `minimumTileWidthFraction` of the width, which keeps narrow full-height
    /// panels out while still covering the narrowest Split View pane.
    static func windowFit(window: CGRect,
                          safeArea: CGRect,
                          sizeTolerance: CGFloat = 0.02,
                          edgeTolerance: CGFloat = 5,
                          minimumTileWidthFraction: CGFloat = 0.2) -> WindowFit {
        guard safeArea.width > 0, safeArea.height > 0 else { return .none }
        let heightMatches = abs(window.height - safeArea.height) < safeArea.height * sizeTolerance
            && abs(window.minY - safeArea.minY) < edgeTolerance
        guard heightMatches else { return .none }

        let widthMatches = abs(window.width - safeArea.width) < safeArea.width * sizeTolerance
            && abs(window.minX - safeArea.minX) < edgeTolerance
        if widthMatches { return .whole }

        let insideHorizontally = window.minX > safeArea.minX - edgeTolerance
            && window.maxX < safeArea.maxX + edgeTolerance
        guard insideHorizontally, window.width >= safeArea.width * minimumTileWidthFraction else { return .none }
        return .tile
    }

    /// Whether an Accessibility window frame is the on-screen window that was
    /// detected, so the fullscreen check reads that window and not another one
    /// of the same app (for example a fullscreen window on another Space).
    static func isSameWindow(_ frame: CGRect, as detected: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(frame.minX - detected.minX) <= tolerance
            && abs(frame.minY - detected.minY) <= tolerance
            && abs(frame.width - detected.width) <= tolerance
            && abs(frame.height - detected.height) <= tolerance
    }

    /// Follow-up checks allowed after a Space, screen, frontmost-app or
    /// playback change. Anything later is picked up by the next such event.
    static let maxRechecks = 3

    /// Seconds to wait before the next follow-up check, given how many have run
    /// since the last change: 2, 4 and 8 s, for playback started right after
    /// going fullscreen. Nil once `maxRechecks` is reached, so a fullscreen app
    /// that never plays stops costing Now Playing queries.
    static func recheckDelay(afterRechecks rechecksDone: Int) -> TimeInterval? {
        let done = max(rechecksDone, 0)
        guard done < maxRechecks else { return nil }
        return 2 * pow(2, Double(done))
    }
}
