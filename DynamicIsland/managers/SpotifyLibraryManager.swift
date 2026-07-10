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

import AppKit
import AuthenticationServices
import CryptoKit
import Defaults
import Foundation

/// Official Spotify Web API access via OAuth 2.0 PKCE, scoped to the user's
/// Liked Songs (user-library-read / user-library-modify). Independent from
/// SpotifyAuthManager's sp_dc cookie session: Spotify rejects those web-player
/// tokens on api.spotify.com, so the like button needs a registered app token.
@MainActor
final class SpotifyLibraryManager: NSObject, ObservableObject {
    static let shared = SpotifyLibraryManager()

    static let redirectURI = "atoll-spotify://oauth-callback"
    private static let scopes = "user-library-read user-library-modify"
    private static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    private static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    @Published private(set) var isAuthenticated = false
    @Published private(set) var isAuthorizing = false
    @Published private(set) var statusText = "Not connected."
    @Published private(set) var errorMessage: String?

    private var authSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
        refreshPublishedState()
    }

    var configuredClientID: String {
        Defaults[.spotifyLibraryClientID].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Connect / Disconnect

    func connect() {
        errorMessage = nil
        let clientID = configuredClientID
        guard !clientID.isEmpty else {
            errorMessage = "Paste the Client ID of your Spotify Developer app first."
            return
        }

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge)
        ]

        guard let url = components.url else { return }

        isAuthorizing = true
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "atoll-spotify"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                await self?.handleAuthCallback(callbackURL: callbackURL, error: error, verifier: verifier, clientID: clientID)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    func disconnect() {
        Defaults[.spotifyLibraryAccessToken] = ""
        Defaults[.spotifyLibraryRefreshToken] = ""
        Defaults[.spotifyLibraryTokenExpiration] = 0
        errorMessage = nil
        refreshPublishedState()
    }

    private func handleAuthCallback(callbackURL: URL?, error: Error?, verifier: String, clientID: String) async {
        defer {
            isAuthorizing = false
            refreshPublishedState()
        }

        if let error {
            if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                errorMessage = error.localizedDescription
            }
            return
        }

        guard let callbackURL,
              let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            errorMessage = "Spotify did not return an authorization code."
            return
        }

        do {
            try await exchangeToken(body: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirectURI,
                "client_id": clientID,
                "code_verifier": verifier
            ])
            errorMessage = nil
        } catch {
            errorMessage = "Token exchange failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Tokens

    func validAccessToken(forceRefresh: Bool = false) async -> String? {
        let cachedToken = Defaults[.spotifyLibraryAccessToken]
        let expiration = Defaults[.spotifyLibraryTokenExpiration]
        if !forceRefresh, !cachedToken.isEmpty, expiration > Date().timeIntervalSince1970 + 60 {
            return cachedToken
        }

        let refreshToken = Defaults[.spotifyLibraryRefreshToken]
        let clientID = configuredClientID
        guard !refreshToken.isEmpty, !clientID.isEmpty else { return nil }

        do {
            try await exchangeToken(body: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID
            ])
            return Defaults[.spotifyLibraryAccessToken]
        } catch {
            return nil
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private func exchangeToken(body: [String: String]) async throws {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw URLError(.userAuthenticationRequired)
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        Defaults[.spotifyLibraryAccessToken] = token.accessToken
        if let refreshToken = token.refreshToken, !refreshToken.isEmpty {
            Defaults[.spotifyLibraryRefreshToken] = refreshToken
        }
        Defaults[.spotifyLibraryTokenExpiration] = Date().timeIntervalSince1970 + token.expiresIn
        refreshPublishedState()
    }

    private func refreshPublishedState() {
        isAuthenticated = !Defaults[.spotifyLibraryRefreshToken].isEmpty && !configuredClientID.isEmpty
        if isAuthenticated {
            statusText = "Connected — like button ready."
        } else if configuredClientID.isEmpty {
            statusText = "Not connected."
        } else {
            statusText = "Client ID saved. Connect your Spotify account."
        }
    }

    // MARK: - Saved Tracks API
    // Uses the /me/library endpoints introduced February 2026; the legacy
    // /me/tracks save/contains endpoints silently return 403 for new apps.

    /// nil = unknown (not connected / request failed)
    func isTrackSaved(trackID: String) async -> Bool? {
        guard let data = await request(
            method: "GET",
            path: "/me/library/contains?uris=spotify%3Atrack%3A\(trackID)"
        ) else { return nil }
        return (try? JSONDecoder().decode([Bool].self, from: data))?.first
    }

    func setTrackSaved(_ saved: Bool, trackID: String) async -> Bool {
        await request(
            method: saved ? "PUT" : "DELETE",
            path: "/me/library?uris=spotify%3Atrack%3A\(trackID)"
        ) != nil
    }

    private func request(method: String, path: String, retryOnUnauthorized: Bool = true) async -> Data? {
        guard let accessToken = await validAccessToken(),
              let url = URL(string: "https://api.spotify.com/v1\(path)")
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            if httpResponse.statusCode == 401, retryOnUnauthorized {
                _ = await validAccessToken(forceRefresh: true)
                return await self.request(method: method, path: path, retryOnUnauthorized: false)
            }

            guard (200..<300).contains(httpResponse.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(length: Int) -> String {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension SpotifyLibraryManager: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.mainWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }
}
