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

/// Cider's API token, needed only for the Favorite Song control.
///
/// Playback works without any of this -- it comes from macOS Now Playing. Only
/// favouriting has to ask Cider directly, so the section says so rather than
/// looking like a requirement for the source as a whole.
struct CiderFavoritingSettingsSection: View {
    @State private var token: String = CiderTokenStore.shared.token

    var body: some View {
        Section {
            // No `settingsHighlight` here: `SettingsTab` is private to
            // SettingsView, and the sibling Spotify sections do without it too.
            SecureField(String(localized: "API token"), text: $token)
                .textFieldStyle(.roundedBorder)
                .onChange(of: token) { _, value in
                    CiderTokenStore.shared.setToken(value)
                }
        } header: {
            Text("Favorite Song in Cider")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Playback needs none of this. The Favorite Song control does, because favouriting is not something macOS Now Playing can carry -- Atoll has to ask Cider itself.")

                Text("In Cider, open Settings > Connectivity > Manage External Application Access, switch the API on, and paste the token it generates here. If you turn its authentication off instead, leave this empty.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
