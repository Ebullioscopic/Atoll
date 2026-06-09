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

private final class CallCounter {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

private final class OAuthMockProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
    override class func canInit(with r: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }
    override func startLoading() {
        let (resp, data) = OAuthMockProtocol.handler!(request)
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class SpotifyOAuthManagerTests: XCTestCase {
    private func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [OAuthMockProtocol.self]; return URLSession(configuration: c)
    }
    private func http(_ url: URL, _ code: Int) -> HTTPURLResponse { HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)! }
    private func store() -> UserDefaults { UserDefaults(suiteName: "oauth-\(UUID().uuidString)")! }

    func test_authorizeURL_hasPKCEandScopes() {
        let d = store(); d.set("CID", forKey: "spotifyOAuthClientID")
        let mgr = SpotifyOAuthManager(defaults: d, session: session())
        let (url, verifier) = mgr.makeAuthorizeURL()
        let s = url!.absoluteString
        XCTAssertTrue(s.hasPrefix("https://accounts.spotify.com/authorize"))
        XCTAssertTrue(s.contains("client_id=CID"))
        XCTAssertTrue(s.contains("response_type=code"))
        XCTAssertTrue(s.contains("code_challenge_method=S256"))
        XCTAssertTrue(s.contains("code_challenge="))
        XCTAssertTrue(s.contains("user-modify-playback-state"))
        XCTAssertFalse(verifier.isEmpty)
    }

    func test_exchangeCode_storesTokens_andIsAuthenticated() async {
        let d = store(); d.set("CID", forKey: "spotifyOAuthClientID")
        OAuthMockProtocol.handler = { req in
            let body = #"{"access_token":"AT","token_type":"Bearer","expires_in":3600,"refresh_token":"RT","scope":"x"}"#
            return (self.http(req.url!, 200), body.data(using: .utf8)!)
        }
        let mgr = SpotifyOAuthManager(defaults: d, session: session())
        await mgr.exchangeCode("CODE", verifier: "VER")
        XCTAssertTrue(mgr.isAuthenticated)
        let tok = await mgr.validAccessToken()
        XCTAssertEqual(tok, "AT")
    }

    func test_validAccessToken_refreshesWhenExpired() async {
        let d = store()
        d.set("CID", forKey: "spotifyOAuthClientID")
        d.set("OLD", forKey: "spotifyOAuthAccessToken")
        d.set("RT", forKey: "spotifyOAuthRefreshToken")
        d.set(Date().timeIntervalSince1970 - 10, forKey: "spotifyOAuthExpiration")
        OAuthMockProtocol.handler = { req in
            let body = #"{"access_token":"NEW","token_type":"Bearer","expires_in":3600}"#
            return (self.http(req.url!, 200), body.data(using: .utf8)!)
        }
        let mgr = SpotifyOAuthManager(defaults: d, session: session())
        let tok = await mgr.validAccessToken()
        XCTAssertEqual(tok, "NEW")
    }

    func test_validAccessToken_nilWhenNoTokenAndNoRefresh() async {
        let mgr = SpotifyOAuthManager(defaults: store(), session: session())
        let tok = await mgr.validAccessToken()
        XCTAssertNil(tok)
    }

    func test_concurrentRefresh_coalescesToOneNetworkCall() async {
        let d = store()
        d.set("CID", forKey: "spotifyOAuthClientID")
        d.set("OLD", forKey: "spotifyOAuthAccessToken")
        d.set("RT", forKey: "spotifyOAuthRefreshToken")
        d.set(Date().timeIntervalSince1970 - 10, forKey: "spotifyOAuthExpiration")
        let counter = CallCounter()
        OAuthMockProtocol.handler = { req in
            counter.bump()
            let body = #"{"access_token":"NEW","token_type":"Bearer","expires_in":3600,"refresh_token":"RT2"}"#
            return (self.http(req.url!, 200), body.data(using: .utf8)!)
        }
        let mgr = SpotifyOAuthManager(defaults: d, session: session())
        async let a = mgr.validAccessToken()
        async let b = mgr.validAccessToken()
        let (ta, tb) = await (a, b)
        XCTAssertEqual(ta, "NEW")
        XCTAssertEqual(tb, "NEW")
        XCTAssertEqual(counter.count, 1, "two concurrent refreshes must coalesce to a single token request")
    }
}
