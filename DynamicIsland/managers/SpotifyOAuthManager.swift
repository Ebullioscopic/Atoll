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

import Combine
import Foundation

@MainActor
final class SpotifyOAuthManager: ObservableObject {
    static let shared = SpotifyOAuthManager()

    static let redirectURI = "atoll://callback"
    static let scopes = [
        "playlist-read-private", "playlist-read-collaborative",
        "user-read-recently-played", "user-library-read",
        "user-read-playback-state", "user-modify-playback-state"
    ]

    @Published private(set) var isAuthenticated = false
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let session: URLSession
    private let authorizeBase = "https://accounts.spotify.com/authorize"
    private let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        self.isAuthenticated = !(defaults.string(forKey: "spotifyOAuthRefreshToken") ?? "").isEmpty
    }

    private var clientID: String { defaults.string(forKey: "spotifyOAuthClientID") ?? "" }

    func makeAuthorizeURL() -> (URL?, verifier: String) {
        let verifier = SpotifyPKCE.makeVerifier()
        let challenge = SpotifyPKCE.challenge(for: verifier)
        var comps = URLComponents(string: authorizeBase)
        comps?.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "state", value: UUID().uuidString)
        ]
        return (comps?.url, verifier)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    func exchangeCode(_ code: String, verifier: String) async {
        await postToken([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier
        ], isRefresh: false)
    }

    func validAccessToken(forceRefresh: Bool = false) async -> String? {
        let token = defaults.string(forKey: "spotifyOAuthAccessToken") ?? ""
        let exp = defaults.double(forKey: "spotifyOAuthExpiration")
        if !forceRefresh, !token.isEmpty, exp > Date().timeIntervalSince1970 + 60 {
            return token
        }
        let refresh = defaults.string(forKey: "spotifyOAuthRefreshToken") ?? ""
        guard !refresh.isEmpty else { return token.isEmpty ? nil : token }
        await postToken([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientID
        ], isRefresh: true)
        let newToken = defaults.string(forKey: "spotifyOAuthAccessToken") ?? ""
        return newToken.isEmpty ? nil : newToken
    }

    func disconnect() {
        defaults.removeObject(forKey: "spotifyOAuthAccessToken")
        defaults.removeObject(forKey: "spotifyOAuthRefreshToken")
        defaults.removeObject(forKey: "spotifyOAuthExpiration")
        isAuthenticated = false
    }

    private func postToken(_ form: [String: String], isRefresh: Bool) async {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let snippet = String(data: data.prefix(300), encoding: .utf8) ?? ""
                NSLog("[SpotifyOAuth] token endpoint failed: %@", snippet)
                errorMessage = String(localized: "Spotify sign-in failed.")
                if isRefresh { disconnect() }
                return
            }
            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            defaults.set(token.access_token, forKey: "spotifyOAuthAccessToken")
            defaults.set(Date().timeIntervalSince1970 + token.expires_in, forKey: "spotifyOAuthExpiration")
            if let rt = token.refresh_token { defaults.set(rt, forKey: "spotifyOAuthRefreshToken") }
            isAuthenticated = !(defaults.string(forKey: "spotifyOAuthRefreshToken") ?? "").isEmpty || !token.access_token.isEmpty
            errorMessage = nil
        } catch {
            NSLog("[SpotifyOAuth] token error: %@", String(describing: error))
            errorMessage = String(localized: "Spotify sign-in failed.")
        }
    }
}
