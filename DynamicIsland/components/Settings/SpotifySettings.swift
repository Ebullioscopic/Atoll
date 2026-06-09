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
    @ObservedObject private var oauth = SpotifyOAuthManager.shared
    @Default(.spotifyOAuthClientID) private var clientID
    @Default(.spotifyStandalonePlayback) private var standalone
    @ObservedObject private var player = SpotifyPlayerManager.shared
    @State private var authSheet: AuthSheetData?

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
            Section(String(localized: "Standalone Playback")) {
                Toggle(String(localized: "Play inside Atoll (no Spotify app needed)"), isOn: $standalone)
                Text(String(localized: "Requires Spotify Premium. Plays audio through Atoll itself as a Spotify Connect device."))
                    .font(.caption).foregroundStyle(.secondary)
                if standalone {
                    if player.isReady {
                        HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(String(localized: "Atoll player ready")) }
                    } else if let status = player.statusMessage {
                        Text(status).font(.caption).foregroundStyle(.red)
                    } else {
                        Text(String(localized: "Starting player…")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear { SpotifyPlayerManager.shared.start() }
            Section(String(localized: "Spotify Account (Web API)")) {
                TextField(String(localized: "Client ID"), text: $clientID)
                    .textFieldStyle(.roundedBorder)
                LabeledContent(String(localized: "Redirect URI"), value: SpotifyOAuthManager.redirectURI)
                Text(String(localized: "Create a free app at developer.spotify.com, add the redirect URI above to it, paste its Client ID here, then Connect."))
                    .font(.caption).foregroundStyle(.secondary)
                if oauth.isAuthenticated {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(String(localized: "Connected"))
                    }
                    if !oauth.canModifyLibrary {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            Text(String(localized: "Like/unlike isn’t authorized for this session. Disconnect and reconnect — the Spotify consent screen will now ask for the library permission."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    DisclosureGroup(String(localized: "Granted permissions")) {
                        Text(oauth.grantedScopesDisplay)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    Button(String(localized: "Disconnect"), role: .destructive) { oauth.disconnect() }
                } else {
                    Button(String(localized: "Connect with Spotify")) {
                        let (url, verifier) = oauth.makeAuthorizeURL()
                        if let url { authSheet = AuthSheetData(url: url, verifier: verifier) }
                    }
                    .disabled(clientID.isEmpty)
                }
                if let err = oauth.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $authSheet) { data in
            SpotifyOAuthSheet(authorizeURL: data.url, verifier: data.verifier, onFinished: { SpotifyPlayerManager.shared.restart() })
        }
    }
}

struct AuthSheetData: Identifiable {
    let id = UUID()
    let url: URL
    let verifier: String
}
