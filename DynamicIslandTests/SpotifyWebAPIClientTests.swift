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

import XCTest
@testable import Atoll

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = MockURLProtocol.handler else { fatalError("no handler") }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SpotifyWebAPIClientTests: XCTestCase {
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
    private func http(_ url: URL, _ code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
    }

    func test_currentUserPlaylists_buildsAuthorizedRequest_andDecodes() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            let body = #"{"items":[{"id":"p1","name":"N","uri":"spotify:playlist:p1","images":[],"tracks":{"total":1},"owner":{"display_name":null}}],"next":null,"total":1}"#
            return (self.http(req.url!, 200), body.data(using: .utf8)!)
        }
        let client = SpotifyWebAPIClient(session: makeSession(), tokenProvider: { _ in "TOKEN123" })
        let paging = try await client.currentUserPlaylists(limit: 50, offset: 0)
        XCTAssertEqual(paging.items.first?.id, "p1")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer TOKEN123")
        XCTAssertTrue(captured?.url?.absoluteString.contains("/v1/me/playlists") == true)
        XCTAssertTrue(captured?.url?.absoluteString.contains("limit=50") == true)
    }

    func test_401_refreshesTokenAndRetriesOnce() async throws {
        var calls = 0
        var forceRefreshSeen = false
        MockURLProtocol.handler = { req in
            calls += 1
            if calls == 1 { return (self.http(req.url!, 401), Data()) }
            let body = #"{"items":[],"next":null,"total":0}"#
            return (self.http(req.url!, 200), body.data(using: .utf8)!)
        }
        let client = SpotifyWebAPIClient(session: makeSession(), tokenProvider: { force in
            if force { forceRefreshSeen = true }
            return "TOKEN"
        })
        _ = try await client.currentUserPlaylists(limit: 10, offset: 0)
        XCTAssertEqual(calls, 2, "should retry once after 401")
        XCTAssertTrue(forceRefreshSeen, "should force-refresh the token on 401")
    }

    func test_startPlayback_sendsPutWithContextBody() async throws {
        var captured: URLRequest?
        var capturedBody: Data?
        MockURLProtocol.handler = { req in
            captured = req
            capturedBody = req.httpBody ?? req.httpBodyStream.flatMap { stream in
                stream.open(); defer { stream.close() }
                var data = Data(); var buf = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
                return data
            }
            return (self.http(req.url!, 204), Data())
        }
        let client = SpotifyWebAPIClient(session: makeSession(), tokenProvider: { _ in "T" })
        try await client.startPlayback(contextURI: "spotify:playlist:p1", uris: nil, offsetURI: nil, deviceID: nil)
        XCTAssertEqual(captured?.httpMethod, "PUT")
        XCTAssertTrue(captured?.url?.absoluteString.contains("/v1/me/player/play") == true)
        let json = try XCTUnwrap(capturedBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(json["context_uri"] as? String, "spotify:playlist:p1")
    }

    func test_nonRetriableError_throws() async {
        MockURLProtocol.handler = { req in (self.http(req.url!, 500), Data()) }
        let client = SpotifyWebAPIClient(session: makeSession(), tokenProvider: { _ in "T" })
        do { _ = try await client.availableDevices(); XCTFail("expected throw") }
        catch { /* ok */ }
    }

    func test_savedTracksContains_decodesBoolArray_andEncodesURIs() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            return (self.http(req.url!, 200), "[true,false]".data(using: .utf8)!)
        }
        let client = SpotifyWebAPIClient(session: makeSession(), tokenProvider: { _ in "T" })
        let result = try await client.savedTracksContains(ids: ["spotify:track:abcdefghijklmnopqrstuv", "xyzabcdefghijklmnopqrs"])
        XCTAssertEqual(result, [true, false])
        let url = try XCTUnwrap(captured?.url?.absoluteString)
        // Unified Library endpoint; bare and prefixed inputs both normalize to encoded URIs.
        XCTAssertTrue(url.contains("/v1/me/library/contains?uris="), url)
        XCTAssertTrue(url.contains("uris=spotify%3Atrack%3Aabcdefghijklmnopqrstuv,spotify%3Atrack%3Axyzabcdefghijklmnopqrs"), url)
    }

    func test_saveTracks_sendsPutToLibraryWithURIs() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            return (self.http(req.url!, 200), Data())
        }
        let client = SpotifyWebAPIClient(session: makeSession(), tokenProvider: { _ in "T" })
        try await client.saveTracks(ids: ["spotify:track:abcdefghijklmnopqrstuv"])
        XCTAssertEqual(captured?.httpMethod, "PUT")
        let url = try XCTUnwrap(captured?.url?.absoluteString)
        XCTAssertTrue(url.contains("/v1/me/library?uris="), url)
        XCTAssertTrue(url.contains("uris=spotify%3Atrack%3Aabcdefghijklmnopqrstuv"), url)
    }

    func test_removeSavedTracks_sendsDeleteToLibraryWithURIs() async throws {
        var captured: URLRequest?
        MockURLProtocol.handler = { req in
            captured = req
            return (self.http(req.url!, 200), Data())
        }
        let client = SpotifyWebAPIClient(session: makeSession(), tokenProvider: { _ in "T" })
        try await client.removeSavedTracks(ids: ["abcdefghijklmnopqrstuv"])
        XCTAssertEqual(captured?.httpMethod, "DELETE")
        let url = try XCTUnwrap(captured?.url?.absoluteString)
        XCTAssertTrue(url.contains("/v1/me/library?uris="), url)
        XCTAssertTrue(url.contains("uris=spotify%3Atrack%3Aabcdefghijklmnopqrstuv"), url)
    }

    func test_transferPlayback_sendsPutWithDeviceIdsAndPlay() async throws {
        var captured: URLRequest?
        var capturedBody: Data?
        MockURLProtocol.handler = { req in
            captured = req
            capturedBody = req.httpBody ?? req.httpBodyStream.flatMap { stream in
                stream.open(); defer { stream.close() }
                var data = Data(); var buf = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
                return data
            }
            return (self.http(req.url!, 204), Data())
        }
        let client = SpotifyWebAPIClient(session: makeSession(), tokenProvider: { _ in "T" })
        try await client.transferPlayback(deviceIDs: ["atoll-dev"], play: true)
        XCTAssertEqual(captured?.httpMethod, "PUT")
        XCTAssertTrue(captured?.url?.absoluteString.contains("/v1/me/player") == true)
        let json = try XCTUnwrap(capturedBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        XCTAssertEqual(json["device_ids"] as? [String], ["atoll-dev"])
        XCTAssertEqual(json["play"] as? Bool, true)
    }

    func test_playlistTracks_skipsUndecodableItems() async throws {
        MockURLProtocol.handler = { req in
            // item0 is a valid track; item1's track lacks `artists` (podcast-episode shape)
            // and must be dropped, not fail the whole page.
            let body = #"{"items":[{"track":{"id":"t1","name":"Song","uri":"spotify:track:t1","artists":[{"name":"A"}]}},{"track":{"id":"e1","name":"Episode","uri":"spotify:episode:e1"}}],"next":null,"total":2}"#
            return (self.http(req.url!, 200), body.data(using: .utf8)!)
        }
        let client = SpotifyWebAPIClient(session: makeSession(), tokenProvider: { _ in "T" })
        let page = try await client.playlistTracks(playlistID: "p1", limit: 50, offset: 0)
        XCTAssertEqual(page.items.map(\.name), ["Song"])
    }
}
