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
import Foundation
import Security

/// Official Spotify Web API access via OAuth 2.0 PKCE, scoped to the user's
/// Liked Songs (user-library-read / user-library-modify). Independent from
/// SpotifyAuthManager's sp_dc cookie session: Spotify rejects those web-player
/// tokens on api.spotify.com, so the like button needs a registered app token.
///
/// Coordinates SpotifyOAuthService (auth) and SpotifyLibraryAPI (calls), and
/// publishes raw state; the settings view owns all user-facing wording.
@MainActor
final class SpotifyLibraryManager: ObservableObject {
    static let shared = SpotifyLibraryManager()

    static let redirectURI = SpotifyOAuthService.redirectURI

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthorizing = false
    @Published private(set) var error: SpotifyLibraryError?

    private let tokenStore: SpotifyTokenStoring
    private let oauth: SpotifyOAuthService
    private let api: SpotifyLibraryAPI

    /// Use `.shared`. The injectable initializer exists for tests: a second live
    /// instance would race the first over Spotify's rotating refresh token.
    /// `authSession` defaults to nil rather than a presenter instance because a
    /// default argument is evaluated in a nonisolated context, and the presenter
    /// is main-actor bound.
    init(
        tokenStore: SpotifyTokenStoring = KeychainSpotifyTokenStore(),
        httpClient: SpotifyHTTPClient = URLSessionSpotifyHTTPClient(),
        authSession: SpotifyAuthSessionPresenting? = nil
    ) {
        self.tokenStore = tokenStore
        self.oauth = SpotifyOAuthService(
            tokenStore: tokenStore,
            httpClient: httpClient,
            authSession: authSession ?? WebAuthenticationSessionPresenter()
        )
        self.api = SpotifyLibraryAPI(tokenProvider: oauth, httpClient: httpClient)

        migrateLegacyTokensIfNeeded()
        oauth.onTokenStateChange = { [weak self] in self?.refreshAuthenticationState() }
        refreshAuthenticationState()
    }

    /// Tokens were briefly stored in Defaults; move them into the Keychain once.
    /// The Defaults copy is only cleared once the Keychain write is confirmed,
    /// so a failed write can never lose the token.
    private func migrateLegacyTokensIfNeeded() {
        let legacyAccessToken = Defaults[.spotifyLibraryAccessToken]
        if !legacyAccessToken.isEmpty,
           tokenStore.write(legacyAccessToken, account: .accessToken) == errSecSuccess {
            Defaults[.spotifyLibraryAccessToken] = ""
        }
        let legacyRefreshToken = Defaults[.spotifyLibraryRefreshToken]
        if !legacyRefreshToken.isEmpty,
           tokenStore.write(legacyRefreshToken, account: .refreshToken) == errSecSuccess {
            Defaults[.spotifyLibraryRefreshToken] = ""
        }
    }

    var configuredClientID: String {
        Defaults[.spotifyLibraryClientID].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Connect / Disconnect

    func connect() {
        error = nil
        let clientID = configuredClientID
        guard !clientID.isEmpty else {
            error = .missingClientID
            return
        }

        isAuthorizing = true
        Task {
            do {
                try await oauth.authorize(clientID: clientID)
                error = nil
            } catch SpotifyLibraryError.canceled {
                // The user closed the login window; not an error.
            } catch let authError as SpotifyLibraryError {
                error = authError
            } catch {
                self.error = .authSessionFailed(error.localizedDescription)
            }
            isAuthorizing = false
            refreshAuthenticationState()
        }
    }

    /// Spotify exposes no token revocation endpoint for PKCE apps, so deleting
    /// the local pair is the whole of what disconnecting can do. Users revoke
    /// the app itself at spotify.com/account/apps.
    func disconnect() {
        oauth.clearTokens()
        Defaults[.spotifyLibraryAccessToken] = ""
        Defaults[.spotifyLibraryRefreshToken] = ""
        error = nil
        refreshAuthenticationState()
    }

    // MARK: - Saved Tracks

    /// nil = unknown (not connected / request failed)
    func isTrackSaved(trackID: String) async -> Bool? {
        await api.isTrackSaved(trackID: trackID)
    }

    func setTrackSaved(_ saved: Bool, trackID: String) async -> Bool {
        await api.setTrackSaved(saved, trackID: trackID)
    }

    // MARK: - State

    private func refreshAuthenticationState() {
        let hasRefreshToken = !(tokenStore.read(.refreshToken) ?? "").isEmpty
        isAuthenticated = hasRefreshToken && !configuredClientID.isEmpty
    }
}
