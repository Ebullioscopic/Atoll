import CodeIslandCore
import CodeIslandUI
import Foundation
import XCTest
@testable import CodeIslandRuntime

final class PhaseSevenReleaseTests: XCTestCase {
    func testCompletionCanStayStateOnlyAndSmartSuppressionCanBeDisabled() {
        let session = metadata(state: .recentlyCompleted)
        let subject = CodeIslandActivitySubject(metadata: session)
        let intent = CodeIslandActivityIntent(
            kind: .completed,
            subject: subject,
            occurredAt: session.updatedAt
        )
        let context = CodeIslandPresentationContext(
            occupancy: .available,
            supportsSecondaryIndicator: false,
            originMatch: .exactSession
        )

        XCTAssertEqual(
            CodeIslandPresentationPolicy().disposition(
                for: intent,
                context: context,
                preferences: CodeIslandPresentationPreferences(
                    completionPresentation: .off
                )
            ),
            .stateOnly
        )
        XCTAssertEqual(
            CodeIslandPresentationPolicy().disposition(
                for: intent,
                context: context,
                preferences: CodeIslandPresentationPreferences(
                    smartSuppressionEnabled: false
                )
            ),
            .present(.completed)
        )
    }

    func testRetentionNeverRemovesAnActiveSession() {
        let now = Date(timeIntervalSince1970: 20_000)
        let active = metadata(
            state: .working,
            updatedAt: now.addingTimeInterval(-7_200)
        )
        let expired = metadata(
            id: "expired",
            state: .failed,
            updatedAt: now.addingTimeInterval(-3_600)
        )

        XCTAssertEqual(
            SessionMetadataRetentionPolicy(retentionMinutes: 30)
                .retainedSessions(from: [active, expired], now: now)
                .map(\.sessionID.rawValue),
            ["phase-seven"]
        )
    }

    func testRetentionSchedulesTheNextTerminalExpirationOnly() {
        let now = Date(timeIntervalSince1970: 20_000)
        let active = metadata(
            state: .working,
            updatedAt: now.addingTimeInterval(-7_200)
        )
        let terminal = metadata(
            id: "terminal",
            state: .recentlyCompleted,
            updatedAt: now.addingTimeInterval(-600)
        )

        XCTAssertEqual(
            SessionMetadataRetentionPolicy(retentionMinutes: 30)
                .nextExpirationDate(for: [active, terminal]),
            now.addingTimeInterval(1_200)
        )
        XCTAssertNil(
            SessionMetadataRetentionPolicy(retentionMinutes: 0)
                .nextExpirationDate(for: [terminal])
        )
    }

    func testRuntimeKeepsItsProjectionWhenRetentionCannotPersist() {
        let now = Date(timeIntervalSince1970: 20_000)
        let expired = metadata(
            state: .failed,
            updatedAt: now.addingTimeInterval(-3_600)
        )
        let store = ThrowingMetadataStore(sessions: [expired])
        let runtime = CodeIslandRuntime(
            coordinator: CodeIslandActivationCoordinator(
                preflight: TestPreflight(),
                listener: TestListener(),
                installer: TestInstaller()
            ),
            metadataStore: store
        )

        XCTAssertFalse(
            runtime.applyRetentionPolicy(retentionMinutes: 30, now: now)
        )
        XCTAssertEqual(runtime.sessions, [expired])
    }

    func testSelectedResourcesAndLocalizationResolveFromThePackage() {
        XCTAssertEqual(
            Set(CodeIslandSoundEffect.allCases.map(\.resourceName)),
            ["8bit_approval", "8bit_complete", "8bit_error", "8bit_start"]
        )
        for effect in CodeIslandSoundEffect.allCases {
            XCTAssertNotNil(effect.resourceURL(), effect.resourceName)
        }
        XCTAssertEqual(CodeIslandLocalization.string("Working"), "Working")
    }

    func testCodexOnlyDefaultProviderDoesNotOfferANoOpPreferenceImport() {
        let legacy = CodeIslandLegacyFeaturePreferences(
            defaultMascotProvider: .codex
        )

        XCTAssertFalse(legacy.hasImportableFeaturePreferences)
    }

    private func metadata(
        id: String = "phase-seven",
        state: SessionState,
        updatedAt: Date = Date(timeIntervalSince1970: 1_100)
    ) -> SessionMetadata {
        SessionMetadata(
            provider: .codex,
            sessionID: OpaqueSessionID(id)!,
            project: ProjectIdentity(displayName: "Atoll")!,
            origin: nil,
            state: state,
            startedAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: updatedAt,
            endedAt: state.isTerminal ? updatedAt : nil
        )
    }
}

private final class ThrowingMetadataStore: SessionMetadataStoring, @unchecked Sendable {
    private let sessions: [SessionMetadata]

    init(sessions: [SessionMetadata]) {
        self.sessions = sessions
    }

    func load() throws -> [SessionMetadata] { sessions }
    func save(_ sessions: [SessionMetadata]) throws { throw CocoaError(.fileWriteUnknown) }
}

private struct TestPreflight: CodeIslandActivationPreflighting {
    func validate(plan: CodeIslandInstallationPlan) throws {}
}

private struct TestListener: CodeIslandListenerControlling {
    func start(at socketURL: URL) throws {}
    func enterPassThrough() {}
    func drain(timeout: TimeInterval) {}
    func stop() {}
}

private struct TestInstaller: CodeIslandManagedInstalling {
    func install(plan: CodeIslandInstallationPlan) throws -> CodeIslandManagedInstallationReceipt {
        throw CodeIslandActivationError.invalidPlan
    }
    func verify(receipt: CodeIslandManagedInstallationReceipt) throws {}
    func remove(receipt: CodeIslandManagedInstallationReceipt) throws {}
}
