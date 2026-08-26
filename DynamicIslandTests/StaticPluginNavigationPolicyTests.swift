/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import SwiftUI
import WebKit
import XCTest

@testable import Atoll

final class StaticPluginNavigationPolicyTests: XCTestCase {
    private struct IgnoringExternalOpener: StaticPluginExternalOpening {
        func open(_ url: URL) {}
    }

    private let rootURL = URL(fileURLWithPath: "/tmp/Tools.atollplugin", isDirectory: true)
    private let allowedURL = URL(string: "https://geojson.io/")!
    private let allowedPrefix = "https://uri.amap.com/marker?"

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

    func testAllowlistedQueryPrefixUserClickOpensExternally() {
        let target = URL(
            string: "https://uri.amap.com/marker?position=116.403372,39.924912&coordinate=gaode"
        )!

        XCTAssertEqual(
            makePolicy(allowedExternalURLPrefixes: [allowedPrefix]).decision(
                for: target,
                userActivated: true,
                mainFrame: true
            ),
            .openExternally(target)
        )
    }

    func testQueryPrefixDoesNotPermitAnotherHostOrPath() {
        let policy = makePolicy(allowedExternalURLPrefixes: [allowedPrefix])

        for value in [
            "https://uri.amap.com.evil/marker?position=116,39",
            "https://uri.amap.com/marker-extra?position=116,39",
            "https://uri.amap.com/other?position=116,39"
        ] {
            XCTAssertEqual(
                policy.decision(
                    for: URL(string: value)!,
                    userActivated: true,
                    mainFrame: true
                ),
                .cancel
            )
        }
    }

    func testScriptedAndPopupNavigationAreCancelled() {
        let policy = makePolicy()

        XCTAssertEqual(policy.decision(for: allowedURL, userActivated: false, mainFrame: true), .cancel)
        XCTAssertEqual(policy.decision(for: allowedURL, userActivated: true, mainFrame: false), .cancel)

        let prefixedURL = URL(string: "https://uri.amap.com/marker?position=116,39")!
        let prefixPolicy = makePolicy(allowedExternalURLPrefixes: [allowedPrefix])
        XCTAssertEqual(
            prefixPolicy.decision(for: prefixedURL, userActivated: false, mainFrame: true),
            .cancel
        )
        XCTAssertEqual(
            prefixPolicy.decision(for: prefixedURL, userActivated: true, mainFrame: false),
            .cancel
        )
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
        let filters = rules.compactMap {
            ($0["trigger"] as? [String: Any])?["url-filter"] as? String
        }
        let actions = rules.compactMap {
            ($0["action"] as? [String: Any])?["type"] as? String
        }

        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(Set(filters), ["^https?://.*", "^wss?://.*"])
        XCTAssertEqual(actions, ["block", "block"])
    }

    func testSuccessfulNavigationClearsPreviousLoadingError() throws {
        var loadingError: String? = "Previous load failed"
        let coordinator = StaticPluginWebRepresentable.Coordinator(
            plugin: try makePlugin(),
            loadingError: Binding(
                get: { loadingError },
                set: { loadingError = $0 }
            ),
            externalOpener: IgnoringExternalOpener()
        )

        coordinator.webView(WKWebView(), didFinish: nil)

        XCTAssertNil(loadingError)
    }

    private func makePolicy(
        allowedExternalURLPrefixes: Set<String> = []
    ) -> StaticPluginNavigationPolicy {
        StaticPluginNavigationPolicy(
            pluginRoot: rootURL,
            allowedExternalURLs: [allowedURL],
            allowedExternalURLPrefixes: allowedExternalURLPrefixes
        )
    }

    private func makePlugin() throws -> InstalledStaticPlugin {
        let manifest = try JSONDecoder().decode(
            StaticPluginManifest.self,
            from: Data(
                """
                {
                  "schemaVersion": 1,
                  "id": "com.example.tools",
                  "name": "Tools",
                  "version": "1.0.0",
                  "entrypoint": "index.html",
                  "tab": {
                    "title": "Tools",
                    "icon": "wrench.and.screwdriver"
                  },
                  "allowedExternalURLs": [],
                  "allowedExternalURLPrefixes": []
                }
                """.utf8
            )
        )
        return InstalledStaticPlugin(
            manifest: manifest,
            rootURL: rootURL,
            entrypointURL: rootURL.appendingPathComponent("index.html"),
            allowedExternalURLs: [],
            allowedExternalURLPrefixes: []
        )
    }
}
