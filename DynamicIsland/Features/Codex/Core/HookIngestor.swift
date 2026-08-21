import Foundation

public struct HookIngestor {
    public let paths: AppPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let writer: AtomicFileWriter

    public init(paths: AppPaths = .default) {
        self.paths = paths
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.writer = AtomicFileWriter()
    }

    public func ingest(
        rawEvent: Data,
        receivedAt: Date = Date(),
        eventID: UUID = UUID()
    ) throws -> URL {
        let event = try decoder.decode(CodexHookEvent.self, from: rawEvent)
        let envelope = CodexHookEnvelope(
            eventID: eventID,
            receivedAt: receivedAt,
            payload: event
        )
        let data = try encoder.encode(envelope)
        try paths.prepareDirectories()
        let fileName = "\(Int(receivedAt.timeIntervalSince1970 * 1_000))-\(eventID.uuidString).json"
        let destination = paths.inbox.appendingPathComponent(fileName)
        try writer.write(data, to: destination)
        return destination
    }
}
