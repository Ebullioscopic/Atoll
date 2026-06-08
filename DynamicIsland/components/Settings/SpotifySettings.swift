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

import Defaults
import SwiftUI

struct SpotifySettings: View {
    @Default(.enableSpotifyFeature) private var enableSpotify
    @Default(.spotifyDefaultShuffle) private var defaultShuffle
    @Default(.spotifyRecentLimit) private var recentLimit

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Enable Spotify tab"), isOn: $enableSpotify)
            }
            Section(String(localized: "Playback")) {
                Toggle(String(localized: "Shuffle by default"), isOn: $defaultShuffle)
                Stepper(value: $recentLimit, in: 5...50) {
                    Text("Recently played shown: \(recentLimit)")
                }
            }
            SpotifyAuthSettingsSection()
        }
        .formStyle(.grouped)
    }
}
