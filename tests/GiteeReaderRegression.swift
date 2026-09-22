import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GIFixtureProtocol: URLProtocol {
    static var status = 200
    static var payload = Data()
    static var lastRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct GiteeReaderRegression {
    static var count = 0
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        count += 1
        if !value() { fatalError("Gitee regression: \(message)") }
    }
    static func main() async throws {
        let a = GIIssueRoute(repository: "team/alpha", number: "IAbC12")
        let b = GIIssueRoute(repository: "other/beta", number: "IBBB9")
        expect(GIIssueLinks.resolve(b.url.absoluteString, relativeTo: a.url) == .issue(b, fragment:nil), "cross repository route")
        expect(GIIssueLinks.resolve("/other/beta/issues/IBBB9#note_42", relativeTo:a.url) == .issue(b, fragment:"note_42"), "root relative comment")
        expect(GIIssueLinks.resolve("#note_42", relativeTo:a.url) == .issue(a, fragment:"note_42"), "same issue fragment")
        expect(GIIssueLinks.resolve("IAbC13", relativeTo:a.url) == .issue(GIIssueRoute(repository:"team/alpha",number:"IAbC13"), fragment:nil), "relative issue number")
        expect(GIIssueLinks.resolve("https://gitee.com/team/alpha/issues/IAbC12/?utm_source=x", relativeTo:a.url) == .issue(a, fragment:nil), "trailing slash and non-sensitive query")
        expect(GIIssueLinks.resolve("http://gitee.com/team/alpha/issues/IAbC12", relativeTo:a.url) == .issue(a, fragment:nil), "legacy http canonicalizes to native https API")
        expect(GIIssueLinks.resolve("//gitee.com/other/beta/issues/IBBB9", relativeTo:a.url) == .issue(b, fragment:nil), "protocol relative")
        for raw in ["javascript:alert(1)","data:text/html,x","file:///etc/passwd","gitee://a", "", "https://x:g@gitee.com/team/alpha/issues/IAbC12", "https://gitee.com/team/alpha/issues/IAbC12?access_token=secret", "https://gitee.com/team/alpha/issues/IAbC12?TOKEN=secret", "https://gitee.com\\@evil.test/team/alpha/issues/IAbC12", "https://gitee.com/team/alpha/issues/IAbC12\n"] {
            if raw.hasSuffix("\n") { continue } // Surrounding whitespace is deliberately trimmed.
            expect(GIIssueLinks.resolve(raw, relativeTo:a.url) == .blocked, "unsafe URL is blocked")
        }
        for raw in ["https://gitee.com.evil.test/team/alpha/issues/IAbC12", "https://evil.test/gitee.com/team/alpha/issues/IAbC12", "https://gitee.com/team/alpha/pulls/12", "https://gitee.com/team/alpha/blob/main/README.md", "https://gitee.com/team%2Fbad/alpha/issues/IAbC12", "https://gitee.com:8443/team/alpha/issues/IAbC12"] {
            if case .external = GIIssueLinks.resolve(raw, relativeTo:a.url) {} else { fatalError("Must remain external: \(raw)") }
            count += 1
        }
        expect(GIIssueLinks.commentID("note_42") == 42, "Gitee comment anchor")
        expect(GIIssueLinks.commentID("issuecomment-42") == 42, "alternate comment anchor")
        expect(GIIssueLinks.commentID("user-content-heading") == nil, "heading is not issue or comment number")
        expect(GIIssueLinks.resolve("#heading", relativeTo:a.url) == .issue(a, fragment:"heading"), "heading retained")
        var history = GIHistory()
        expect(history.current == nil && !history.canBack, "empty history")
        history.push(a); let aid = history.current!.id
        history.snapshot(id:aid,y:640,anchorHandled:true)
        history.push(b,fragment:"note_42")
        expect(history.canBack && history.current!.fragment == "note_42", "push navigation")
        history.move(-1)
        expect(history.current!.route == a && history.current!.scrollY == 640, "back restores scroll")
        expect(history.canForward, "forward available")
        history.move(1); expect(history.current!.route == b, "forward restores linked issue")
        history.move(-1); history.push(GIIssueRoute(repository:"team/alpha",number:"INEW"))
        expect(!history.canForward && history.visits.count == 2, "new path truncates forward stack")
        history.snapshot(id:aid,y:Double.nan)
        history.move(-1); expect(history.current!.scrollY == 0, "invalid geometry guarded")
        for n in 0..<150 { history.push(GIIssueRoute(repository:"team/alpha",number:"I\(n)")) }
        expect(history.visits.count == 100 && history.current!.route.number == "I149", "history bounded")
        history.reset(); expect(history.current == nil && history.visits.isEmpty, "account reset erases history")
        let issueData = Data(#"{"id":123,"number":"IAbC12","title":"中文标题","state":"custom-state","body":"**正文**","user":{"id":2,"login":"alice"},"comments":1}"#.utf8)
        let issue = try JSONDecoder().decode(GIIssue.self, from:issueData)
        expect(issue.number == "IAbC12" && issue.stateTitle == "custom-state", "case-sensitive number and custom states")
        let repo = try JSONDecoder().decode(GIRepository.self, from:Data(#"{"id":1,"full_name":"团队 / 显示名称","name":"显示名称","html_url":"https://gitee.com/team/actual-path"}"#.utf8))
        expect(repo.path == "team/actual-path", "API path derived from canonical repository URL, not display name")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GIFixtureProtocol.self]
        let api = GIAPI(token:"fixture-only-not-a-real-token",configuration:config)
        GIFixtureProtocol.status = 200; GIFixtureProtocol.payload = issueData
        let loaded: GIIssue = try await api.issue(a)
        expect(loaded.title == "中文标题", "API decoding")
        let request = GIFixtureProtocol.lastRequest!
        expect(request.httpMethod == "GET", "read-only method")
        expect(request.url!.host == "gitee.com" && request.url!.path == "/api/v5/repos/team/alpha/issues/IAbC12", "fixed API host and route")
        expect(request.value(forHTTPHeaderField:"Authorization") == "Bearer fixture-only-not-a-real-token", "token confined to header")
        expect(!(request.url!.absoluteString.contains("token")), "no credentials in URL")
        for status in [401,403,404,429,500,302] {
            GIFixtureProtocol.status = status
            do { let _: GIIssue = try await api.issue(a); fatalError("Expected HTTP error") }
            catch let error as GIServiceError {
                expect(!error.localizedDescription.contains("fixture-only"), "error redacts credentials")
                if status == 302 { if case .unsafeRedirect = error {} else { fatalError("redirect must be blocked") } }
            }
        }
        GIFixtureProtocol.status = 200; GIFixtureProtocol.payload = Data("not JSON".utf8)
        do { let _: GIIssue = try await api.issue(a); fatalError("Expected malformed JSON error") }
        catch { expect(error is GIServiceError, "malformed JSON handled") }
        api.cancel()
        print("PASS: \(count) production Gitee routing/history/API assertions; all network responses are local fixtures.")
    }
}
