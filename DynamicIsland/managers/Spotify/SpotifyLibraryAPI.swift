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

import Foundation

/// Saved-tracks calls against the Spotify Web API.
///
/// Uses the /me/library endpoints introduced February 2026; the legacy
/// /me/tracks save/contains endpoints silently return 403 for new apps.
@MainActor
final class SpotifyLibraryAPI {
    private static let baseURL = "https://api.spotify.com/v1"

    /// Spotify's Retry-After is usually a few seconds but can be minutes during
    /// a hard rate limit. A like button must never hang that long: past this
    /// ceiling the request fails and the next user action retries.
    private static let maxRetryAfter: TimeInterval = 5
    private static let defaultRetryAfter: TimeInterval = 1

    private let tokenProvider: SpotifyTokenProviding
    private let httpClient: SpotifyHTTPClient

    init(tokenProvider: SpotifyTokenProviding, httpClient: SpotifyHTTPClient) {
        self.tokenProvider = tokenProvider
        self.httpClient = httpClient
    }

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

    /// 401 and 429 carry separate retry budgets so a 401 -> 429 -> 401 sequence
    /// cannot loop.
    private func request(
        method: String,
        path: String,
        allowUnauthorizedRetry: Bool = true,
        allowRateLimitRetry: Bool = true
    ) async -> Data? {
        guard let accessToken = await tokenProvider.validAccessToken(forceRefresh: false),
              let url = URL(string: "\(Self.baseURL)\(path)")
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, httpResponse) = try await httpClient.data(for: request)

            if httpResponse.statusCode == 401, allowUnauthorizedRetry {
                _ = await tokenProvider.validAccessToken(forceRefresh: true)
                return await self.request(
                    method: method,
                    path: path,
                    allowUnauthorizedRetry: false,
                    allowRateLimitRetry: allowRateLimitRetry
                )
            }

            if httpResponse.statusCode == 429, allowRateLimitRetry {
                guard let delay = Self.retryDelay(from: httpResponse) else { return nil }
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    // Cancelled: the user already skipped past this track.
                    return nil
                }
                return await self.request(
                    method: method,
                    path: path,
                    allowUnauthorizedRetry: allowUnauthorizedRetry,
                    allowRateLimitRetry: false
                )
            }

            guard (200..<300).contains(httpResponse.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// nil = do not retry. Spotify sends Retry-After as integer seconds; the
    /// RFC 9110 HTTP-date form falls back to the default rather than failing.
    private static func retryDelay(from response: HTTPURLResponse) -> TimeInterval? {
        let header = response.value(forHTTPHeaderField: "Retry-After")
        let delay = header.flatMap(Int.init).map(TimeInterval.init) ?? defaultRetryAfter
        guard delay <= maxRetryAfter else { return nil }
        return max(0, delay)
    }
}
