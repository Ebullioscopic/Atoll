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

struct SpotifyLikeButtonSettingsSection: View {
    @Default(.spotifyLibraryClientID) private var clientID
    @ObservedObject private var libraryManager = SpotifyLibraryManager.shared

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("The like button needs its own Spotify app registration (the Canvas cookie session cannot modify your library). Create a free app at developer.spotify.com, add the redirect URI below, then paste the app's Client ID here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Client ID", text: $clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())

                HStack(spacing: 6) {
                    Text("Redirect URI:")
                        .foregroundStyle(.secondary)
                    Text(SpotifyLibraryManager.redirectURI)
                        .textSelection(.enabled)
                        .monospaced()
                }
                .font(.caption)
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(libraryManager.isAuthenticated ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)

                Text(libraryManager.statusText)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = libraryManager.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(libraryManager.isAuthorizing ? "Connecting..." : "Connect Spotify Account") {
                    libraryManager.connect()
                }
                .disabled(clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || libraryManager.isAuthorizing)

                Button("Disconnect") {
                    libraryManager.disconnect()
                }
                .disabled(!libraryManager.isAuthenticated)

                Link("Open Developer Dashboard", destination: URL(string: "https://developer.spotify.com/dashboard")!)
                    .font(.caption)
            }
        } header: {
            Text("Spotify Like Button")
        } footer: {
            Text("Uses Spotify's official Web API (OAuth) with access limited to reading and changing your Liked Songs. Add the 'Like Song' control to a media slot to show the button.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
