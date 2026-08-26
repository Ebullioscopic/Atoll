/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import Combine
import Foundation

enum StaticPluginManagerError: LocalizedError, Equatable {
    case replacementConfirmationRequired(String)
    case pluginNotFound(String)
    case installedPackageNameMismatch(expected: String, actual: String)
    case pluginChangedDuringInstall(expectedID: String, actualID: String)

    var errorDescription: String? {
        switch self {
        case .replacementConfirmationRequired(let pluginID):
            return "A plugin with ID \(pluginID) is already installed. Confirm Replace to continue."
        case .pluginNotFound(let pluginID):
            return "The static plugin \(pluginID) is not installed."
        case .installedPackageNameMismatch(let expected, let actual):
            return "Installed plugin package \(actual) must be named \(expected)."
        case .pluginChangedDuringInstall(let expectedID, let actualID):
            return "Plugin ID changed from \(expectedID) to \(actualID) while it was being installed."
        }
    }
}

@MainActor
final class StaticPluginManager: ObservableObject {
    typealias ReplaceItem = (_ originalURL: URL, _ newURL: URL) throws -> Void

    static let shared = StaticPluginManager()

    /// 所有通过校验的已安装插件。
    @Published private(set) var plugins: [InstalledStaticPlugin] = []
    /// 当前被用户禁用的插件 ID；独立存储以避免修改插件包。
    @Published private(set) var disabledPluginIDs: Set<String>
    /// 扫描时发现但无法加载的插件错误。
    @Published private(set) var discoveryErrors: [String] = []
    /// 每次重新扫描后递增，使同 ID Replace 也能触发界面和窗口刷新。
    @Published private(set) var reloadRevision: UInt = 0

    private let installationRoot: URL
    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let validator: StaticPluginPackageValidator
    private let replaceItem: ReplaceItem
    private static let disabledPluginIDsKey = "disabledStaticPluginIDs"

    var enabledPlugins: [InstalledStaticPlugin] {
        plugins.filter { !disabledPluginIDs.contains($0.id) }
    }

    init(
        installationRoot: URL? = nil,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        replaceItem: ReplaceItem? = nil
    ) {
        let resolvedRoot = installationRoot ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("StaticPlugins", isDirectory: true)
        self.installationRoot = resolvedRoot
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.validator = StaticPluginPackageValidator(fileManager: fileManager)
        self.disabledPluginIDs = Set(userDefaults.stringArray(forKey: Self.disabledPluginIDsKey) ?? [])
        self.replaceItem = replaceItem ?? { originalURL, newURL in
            _ = try fileManager.replaceItemAt(
                originalURL,
                withItemAt: newURL,
                backupItemName: nil,
                options: []
            )
        }
        reload()
    }

    /// 重新扫描安装目录；单个坏包不会阻止其他插件加载。
    func reload() {
        defer { reloadRevision &+= 1 }
        do {
            try fileManager.createDirectory(at: installationRoot, withIntermediateDirectories: true)
            let packageURLs = try fileManager.contentsOfDirectory(
                at: installationRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            var loadedPlugins: [InstalledStaticPlugin] = []
            var errors: [String] = []
            for packageURL in packageURLs
                .filter({ $0.pathExtension.lowercased() == "atollplugin" })
                .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                do {
                    let plugin = try validator.validate(packageURL: packageURL)
                    let expectedName = installedPackageName(for: plugin.id)
                    guard packageURL.lastPathComponent == expectedName else {
                        throw StaticPluginManagerError.installedPackageNameMismatch(
                            expected: expectedName,
                            actual: packageURL.lastPathComponent
                        )
                    }
                    loadedPlugins.append(plugin)
                } catch {
                    errors.append("\(packageURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            plugins = loadedPlugins.sorted {
                $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending
            }
            discoveryErrors = errors
        } catch {
            plugins = []
            discoveryErrors = [error.localizedDescription]
        }
    }

    /// 安装新插件；相同 ID 只有在明确确认后才替换。
    func install(from sourceURL: URL, replacingExisting: Bool) throws {
        let sourcePlugin = try validator.validate(packageURL: sourceURL)
        try fileManager.createDirectory(at: installationRoot, withIntermediateDirectories: true)
        let destinationURL = installedURL(for: sourcePlugin.id)
        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
        if destinationExists && !replacingExisting {
            throw StaticPluginManagerError.replacementConfirmationRequired(sourcePlugin.id)
        }

        let stagingParentURL = installationRoot
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagedPackageURL = stagingParentURL
            .appendingPathComponent("\(sourcePlugin.id).atollplugin", isDirectory: true)
        try fileManager.createDirectory(at: stagingParentURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingParentURL) }

        try fileManager.copyItem(at: sourceURL, to: stagedPackageURL)
        let stagedPlugin = try validator.validate(packageURL: stagedPackageURL)
        guard stagedPlugin.id == sourcePlugin.id else {
            throw StaticPluginManagerError.pluginChangedDuringInstall(
                expectedID: sourcePlugin.id,
                actualID: stagedPlugin.id
            )
        }

        if destinationExists {
            try replaceItem(destinationURL, stagedPackageURL)
        } else {
            try fileManager.moveItem(at: stagedPackageURL, to: destinationURL)
        }
        reload()
    }

    /// 更新启用状态并立即发布标签页变化。
    func setEnabled(_ enabled: Bool, pluginID: String) {
        guard plugins.contains(where: { $0.id == pluginID }) else { return }
        var updatedIDs = disabledPluginIDs
        if enabled {
            updatedIDs.remove(pluginID)
        } else {
            updatedIDs.insert(pluginID)
        }
        disabledPluginIDs = updatedIDs
        persistDisabledPluginIDs()
    }

    /// 返回插件当前是否被用户禁用。
    func isDisabled(pluginID: String) -> Bool {
        disabledPluginIDs.contains(pluginID)
    }

    /// 删除指定插件及其禁用状态。
    func remove(pluginID: String) throws {
        guard plugins.contains(where: { $0.id == pluginID }) else {
            throw StaticPluginManagerError.pluginNotFound(pluginID)
        }
        try fileManager.removeItem(at: installedURL(for: pluginID))
        var updatedIDs = disabledPluginIDs
        updatedIDs.remove(pluginID)
        disabledPluginIDs = updatedIDs
        persistDisabledPluginIDs()
        reload()
    }

    private func installedURL(for pluginID: String) -> URL {
        installationRoot.appendingPathComponent(installedPackageName(for: pluginID), isDirectory: true)
    }

    private func installedPackageName(for pluginID: String) -> String {
        "\(pluginID).atollplugin"
    }

    private func persistDisabledPluginIDs() {
        userDefaults.set(disabledPluginIDs.sorted(), forKey: Self.disabledPluginIDsKey)
    }
}
