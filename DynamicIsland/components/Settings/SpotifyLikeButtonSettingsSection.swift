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

                Text(statusText)
                    .foregroundStyle(.secondary)
            }

            if let error = libraryManager.error {
                Text(message(for: error))
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

    /// Derived from the view's own client ID binding rather than the manager's
    /// copy, so the line updates while the user is still typing.
    private var statusText: String {
        if libraryManager.isAuthenticated {
            return String(localized: "Connected — like button ready.")
        }
        if clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Not connected.")
        }
        return String(localized: "Client ID saved. Connect your Spotify account.")
    }

    private func message(for error: SpotifyLibraryError) -> String {
        switch error {
        case .missingClientID:
            return String(localized: "Paste the Client ID of your Spotify Developer app first.")
        case .secureRandomUnavailable:
            return String(localized: "Unable to generate secure random data for the login.")
        case .canceled:
            return ""
        case .missingAuthorizationCode:
            return String(localized: "Spotify did not return an authorization code.")
        case .authSessionFailed(let description):
            return String(localized: "Spotify login failed: \(description)")
        case .tokenExchangeFailed(let description):
            return String(localized: "Token exchange failed: \(description)")
        case .refreshTokenRevoked:
            return String(localized: "Spotify revoked access. Connect your account again.")
        }
    }
}
