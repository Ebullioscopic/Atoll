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

enum StaticPluginValidationError: LocalizedError, Equatable {
    case notPluginDirectory
    case symbolicLink(String)
    case missingManifest
    case unreadableManifest
    case unsupportedSchema(Int)
    case invalidIdentifier
    case emptyDisplayValue(String)
    case unsafeEntrypoint
    case invalidExternalURL(String)
    case invalidExternalURLPrefix(String)

    var errorDescription: String? {
        switch self {
        case .notPluginDirectory:
            return "Select a directory ending in .atollplugin."
        case .symbolicLink(let path):
            return "Plugin packages cannot contain symbolic links: \(path)"
        case .missingManifest:
            return "The plugin does not contain a regular manifest.json file."
        case .unreadableManifest:
            return "The plugin manifest is not valid JSON."
        case .unsupportedSchema(let version):
            return "Plugin schema version \(version) is not supported."
        case .invalidIdentifier:
            return "The plugin ID must use a reverse-DNS-style value."
        case .emptyDisplayValue(let field):
            return "The plugin manifest field \(field) cannot be empty."
        case .unsafeEntrypoint:
            return "The plugin entry point must be a regular HTML file inside the package."
        case .invalidExternalURL(let value):
            return "External URL is not an absolute HTTP or HTTPS URL: \(value)"
        case .invalidExternalURLPrefix(let value):
            return "External URL prefix must be an absolute HTTP or HTTPS URL ending in ?: \(value)"
        }
    }
}

struct StaticPluginPackageValidator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// 校验未受信任的插件目录，并只返回已完成路径约束检查的数据。
    func validate(packageURL: URL) throws -> InstalledStaticPlugin {
        let sourceValues = try? packageURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard packageURL.pathExtension.lowercased() == "atollplugin",
              sourceValues?.isDirectory == true else {
            throw StaticPluginValidationError.notPluginDirectory
        }
        if sourceValues?.isSymbolicLink == true {
            throw StaticPluginValidationError.symbolicLink(packageURL.lastPathComponent)
        }

        try rejectSymbolicLinks(in: packageURL)
        let rootURL = packageURL.standardizedFileURL.resolvingSymlinksInPath()
        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        guard isRegularFile(manifestURL) else {
            throw StaticPluginValidationError.missingManifest
        }

        let manifest: StaticPluginManifest
        do {
            manifest = try JSONDecoder().decode(
                StaticPluginManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw StaticPluginValidationError.unreadableManifest
        }

        guard manifest.schemaVersion == 1 else {
            throw StaticPluginValidationError.unsupportedSchema(manifest.schemaVersion)
        }
        guard isValidIdentifier(manifest.id) else {
            throw StaticPluginValidationError.invalidIdentifier
        }
        try requireDisplayValue(manifest.name, field: "name")
        try requireDisplayValue(manifest.version, field: "version")
        try requireDisplayValue(manifest.tab.title, field: "tab.title")

        let entrypointURL = rootURL
            .appendingPathComponent(manifest.entrypoint)
            .standardizedFileURL
              .resolvingSymlinksInPath()
        guard entrypointURL.pathExtension.lowercased() == "html",
              isContained(entrypointURL, by: rootURL),
              isRegularFile(entrypointURL) else {
            throw StaticPluginValidationError.unsafeEntrypoint
        }

        let externalURLs = try Set(manifest.allowedExternalURLs.map(validateExternalURL))
        let externalURLPrefixes = try Set(
            manifest.allowedExternalURLPrefixes.map(validateExternalURLPrefix)
        )
        return InstalledStaticPlugin(
            manifest: manifest,
            rootURL: rootURL,
            entrypointURL: entrypointURL,
            allowedExternalURLs: externalURLs,
            allowedExternalURLPrefixes: externalURLPrefixes
        )
    }

    private func rejectSymbolicLinks(in rootURL: URL) throws {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: []
        ) else {
            throw StaticPluginValidationError.notPluginDirectory
        }
        for case let itemURL as URL in enumerator {
            if try itemURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
                throw StaticPluginValidationError.symbolicLink(itemURL.lastPathComponent)
            }
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private func isValidIdentifier(_ identifier: String) -> Bool {
        let segments = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy { segment in
            segment.range(
                of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$"#,
                options: .regularExpression
            ) != nil
        }
    }

    private func requireDisplayValue(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StaticPluginValidationError.emptyDisplayValue(field)
        }
    }

    private func validateExternalURL(_ value: String) throws -> URL {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw StaticPluginValidationError.invalidExternalURL(value)
        }
        return url
    }

    /// 动态 URL 前缀必须在查询分隔符处结束，避免主机名或路径的文本前缀误匹配。
    private func validateExternalURLPrefix(_ value: String) throws -> String {
        guard value.hasSuffix("?"),
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.fragment == nil else {
            throw StaticPluginValidationError.invalidExternalURLPrefix(value)
        }
        return value
    }

    private func isContained(_ candidateURL: URL, by rootURL: URL) -> Bool {
        candidateURL.path == rootURL.path || candidateURL.path.hasPrefix(rootURL.path + "/")
    }
}
