import Foundation

public struct CodexDiagnosticsSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let activeSessionCount: Int
    public let runningCount: Int
    public let waitingCount: Int
    public let staleCount: Int
    public let recentCompletionCount: Int
    public let inboxPendingCount: Int
    public let failedEventCount: Int
    public let lastEventAt: Date?
    public let helperPath: String?
    public let helperVersion: String?

    public init(
        generatedAt: Date = Date(),
        activeSessionCount: Int,
        runningCount: Int,
        waitingCount: Int,
        staleCount: Int,
        recentCompletionCount: Int,
        inboxPendingCount: Int,
        failedEventCount: Int,
        lastEventAt: Date?,
        helperPath: String? = nil,
        helperVersion: String? = nil
    ) {
        self.generatedAt = generatedAt
        self.activeSessionCount = activeSessionCount
        self.runningCount = runningCount
        self.waitingCount = waitingCount
        self.staleCount = staleCount
        self.recentCompletionCount = recentCompletionCount
        self.inboxPendingCount = inboxPendingCount
        self.failedEventCount = failedEventCount
        self.lastEventAt = lastEventAt
        self.helperPath = helperPath
        self.helperVersion = helperVersion
    }

    public func redactedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

public struct DiagnosticsCollector {
    public let paths: AppPaths
    private let fileManager: FileManager

    public init(paths: AppPaths = .default, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func collect(
        snapshot: CodexTaskStoreSnapshot,
        generatedAt: Date = Date(),
        helperPath: String? = nil,
        helperVersion: String? = nil
    ) throws -> CodexDiagnosticsSnapshot {
        let pending = try countJSONFiles(in: paths.inbox)
        let failed = try countJSONFiles(in: paths.failed)
        let active = snapshot.tasks.filter {
            $0.status == .running || $0.status == .waitingForApproval
        }
        return CodexDiagnosticsSnapshot(
            generatedAt: generatedAt,
            activeSessionCount: active.count,
            runningCount: active.filter { $0.status == .running }.count,
            waitingCount: active.filter { $0.status == .waitingForApproval }.count,
            staleCount: snapshot.tasks.filter { $0.status == .stale }.count,
            recentCompletionCount: snapshot.recentCompletions.count,
            inboxPendingCount: pending,
            failedEventCount: failed,
            lastEventAt: snapshot.tasks.map(\.lastActivityAt).max(),
            helperPath: helperPath,
            helperVersion: helperVersion
        )
    }

    private func countJSONFiles(in directory: URL) throws -> Int {
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.count
    }
}
