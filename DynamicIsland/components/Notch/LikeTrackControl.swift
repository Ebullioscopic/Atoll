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

import SwiftUI

/// Derived, ready-to-render state for the "like current track" control.
///
/// This is the single place that maps `MusicManager.isCurrentTrackLiked`
/// (a `Bool?`, where `nil` means "unknown / not yet resolved") onto the
/// visual facts every player view needs. Keeping the mapping here means the
/// three player views can never drift apart.
struct LikeTrackPresentation {
    /// SF Symbol name: filled heart when liked, outline otherwise.
    let iconName: String
    /// Whether the track is currently liked (drives each view's active tint).
    let isActive: Bool
    /// Whether the control should be non-interactive: the liked-state is
    /// unknown, or the source will report it but not change it.
    let isDisabled: Bool
    /// Opacity to dim the control with while the liked-state is unknown.
    let dimmedOpacity: Double

    init(isCurrentTrackLiked: Bool?, isReadOnly: Bool = false) {
        let liked = isCurrentTrackLiked == true
        let unknown = isCurrentTrackLiked == nil

        iconName = liked ? "heart.fill" : "heart"
        isActive = liked
        isDisabled = unknown || isReadOnly
        // A read-only heart is not dimmed. It is showing a real answer, and
        // dimming it would read as "not working" rather than "not yours to
        // change from here".
        dimmedOpacity = unknown ? 0.4 : 1
    }
}

/// Shared wrapper for the "like current track" heart button.
///
/// It owns the liked-state logic and the toggle action, and hands the derived
/// ``LikeTrackPresentation`` plus a `toggle` closure to a caller-supplied
/// `@ViewBuilder`. Each player view keeps rendering its *own* button chrome
/// (`HoverButton`, a private `controlButton`, …) so on-screen appearance and
/// animations are preserved — only the duplicated mapping and the
/// `.disabled` / `.opacity` modifiers are centralized here and applied once.
///
/// Example:
/// ```swift
/// LikeTrackControl { presentation, toggle in
///     HoverButton(
///         icon: presentation.iconName,
///         iconColor: presentation.isActive ? brandAccentColor : .white,
///         scale: .medium
///     ) {
///         toggle()
///     }
/// }
/// ```
struct LikeTrackControl<Content: View>: View {
    @ObservedObject private var musicManager = MusicManager.shared

    private let content: (LikeTrackPresentation, @escaping () -> Void) -> Content

    init(
        @ViewBuilder content: @escaping (LikeTrackPresentation, @escaping () -> Void) -> Content
    ) {
        self.content = content
    }

    var body: some View {
        let presentation = LikeTrackPresentation(
            isCurrentTrackLiked: musicManager.isCurrentTrackLiked,
            isReadOnly: musicManager.activeSourceFavoritingIsReadOnly
        )

        content(presentation) {
            MusicManager.shared.toggleLike()
        }
        .disabled(presentation.isDisabled)
        .opacity(presentation.dimmedOpacity)
    }
}
