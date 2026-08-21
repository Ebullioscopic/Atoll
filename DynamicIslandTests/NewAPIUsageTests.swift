/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Foundation
import XCTest
@testable import Atoll

final class NewAPIUsageTests: XCTestCase {
    func testDecodesIntegerAndNumericStringFields() throws {
        let user = try JSONDecoder().decode(
            NewAPIUser.self,
            from: Data(#"{"quota":"1500000","used_quota":500000,"request_count":"12"}"#.utf8)
        )
        XCTAssertEqual(user, NewAPIUser(quota: 1_500_000, usedQuota: 500_000, requestCount: 12))

        let stat = try JSONDecoder().decode(
            NewAPIStat.self,
            from: Data(#"{"quota":"1234","rpm":7.0,"tpm":9876}"#.utf8)
        )
        XCTAssertEqual(stat, NewAPIStat(quota: 1_234, rpm: 7, tpm: 9_876))
    }

    func testNormalizesBaseURLAndPreservesSubpath() {
        XCTAssertEqual(
            NewAPIClient.normalizedBaseURL(" https://example.com/new-api/ ")?.absoluteString,
            "https://example.com/new-api"
        )
        XCTAssertEqual(
            NewAPIClient.normalizedBaseURL("https://example.com/new-api")?.appendingPathComponent("api/user/self").absoluteString,
            "https://example.com/new-api/api/user/self"
        )
        XCTAssertNil(NewAPIClient.normalizedBaseURL("https://example.com/new-api?token=secret"))
        XCTAssertNil(NewAPIClient.normalizedBaseURL("example.com"))
    }

    func testFetchAccountUsesBearerAuthAndConsumeLogType() async throws {
        let recorder = RequestRecorder()
        let client = NewAPIClient { request in
            recorder.append(request)
            let body: String
            if request.url?.path.hasSuffix("/api/user/self") == true {
                body = #"{"success":true,"data":{"quota":1500000,"used_quota":500000,"request_count":12}}"#
            } else {
                body = #"{"success":true,"data":{"quota":1234,"rpm":7,"tpm":9876}}"#
            }
            return (
                Data(body.utf8),
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
            )
        }

        let account = NewAPIAccount(name: "Primary", baseURL: "https://example.com/new-api/")
        let snapshot = try await client.fetchAccount(
            account,
            apiKey: "secret-key",
            now: Date(timeIntervalSince1970: 1_700_000_000),
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(snapshot.balanceQuota, 1_500_000)
        XCTAssertEqual(snapshot.todayQuota, 1_234)
        XCTAssertEqual(snapshot.currentRPM, 7)
        XCTAssertEqual(snapshot.currentTPM, 9_876)
        XCTAssertEqual(recorder.requests.count, 4)

        for request in recorder.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        }

        let statRequests = recorder.requests.filter { $0.url?.path.hasSuffix("/api/log/self/stat") == true }
        XCTAssertEqual(statRequests.count, 3)
        for request in statRequests {
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(items.first(where: { $0.name == "type" })?.value, "2")
            XCTAssertNotNil(items.first(where: { $0.name == "start_timestamp" })?.value)
            XCTAssertNotNil(items.first(where: { $0.name == "end_timestamp" })?.value)
        }
    }

    func testProviderAggregatesMultipleAccountsAndKeepsFailuresIsolated() async throws {
        let first = NewAPIAccount(name: "10 Production", baseURL: "https://first.example")
        let second = NewAPIAccount(name: "20 Staging", baseURL: "https://second.example")
        let source = TestAccountSource(
            accounts: [first, second],
            keys: [first.id: "first-key", second.id: "second-key"]
        )
        let client = NewAPIClient { request in
            if request.url?.host == "second.example" {
                throw NewAPIClientError.httpFailure
            }
            let body: String
            if request.url?.path.hasSuffix("/api/user/self") == true {
                body = #"{"success":true,"data":{"quota":500,"used_quota":100,"request_count":2}}"#
            } else {
                body = #"{"success":true,"data":{"quota":25,"rpm":1,"tpm":2}}"#
            }
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            )
        }

        let snapshot = try await NewAPIUsageProvider(accountSource: source, client: client)
            .fetchSnapshot(now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(snapshot.newAPIAccounts.map(\.name), ["10 Production", "20 Staging"])
        XCTAssertEqual(snapshot.newAPIAccounts[0].balanceQuota, 500)
        XCTAssertNil(snapshot.newAPIAccounts[0].errorMessage)
        XCTAssertEqual(snapshot.newAPIAccounts[1].errorMessage, "New API request failed")
    }

    func testMissingAPIKeyDoesNotReachClientOrExposeSecret() async throws {
        let account = NewAPIAccount(name: "Missing", baseURL: "https://example.com")
        let source = TestAccountSource(accounts: [account], keys: [:])
        let client = NewAPIClient { _ in
            XCTFail("A missing API key must not create a request")
            throw NewAPIClientError.httpFailure
        }

        let snapshot = try await NewAPIUsageProvider(accountSource: source, client: client)
            .fetchSnapshot(now: Date())
        let error = snapshot.newAPIAccounts[0].errorMessage
        XCTAssertEqual(error, "API key not configured")
        XCTAssertFalse(error?.contains("secret") == true)
    }
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    func append(_ request: URLRequest) {
        lock.lock()
        recordedRequests.append(request)
        lock.unlock()
    }
}

private struct TestAccountSource: NewAPIAccountProviding {
    let configuredAccounts: [NewAPIAccount]
    let keys: [UUID: String]

    init(accounts: [NewAPIAccount], keys: [UUID: String]) {
        configuredAccounts = accounts
        self.keys = keys
    }

    func accounts() -> [NewAPIAccount] { configuredAccounts }

    func apiKey(for account: NewAPIAccount) -> String? { keys[account.id] }
}
