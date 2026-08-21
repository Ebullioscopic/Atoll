import Foundation

public struct AppPaths: Sendable {
    public let root: URL

    public nonisolated init(root: URL) {
        self.root = root
    }

    public nonisolated static var `default`: AppPaths {
        if let override = ProcessInfo.processInfo.environment["ATOLL_CODEX_DATA_ROOT"],
           !override.isEmpty {
            return AppPaths(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        return AppPaths(
            root: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Atoll/Codex", isDirectory: true)
        )
    }

    public nonisolated static var legacy: AppPaths {
        if let override = ProcessInfo.processInfo.environment["ATOLL_CODEX_LEGACY_DATA_ROOT"],
           !override.isEmpty {
            return AppPaths(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        return AppPaths(
            root: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/CodexAtoll", isDirectory: true)
        )
    }

    public var inbox: URL { root.appendingPathComponent("inbox", isDirectory: true) }
    public var processed: URL { root.appendingPathComponent("processed", isDirectory: true) }
    public var failed: URL { root.appendingPathComponent("failed", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
    public var stateDirectory: URL { root.appendingPathComponent("state", isDirectory: true) }
    public var stateFile: URL { stateDirectory.appendingPathComponent("tasks.json") }
    public var migrationStateFile: URL { root.appendingPathComponent("migration.json") }

    public func prepareDirectories(fileManager: FileManager = .default) throws {
        for directory in [root, inbox, processed, failed, logs, stateDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
