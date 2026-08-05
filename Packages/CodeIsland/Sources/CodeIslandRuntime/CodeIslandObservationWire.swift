import CodeIslandCore
import Foundation

/// Failures raised before a listener accepts a metadata-only observation.
public enum CodeIslandObservationWireError: Error, Equatable {
    case envelopeTooLarge
    case invalidSchema
    case unsupportedSchemaVersion(Int)
}

/// The sole wire codec shared by Atoll's helper and observation listener.
///
/// It deliberately reconstructs every domain value through its validating
/// initializer and rejects unknown JSON keys. Provider payload dictionaries
/// therefore cannot be tunneled through this seam.
public struct CodeIslandObservationWireCodec: Sendable {
    public static let schemaVersion = 1
    public static let maximumEnvelopeSize = 32_768

    public init() {}

    public func encode(_ observation: SessionObservation) throws -> Data {
        let envelope = Envelope(
            schemaVersion: Self.schemaVersion,
            observation: ObservationValue(observation)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(envelope)
        guard data.count <= Self.maximumEnvelopeSize else {
            throw CodeIslandObservationWireError.envelopeTooLarge
        }
        return data
    }

    public func decode(_ data: Data) throws -> SessionObservation {
        guard data.count <= Self.maximumEnvelopeSize else {
            throw CodeIslandObservationWireError.envelopeTooLarge
        }
        try validateKeys(in: data)
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw CodeIslandObservationWireError.invalidSchema
        }
        guard envelope.schemaVersion == Self.schemaVersion else {
            throw CodeIslandObservationWireError.unsupportedSchemaVersion(
                envelope.schemaVersion
            )
        }
        return try envelope.observation.domainValue()
    }

    private func validateKeys(in data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(root.keys).isSubset(of: ["schemaVersion", "observation"]),
              root["schemaVersion"] != nil,
              let observation = root["observation"] as? [String: Any],
              Set(observation.keys).isSubset(of: [
                "provider", "sessionID", "project", "origin", "transition", "observedAt",
              ]),
              observation["provider"] != nil,
              observation["sessionID"] != nil,
              observation["transition"] != nil,
              observation["observedAt"] != nil
        else {
            throw CodeIslandObservationWireError.invalidSchema
        }

        if let project = observation["project"] as? [String: Any] {
            guard Set(project.keys).isSubset(of: ["displayName", "workingDirectory"]),
                  project["displayName"] != nil else {
                throw CodeIslandObservationWireError.invalidSchema
            }
        } else if observation["project"] is NSNull == false,
                  observation["project"] != nil {
            throw CodeIslandObservationWireError.invalidSchema
        }

        if let origin = observation["origin"] as? [String: Any] {
            guard Set(origin.keys).isSubset(of: [
                "applicationBundleIdentifier",
                "terminalSessionIdentifier",
                "workspaceIdentifier",
                "paneIdentifier",
                "tty",
            ]) else {
                throw CodeIslandObservationWireError.invalidSchema
            }
        } else if observation["origin"] is NSNull == false,
                  observation["origin"] != nil {
            throw CodeIslandObservationWireError.invalidSchema
        }
    }
}

private struct Envelope: Codable {
    let schemaVersion: Int
    let observation: ObservationValue
}

private struct ObservationValue: Codable {
    let provider: AgentProvider
    let sessionID: String
    let project: ProjectValue?
    let origin: OriginValue?
    let transition: TransitionValue
    let observedAt: TimeInterval

    init(_ observation: SessionObservation) {
        provider = observation.provider
        sessionID = observation.sessionID.rawValue
        project = observation.project.map(ProjectValue.init)
        origin = observation.origin.map(OriginValue.init)
        transition = TransitionValue(observation.transition)
        observedAt = observation.observedAt.timeIntervalSince1970
    }

    func domainValue() throws -> SessionObservation {
        guard provider == .codex,
              let sessionID = OpaqueSessionID(sessionID),
              observedAt.isFinite,
              let transition = transition.domainValue else {
            throw CodeIslandObservationWireError.invalidSchema
        }

        let project: ProjectIdentity?
        if let value = self.project {
            guard let validated = ProjectIdentity(
                displayName: value.displayName,
                workingDirectory: value.workingDirectory
            ) else {
                throw CodeIslandObservationWireError.invalidSchema
            }
            project = validated
        } else {
            project = nil
        }

        let origin = self.origin.map {
            OriginNavigation(
                applicationBundleIdentifier: $0.applicationBundleIdentifier,
                terminalSessionIdentifier: $0.terminalSessionIdentifier,
                workspaceIdentifier: $0.workspaceIdentifier,
                paneIdentifier: $0.paneIdentifier,
                tty: $0.tty
            )
        }
        if self.origin != nil, origin?.isEmpty != false {
            throw CodeIslandObservationWireError.invalidSchema
        }

        return SessionObservation(
            provider: provider,
            sessionID: sessionID,
            project: project,
            origin: origin,
            transition: transition,
            observedAt: Date(timeIntervalSince1970: observedAt)
        )
    }
}

private struct ProjectValue: Codable {
    let displayName: String
    let workingDirectory: String?

    init(_ project: ProjectIdentity) {
        displayName = project.displayName
        workingDirectory = project.workingDirectory
    }
}

private struct OriginValue: Codable {
    let applicationBundleIdentifier: String?
    let terminalSessionIdentifier: String?
    let workspaceIdentifier: String?
    let paneIdentifier: String?
    let tty: String?

    init(_ origin: OriginNavigation) {
        applicationBundleIdentifier = origin.applicationBundleIdentifier
        terminalSessionIdentifier = origin.terminalSessionIdentifier
        workspaceIdentifier = origin.workspaceIdentifier
        paneIdentifier = origin.paneIdentifier
        tty = origin.tty
    }
}

private enum TransitionValue: String, Codable {
    case started
    case active
    case waitingForApproval
    case waitingForQuestion
    case completed
    case failed
    case cancelled
    case ended

    init(_ transition: SessionTransition) {
        switch transition {
        case .started: self = .started
        case .active: self = .active
        case .waitingForOrigin(.approval): self = .waitingForApproval
        case .waitingForOrigin(.question): self = .waitingForQuestion
        case .completed: self = .completed
        case .failed: self = .failed
        case .cancelled: self = .cancelled
        case .ended: self = .ended
        }
    }

    var domainValue: SessionTransition? {
        switch self {
        case .started: return .started
        case .active: return .active
        case .waitingForApproval: return .waitingForOrigin(.approval)
        case .waitingForQuestion: return .waitingForOrigin(.question)
        case .completed: return .completed
        case .failed: return .failed
        case .cancelled: return .cancelled
        case .ended: return .ended
        }
    }
}
