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
import Security
import XCTest
@testable import Atoll

/// Exercises the seams the Spotify refactor introduced: the token store,
/// the HTTP client, and the auth session are all injectable, so the OAuth
/// service and the library API can be driven with no network.
@MainActor
final class SpotifyLibraryTests: XCTestCase {

    // MARK: - Fakes

    private final class FakeTokenStore: SpotifyTokenStoring, @unchecked Sendable {
        var storage: [SpotifyTokenAccount: String] = [:]
        /// When non-nil, write() reports this status and stores nothing, so tests
        /// can exercise the failed-Keychain-write path.
        var writeFailure: OSStatus?
        func read(_ account: SpotifyTokenAccount) -> String? { storage[account] }
        @discardableResult
        func write(_ value: String, account: SpotifyTokenAccount) -> OSStatus {
            if let writeFailure { return writeFailure }
            storage[account] = value
            return errSecSuccess
        }
        @discardableResult
        func delete(_ account: SpotifyTokenAccount) -> OSStatus {
            storage[account] = nil
            return errSecSuccess
        }
    }

    private final class FakeHTTPClient: SpotifyHTTPClient, @unchecked Sendable {
        /// Each queued response is consumed in order; the recorder captures the
        /// requests so tests can assert on method and URL.
        var responses: [(Data, HTTPURLResponse)] = []
        var requests: [URLRequest] = []
        private var index = 0

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            requests.append(request)
            guard index < responses.count else {
                throw URLError(.badServerResponse)
            }
            defer { index += 1 }
            return responses[index]
        }
    }

    private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.spotify.com/v1/me/library")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    /// A token provider that always hands back the same bearer, so the API tests
    /// don't have to stand up a full OAuth service.
    private final class StubTokenProvider: SpotifyTokenProviding {
        var token: String? = "stub-access-token"
        var forceRefreshCount = 0
        func validAccessToken(forceRefresh: Bool) async -> String? {
            if forceRefresh { forceRefreshCount += 1 }
            return token
        }
    }

    // MARK: - Rate limiting (item 6)

    func testRequestRetriesAfter429WithinCeiling() async {
        let provider = StubTokenProvider()
        let http = FakeHTTPClient()
        http.responses = [
            (Data("[true]".utf8), response(429, headers: ["Retry-After": "0"])),
            (Data("[true]".utf8), response(200))
        ]
        let api = SpotifyLibraryAPI(tokenProvider: provider, httpClient: http)

        let saved = await api.isTrackSaved(trackID: "abc")

        XCTAssertEqual(saved, true)
        XCTAssertEqual(http.requests.count, 2, "429 should trigger exactly one retry")
    }

    func testRequestGivesUpWhenRetryAfterExceedsCeiling() async {
        let provider = StubTokenProvider()
        let http = FakeHTTPClient()
        http.responses = [
            (Data(), response(429, headers: ["Retry-After": "600"]))
        ]
        let api = SpotifyLibraryAPI(tokenProvider: provider, httpClient: http)

        let saved = await api.isTrackSaved(trackID: "abc")

        XCTAssertNil(saved, "A multi-minute Retry-After must not block the like button")
        XCTAssertEqual(http.requests.count, 1, "No retry should be attempted past the ceiling")
    }

    // MARK: - 401 refresh (unchanged behaviour, now under test)

    func testRequestRefreshesTokenOnce401() async {
        let provider = StubTokenProvider()
        let http = FakeHTTPClient()
        http.responses = [
            (Data(), response(401)),
            (Data("[false]".utf8), response(200))
        ]
        let api = SpotifyLibraryAPI(tokenProvider: provider, httpClient: http)

        let saved = await api.isTrackSaved(trackID: "abc")

        XCTAssertEqual(saved, false)
        XCTAssertEqual(provider.forceRefreshCount, 1, "A 401 should force exactly one refresh")
        XCTAssertEqual(http.requests.count, 2)
    }

    func testSetTrackSavedSendsPutAndDelete() async {
        let provider = StubTokenProvider()
        let http = FakeHTTPClient()
        http.responses = [
            (Data(), response(200)),
            (Data(), response(200))
        ]
        let api = SpotifyLibraryAPI(tokenProvider: provider, httpClient: http)

        _ = await api.setTrackSaved(true, trackID: "abc")
        _ = await api.setTrackSaved(false, trackID: "abc")

        XCTAssertEqual(http.requests[0].httpMethod, "PUT")
        XCTAssertEqual(http.requests[1].httpMethod, "DELETE")
    }

    // MARK: - Token exchange & revocation detection (item 5's real bug)

    func testInvalidGrantOnRefreshClearsTokens() async {
        let store = FakeTokenStore()
        store.storage[.accessToken] = "old-access"
        store.storage[.refreshToken] = "revoked-refresh"
        Defaults[.spotifyLibraryClientID] = "test-client-id"
        Defaults[.spotifyLibraryTokenExpiration] = 0  // force a refresh

        let http = FakeHTTPClient()
        http.responses = [
            (Data(#"{"error":"invalid_grant","error_description":"revoked"}"#.utf8), response(400))
        ]
        let service = SpotifyOAuthService(
            tokenStore: store,
            httpClient: http,
            authSession: NoopAuthSession()
        )

        let token = await service.validAccessToken(forceRefresh: false)

        XCTAssertNil(token)
        XCTAssertNil(store.storage[.refreshToken], "A revoked refresh token must be cleared")
        XCTAssertNil(store.storage[.accessToken])
    }

    func testValidCachedTokenSkipsNetwork() async {
        let store = FakeTokenStore()
        store.storage[.accessToken] = "cached-access"
        store.storage[.refreshToken] = "refresh"
        Defaults[.spotifyLibraryClientID] = "test-client-id"
        Defaults[.spotifyLibraryTokenExpiration] = Date().timeIntervalSince1970 + 3600

        let http = FakeHTTPClient()
        let service = SpotifyOAuthService(
            tokenStore: store,
            httpClient: http,
            authSession: NoopAuthSession()
        )

        let token = await service.validAccessToken(forceRefresh: false)

        XCTAssertEqual(token, "cached-access")
        XCTAssertTrue(http.requests.isEmpty, "A token valid past the leeway must not hit the network")
    }

    private final class NoopAuthSession: SpotifyAuthSessionPresenting {
        func authenticate(url: URL, callbackURLScheme: String) async throws -> URL {
            throw SpotifyLibraryError.canceled
        }
    }

    // MARK: - Legacy migration (item 2: no data loss on a failed Keychain write)

    func testMigrationKeepsDefaultsWhenKeychainWriteFails() {
        Defaults[.spotifyLibraryAccessToken] = "legacy-access"
        Defaults[.spotifyLibraryRefreshToken] = "legacy-refresh"
        let store = FakeTokenStore()
        store.writeFailure = errSecIO  // simulate the Keychain rejecting the write

        _ = SpotifyLibraryManager(
            tokenStore: store,
            httpClient: FakeHTTPClient(),
            authSession: NoopAuthSession()
        )

        XCTAssertEqual(Defaults[.spotifyLibraryAccessToken], "legacy-access",
                       "A failed Keychain write must not drop the only copy of the token")
        XCTAssertEqual(Defaults[.spotifyLibraryRefreshToken], "legacy-refresh")
    }

    func testMigrationClearsDefaultsOnSuccessfulWrite() {
        Defaults[.spotifyLibraryAccessToken] = "legacy-access"
        Defaults[.spotifyLibraryRefreshToken] = "legacy-refresh"
        let store = FakeTokenStore()

        _ = SpotifyLibraryManager(
            tokenStore: store,
            httpClient: FakeHTTPClient(),
            authSession: NoopAuthSession()
        )

        XCTAssertEqual(store.storage[.accessToken], "legacy-access")
        XCTAssertEqual(store.storage[.refreshToken], "legacy-refresh")
        XCTAssertEqual(Defaults[.spotifyLibraryAccessToken], "",
                       "A confirmed write should clear the legacy Defaults copy")
        XCTAssertEqual(Defaults[.spotifyLibraryRefreshToken], "")
    }
}
