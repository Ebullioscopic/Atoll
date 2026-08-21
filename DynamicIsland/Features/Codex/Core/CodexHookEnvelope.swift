import Foundation

public struct CodexHookEnvelope: Codable, Equatable, Sendable {
    public let eventID: UUID
    public let receivedAt: Date
    public let source: String
    public let payload: CodexHookEvent

    public init(
        eventID: UUID = UUID(),
        receivedAt: Date = Date(),
        source: String = "codex-hook",
        payload: CodexHookEvent
    ) {
        self.eventID = eventID
        self.receivedAt = receivedAt
        self.source = source
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case receivedAt = "received_at"
        case source
        case payload
    }
}
