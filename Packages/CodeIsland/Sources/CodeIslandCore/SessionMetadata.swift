import Foundation

/// A coding tool whose observations can be normalized by Code Island.
public enum AgentProvider: String, Codable, CaseIterable, Sendable {
    /// OpenAI Codex CLI or app sessions observed through a verified contract.
    case codex
}

/// A provider-owned identifier treated only as an opaque lookup key.
///
/// Restricting the representation prevents content-like values from being
/// smuggled into the metadata archive through an identifier field.
public struct OpaqueSessionID: Hashable, Sendable {
    /// The validated provider key. Callers must not infer structure from it.
    public let rawValue: String

    /// Creates an identifier from a bounded ASCII provider key.
    /// - Parameter rawValue: A 1-256 byte identifier using letters, digits,
    ///   `-`, `.`, `:`, `@`, or `_`.
    public init?(_ rawValue: String) {
        guard !rawValue.isEmpty,
              rawValue.utf8.count <= 256,
              rawValue.utf8.allSatisfy(Self.isAllowedByte) else {
            return nil
        }
        self.rawValue = rawValue
    }

    private static func isAllowedByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 48...57, 65...90, 97...122:
            return true
        case 45, 46, 58, 64, 95: // - . : @ _
            return true
        default:
            return false
        }
    }
}

extension OpaqueSessionID: Codable {
    /// Decodes and revalidates a single-value identifier.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = OpaqueSessionID(rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid opaque session identifier"
            )
        }
        self = value
    }

    /// Encodes the identifier as a single string value.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Project information permitted in the metadata projection.
public struct ProjectIdentity: Codable, Equatable, Sendable {
    /// A compact project label safe for the dashboard.
    public let displayName: String

    /// The optional project path used for identity and origin navigation.
    public let workingDirectory: String?

    /// Creates an explicitly named project identity.
    /// - Parameters:
    ///   - displayName: The project label, limited to 255 UTF-8 bytes.
    ///   - workingDirectory: An optional path, limited to 4,096 UTF-8 bytes.
    public init?(displayName: String, workingDirectory: String? = nil) {
        guard let displayName = MetadataFieldSanitizer.value(displayName, maximumUTF8Count: 255) else {
            return nil
        }
        self.displayName = displayName
        self.workingDirectory = MetadataFieldSanitizer.value(
            workingDirectory,
            maximumUTF8Count: 4_096
        )
    }

    /// Creates a project identity whose label is the path's final component.
    /// - Parameter workingDirectory: The project path to standardize.
    public init?(workingDirectory: String) {
        guard let directory = MetadataFieldSanitizer.value(
            workingDirectory,
            maximumUTF8Count: 4_096
        ) else {
            return nil
        }

        let standardized = URL(fileURLWithPath: directory).standardizedFileURL.path
        let lastComponent = (standardized as NSString).lastPathComponent
        let displayName = lastComponent.isEmpty ? standardized : lastComponent
        self.init(displayName: displayName, workingDirectory: standardized)
    }
}

/// Navigation-only handles used to return to the exact originating surface.
public struct OriginNavigation: Codable, Equatable, Sendable {
    /// Bundle identifier of the terminal or native origin application.
    public let applicationBundleIdentifier: String?

    /// Terminal-emulator session identifier, when one is available.
    public let terminalSessionIdentifier: String?

    /// Workspace identifier for a terminal or multiplexer.
    public let workspaceIdentifier: String?

    /// Pane, surface, window, or terminal identifier within the workspace.
    public let paneIdentifier: String?

    /// TTY path used as a precise terminal-session handle.
    public let tty: String?

