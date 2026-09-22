import XCTest
@testable import ToolIsleCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
actor MockTransport: GiteeTransport {
    enum Reply: Sendable { case data(String, Int, [String: String]); case offline }
    var replies: [Reply]
    var requests: [URLRequest] = []
    init(_ replies: [Reply]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        switch replies.removeFirst() {
        case .offline: throw URLError(.notConnectedToInternet)
        case let .data(body, status, headers): return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
        }
    }
}
final class CoreTests: XCTestCase {
    let repositoryJSON = #"{"id":12,"full_name":"team/project","name":"project","default_branch":"feature/docs","private":true}"#
    func repository() throws -> GiteeRepository {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GiteeRepository.self, from: Data(repositoryJSON.utf8))
    }
    func testTokenOnlyInAuthorizationHeader() async throws {
        let transport = MockTransport([.data(#"{"id":1,"login":"fixture"}"#, 200, [:])])
        let client = GiteeClient(token: "test-token-not-a-credential", transport: transport)
        let user = try await client.user(); XCTAssertEqual(user.id, 1)
        let requests = await transport.requests
        XCTAssertEqual(requests[0].httpMethod, "GET")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer test-token-not-a-credential")
        XCTAssertFalse(requests[0].url!.absoluteString.contains("test-token"))
        XCTAssertEqual(requests[0].url?.host, "gitee.com")
    }
    func testWatchPagination() async throws {
        let transport = MockTransport([.data("[" + repositoryJSON + "]", 200, [:])])
        let result = try await GiteeClient(token: "fixture", transport: transport).repositories(.subscriptions, page: 2)
        XCTAssertEqual(result.value[0].fullName, "team/project")
        let request = await transport.requests[0]
        XCTAssertEqual(request.url?.path, "/api/v5/user/subscriptions")
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertTrue(query.contains(URLQueryItem(name: "page", value: "2")))
        XCTAssertTrue(query.contains(URLQueryItem(name: "per_page", value: "100")))
    }
    func testStringIssueIdentifiersAndStatus() async throws {
        let transport = MockTransport([.data(#"[{"id":2,"number":"IABC12","title":"测试","state":"progressing"}]"#, 200, [:])])
        let issues = try await GiteeClient(token: "fixture", transport: transport).issues(repository()).value
        XCTAssertEqual(issues[0].number, "IABC12"); XCTAssertEqual(issues[0].state, "progressing")
    }
    func testOfflineCacheIsLabelled() async throws {
        let transport = MockTransport([.data("[]", 200, [:]), .offline])
        let client = GiteeClient(token: "fixture", transport: transport)
        let live = try await client.repositories(.starred, page: 1)
        let offline = try await client.repositories(.starred, page: 1)
        XCTAssertFalse(live.isOffline); XCTAssertTrue(offline.isOffline)
    }
    func testUnauthorizedNeverReturnsCache() async throws {
        let transport = MockTransport([.data("[]", 200, [:]), .data("do not expose server details", 401, [:]), .offline])
        let client = GiteeClient(token: "fixture", transport: transport)
        _ = try await client.repositories(.starred, page: 1)
        do { _ = try await client.repositories(.starred, page: 1); XCTFail("401 must throw") }
        catch { XCTAssertEqual(error as? GiteeError, .unauthorized) }
        do { _ = try await client.repositories(.starred, page: 1); XCTFail("cache must be cleared") }
        catch { XCTAssertTrue(error is URLError) }
    }
    func testForbiddenAndNotFoundNeverReturnCache() async throws {
        for status in [403, 404] {
            let client = GiteeClient(token: "fixture", transport: MockTransport([.data("[]", 200, [:]), .data("secret server detail", status, [:])]))
            _ = try await client.repositories(.starred, page: 1)
            do { _ = try await client.repositories(.starred, page: 1); XCTFail("HTTP error must not use stale permissions") }
            catch { XCTAssertFalse(error.localizedDescription.contains("secret server detail")) }
        }
    }
    func testRateLimitStopsRequests() async throws {
        let transport = MockTransport([.data("{}", 429, ["Retry-After": "60"])])
        let client = GiteeClient(token: "fixture", transport: transport)
        for _ in 0..<2 {
            do { _ = try await client.user(); XCTFail("rate limited") }
            catch { guard case GiteeError.rateLimited = error else { XCTFail("wrong error"); return } }
        }
        let count = await transport.requests.count; XCTAssertEqual(count, 1)
    }
    func testInvalidatedClientNeverSendsAnotherRequest() async throws {
        let transport = MockTransport([.data("[]", 200, [:])])
        let client = GiteeClient(token: "fixture", transport: transport)
        _ = try await client.repositories(.starred, page: 1)
        try await client.invalidate()
        do { _ = try await client.repositories(.starred, page: 1); XCTFail("signed-out clients must not send requests") }
        catch { XCTAssertEqual(error as? GiteeError, .unauthorized) }
        let count = await transport.requests.count; XCTAssertEqual(count, 1)
    }
    func testMalformedJSON() async throws {
        let client = GiteeClient(token: "fixture", transport: MockTransport([.data("<html>error</html>", 200, [:])]))
        do { _ = try await client.user(); XCTFail("must fail") } catch { XCTAssertEqual(error as? GiteeError, .invalidResponse) }
    }
    func testPathsAndRefEncoding() throws {
        XCTAssertThrowsError(try GiteePath.segments("../secret"))
        XCTAssertThrowsError(try GiteePath.segments("/etc/passwd"))
        XCTAssertThrowsError(try GiteePath.segments("a/./b"))
        let url = try GiteePath.url(["repos", "team", "project", "contents", "中文 #.md"], query: [.init(name: "ref", value: "feature/docs")])
        XCTAssertEqual(url.host, "gitee.com")
        XCTAssertTrue(url.absoluteString.contains("%23"))
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "feature/docs")
        XCTAssertNil(GiteePath.safeBrowserURL("https://gitee.com.evil.example"))
        XCTAssertNil(GiteePath.safeBrowserURL("javascript:alert(1)"))
        XCTAssertNotNil(GiteePath.safeBrowserURL("https://gitee.com/team/project"))
    }
    func testFileDecoding() throws {
        let body = #"{"type":"file","name":"a.md","path":"docs/a.md","encoding":"base64","content":"IyBUb29sSXNsZQ=="}"#
        let file = try JSONDecoder().decode(GiteeFile.self, from: Data(body.utf8))
        XCTAssertEqual(try file.text(), "# ToolIsle")
    }
    func testAccountScopedDiskCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = GiteeClient(token: "fixture", transport: MockTransport([.data("[]", 200, [:])]))
        try await first.configureDiskCache(directory: directory, accountID: 1)
        _ = try await first.repositories(.starred, page: 1)
        let second = GiteeClient(token: "fixture", transport: MockTransport([.offline]))
        try await second.configureDiskCache(directory: directory, accountID: 2)
        do { _ = try await second.repositories(.starred, page: 1); XCTFail("accounts must not share cache") } catch { XCTAssertTrue(error is URLError) }
        let same = GiteeClient(token: "fixture", transport: MockTransport([.offline]))
        try await same.configureDiskCache(directory: directory, accountID: 1)
        let result = try await same.repositories(.starred, page: 1); XCTAssertTrue(result.isOffline)
        try await first.clearCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("gitee-1.json").path))
    }
    func testJSONBase64AndDates() throws {
        XCTAssertEqual(try TextTools.json("{\"b\":2,\"a\":1}", pretty: false), "{\"a\":1,\"b\":2}")
        XCTAssertThrowsError(try TextTools.json("{bad", pretty: true))
        XCTAssertEqual(try TextTools.base64(try TextTools.base64("工具岛 🌊", decode: false), decode: true), "工具岛 🌊")
        XCTAssertThrowsError(try TextTools.base64("%%%", decode: true))
        XCTAssertEqual(try TextTools.timestamp("0", milliseconds: false), "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(try TextTools.timestamp("1000", milliseconds: true), "1970-01-01T00:00:01.000Z")
        XCTAssertTrue(try TextTools.date("1970-01-01T08:00:00+08:00").contains("秒：0"))
        XCTAssertThrowsError(try TextTools.timestamp("nan", milliseconds: false))
        XCTAssertThrowsError(try TextTools.timestamp("1e99", milliseconds: false))
    }
}
