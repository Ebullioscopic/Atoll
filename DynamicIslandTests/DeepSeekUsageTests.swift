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

/// DeepSeek reports a prepaid balance rather than usage over time (#709).
final class DeepSeekUsageTests: XCTestCase {
    private func response(_ body: String, status: Int = 200) -> DeepSeekClient {
        DeepSeekClient { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/user/balance")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            return (
                Data(body.utf8),
                HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            )
        }
    }

    func testDecodesStringAmountsPerCurrency() async throws {
        let client = response(#"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"12.34","granted_balance":"0.00","topped_up_balance":"12.34"},{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}"#)

        let snapshot = try await client.fetchSnapshot(apiKey: "test-key", now: Date())

        XCTAssertEqual(snapshot.deepSeekBalance, DeepSeekBalanceResponse(isAvailable: true, balances: [
            DeepSeekBalance(currency: "USD", total: 12.34, granted: 0, toppedUp: 12.34),
            DeepSeekBalance(currency: "CNY", total: 110, granted: 10, toppedUp: 100)
        ]))
    }

    func testReportsUnavailableBalance() async throws {
        let client = response(#"{"is_available":false,"balance_infos":[]}"#)
        let balance = try await client.fetchBalance(apiKey: "test-key")
        XCTAssertFalse(balance.isAvailable)
        XCTAssertTrue(balance.balances.isEmpty)
    }

    func testRejectedKeyIsAnError() async {
        let client = response(#"{"error":{"message":"Authentication Fails"}}"#, status: 401)
        do {
            _ = try await client.fetchBalance(apiKey: "test-key")
            XCTFail("Expected a 401 to throw")
        } catch {
            XCTAssertEqual(error as? DeepSeekClientError, .httpFailure)
        }
    }

    func testProviderRequiresConfiguredKey() async {
        let provider = DeepSeekUsageProvider(keySource: TestDeepSeekKeySource(key: "  "), client: DeepSeekClient { _ in
            XCTFail("Missing DeepSeek key must not create a request")
            throw DeepSeekClientError.httpFailure
        })
        do {
            _ = try await provider.fetchSnapshot(now: Date())
            XCTFail("Expected missing key to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "DeepSeek API key not configured")
        }
    }
}

private struct TestDeepSeekKeySource: DeepSeekAPIKeyProviding {
    let key: String?
    func apiKey() -> String? { key }
}
