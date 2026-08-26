/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import XCTest

@testable import Atoll

final class StaticPluginNavigationPolicyTests: XCTestCase {
    private let rootURL = URL(fileURLWithPath: "/tmp/Tools.atollplugin", isDirectory: true)
    private let allowedURL = URL(string: "https://geojson.io/")!

    func testLocalFileInsidePluginRootIsAllowed() {
        let policy = makePolicy()

        XCTAssertEqual(
            policy.decision(
                for: rootURL.appendingPathComponent("assets/app.js"),
                userActivated: false,
                mainFrame: true
            ),
            .allow
        )
    }

    func testLocalFileOutsidePluginRootIsCancelled() {
        XCTAssertEqual(
            makePolicy().decision(
                for: URL(fileURLWithPath: "/tmp/private.txt"),
                userActivated: true,
                mainFrame: true
            ),
            .cancel
        )
    }

    func testExactAllowlistedUserClickOpensExternally() {
        XCTAssertEqual(
            makePolicy().decision(for: allowedURL, userActivated: true, mainFrame: true),
            .openExternally(allowedURL)
        )
    }

    func testAllowlistedUserClickWithoutTargetFrameOpensExternally() {
        XCTAssertEqual(
            makePolicy().decision(for: allowedURL, userActivated: true, mainFrame: nil),
            .openExternally(allowedURL)
        )
    }

    func testScriptedAndPopupNavigationAreCancelled() {
        let policy = makePolicy()

        XCTAssertEqual(policy.decision(for: allowedURL, userActivated: false, mainFrame: true), .cancel)
        XCTAssertEqual(policy.decision(for: allowedURL, userActivated: true, mainFrame: false), .cancel)
    }

    func testUndeclaredAndNonHTTPURLsAreCancelled() {
        let policy = makePolicy()

        XCTAssertEqual(
            policy.decision(for: URL(string: "https://example.com/")!, userActivated: true, mainFrame: true),
            .cancel
        )
        XCTAssertEqual(
            policy.decision(for: URL(string: "https://geojson.io/?changed=true")!, userActivated: true, mainFrame: true),
            .cancel
        )
        XCTAssertEqual(
            policy.decision(for: URL(string: "mailto:test@example.com")!, userActivated: true, mainFrame: true),
            .cancel
        )
    }

    func testContentRulesBlockHTTPAndWebSocketLoads() throws {
        let data = try XCTUnwrap(StaticPluginWebView.networkBlockingRules.data(using: .utf8))
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        XCTAssertEqual(rules.count, 2)
        XCTAssertTrue(StaticPluginWebView.networkBlockingRules.contains("^https?://"))
        XCTAssertTrue(StaticPluginWebView.networkBlockingRules.contains("^wss?://"))
    }

    private func makePolicy() -> StaticPluginNavigationPolicy {
        StaticPluginNavigationPolicy(
            pluginRoot: rootURL,
            allowedExternalURLs: [allowedURL]
        )
    }
}
