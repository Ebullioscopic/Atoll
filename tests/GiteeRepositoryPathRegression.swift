import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GIPathFixture: URLProtocol {
    static var requests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let path = request.url!.path
        let status: Int
        let body: String
        switch path {
        case "/api/v5/user": status=200; body=#"{"id":3,"login":"fixture-user"}"#
        case "/api/v5/user/subscriptions":
            status=200; body=#"[{"id":7,"full_name":"team/project","name":"Project","html_url":"https://gitee.com/team/project.git"}]"#
        case "/api/v5/repos/team/project/issues":
            status=200; body=#"[{"id":1,"number":"IAbC12","title":"Synthetic issue A","state":"open","body":"[B](https://gitee.com/other/linked/issues/ILink#note_42)"}]"#
        case "/api/v5/repos/other/linked/issues/ILink":
            status=200; body=#"{"id":2,"number":"ILink","title":"Synthetic issue B","state":"open","body":"fixture only"}"#
        case "/api/v5/repos/other/linked/issues/ILink/comments":
            status=200; body=#"[{"id":42,"body":"Synthetic comment"}]"#
        default: status=404; body=#"{"message":"Not Found"}"#
        }
        client?.urlProtocol(self, didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:["Content-Type":"application/json"])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct GiteeRepositoryPathRegression {
    static var count=0
    static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        count += 1; precondition(condition(),name)
    }
    static func main() async throws {
        let decode: (String) throws -> GIRepository = { try JSONDecoder().decode(GIRepository.self,from:Data($0.utf8)) }
        let clone=try decode(#"{"id":7,"full_name":"team/project","name":"Project","html_url":"https://gitee.com/team/project.git"}"#)
        expect(clone.path=="team/project","clone suffix removed")
        let cached=try JSONDecoder().decode([GIRepository].self,from:JSONEncoder().encode([clone]))
        expect(cached[0].path=="team/project","persisted pre-fix record repairs without reselection")
        let canonical=try decode(#"{"id":8,"full_name":"显示空间/显示名称","name":"显示名称","path":"actual","namespace":{"path":"actual-space"},"owner":{"login":"different-owner"},"html_url":"https://gitee.com/old-space/old-name.git"}"#)
        expect(canonical.path=="actual-space/actual","API namespace and path override display names and stale URLs")
        let genuine=try decode(#"{"id":9,"full_name":"team/actual.git","name":"actual.git","path":"actual.git","namespace":{"path":"team"},"html_url":"https://gitee.com/team/actual.git.git"}"#)
        expect(genuine.path=="team/actual.git","authoritative repo path is not blindly stripped")
        for raw in ["https://gitee.com/team/project.git","https://gitee.com/team/project.git/","team/project.git","git@gitee.com:team/project.git","https://www.gitee.com/team/project.git?from=watch"] {
            expect(GIRepositoryAddress.legacyPath(raw)=="team/project","legacy repository representation")
        }
        for raw in ["https://evil.test/team/project.git","https://gitee.com.evil.test/team/project","https://gitee.com/team%2Fbad/project.git","https://gitee.com/team/project/issues/1","显示 空间/显示 名称","team/..","team/.git","https://user:pass@gitee.com/team/project.git","https://gitee.com:8443/team/project.git"] {
            expect(GIRepositoryAddress.legacyPath(raw)==nil,"reject unsafe or non-repository address")
        }
        let a=GIIssueRoute(repository:"team/project",number:"IAbC12")
        expect(GIIssueLinks.resolve("https://gitee.com/team/project.git/issues/IAbC12#note_42",relativeTo:a.url) == .issue(a,fragment:"note_42"),"linked clone URL normalized with case and anchor preserved")
        expect(GIServiceError.message(URLError(.cannotFindHost)).contains("DNS"),"DNS failure distinct from auth")
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[GIPathFixture.self]
        let api=GIAPI(token:"fixture-only",configuration:config)
        do { let _: [GIIssue] = try await api.get(["repos","team","project.git","issues"]); fatalError("expected old clone-path 404") }
        catch GIServiceError.missing { expect(true,"reproduced old clone-path 404 in fixture") }
        let user=try await api.user();expect(user.id==3,"user decode")
        let repos=try await api.repositories(source:"subscriptions",page:1)
        let issues=try await api.issues(repository:repos[0].path,page:1)
        expect(issues.count==1 && issues[0].number=="IAbC12","watch metadata to successful canonical issues list")
        let b=GIIssueRoute(repository:"other/linked",number:"ILink")
        expect(GIIssueLinks.resolve(b.url.absoluteString+"#note_42",relativeTo:a.url) == .issue(b,fragment:"note_42"),"cross issue link")
        let detail=try await api.issue(b);let comments=try await api.comments(b,page:1)
        expect(detail.number=="ILink" && comments.first?.id==42,"linked detail and comment decode")
        for request in GIPathFixture.requests {
            expect(request.httpMethod=="GET" && request.url?.host=="gitee.com","read only fixed host")
            expect(request.value(forHTTPHeaderField:"Authorization")=="Bearer fixture-only" && !request.url!.absoluteString.contains("fixture-only"),"credential only in header")
        }
        for raw in ["","team/repo/extra","../repo"] {
            do { let _: [GIIssue]=try await api.issues(repository:raw,page:1);fatalError("invalid repository accepted") }
            catch { expect(error is GIServiceError,"invalid path rejected before request") }
        }
        api.cancel()
        print("PASS: \(count) repository-path/request-chain assertions; all responses are synthetic, not a real Gitee account test.")
    }
}
