import XCTest
@testable import CodeIsland
@testable import CodeIslandCore

/// QoderWork (#249) — Qoder's standalone desktop assistant app (not the IDE,
/// not the CLI). Hooks are Claude-format JSON, but ONLY in user-level
/// ~/.qoderwork/settings.json, and QoderWork must be restarted to pick up
/// config changes.
final class QoderWorkSupportTests: XCTestCase {

    func testQoderWorkCLIConfigEntry() throws {
        let cli = try XCTUnwrap(
            ConfigInstaller.allCLIs.first(where: { $0.source == "qoderwork" }),
            "QoderWork must be a built-in CLI"
        )
        XCTAssertEqual(cli.name, "QoderWork")
        XCTAssertEqual(cli.configPath, ".qoderwork/settings.json")
        XCTAssertEqual(cli.configKey, "hooks")
        if case .claude = cli.format {} else {
            XCTFail("QoderWork hooks are Claude-format JSON")
        }
        XCTAssertFalse(cli.events.isEmpty)
        let permission = try XCTUnwrap(cli.events.first { $0.0 == "PermissionRequest" })
        XCTAssertEqual(permission.1, 86400)
        XCTAssertFalse(permission.2)
    }

    func testQoderWorkSourceNormalization() {
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("qoderwork"), "qoderwork")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("QoderWork"), "qoderwork")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("qoder-work"), "qoderwork")
        // The desktop-assistant source must never fold into the IDE or CLI variants.
        XCTAssertNotEqual(SessionSnapshot.normalizedSupportedSource("qoderwork"), "qoder")
        XCTAssertNotEqual(SessionSnapshot.normalizedSupportedSource("qoderwork"), "qoder-cli")
    }

    func testQoderWorkSessionClassification() {
        var session = SessionSnapshot()
        session.source = "qoderwork"
        XCTAssertEqual(session.sourceLabel, "QoderWork")
        // Standalone app: completion comes from the standard Stop hook, and it
        // must not participate in IDE-host ancestry inference (#220).
        XCTAssertFalse(SessionSnapshot.ideCompletionSources.contains("qoderwork"))
        XCTAssertFalse(SessionSnapshot.ideHostSources.contains("qoderwork"))
    }

    func testQoderWorkFoldsOntoQoderBuddySlot() {
        XCTAssertEqual(MascotID(sourceName: "qoderwork"), .qoder)
    }
}
