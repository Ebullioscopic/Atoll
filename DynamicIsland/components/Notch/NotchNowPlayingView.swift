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

import SwiftUI

/// The Now Playing tab: the standard music player across the whole row, with
/// no calendar or lyrics beside it.
///
/// It wraps the player the way ``NotchHomeView`` wrapped it -- the same
/// padding, blur and transition -- so the album art still flies in and out of
/// the closed notch through `albumArtNamespace`.
struct NotchNowPlayingView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                MusicPlayerView(albumArtNamespace: albumArtNamespace)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.animation(.smooth.speed(0.9))
                        .combined(with: .move(edge: .top)))
                    .blur(radius: vm.notchState == .closed ? 30 : 0)
                    .padding(8)
            }
        }
        .transition(.opacity)
    }
}
