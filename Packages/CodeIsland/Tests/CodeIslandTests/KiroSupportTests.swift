import XCTest
@testable import CodeIsland
import CodeIslandCore

/// Locks in the wire-level pieces of Kiro CLI support (#127) — the parts that
/// don't need a live Kiro install to verify, but where a typo would silently
/// break the whole integration: event-name mapping, default event list,
/// supported-source recognition, and the new `.kiroAgent` HookFormat.
final class KiroSupportTests: XCTestCase {

    // MARK: - EventNormalizer

    func testEventNormalizerMapsKiroAgentSpawnToSessionStart() {
        XCTAssertEqual(EventNormalizer.normalize("agentSpawn"), "SessionStart")
    }

    func testEventNormalizerMapsKiroUserPromptSubmitToInternalName() {
        // Kiro uses singular `userPromptSubmit`, distinct from Copilot's
        // `userPromptSubmitted` — both must normalize to "UserPromptSubmit".
        XCTAssertEqual(EventNormalizer.normalize("userPromptSubmit"), "UserPromptSubmit")
        XCTAssertEqual(EventNormalizer.normalize("userPromptSubmitted"), "UserPromptSubmit")
    }

    func testEventNormalizerCoversAllKiroEvents() {
        // The five events Kiro sends; if any of these silently fall through to
        // the `default` branch (returning the raw camelCase name), HookServer
        // routing will misbehave — assert the full set explicitly.
        XCTAssertEqual(EventNormalizer.normalize("agentSpawn"), "SessionStart")
        XCTAssertEqual(EventNormalizer.normalize("userPromptSubmit"), "UserPromptSubmit")
        XCTAssertEqual(EventNormalizer.normalize("preToolUse"), "PreToolUse")
        XCTAssertEqual(EventNormalizer.normalize("postToolUse"), "PostToolUse")
        XCTAssertEqual(EventNormalizer.normalize("stop"), "Stop")
    }

    // MARK: - SessionSnapshot supported source recognition

    func testKiroIsRecognizedAsSupportedSource() {
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("kiro"), "kiro")
    }

    func testKiroAliasesNormalizeToKiro() {
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("kiro-cli"), "kiro")
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("kirocli"), "kiro")
        // Prefix-match path (via the hasPrefix("kiro") clause) — covers any
        // future "kiro-something" sub-brand without us needing to enumerate it.
        XCTAssertEqual(SessionSnapshot.normalizedSupportedSource("kiro-pro"), "kiro")
    }

    func testKiroDisplayName() {
        var snapshot = SessionSnapshot()
        snapshot.source = "kiro"
        XCTAssertEqual(snapshot.sourceLabel, "Kiro")
    }

    // MARK: - ConfigInstaller — Kiro CLIConfig + default events

    func testKiroDefaultEventsAreCamelCaseAndComplete() {
        // Kiro CLI hooks contract: 5 camelCase events. Order isn't strictly
        // required by Kiro, but locking it stabilizes the hook-install diff.
        let names = ConfigInstaller.defaultEvents(for: .kiroAgent).map { $0.0 }
        XCTAssertEqual(names, ["agentSpawn", "userPromptSubmit", "preToolUse", "postToolUse", "stop"])
    }

    func testHookFormatKiroAgentRoundTripsThroughStorageValue() {
        // `HookFormat.storageValue` is what we persist for custom CLIs in
        // UserDefaults; missing a case here would silently demote Kiro custom
        // configs to a different format on load.
        XCTAssertEqual(HookFormat.kiroAgent.storageValue, "kiroAgent")
        XCTAssertEqual(HookFormat(storageValue: "kiroAgent"), .kiroAgent)
        XCTAssertEqual(HookFormat(storageValue: "kiroagent"), .kiroAgent)  // case-insensitive
    }
}
