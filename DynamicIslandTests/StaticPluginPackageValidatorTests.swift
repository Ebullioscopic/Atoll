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

final class StaticPluginPackageValidatorTests: XCTestCase {
    private var rootURL: URL!
    private let validator = StaticPluginPackageValidator()

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
        rootURL = nil
    }

    func testValidPackageProducesPlugin() throws {
        let plugin = try validator.validate(packageURL: makePackage())

        XCTAssertEqual(plugin.id, "com.example.tools")
        XCTAssertEqual(plugin.entrypointURL.lastPathComponent, "index.html")
        XCTAssertEqual(plugin.allowedExternalURLs, [URL(string: "https://geojson.io/")!])
        XCTAssertEqual(plugin.allowedExternalURLPrefixes, ["https://uri.amap.com/marker?"])
    }

    func testMissingExternalURLListsDefaultToEmpty() throws {
        let plugin = try validator.validate(
            packageURL: makePackage(allowedURLs: nil, allowedURLPrefixes: nil)
        )

        XCTAssertTrue(plugin.allowedExternalURLs.isEmpty)
        XCTAssertTrue(plugin.allowedExternalURLPrefixes.isEmpty)
    }

    func testUnsupportedSchemaIsRejected() throws {
        assertThrows(.unsupportedSchema(2)) {
            _ = try validator.validate(packageURL: makePackage(schemaVersion: 2))
        }
    }

    func testUnsafeIdentifierIsRejected() throws {
        for id in ["../escape", "工具.example"] {
            assertThrows(.invalidIdentifier) {
                _ = try validator.validate(packageURL: makePackage(id: id))
            }
        }
    }

    func testTraversalEntrypointIsRejected() throws {
        try Data("outside".utf8).write(to: rootURL.appendingPathComponent("outside.html"))

        assertThrows(.unsafeEntrypoint) {
            _ = try validator.validate(packageURL: makePackage(entrypoint: "../outside.html"))
        }
    }

    func testPackageContainingSymlinkIsRejected() throws {
        let outsideURL = rootURL.appendingPathComponent("outside.html")
        try Data("outside".utf8).write(to: outsideURL)
        let packageURL = try makePackage()
        try FileManager.default.createSymbolicLink(
            at: packageURL.appendingPathComponent("escaped.html"),
            withDestinationURL: outsideURL
        )

        assertThrows(.symbolicLink("escaped.html")) {
            _ = try validator.validate(packageURL: packageURL)
        }
    }

    func testNonHTTPExternalURLIsRejected() throws {
        assertThrows(.invalidExternalURL("file:///tmp/private")) {
            _ = try validator.validate(
                packageURL: makePackage(allowedURLs: ["file:///tmp/private"])
            )
        }
    }

    func testExternalURLPrefixWithoutQueryDelimiterIsRejected() throws {
        assertThrows(.invalidExternalURLPrefix("https://uri.amap.com/marker")) {
            _ = try validator.validate(
                packageURL: makePackage(
                    allowedURLPrefixes: ["https://uri.amap.com/marker"]
                )
            )
        }
    }

    func testEmptyDisplayValueIsRejected() throws {
        assertThrows(.emptyDisplayValue("name")) {
            _ = try validator.validate(packageURL: makePackage(name: "  "))
        }
    }

    private func assertThrows(
        _ expectedError: StaticPluginValidationError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? StaticPluginValidationError,
                expectedError,
                file: file,
                line: line
            )
        }
    }

    @discardableResult
    private func makePackage(
        id: String = "com.example.tools",
        name: String = "Tools",
        version: String = "1.0.0",
        schemaVersion: Int = 1,
        entrypoint: String = "index.html",
        allowedURLs: [String]? = ["https://geojson.io/"],
        allowedURLPrefixes: [String]? = ["https://uri.amap.com/marker?"]
    ) throws -> URL {
        let packageURL = rootURL.appendingPathComponent("Tools.atollplugin", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)

        var manifest: [String: Any] = [
            "schemaVersion": schemaVersion,
            "id": id,
            "name": name,
            "version": version,
            "entrypoint": entrypoint,
            "tab": [
                "title": "Tools",
                "icon": "wrench.and.screwdriver",
                "preferredHeight": 360
            ]
        ]
        if let allowedURLs {
            manifest["allowedExternalURLs"] = allowedURLs
        }
        if let allowedURLPrefixes {
            manifest["allowedExternalURLPrefixes"] = allowedURLPrefixes
        }

        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
        try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))
        try Data("<html></html>".utf8).write(to: packageURL.appendingPathComponent("index.html"))
        return packageURL
    }
}

