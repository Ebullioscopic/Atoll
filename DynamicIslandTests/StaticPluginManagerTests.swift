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

    private final class MutatingCopyFileManager: FileManager {
        var mutateCopiedPackage: ((URL) throws -> Void)?

        override func copyItem(at srcURL: URL, to dstURL: URL) throws {
            try super.copyItem(at: srcURL, to: dstURL)
            try mutateCopiedPackage?(dstURL)
        }
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

    func testInvalidStagedReplacementKeepsOldVersion() throws {
        let fileManager = MutatingCopyFileManager()
        let manager = makeManager(fileManager: fileManager)
        try manager.install(from: makePackage(version: "1.0.0"), replacingExisting: false)

        fileManager.mutateCopiedPackage = { stagedPackageURL in
            try FileManager.default.removeItem(
                at: stagedPackageURL.appendingPathComponent("index.html")
            )
        }

        XCTAssertThrowsError(
            try manager.install(from: makePackage(version: "2.0.0"), replacingExisting: true)
        ) { error in
            XCTAssertEqual(error as? StaticPluginValidationError, .unsafeEntrypoint)
        }

        fileManager.mutateCopiedPackage = nil
        manager.reload()
        XCTAssertEqual(manager.plugins.first?.manifest.version, "1.0.0")
    }

    func testStagedPluginIDChangeKeepsOldVersion() throws {
        let fileManager = MutatingCopyFileManager()
        let manager = makeManager(fileManager: fileManager)
        try manager.install(from: makePackage(version: "1.0.0"), replacingExisting: false)

        fileManager.mutateCopiedPackage = { stagedPackageURL in
            let manifestURL = stagedPackageURL.appendingPathComponent("manifest.json")
            var manifest = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
            )
            manifest["id"] = "com.example.changed"
            try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        }

        XCTAssertThrowsError(
            try manager.install(from: makePackage(version: "2.0.0"), replacingExisting: true)
        ) { error in
            XCTAssertEqual(
                error as? StaticPluginManagerError,
                .pluginChangedDuringInstall(
                    expectedID: "com.example.tools",
                    actualID: "com.example.changed"
                )
            )
        }

        fileManager.mutateCopiedPackage = nil
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

    func testReloadRejectsPackageWhoseDirectoryDoesNotMatchPluginID() throws {
        let manager = makeManager()
        let mismatchedURL = installationRootURL
            .appendingPathComponent("wrong-name.atollplugin", isDirectory: true)
        try FileManager.default.copyItem(at: makePackage(), to: mismatchedURL)

        manager.reload()

        XCTAssertTrue(manager.plugins.isEmpty)
        XCTAssertEqual(manager.discoveryErrors.count, 1)
    }

    func testReloadRevisionChangesForSameIDReplacement() throws {
        let manager = makeManager()
        try manager.install(from: makePackage(), replacingExisting: false)
        let installedRevision = manager.reloadRevision

        try manager.install(from: makePackage(), replacingExisting: true)

        XCTAssertGreaterThan(manager.reloadRevision, installedRevision)
    }

    private func makeManager(
        fileManager: FileManager = .default,
        replaceItem: StaticPluginManager.ReplaceItem? = nil
    ) -> StaticPluginManager {
        StaticPluginManager(
            installationRoot: installationRootURL,
            userDefaults: defaults,
            fileManager: fileManager,
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
