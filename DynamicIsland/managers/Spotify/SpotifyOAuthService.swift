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

import CryptoKit
import Defaults
import Foundation
import Security

/// Narrow view of the OAuth service for consumers that only need a bearer
/// token, so the API client stays unaware of PKCE.
@MainActor
protocol SpotifyTokenProviding: AnyObject {
    func validAccessToken(forceRefresh: Bool) async -> String?
}

/// OAuth 2.0 PKCE against Spotify's accounts service: authorization, token
/// exchange and refresh. Owns nothing user-facing.
@MainActor
final class SpotifyOAuthService: SpotifyTokenProviding {
    static let redirectURI = "atoll-spotify://oauth-callback"

    private static let callbackScheme = "atoll-spotify"
    private static let scopes = "user-library-read user-library-modify"
    private static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    private static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    /// Treat a token as expired this many seconds early, so a request sent just
    /// under the wire cannot arrive at Spotify after the real expiry.
    private static let expiryLeeway: TimeInterval = 60

    /// Fires whenever the stored token pair changes, including refreshes that
    /// originate from a background API call rather than from the manager.
    var onTokenStateChange: (() -> Void)?

    private let tokenStore: SpotifyTokenStoring
    private let httpClient: SpotifyHTTPClient
    private let authSession: SpotifyAuthSessionPresenting

    /// Spotify rotates the refresh token on every exchange, so concurrent
    /// refreshes must share a single in-flight request.
    private var refreshTask: Task<String?, Never>?

    init(
        tokenStore: SpotifyTokenStoring,
        httpClient: SpotifyHTTPClient,
        authSession: SpotifyAuthSessionPresenting
    ) {
        self.tokenStore = tokenStore
        self.httpClient = httpClient
        self.authSession = authSession
    }

    // MARK: - Authorization

    func authorize(clientID: String) async throws {
        guard let verifier = Self.randomURLSafeString(length: 64) else {
            throw SpotifyLibraryError.secureRandomUnavailable
        }
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

        guard let url = components.url else {
            throw SpotifyLibraryError.authSessionFailed("Could not build the Spotify authorization URL.")
        }

        let callbackURL = try await authSession.authenticate(
            url: url,
            callbackURLScheme: Self.callbackScheme
        )

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw SpotifyLibraryError.missingAuthorizationCode
        }

        try await exchangeToken(
            body: [
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirectURI,
                "client_id": clientID,
                "code_verifier": verifier
            ],
            grant: .authorizationCode
        )
    }

    func clearTokens() {
        tokenStore.delete(.accessToken)
        tokenStore.delete(.refreshToken)
        Defaults[.spotifyLibraryTokenExpiration] = 0
    }

    // MARK: - Tokens

    func validAccessToken(forceRefresh: Bool = false) async -> String? {
        if !forceRefresh,
           let cachedToken = tokenStore.read(.accessToken),
           !cachedToken.isEmpty,
           Defaults[.spotifyLibraryTokenExpiration] > Date().timeIntervalSince1970 + Self.expiryLeeway {
            return cachedToken
        }

        if let refreshTask {
            return await refreshTask.value
        }

        guard let refreshToken = tokenStore.read(.refreshToken),
              !refreshToken.isEmpty
        else { return nil }
        let clientID = configuredClientID
        guard !clientID.isEmpty else { return nil }

        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            do {
                try await self.exchangeToken(
                    body: [
                        "grant_type": "refresh_token",
                        "refresh_token": refreshToken,
                        "client_id": clientID
                    ],
                    grant: .refresh
                )
                return self.tokenStore.read(.accessToken)
            } catch {
                return nil
            }
        }
        refreshTask = task
        let token = await task.value
        refreshTask = nil
        return token
    }

    private var configuredClientID: String {
        Defaults[.spotifyLibraryClientID].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private enum Grant {
        case authorizationCode
        case refresh
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

    private struct TokenErrorResponse: Decodable {
        let error: String
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    private func exchangeToken(body: [String: String], grant: Grant) async throws {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, httpResponse) = try await httpClient.data(for: request)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw tokenError(from: data, grant: grant)
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        tokenStore.write(token.accessToken, account: .accessToken)
        if let refreshToken = token.refreshToken, !refreshToken.isEmpty {
            tokenStore.write(refreshToken, account: .refreshToken)
        }
        Defaults[.spotifyLibraryTokenExpiration] = Date().timeIntervalSince1970 + token.expiresIn
        onTokenStateChange?()
    }

    /// Spotify has no token revocation endpoint (see disconnect() in
    /// SpotifyLibraryManager); a refresh token dying server-side surfaces here as
    /// `invalid_grant`. Without clearing the pair the app would keep reporting
    /// itself connected while every like silently no-ops.
    private func tokenError(from data: Data, grant: Grant) -> SpotifyLibraryError {
        guard let decoded = try? JSONDecoder().decode(TokenErrorResponse.self, from: data) else {
            return .tokenExchangeFailed(URLError(.userAuthenticationRequired).localizedDescription)
        }
        if grant == .refresh, decoded.error == "invalid_grant" {
            clearTokens()
            onTokenStateChange?()
            return .refreshTokenRevoked
        }
        return .tokenExchangeFailed(decoded.errorDescription ?? decoded.error)
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(length: Int) -> String? {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        guard SecRandomCopyBytes(kSecRandomDefault, length, &bytes) == errSecSuccess else {
            return nil
        }
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
