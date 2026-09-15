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
import Defaults
import Foundation

/// Cider, a third-party Apple Music client.
///
/// Playback is followed through macOS Now Playing like the other filtered
/// sources. Favouriting is not available there -- Now Playing carries no such
/// command -- so it goes over the local HTTP API Cider exposes for external
/// applications, which reports `inFavorites` and accepts a rating back.
final class CiderController: FilteredNowPlayingController {
    static let bundleIdentifier = "sh.cider.genten.mac"

    init?() {
        super.init(
            bundleIdentifier: Self.bundleIdentifier,
            controllerName: "CiderController"
        )
    }

    /// True whether or not Cider is up, so the control keeps its place in the
    /// palette while the app is closed. See ``MediaControllerProtocol``.
    @MainActor
    override var canEverFavorite: Bool { true }

    @MainActor
    override var supportsFavoriting: Bool { CiderFavoriting.isAvailable }

    /// Cider accepts a rating back, so unlike TIDAL the heart is live rather
    /// than a read-only indicator.
    @MainActor
    override var favoritingIsReadOnly: Bool { false }

    override func isCurrentTrackFavorited() async -> Bool? {
        await CiderFavoriting.shared.isCurrentTrackFavorited()
    }

    @discardableResult
    override func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool {
        await CiderFavoriting.shared.setCurrentTrackFavorited(favorited)
    }
}

// MARK: - Favouriting over Cider's local API

protocol CiderHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionCiderHTTPClient: CiderHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// Talks to the HTTP API Cider exposes on the loopback interface.
///
/// The API is opt-in on Cider's side: the user turns it on and either generates
/// a token or disables authentication, under Settings > Connectivity > Manage
/// External Application Access. When a token is set it goes in an `apptoken`
/// header -- bare, with no `Bearer` prefix. Cider's own documentation calls that
/// header `apitoken`, which the server does not accept; `apptoken` is what it
/// actually reads.
struct CiderFavoriting: Sendable {
    static let shared = CiderFavoriting()

    /// Cider's default port for external application access.
    static let defaultPort = 10767

    static var defaultBaseURL: URL {
        // `localhost` rather than a literal 127.0.0.1: it resolves to
        // whichever loopback the machine actually has, and URLSession tries
        // both families, so this still reaches Cider on a host with IPv4
        // switched off.
        URL(string: "http://localhost:\(defaultPort)/api/v1/playback")!
    }

    private let httpClient: CiderHTTPClient
    private let baseURL: URL
    private let tokenProvider: @Sendable () -> String

    /// The arguments exist so the tests can drive this without Cider; nothing
    /// in the app passes anything but the defaults.
    init(
        httpClient: CiderHTTPClient = URLSessionCiderHTTPClient(),
        baseURL: URL = CiderFavoriting.defaultBaseURL,
        tokenProvider: @escaping @Sendable () -> String = { CiderTokenStore.shared.token }
    ) {
        self.httpClient = httpClient
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    /// Whether favouriting can be attempted at all.
    ///
    /// Only that Cider is running. Whether its API is switched on, and whether
    /// the token matches, is not knowable without asking -- so a wrong or
    /// missing token surfaces as a request that fails, rather than as a control
    /// that quietly disappears.
    @MainActor
    static var isAvailable: Bool {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: CiderController.bundleIdentifier)
            .isEmpty == false
    }

    /// nil when the answer is not knowable: Cider closed, API off, bad token, or
    /// nothing playing. The heart reads that as unknown rather than as "not
    /// favourited".
    func isCurrentTrackFavorited() async -> Bool? {
        await nowPlaying()?.info.inFavorites
    }

    @discardableResult
    func setCurrentTrackFavorited(_ favorited: Bool) async -> Bool {
        // -1 dislikes, 0 clears, 1 favourites. Un-favouriting clears rather than
        // dislikes: a dislike is a separate opinion, and it would follow the
        // user around Apple Music's recommendations.
        await setRating(favorited ? 1 : 0)
    }

    // MARK: - Requests

    struct NowPlayingResponse: Decodable {
        struct Info: Decodable {
            let inFavorites: Bool?
            let inLibrary: Bool?
        }
        let info: Info
    }

    func nowPlaying() async -> NowPlayingResponse? {
        guard let data = await send(request(path: "now-playing", method: "GET")) else {
            return nil
        }
        return try? JSONDecoder().decode(NowPlayingResponse.self, from: data)
    }

    @discardableResult
    func setRating(_ rating: Int) async -> Bool {
        var request = request(path: "set-rating", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["rating": rating])
        return await send(request) != nil
    }

    func request(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        // A short timeout: this is a loopback call to an app on the same Mac,
        // and the heart should not sit spinning if the API is switched off.
        request.timeoutInterval = 3

        let token = tokenProvider().trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "apptoken")
        }
        return request
    }

    /// Returns the body on a 2xx and nil on anything else. Cider being closed,
    /// its API being off, and a rejected token are all the same answer here: we
    /// do not know, and nothing on screen should change.
    private func send(_ request: URLRequest) async -> Data? {
        do {
            let (data, response) = try await httpClient.data(for: request)
            guard (200..<300).contains(response.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
