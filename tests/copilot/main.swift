import Foundation

@main struct CopilotQuotaChecks {
    static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        func payload(_ json: String) throws -> CopilotQuotaPayload {
            try JSONDecoder().decode(CopilotQuotaPayload.self, from: Data(json.utf8))
        }
        let paid = try payload(#"{"copilot_plan":"individual_pro","quota_reset_date":"2026-12-01","quota_snapshots":{"premium_interactions":{"entitlement":300,"remaining":90,"percent_remaining":30},"chat":{"unlimited":true,"entitlement":-1}}}"#)
        check(paid.copilot_plan == "individual_pro", "plan")
        check(paid.quotas[0].usedPercent == 70, "remaining converted to consumed")
        check(paid.quotas[0].remaining == 90, "requests remaining")
        check(paid.quotas[0].resetsAt != nil, "calendar reset date")
        check(paid.quotas[1].unlimited && paid.quotas[1].usedPercent == nil, "unlimited is not 0%")
        let credits = try payload(#"{"token_based_billing":true,"quota_reset_date_utc":"2026-12-01T00:00:00.123Z","quota_snapshots":{"premium_interactions":{"entitlement":10000,"remaining":5996,"percent_remaining":59.96}}}"#)
        check(credits.quotas[0].title == "AI credits", "credit billing label")
        check(abs(credits.quotas[0].usedPercent! - 40.04) < 0.0001, "fractional percentages")
        check(credits.quotas[0].resetsAt != nil, "fractional ISO reset")
        let precise = try payload(#"{"quota_snapshots":{"premium_interactions":{"entitlement":300,"remaining":93,"quota_remaining":93.5,"quota_reset_at":1800000000}}}"#)
        check(precise.quotas[0].remaining == 93.5, "prefer precise remaining")
        check(abs(precise.quotas[0].usedPercent! - (100 * (1 - 93.5 / 300))) < 0.0001, "count fallback")
        check(precise.quotas[0].resetsAt == Date(timeIntervalSince1970: 1800000000), "bucket reset date")
        let unavailable = try payload(#"{"quota_snapshots":{"premium_interactions":{"entitlement":0}}}"#)
        check(unavailable.quotas[0].usedPercent == nil, "placeholder is unavailable, not empty quota")
        let empty = try payload("{}")
        check(empty.quotas.isEmpty, "missing quota data")
        let exhausted = try payload(#"{"quota_snapshots":{"premium_interactions":{"entitlement":300,"remaining":-5,"percent_remaining":-1}}}"#)
        check(exhausted.quotas[0].usedPercent == 100, "exhausted clamped")
        check(exhausted.quotas[0].remaining == 0, "remaining nonnegative")
        let publicURL = try CopilotEndpoint.url(host: "github.com")
        check(publicURL.host == "api.github.com", "public GitHub")
        let enterpriseURL = try CopilotEndpoint.url(host: " EXAMPLE-COMPANY.GHE.COM ")
        check(enterpriseURL.host == "api.example-company.ghe.com", "enterprise tenant")
        for host in ["http://github.com", "evil.com", "github.com@evil.com", "github.com/path", "api.github.com", "github.com:443", "evil.ghe.com.attacker.com"] {
            do { _ = try CopilotEndpoint.url(host: host); fatalError("Unsafe host accepted") }
            catch { checks += 1 }
        }
        for token in ["test-token", "token_with_underscores", "a.b-c_123", "abc+/=="] {
            check(CopilotTokenValidation.isValid(token), "valid bearer-token format")
        }
        for token in ["", "hello world", "abc\nHeader: injected", "abc\r", "abc\t", "abc\0", "clé", "{\"token\":\"secret\"}", String(repeating: "x", count: 8193)] {
            check(!CopilotTokenValidation.isValid(token), "reject malformed bearer-token input")
        }
        let validJSON = Data(#"{"quota_snapshots":{"premium_interactions":{"entitlement":300,"remaining":90}}}"#.utf8)
        let client = CopilotQuotaClient(fetch: { request in
            check(request.url?.absoluteString == "https://api.example-company.ghe.com/copilot_internal/user", "exact HTTPS destination")
            check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token", "authorization header")
            check(!request.httpShouldHandleCookies, "cookies disabled")
            check(request.timeoutInterval == 15, "timeout")
            return (validJSON, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let quota = try await client.fetchQuota(host: "example-company.ghe.com", token: "test-token")
        check(quota.quotas[0].usedPercent == 70, "real transport mapping")
        let shouldNotSend = CopilotQuotaClient(fetch: { _ in
            fatalError("Invalid credentials must never make a request")
        })
        for (host, token) in [("attacker.example", "secret"), ("github.com", "bad\nheader"), ("github.com", "bad\0header")] {
            do { _ = try await shouldNotSend.fetchQuota(host: host, token: token); fatalError("Expected rejection") }
            catch { check(error is CopilotQuotaError, "safe validation error") }
        }
        for status in [301, 401, 403, 429, 500] {
            let rejected = CopilotQuotaClient(fetch: { request in
                (Data("SECRET response body".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            })
            do { _ = try await rejected.fetchQuota(host: "github.com", token: "test-token"); fatalError("Expected HTTP error") }
            catch {
                check(error is CopilotQuotaError, "HTTP failure reported")
                check(!error.localizedDescription.contains("SECRET"), "no response-body disclosure")
            }
        }
        let networkFailure = CopilotQuotaClient(fetch: { _ in
            throw NSError(domain: "SECRET token", code: 1, userInfo: [NSLocalizedDescriptionKey: "SECRET token"])
        })
        do { _ = try await networkFailure.fetchQuota(host: "github.com", token: "test-token"); fatalError("Expected network error") }
        catch { check(!error.localizedDescription.contains("SECRET"), "sanitize transport error") }
        for data in [Data("{}".utf8), Data("not json".utf8), Data(repeating: 32, count: 1_048_577)] {
            let invalid = CopilotQuotaClient(fetch: { request in
                (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
            do { _ = try await invalid.fetchQuota(host: "github.com", token: "test-token"); fatalError("Expected payload rejection") }
            catch { check(error is CopilotQuotaError, "bounded payload validation") }
        }
        let unexpectedURL = CopilotQuotaClient(fetch: { _ in
            (validJSON, HTTPURLResponse(url: URL(string: "https://attacker.example")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        do { _ = try await unexpectedURL.fetchQuota(host: "github.com", token: "test-token"); fatalError("Expected URL rejection") }
        catch { check(error is CopilotQuotaError, "reject response from unexpected URL") }
        let session = URLSession(configuration: .ephemeral)
        let request = URLRequest(url: URL(string: "https://github.com")!)
        let task = session.dataTask(with: request)
        var redirected: URLRequest? = request
        CopilotRedirectPolicy().urlSession(session, task: task,
            willPerformHTTPRedirection: HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!,
            newRequest: URLRequest(url: URL(string: "https://attacker.example")!),
            completionHandler: { redirected = $0 })
        check(redirected == nil, "URLSession delegate refuses redirect")
        session.invalidateAndCancel()
        print("\(checks) Copilot quota/security checks passed")
    }
}
