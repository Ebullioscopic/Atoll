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
    }

    func testMissingExternalURLListDefaultsToEmpty() throws {
        let plugin = try validator.validate(packageURL: makePackage(allowedURLs: nil))

        XCTAssertTrue(plugin.allowedExternalURLs.isEmpty)
    }

    func testUnsupportedSchemaIsRejected() throws {
        XCTAssertThrowsError(try validator.validate(packageURL: makePackage(schemaVersion: 2)))
    }

    func testUnsafeIdentifierIsRejected() throws {
        XCTAssertThrowsError(try validator.validate(packageURL: makePackage(id: "../escape")))
        XCTAssertThrowsError(try validator.validate(packageURL: makePackage(id: "工具.example")))
    }

    func testTraversalEntrypointIsRejected() throws {
        try Data("outside".utf8).write(to: rootURL.appendingPathComponent("outside.html"))

        XCTAssertThrowsError(try validator.validate(packageURL: makePackage(entrypoint: "../outside.html")))
    }

    func testPackageContainingSymlinkIsRejected() throws {
        let outsideURL = rootURL.appendingPathComponent("outside.html")
        try Data("outside".utf8).write(to: outsideURL)
        let packageURL = try makePackage()
        try FileManager.default.createSymbolicLink(
            at: packageURL.appendingPathComponent("escaped.html"),
            withDestinationURL: outsideURL
        )

        XCTAssertThrowsError(try validator.validate(packageURL: packageURL))
    }

    func testNonHTTPExternalURLIsRejected() throws {
        XCTAssertThrowsError(
            try validator.validate(packageURL: makePackage(allowedURLs: ["file:///tmp/private"]))
        )
    }

    func testEmptyDisplayValueIsRejected() throws {
        XCTAssertThrowsError(try validator.validate(packageURL: makePackage(name: "  ")))
    }

    @discardableResult
    private func makePackage(
        id: String = "com.example.tools",
        name: String = "Tools",
        version: String = "1.0.0",
        schemaVersion: Int = 1,
        entrypoint: String = "index.html",
        allowedURLs: [String]? = ["https://geojson.io/"]
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

        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted])
        try manifestData.write(to: packageURL.appendingPathComponent("manifest.json"))
        try Data("<html></html>".utf8).write(to: packageURL.appendingPathComponent("index.html"))
        return packageURL
    }
}

final class StaticPluginLayoutTests: XCTestCase {
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
}
