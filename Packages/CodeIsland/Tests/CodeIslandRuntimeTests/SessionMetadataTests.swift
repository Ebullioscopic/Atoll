import Foundation
import XCTest
import CodeIslandCore
@testable import CodeIslandRuntime

final class SessionMetadataTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_754_275_200)

    func testProjectionRetainsOnlySanitizedIdentityStateOriginAndTimestamps() throws {
        let sessionID = try XCTUnwrap(OpaqueSessionID("thr_123-safe"))
        let project = try XCTUnwrap(ProjectIdentity(workingDirectory: "/workspace/atoll"))
        let origin = OriginNavigation(
            applicationBundleIdentifier: "com.example.Terminal",
            terminalSessionIdentifier: "session-1",
            workspaceIdentifier: "workspace-1",
            paneIdentifier: "pane-1",
            tty: "/dev/ttys001"
        )
        let projector = SessionMetadataProjector()

        let started = projector.applying(
            SessionObservation(
                provider: .codex,
                sessionID: sessionID,
                project: project,
                origin: origin,
                transition: .started,
                observedAt: timestamp
            ),
            to: nil
        )
        let waiting = projector.applying(
            SessionObservation(
                provider: .codex,
                sessionID: sessionID,
                project: nil,
                origin: nil,
                transition: .waitingForOrigin(.approval),
                observedAt: timestamp.addingTimeInterval(3)
            ),
            to: started
        )

        XCTAssertEqual(waiting.provider, .codex)
        XCTAssertEqual(waiting.sessionID, sessionID)
        XCTAssertEqual(waiting.project, project)
        XCTAssertEqual(waiting.origin, origin)
        XCTAssertEqual(waiting.state, .waitingForApproval)
        XCTAssertEqual(waiting.startedAt, timestamp)
        XCTAssertEqual(waiting.updatedAt, timestamp.addingTimeInterval(3))
        XCTAssertNil(waiting.endedAt)
    }

    func testOpaqueSessionIDRejectsContentLikeOrOversizedValues() {
        XCTAssertNotNil(OpaqueSessionID("thr_abc-123:child"))
        XCTAssertNil(OpaqueSessionID("please approve this command"))
        XCTAssertNil(OpaqueSessionID(String(repeating: "x", count: 257)))
    }

    func testProjectorIgnoresAnOutOfOrderObservation() throws {
        let current = try makeMetadata(updatedAt: timestamp.addingTimeInterval(10))
        let staleObservation = SessionObservation(
            provider: .codex,
            sessionID: current.sessionID,
            project: nil,
            origin: nil,
            transition: .failed,
            observedAt: timestamp
        )

        XCTAssertEqual(
            SessionMetadataProjector().applying(staleObservation, to: current),
            current
        )
    }

    func testArchiveRoundTripsWithAWhitelistedJSONShape() throws {
        let metadata = try makeMetadata()
        let codec = SessionMetadataArchiveCodec()
        let encoded = try codec.encode([metadata])
        let decoded = try codec.decode(encoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(decoded, [metadata])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "sessions"])
        XCTAssertEqual(Set(try XCTUnwrap((object["sessions"] as? [[String: Any]])?.first).keys), [
            "endedAt", "origin", "project", "provider", "sessionID", "startedAt", "state", "updatedAt",
        ])

        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for forbiddenValue in [
            "private user prompt",
            "private assistant response",
            "rm -rf private-command",
            "which option should I choose",
            "private tool input",
            "raw-provider-payload",
        ] {
            XCTAssertFalse(json.contains(forbiddenValue))
        }
    }

    func testFileStoreReturnsEmptyForMissingFileAndRoundTripsMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSessionMetadataStore(
            fileURL: directory.appendingPathComponent("sessions.json")
        )

        XCTAssertEqual(try store.load(), [])

        let metadata = try makeMetadata()
        try store.save([metadata])

        XCTAssertEqual(try store.load(), [metadata])
        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("sessions.json").path
        )
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testArchiveRejectsAnUnsupportedSchemaVersion() throws {
        let codec = SessionMetadataArchiveCodec()
        let encoded = try codec.encode([try makeMetadata()])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["schemaVersion"] = 99
        let unsupported = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try codec.decode(unsupported)) { error in
            XCTAssertEqual(
                error as? SessionMetadataArchiveError,
                .unsupportedSchemaVersion(99)
            )
        }
    }

    private func makeMetadata(updatedAt: Date? = nil) throws -> SessionMetadata {
        SessionMetadata(
            provider: .codex,
            sessionID: try XCTUnwrap(OpaqueSessionID("thr_metadata")),
            project: try XCTUnwrap(ProjectIdentity(workingDirectory: "/workspace/atoll")),
            origin: OriginNavigation(
                applicationBundleIdentifier: "com.example.Terminal",
                terminalSessionIdentifier: "session-1",
                workspaceIdentifier: "workspace-1",
                paneIdentifier: "pane-1",
                tty: "/dev/ttys001"
            ),
            state: .working,
            startedAt: timestamp,
            updatedAt: updatedAt ?? timestamp,
            endedAt: nil
        )
    }
}
