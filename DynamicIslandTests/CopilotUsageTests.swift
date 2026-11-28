import Foundation
import XCTest
@testable import Atoll

final class CopilotUsageTests: XCTestCase {
    func testEnterpriseRequestAndConsumedQuotaWithoutInventedTokenUsage() async throws {
        let provider = CopilotUsageProvider(fetch: { request in
            XCTAssertEqual(request.url?.host, "api.example-company.ghe.com")
            XCTAssertEqual(request.url?.path, "/copilot_internal/user")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.timeoutInterval, 15)
            let data = Data(#"{"copilot_plan":"business","quota_snapshots":{"premium_interactions":{"entitlement":10000,"remaining":5996,"percent_remaining":59.96}}}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, credentials: { ("example-company.ghe.com", "test-token") })
        let now = Date()
        let snapshot = try await provider.fetchSnapshot(now: now)
        XCTAssertEqual(snapshot.plan, "business")
        XCTAssertEqual(snapshot.copilotQuotas[0].usedPercent!, 40.04, accuracy: 0.001)
        XCTAssertEqual(snapshot.copilotQuotas[0].remaining, 5996)
        XCTAssertNil(snapshot.sessionLimit)
        XCTAssertNil(snapshot.weekLimit)
        XCTAssertEqual(snapshot.today.totalTokens, 0)
        XCTAssertEqual(snapshot.lastUpdated, now)
    }

    func testAuthorizationFailureDoesNotExposeResponseBodyOrToken() async {
        let provider = CopilotUsageProvider(fetch: { request in
            (Data("private server details".utf8), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!)
        }, credentials: { ("github.com", "test-token") })
        do { _ = try await provider.fetchSnapshot(now: Date()); XCTFail("Expected authorization error") }
        catch {
            XCTAssertTrue(error.localizedDescription.contains("access denied"))
            XCTAssertFalse(error.localizedDescription.contains("test-token"))
            XCTAssertFalse(error.localizedDescription.contains("private server details"))
        }
    }

    func testMissingQuotaIsUnavailable() async {
        let provider = CopilotUsageProvider(fetch: { request in
            (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, credentials: { ("github.com", "test-token") })
        do { _ = try await provider.fetchSnapshot(now: Date()); XCTFail("Expected unavailable quota") }
        catch { XCTAssertTrue(error.localizedDescription.contains("quota information")) }
    }

    func testInvalidHostAndAbsentCredentialsNeverMakeRequests() async {
        for credential in [("attacker.example", Optional("secret")), ("github.com", nil)] {
            let provider = CopilotUsageProvider(fetch: { _ in
                XCTFail("Must not transmit credentials")
                throw URLError(.badURL)
            }, credentials: { credential })
            do { _ = try await provider.fetchSnapshot(now: Date()); XCTFail("Expected connection error") }
            catch { XCTAssertTrue(error is CopilotQuotaError) }
        }
    }
}
