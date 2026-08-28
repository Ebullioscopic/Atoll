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

/// Nobody on the project has Cider installed, so what these pin down is the
/// wire format: the paths, the header, the request body, and how each kind of
/// refusal is read. The JSON shapes are the ones Cider's RPC documentation
/// gives for `/api/v1/playback`.
final class CiderFavoritingTests: XCTestCase {
    private actor Recorder {
        private(set) var requests: [URLRequest] = []
        func record(_ request: URLRequest) { requests.append(request) }
    }

    private struct StubClient: CiderHTTPClient {
        let status: Int
        let body: Data
        let recorder: Recorder

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            await recorder.record(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (body, response)
        }
    }

    private struct FailingClient: CiderHTTPClient {
        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            throw URLError(.cannotConnectToHost)
        }
    }

    private func make(
        status: Int = 200,
        json: String = #"{"status":"ok","info":{"inFavorites":false,"inLibrary":false}}"#,
        token: String = "tok-123"
    ) -> (CiderFavoriting, Recorder) {
        let recorder = Recorder()
        let subject = CiderFavoriting(
            httpClient: StubClient(status: status, body: Data(json.utf8), recorder: recorder),
            baseURL: URL(string: "http://127.0.0.1:10767/api/v1/playback")!,
            tokenProvider: { token }
        )
        return (subject, recorder)
    }

    // MARK: - Reading

    func testReadsInFavoritesFromTheInfoObject() async {
        let (subject, _) = make(json: #"{"status":"ok","info":{"inFavorites":true,"inLibrary":true}}"#)

        let favorited = await subject.isCurrentTrackFavorited()

        XCTAssertEqual(favorited, true)
    }

    func testAFalseFavouriteIsNotConfusedWithAnUnknownOne() async {
        let (subject, _) = make(json: #"{"status":"ok","info":{"inFavorites":false}}"#)

        let favorited = await subject.isCurrentTrackFavorited()

        XCTAssertEqual(favorited, false)
    }

    /// Nothing playing: Cider answers, but the field is absent.
    func testAMissingFieldReadsAsUnknown() async {
        let (subject, _) = make(json: #"{"status":"ok","info":{}}"#)

        let favorited = await subject.isCurrentTrackFavorited()

        XCTAssertNil(favorited)
    }

    /// A rejected token must not read as "not favourited", or the heart would
    /// show a confident wrong answer.
    func testARejectedTokenReadsAsUnknown() async {
        let (subject, _) = make(status: 401, json: #"{"error":"unauthorized"}"#)

        let favorited = await subject.isCurrentTrackFavorited()

        XCTAssertNil(favorited)
    }

    /// Cider closed, or its API switched off.
    func testAConnectionFailureReadsAsUnknown() async {
        let subject = CiderFavoriting(
            httpClient: FailingClient(),
            baseURL: URL(string: "http://127.0.0.1:10767/api/v1/playback")!,
            tokenProvider: { "tok-123" }
        )

        let favorited = await subject.isCurrentTrackFavorited()

        XCTAssertNil(favorited)
    }

    // MARK: - Writing

    func testFavouritingSendsRatingOne() async throws {
        let (subject, recorder) = make()

        let ok = await subject.setCurrentTrackFavorited(true)

        XCTAssertTrue(ok)
        let requests = await recorder.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/playback/set-rating")
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Int]
        XCTAssertEqual(body, ["rating": 1])
    }

    /// Un-favouriting clears the rating rather than sending a dislike, which is
    /// a different opinion and would follow the user around Apple Music.
    func testUnfavouritingClearsRatherThanDislikes() async throws {
        let (subject, recorder) = make()

        await subject.setCurrentTrackFavorited(false)

        let requests = await recorder.requests
        let request = try XCTUnwrap(requests.last)
        let body = try JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Int]
        XCTAssertEqual(body, ["rating": 0])
    }

    func testAFailedWriteIsReportedAsFailure() async {
        let (subject, _) = make(status: 500, json: "{}")

        let ok = await subject.setCurrentTrackFavorited(true)

        XCTAssertFalse(ok)
    }

    // MARK: - Transport

    /// Cider's docs name this header `apitoken`; the server only accepts
    /// `apptoken`, so this is the one detail most likely to regress.
    func testTheTokenGoesInAnApptokenHeaderWithNoPrefix() async throws {
        let (subject, recorder) = make(token: "  tok-123  ")

        _ = await subject.isCurrentTrackFavorited()

        let requests = await recorder.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.value(forHTTPHeaderField: "apptoken"), "tok-123")
        XCTAssertNil(request.value(forHTTPHeaderField: "apitoken"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    /// Cider can run its API with authentication off, and then no header is
    /// wanted at all.
    func testNoHeaderIsSentWhenNoTokenIsConfigured() async throws {
        let (subject, recorder) = make(token: "   ")

        _ = await subject.isCurrentTrackFavorited()

        let requests = await recorder.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertNil(request.value(forHTTPHeaderField: "apptoken"))
    }

    func testReadUsesTheDocumentedPath() async throws {
        let (subject, recorder) = make()

        _ = await subject.isCurrentTrackFavorited()

        let requests = await recorder.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/v1/playback/now-playing")
    }

    func testTheDefaultBaseURLIsCidersDocumentedLoopbackPort() {
        XCTAssertEqual(
            CiderFavoriting.defaultBaseURL.absoluteString,
            "http://127.0.0.1:10767/api/v1/playback"
        )
    }
}
