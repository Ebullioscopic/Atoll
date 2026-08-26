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

@MainActor
final class StaticPluginManagerTests: XCTestCase {
    private enum TestReplacementError: Error {
        case failed
    }

    private var rootURL: URL!
    private var installationRootURL: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        installationRootURL = rootURL.appendingPathComponent("Installed", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defaultsSuiteName = "StaticPluginManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        installationRootURL = nil
        rootURL = nil
    }

    func testNewPluginIsInstalledAndDiscovered() throws {
        let manager = makeManager()

        try manager.install(from: makePackage(version: "1.0.0"), replacingExisting: false)

        XCTAssertEqual(manager.plugins.map(\.id), ["com.example.tools"])
        XCTAssertEqual(manager.enabledPlugins.map(\.id), ["com.example.tools"])
        XCTAssertEqual(manager.plugins.first?.manifest.version, "1.0.0")
    }

    func testSameIDRequiresReplaceAndPreservesDisabledState() throws {
        let manager = makeManager()
        try manager.install(from: makePackage(version: "1.0.0"), replacingExisting: false)
        manager.setEnabled(false, pluginID: "com.example.tools")

        XCTAssertThrowsError(
            try manager.install(from: makePackage(version: "2.0.0"), replacingExisting: false)
        )

        try manager.install(from: makePackage(version: "2.0.0"), replacingExisting: true)

        XCTAssertEqual(manager.plugins.first?.manifest.version, "2.0.0")
        XCTAssertTrue(manager.enabledPlugins.isEmpty)
        XCTAssertTrue(manager.isDisabled(pluginID: "com.example.tools"))
    }

    func testDisabledStatePersistsAcrossManagerInstances() throws {
        let manager = makeManager()
        try manager.install(from: makePackage(), replacingExisting: false)
        manager.setEnabled(false, pluginID: "com.example.tools")

        let reloadedManager = makeManager()

        XCTAssertTrue(reloadedManager.isDisabled(pluginID: "com.example.tools"))
        XCTAssertTrue(reloadedManager.enabledPlugins.isEmpty)
    }

    func testInvalidReplacementKeepsOldVersion() throws {
        let manager = makeManager()
        try manager.install(from: makePackage(version: "1.0.0"), replacingExisting: false)

        XCTAssertThrowsError(
            try manager.install(
                from: makePackage(version: "2.0.0", entrypoint: "missing.html", writesEntrypoint: false),
                replacingExisting: true
            )
        )

        manager.reload()
        XCTAssertEqual(manager.plugins.first?.manifest.version, "1.0.0")
    }

    func testFileReplacementFailureKeepsOldVersion() throws {
        let manager = makeManager { _, _ in
            throw TestReplacementError.failed
        }
        try manager.install(from: makePackage(version: "1.0.0"), replacingExisting: false)

        XCTAssertThrowsError(
            try manager.install(from: makePackage(version: "2.0.0"), replacingExisting: true)
        )

        manager.reload()
        XCTAssertEqual(manager.plugins.first?.manifest.version, "1.0.0")
    }

    func testRemoveClearsPackageAndDisabledState() throws {
        let manager = makeManager()
        try manager.install(from: makePackage(), replacingExisting: false)
        manager.setEnabled(false, pluginID: "com.example.tools")

        try manager.remove(pluginID: "com.example.tools")

        XCTAssertTrue(manager.plugins.isEmpty)
        XCTAssertFalse(manager.isDisabled(pluginID: "com.example.tools"))
    }

    func testReloadKeepsValidPluginsWhenAnotherPackageIsInvalid() throws {
        let manager = makeManager()
        try manager.install(from: makePackage(), replacingExisting: false)
        let invalidURL = installationRootURL.appendingPathComponent("broken.atollplugin", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidURL, withIntermediateDirectories: true)

        manager.reload()

        XCTAssertEqual(manager.plugins.map(\.id), ["com.example.tools"])
        XCTAssertEqual(manager.discoveryErrors.count, 1)
    }

    private func makeManager(
        replaceItem: StaticPluginManager.ReplaceItem? = nil
    ) -> StaticPluginManager {
        StaticPluginManager(
            installationRoot: installationRootURL,
            userDefaults: defaults,
            replaceItem: replaceItem
        )
    }

    private func makePackage(
        version: String = "1.0.0",
        entrypoint: String = "index.html",
        writesEntrypoint: Bool = true
    ) throws -> URL {
        let packageURL = rootURL
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).atollplugin", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "id": "com.example.tools",
            "name": "Tools",
            "version": version,
            "entrypoint": entrypoint,
            "tab": ["title": "Tools", "icon": "wrench.and.screwdriver"],
            "allowedExternalURLs": []
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: packageURL.appendingPathComponent("manifest.json"))
        if writesEntrypoint {
            try Data("<html></html>".utf8)
                .write(to: packageURL.appendingPathComponent("index.html"))
        }
        return packageURL
    }
}