final class StaticPluginLayoutTests: XCTestCase {
    func testResolvesSelectedStaticPluginSizeForWindowSizing() throws {
        let plugin = try makePlugin(id: "com.example.tools", preferredHeight: 460)

        XCTAssertEqual(
            StaticPluginLayout.resolvedSize(
                baseSize: CGSize(width: 640, height: 200),
                isStaticPluginView: true,
                selectedPluginID: plugin.id,
                enabledPlugins: [plugin],
                visibleScreenHeight: 900,
                fallbackMaximumHeight: 332
            ),
            CGSize(width: 640, height: 460)
        )
    }

    func testDoesNotResolveSizeOutsideStaticPluginView() throws {
        let plugin = try makePlugin(id: "com.example.tools", preferredHeight: 460)

        XCTAssertNil(
            StaticPluginLayout.resolvedSize(
                baseSize: CGSize(width: 640, height: 200),
                isStaticPluginView: false,
                selectedPluginID: plugin.id,
                enabledPlugins: [plugin],
                visibleScreenHeight: 900,
                fallbackMaximumHeight: 332
            )
        )
    }

    func testUsesRequestedHeightWhenItFitsScreen() {
        XCTAssertEqual(
            StaticPluginLayout.resolvedHeight(
                preferredHeight: 460,
                baseHeight: 200,
                visibleScreenHeight: 900,
                fallbackMaximumHeight: 332
            ),
            460
        )
    }

    func testNeverShrinksBelowBaseHeight() {
        XCTAssertEqual(
            StaticPluginLayout.resolvedHeight(
                preferredHeight: 100,
                baseHeight: 200,
                visibleScreenHeight: 900,
                fallbackMaximumHeight: 332
            ),
            200
        )
    }

    func testClampsToSeventyPercentOfVisibleScreen() {
        XCTAssertEqual(
            StaticPluginLayout.resolvedHeight(
                preferredHeight: 800,
                baseHeight: 200,
                visibleScreenHeight: 600,
                fallbackMaximumHeight: 332
            ),
            420
        )
    }

    func testUsesExistingFallbackWithoutScreenHeight() {
        XCTAssertEqual(
            StaticPluginLayout.resolvedHeight(
                preferredHeight: 460,
                baseHeight: 200,
                visibleScreenHeight: nil,
                fallbackMaximumHeight: 332
            ),
            332
        )
    }

    private func makePlugin(id: String, preferredHeight: Double) throws -> InstalledStaticPlugin {
        let manifestData = Data(
            """
            {
              "schemaVersion": 1,
              "id": "\(id)",
              "name": "Tools",
              "version": "1.0.0",
              "entrypoint": "index.html",
              "tab": {
                "title": "Tools",
                "icon": "wrench.and.screwdriver",
                "preferredHeight": \(preferredHeight)
              },
              "allowedExternalURLs": [],
              "allowedExternalURLPrefixes": []
            }
            """.utf8
        )
        let manifest = try JSONDecoder().decode(StaticPluginManifest.self, from: manifestData)
        let rootURL = URL(fileURLWithPath: "/tmp/\(id).atollplugin", isDirectory: true)
        return InstalledStaticPlugin(
            manifest: manifest,
            rootURL: rootURL,
            entrypointURL: rootURL.appendingPathComponent("index.html"),
            allowedExternalURLs: [],
            allowedExternalURLPrefixes: []
        )
    }
}