    /// Creates navigation metadata from any handles known at observation time.
    public init(
        applicationBundleIdentifier: String?,
        terminalSessionIdentifier: String?,
        workspaceIdentifier: String?,
        paneIdentifier: String?,
        tty: String?
    ) {
        self.applicationBundleIdentifier = MetadataFieldSanitizer.value(
            applicationBundleIdentifier,
            maximumUTF8Count: 255
        )
        self.terminalSessionIdentifier = MetadataFieldSanitizer.value(
            terminalSessionIdentifier,
            maximumUTF8Count: 512
        )
        self.workspaceIdentifier = MetadataFieldSanitizer.value(
            workspaceIdentifier,
            maximumUTF8Count: 512
        )
        self.paneIdentifier = MetadataFieldSanitizer.value(
            paneIdentifier,
            maximumUTF8Count: 512
        )
        self.tty = MetadataFieldSanitizer.value(tty, maximumUTF8Count: 4_096)
    }

    /// Whether the value contains no usable navigation handle.
    public var isEmpty: Bool {
        applicationBundleIdentifier == nil
            && terminalSessionIdentifier == nil
            && workspaceIdentifier == nil
            && paneIdentifier == nil
            && tty == nil
    }
}

/// The complete set of states allowed in a persisted session projection.
public enum SessionState: String, Codable, Sendable {
    /// The agent is currently executing or processing.
    case working

    /// The origin is presenting a provider-owned approval prompt.
    case waitingForApproval

    /// The origin is presenting a provider-owned question.
    case waitingForQuestion

    /// A turn completed recently and may receive a short presentation.
    case recentlyCompleted

    /// A meaningful provider operation failed.
    case failed

    /// The session or observation was cancelled at its origin.
    case cancelled

    /// The provider session ended.
    case ended

    /// Whether the state records an end timestamp in the metadata projection.
    public var isTerminal: Bool {
        switch self {
        case .working, .waitingForApproval, .waitingForQuestion:
            return false
        case .recentlyCompleted, .failed, .cancelled, .ended:
            return true
        }
    }
}

/// The only representation that may be written to disk or exported.
public struct SessionMetadata: Codable, Equatable, Sendable {
    /// Provider that owns the session.
    public let provider: AgentProvider

    /// Opaque provider-owned session key.
    public let sessionID: OpaqueSessionID

    /// Optional project identity permitted for display and navigation.
    public let project: ProjectIdentity?

    /// Optional handles used to return to the origin surface.
    public let origin: OriginNavigation?

    /// Latest derived, content-free session state.
    public let state: SessionState

    /// Time the current projection first observed this session.
    public let startedAt: Date

    /// Time the latest accepted observation was applied.
    public let updatedAt: Date

    /// Time a terminal state was observed, or `nil` for an active state.
    public let endedAt: Date?

    /// Creates the complete metadata-only session projection.
    public init(
        provider: AgentProvider,
        sessionID: OpaqueSessionID,
        project: ProjectIdentity?,
        origin: OriginNavigation?,
        state: SessionState,
        startedAt: Date,
        updatedAt: Date,
        endedAt: Date?
    ) {
        self.provider = provider
        self.sessionID = sessionID
        self.project = project
        self.origin = origin?.isEmpty == true ? nil : origin
        self.state = state
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.endedAt = endedAt
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case sessionID
        case project
        case origin
        case state
        case startedAt
        case updatedAt
        case endedAt
    }

    /// Decodes the fixed metadata-only schema.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(AgentProvider.self, forKey: .provider)
        sessionID = try container.decode(OpaqueSessionID.self, forKey: .sessionID)
        project = try container.decodeIfPresent(ProjectIdentity.self, forKey: .project)
        origin = try container.decodeIfPresent(OriginNavigation.self, forKey: .origin)
        state = try container.decode(SessionState.self, forKey: .state)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
    }

    /// Encodes every fixed schema key, including explicit `null` optionals.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(project, forKey: .project)
        try container.encode(origin, forKey: .origin)
        try container.encode(state, forKey: .state)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(endedAt, forKey: .endedAt)
    }
}

private enum MetadataFieldSanitizer {
    static func value(_ rawValue: String?, maximumUTF8Count: Int) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= maximumUTF8Count,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return nil
        }
        return value
    }
}
