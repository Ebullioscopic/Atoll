import Foundation
import CodeIslandCore

/// Version errors that callers can distinguish from malformed archive data.
public enum SessionMetadataArchiveError: Error, Equatable {
    /// The archive uses a schema this runtime does not understand.
    case unsupportedSchemaVersion(Int)
}

/// A single codec shared by persistence and future user-initiated diagnostics.
public struct SessionMetadataArchiveCodec: Sendable {
    /// Schema written and accepted by this codec.
    public static let schemaVersion = 1

    /// Creates the stateless metadata archive codec.
    public init() {}

    /// Encodes sessions in stable provider/session order.
    public func encode(_ sessions: [SessionMetadata]) throws -> Data {
        let envelope = SessionMetadataEnvelope(
            schemaVersion: Self.schemaVersion,
            sessions: sessions.sorted(by: Self.sortSessions)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }

    /// Decodes an archive after enforcing the exact supported schema version.
    public func decode(_ data: Data) throws -> [SessionMetadata] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(SessionMetadataEnvelope.self, from: data)
        guard envelope.schemaVersion == Self.schemaVersion else {
            throw SessionMetadataArchiveError.unsupportedSchemaVersion(envelope.schemaVersion)
        }
        return envelope.sessions
    }

    private static func sortSessions(_ lhs: SessionMetadata, _ rhs: SessionMetadata) -> Bool {
        if lhs.provider.rawValue != rhs.provider.rawValue {
            return lhs.provider.rawValue < rhs.provider.rawValue
        }
        return lhs.sessionID.rawValue < rhs.sessionID.rawValue
    }
}

/// The narrow persistence seam consumed by a future Atoll host lifecycle.
public protocol SessionMetadataStoring: Sendable {
    /// Loads every persisted sanitized session.
    func load() throws -> [SessionMetadata]

    /// Atomically replaces the persisted sanitized sessions.
    func save(_ sessions: [SessionMetadata]) throws
}

/// File-backed metadata persistence with no default global location.
/// The Atoll host must explicitly supply its application-support URL.
public struct FileSessionMetadataStore: SessionMetadataStoring, Sendable {
    private let fileURL: URL
    private let codec: SessionMetadataArchiveCodec

    /// Creates a store at an explicit Atoll-owned location.
    public init(
        fileURL: URL,
        codec: SessionMetadataArchiveCodec = SessionMetadataArchiveCodec()
    ) {
        self.fileURL = fileURL.standardizedFileURL
        self.codec = codec
    }

    /// Returns an empty collection when no archive exists.
    public func load() throws -> [SessionMetadata] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try codec.decode(Data(contentsOf: fileURL))
    }

    /// Atomically writes a schema-versioned archive with user-only permissions.
    public func save(_ sessions: [SessionMetadata]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try codec.encode(sessions).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

private struct SessionMetadataEnvelope: Codable {
    let schemaVersion: Int
    let sessions: [SessionMetadata]
}
