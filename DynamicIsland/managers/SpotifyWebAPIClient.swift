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

enum SpotifyAPIError: Error, Equatable {
    case notAuthenticated
    case http(Int)
    case decoding
}

/// A playlist/saved-tracks item wrapping a `track`. Decodes leniently: a present-but-
/// undecodable track (e.g. a podcast episode or local file missing `artists`) becomes
/// nil and is dropped, rather than failing the whole page.
struct SpotifyTrackItem: Codable, Equatable {
    let track: SpotifyTrack?
    private enum CodingKeys: String, CodingKey { case track }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        track = (try? c.decodeIfPresent(SpotifyTrack.self, forKey: .track)) ?? nil
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(track, forKey: .track)
    }
}

final class SpotifyWebAPIClient: SpotifyAPI {
    private let session: URLSession
    private let tokenProvider: (_ forceRefresh: Bool) async -> String?
    private let base = "https://api.spotify.com/v1"

    init(session: URLSession = .shared,
         tokenProvider: @escaping (_ forceRefresh: Bool) async -> String? = { await SpotifyOAuthManager.shared.validAccessToken(forceRefresh: $0) }) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: GET helpers

    func currentUserPlaylists(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyPlaylist> {
        try await getJSON("/me/playlists?limit=\(limit)&offset=\(offset)")
    }
    func playlistTracks(playlistID: String, limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack> {
        let paging: SpotifyPaging<SpotifyTrackItem> = try await getJSON("/playlists/\(playlistID)/tracks?limit=\(limit)&offset=\(offset)")
        return SpotifyPaging(items: paging.items.compactMap { $0.track }, next: paging.next, total: paging.total)
    }
    func savedTracks(limit: Int, offset: Int) async throws -> SpotifyPaging<SpotifyTrack> {
        let paging: SpotifyPaging<SpotifyTrackItem> = try await getJSON("/me/tracks?limit=\(limit)&offset=\(offset)")
        return SpotifyPaging(items: paging.items.compactMap { $0.track }, next: paging.next, total: paging.total)
    }
    func recentlyPlayed(limit: Int) async throws -> [SpotifyPlayHistoryItem] {
        let paging: SpotifyPaging<SpotifyPlayHistoryItem> = try await getJSON("/me/player/recently-played?limit=\(limit)")
        return paging.items
    }
    func search(query: String, types: [SpotifySearchType], limit: Int) async throws -> SpotifySearchResponse {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        let q = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
        let t = types.map(\.rawValue).joined(separator: ",")
        return try await getJSON("/search?q=\(q)&type=\(t)&limit=\(limit)")
    }
    func availableDevices() async throws -> [SpotifyDevice] {
        struct DevicesResponse: Codable, Equatable { let devices: [SpotifyDevice] }
        let r: DevicesResponse = try await getJSON("/me/player/devices")
        return r.devices
    }

    // MARK: PUT playback

    func startPlayback(contextURI: String?, uris: [String]?, offsetURI: String?, deviceID: String?) async throws {
        var body: [String: Any] = [:]
        if let contextURI { body["context_uri"] = contextURI }
        if let uris { body["uris"] = uris }
        if let offsetURI { body["offset"] = ["uri": offsetURI] }
        try await put("/me/player/play", query: deviceID.map { "device_id=\($0)" }, body: body)
    }
    func setShuffle(_ on: Bool, deviceID: String?) async throws {
        var q = "state=\(on)"
        if let deviceID { q += "&device_id=\(deviceID)" }
        try await put("/me/player/shuffle", query: q, body: nil)
    }

    // MARK: Core request with 401 retry

    private func getJSON<T: Decodable>(_ path: String) async throws -> T {
        let data = try await perform(path: path, method: "GET", body: nil, query: nil)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch {
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? "<non-utf8>"
            NSLog("[SpotifyAPI] DECODE FAIL %@ -> %@ | body: %@", path, String(describing: error), snippet)
            throw SpotifyAPIError.decoding
        }
    }
    private func put(_ path: String, query: String?, body: [String: Any]?) async throws {
        let data = body.map { try? JSONSerialization.data(withJSONObject: $0) } ?? nil
        _ = try await perform(path: path, method: "PUT", body: data ?? Data(), query: query)
    }

    private func perform(path: String, method: String, body: Data?, query: String?) async throws -> Data {
        func send(forceRefresh: Bool) async throws -> (Data, HTTPURLResponse) {
            guard let token = await tokenProvider(forceRefresh) else {
                NSLog("[SpotifyAPI] NO TOKEN for %@ (forceRefresh: %@)", path, forceRefresh ? "true" : "false")
                throw SpotifyAPIError.notAuthenticated
            }
            var urlString = base + path
            if let query { urlString += (path.contains("?") ? "&" : "?") + query }
            guard let url = URL(string: urlString) else { throw SpotifyAPIError.http(-1) }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body, !body.isEmpty {
                req.httpBody = body
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw SpotifyAPIError.http(-1) }
            return (data, http)
        }
        var (data, http) = try await send(forceRefresh: false)
        if http.statusCode == 401 {
            (data, http) = try await send(forceRefresh: true)
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? "<non-utf8>"
            NSLog("[SpotifyAPI] HTTP %d %@ | body: %@", http.statusCode, path, snippet)
            throw SpotifyAPIError.http(http.statusCode)
        }
        return data
    }
}
