import Foundation
import CryptoKit

public struct HookInstallationState: Codable, Sendable {
    public let helperPath: String
    public let helperVersion: String
    public let helperSHA256: String
    public let installedAt: Date
}

public struct HookInstaller {
    public let paths: AppPaths
    public let hooksConfigURL: URL
    private let fileManager: FileManager
    private let writer: AtomicFileWriter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(paths: AppPaths = .default, hooksConfigURL: URL? = nil, fileManager: FileManager = .default) {
        self.paths = paths
        let environmentHooksURL = ProcessInfo.processInfo.environment["ATOLL_CODEX_HOOKS_CONFIG"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        self.hooksConfigURL = hooksConfigURL
            ?? environmentHooksURL
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
        self.fileManager = fileManager
        self.writer = AtomicFileWriter(fileManager: fileManager)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public var helperURL: URL { paths.root.appendingPathComponent("bin/CodexHookHelper") }
    public var installationStateURL: URL { paths.root.appendingPathComponent("helper-installation.json") }
    public var helperCommand: String {
        let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        let helperPath = helperURL.standardizedFileURL.path
        if helperPath.hasPrefix(homePath + "/") {
            let relativePath = String(helperPath.dropFirst(homePath.count + 1))
            return "\"$HOME/\(relativePath)\""
        }
        return "\"\(helperPath)\""
    }

    public func readHooksConfig() throws -> JSONValue {
        guard fileManager.fileExists(atPath: hooksConfigURL.path) else { return .object([:]) }
        guard let data = try? Data(contentsOf: hooksConfigURL), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw HookConfigError.invalidJSON
        }
        return value
    }

    @discardableResult
    public func installHooks(events: [String]) throws -> HookMergeResult {
        let existing = try readHooksConfig()
        let result = try HookConfigMerger.merge(
            existing: existing,
            helperCommand: helperCommand,
            events: events
        )
        if result.modified {
            _ = try backupExistingHooksConfig()
            try writeHooksConfig(result.document)
        }
        return result
    }

    @discardableResult
    public func uninstallHooks() throws -> Int {
        let existing = try readHooksConfig()
        let result = try HookConfigMerger.remove(existing: existing, helperCommand: helperCommand)
        if result.removedCount > 0 {
            _ = try backupExistingHooksConfig()
            try writeHooksConfig(result.document)
        }
        return result.removedCount
    }

    @discardableResult
    public func backupExistingHooksConfig() throws -> URL? {
        guard fileManager.fileExists(atPath: hooksConfigURL.path) else { return nil }
        let backup = hooksConfigURL.deletingLastPathComponent().appendingPathComponent(
            "hooks.json.backup-\(Int(Date().timeIntervalSince1970 * 1_000))-\(UUID().uuidString)"
        )
        try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: hooksConfigURL, to: backup)
        return backup
    }

    public func writeHooksConfig(_ value: JSONValue) throws {
        try fileManager.createDirectory(at: hooksConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try writer.write(data, to: hooksConfigURL)
    }

    @discardableResult
    public func installHelper(from source: URL, version: String) throws -> URL {
        try fileManager.createDirectory(at: helperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Data(contentsOf: source)
        try writer.write(data, to: helperURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
        let state = HookInstallationState(
            helperPath: helperURL.path,
            helperVersion: version,
            helperSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            installedAt: Date()
        )
        try writer.write(try encoder.encode(state), to: installationStateURL)
        return helperURL
    }

    public func loadInstallationState() throws -> HookInstallationState? {
        guard fileManager.fileExists(atPath: installationStateURL.path) else { return nil }
        return try decoder.decode(HookInstallationState.self, from: Data(contentsOf: installationStateURL))
    }
}
