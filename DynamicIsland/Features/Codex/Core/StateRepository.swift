import Foundation

public struct StateRepository {
    public let paths: AppPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let writer: AtomicFileWriter
    private let fileManager: FileManager

    public init(paths: AppPaths = .default, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.writer = AtomicFileWriter(fileManager: fileManager)
    }

    public func load() throws -> CodexTaskStoreSnapshot {
        try paths.prepareDirectories(fileManager: fileManager)
        guard fileManager.fileExists(atPath: paths.stateFile.path) else { return .empty }
        do {
            return try decoder.decode(CodexTaskStoreSnapshot.self, from: Data(contentsOf: paths.stateFile))
        } catch {
            let backup = paths.stateDirectory.appendingPathComponent(
                "tasks.corrupt-\(Int(Date().timeIntervalSince1970)).json"
            )
            try? fileManager.moveItem(at: paths.stateFile, to: backup)
            return .empty
        }
    }

    public func save(_ snapshot: CodexTaskStoreSnapshot) throws {
        try paths.prepareDirectories(fileManager: fileManager)
        var snapshot = snapshot
        snapshot.savedAt = Date()
        try writer.write(try encoder.encode(snapshot), to: paths.stateFile)
    }
}
