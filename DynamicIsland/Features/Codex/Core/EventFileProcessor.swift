import Foundation

public struct EventFileProcessor {
    public let paths: AppPaths
    private let decoder: JSONDecoder
    private let fileManager: FileManager

    public init(paths: AppPaths = .default, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    @discardableResult
    public func processInbox() throws -> ProcessingSummary {
        try processInbox { _ in }
    }

    @discardableResult
    public func processInbox(
        handling handler: (CodexHookEnvelope) throws -> Void
    ) throws -> ProcessingSummary {
        try paths.prepareDirectories(fileManager: fileManager)
        let files = try fileManager.contentsOfDirectory(
            at: paths.inbox,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var processed = 0
        var failed = 0
        for file in files {
            do {
                let envelope = try decoder.decode(CodexHookEnvelope.self, from: Data(contentsOf: file))
                try handler(envelope)
                try move(file, to: paths.processed)
                processed += 1
            } catch {
                try move(file, to: paths.failed)
                failed += 1
            }
        }
        return ProcessingSummary(scanned: files.count, processed: processed, failed: failed)
    }

    private func move(_ file: URL, to directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(file.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: file, to: destination)
    }
}

public struct ProcessingSummary: Equatable, Sendable {
    public let scanned: Int
    public let processed: Int
    public let failed: Int

    public init(scanned: Int, processed: Int, failed: Int) {
        self.scanned = scanned
        self.processed = processed
        self.failed = failed
    }
}
