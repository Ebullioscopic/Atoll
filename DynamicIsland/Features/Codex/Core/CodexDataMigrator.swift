import Foundation

public struct CodexMigrationResult: Equatable, Sendable {
    public let importedLegacyState: Bool
    public let wasAlreadyCompleted: Bool

    public init(importedLegacyState: Bool, wasAlreadyCompleted: Bool) {
        self.importedLegacyState = importedLegacyState
        self.wasAlreadyCompleted = wasAlreadyCompleted
    }
}

public struct CodexDataMigrator {
    public static let currentVersion = 1

    public let paths: AppPaths
    public let legacyPaths: AppPaths
    private let fileManager: FileManager
    private let writer: AtomicFileWriter
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        paths: AppPaths = .default,
        legacyPaths: AppPaths = .legacy,
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.legacyPaths = legacyPaths
        self.fileManager = fileManager
        self.writer = AtomicFileWriter(fileManager: fileManager)
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    public func migrateIfNeeded(now: Date = Date()) throws -> CodexMigrationResult {
        try paths.prepareDirectories(fileManager: fileManager)

        if let state = try loadMigrationState(), state.version >= Self.currentVersion {
            return CodexMigrationResult(importedLegacyState: false, wasAlreadyCompleted: true)
        }

        var importedLegacyState = false
        if !fileManager.fileExists(atPath: paths.stateFile.path),
           fileManager.fileExists(atPath: legacyPaths.stateFile.path) {
            let legacyState = try Data(contentsOf: legacyPaths.stateFile)
            try writer.write(legacyState, to: paths.stateFile)
            importedLegacyState = true
        }

        let state = MigrationState(
            version: Self.currentVersion,
            importedLegacyState: importedLegacyState,
            migratedAt: now
        )
        try writer.write(try encoder.encode(state), to: paths.migrationStateFile)
        return CodexMigrationResult(
            importedLegacyState: importedLegacyState,
            wasAlreadyCompleted: false
        )
    }

    private func loadMigrationState() throws -> MigrationState? {
        guard fileManager.fileExists(atPath: paths.migrationStateFile.path) else { return nil }
        return try decoder.decode(MigrationState.self, from: Data(contentsOf: paths.migrationStateFile))
    }
}

private struct MigrationState: Codable {
    let version: Int
    let importedLegacyState: Bool
    let migratedAt: Date
}
