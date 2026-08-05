import CodeIslandCore
import CodeIslandRuntime
import CodeIslandUI
import Foundation

@main
struct CodeIslandPhaseSevenReleaseRegression {
    static func main() {
        completionPresentationCanBeDisabled()
        smartSuppressionCanBeDisabled()
        smartSuppressionPreferenceAppliesToEveryHandoffPopOut()
        legacyFeaturePreferencesMapWithoutExpandingTheImportBoundary()
        codexOnlyDefaultProviderDoesNotOfferANoOpImport()
        retentionRemovesOnlyExpiredTerminalMetadata()
        retentionSchedulesCleanupWithoutWaitingForAnotherAgentEvent()
        retentionAcceptsAnExtremePublicInputWithoutOverflow()
        runtimePersistsTheRetainedMetadataProjection()
        runtimeKeepsItsProjectionWhenRetentionCannotPersist()
        selectedSoundResourcesHaveStableNames()
        dashboardGroupingChangesSectionsWithoutChangingUrgencyOrder()
        localizationUsesTheDedicatedPackageTable()
        phaseSixMetadataArchiveStillDecodesWithoutMigration()
    }

    /// Frozen Phase 6 archives use schema 1. Phase 7 adds retention and UI
    /// preferences without changing or enriching that metadata-only wire.
    private static func phaseSixMetadataArchiveStillDecodesWithoutMigration() {
        let phaseSixArchive = Data(
            #"{"schemaVersion":1,"sessions":[{"endedAt":null,"origin":null,"project":{"displayName":"Atoll","workingDirectory":"/workspace/Atoll"},"provider":"codex","sessionID":"phase-six-upgrade","startedAt":"1970-01-01T00:16:40Z","state":"working","updatedAt":"1970-01-01T00:18:20Z"}]}"#.utf8
        )

        do {
            let sessions = try SessionMetadataArchiveCodec().decode(phaseSixArchive)
            guard SessionMetadataArchiveCodec.schemaVersion == 1,
                  sessions.count == 1,
                  sessions[0].sessionID.rawValue == "phase-six-upgrade",
                  sessions[0].state == .working else {
                fatalError("Phase 7 must preserve the Phase 6 metadata archive contract")
            }
        } catch {
            fatalError("Phase 6 metadata archive failed to upgrade in place: \(error)")
        }
    }

    private static func localizationUsesTheDedicatedPackageTable() {
        guard CodeIslandLocalization.tableName == "CodeIsland",
              CodeIslandLocalization.string("Working") == "Working" else {
            fatalError("Code Island copy must resolve through its dedicated package table")
        }
    }

    private static func dashboardGroupingChangesSectionsWithoutChangingUrgencyOrder() {
        let base = Date(timeIntervalSince1970: 30_000)
        let projection = CodeIslandDashboardProjection(sessions: [
            metadata(
                id: "working",
                state: .working,
                updatedAt: base,
                endedAt: nil
            ),
            metadata(
                id: "waiting",
                state: .waitingForApproval,
                updatedAt: base.addingTimeInterval(-10),
                endedAt: nil
            ),
            metadata(
                id: "completed",
                state: .recentlyCompleted,
                updatedAt: base.addingTimeInterval(10),
                endedAt: base.addingTimeInterval(10)
            ),
        ])
        let ungrouped = CodeIslandDashboardLayout(
            items: projection.items,
            grouping: .all
        )
        let byStatus = CodeIslandDashboardLayout(
            items: projection.items,
            grouping: .status
        )

        guard ungrouped.groups.count == 1,
              ungrouped.groups[0].items.map(\.sessionID.rawValue)
                == ["waiting", "working", "completed"],
              byStatus.groups.map(\.items.count) == [1, 1, 1],
              byStatus.groups.flatMap(\.items).map(\.sessionID.rawValue)
                == ["waiting", "working", "completed"] else {
            fatalError("Grouping may change sections but must preserve urgency order")
        }
    }

    private static func selectedSoundResourcesHaveStableNames() {
        let names = Dictionary(uniqueKeysWithValues: CodeIslandSoundEffect.allCases.map {
            ($0, $0.resourceName)
        })
        guard names == [
            .sessionStarted: "8bit_start",
            .attentionRequired: "8bit_approval",
            .completed: "8bit_complete",
            .failed: "8bit_error",
        ] else {
            fatalError("The active sound contract must expose only the four selected effects")
        }
    }

    private static func runtimePersistsTheRetainedMetadataProjection() {
        let now = Date(timeIntervalSince1970: 20_000)
        let store = RecordingMetadataStore(sessions: [
            metadata(
                id: "active",
                state: .working,
                updatedAt: now.addingTimeInterval(-7_200),
                endedAt: nil
            ),
            metadata(
                id: "expired",
                state: .failed,
                updatedAt: now.addingTimeInterval(-3_600),
                endedAt: now.addingTimeInterval(-3_600)
            ),
        ])
        let runtime = CodeIslandRuntime(
            coordinator: CodeIslandActivationCoordinator(
                preflight: NoopPreflight(),
                listener: NoopListener(),
                installer: NoopInstaller()
            ),
            metadataStore: store
        )

        runtime.applyRetentionPolicy(retentionMinutes: 30, now: now)

        guard runtime.sessions.map(\.sessionID.rawValue) == ["active"],
              store.savedSessions.map(\.sessionID.rawValue) == ["active"] else {
            fatalError("Runtime retention must atomically update and persist its sanitized projection")
        }
    }

    private static func runtimeKeepsItsProjectionWhenRetentionCannotPersist() {
        let now = Date(timeIntervalSince1970: 20_000)
        let expired = metadata(
            id: "failed-save",
            state: .failed,
            updatedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-3_600)
        )
        let runtime = CodeIslandRuntime(
            coordinator: CodeIslandActivationCoordinator(
                preflight: NoopPreflight(),
                listener: NoopListener(),
                installer: NoopInstaller()
            ),
            metadataStore: FailingMetadataStore(sessions: [expired])
        )

        guard !runtime.applyRetentionPolicy(retentionMinutes: 30, now: now),
              runtime.sessions == [expired] else {
            fatalError("A failed retention save must not diverge the in-memory projection")
        }
    }

    private static func retentionRemovesOnlyExpiredTerminalMetadata() {
        let now = Date(timeIntervalSince1970: 10_000)
        let sessions = [
            metadata(
                id: "active-old",
                state: .working,
                updatedAt: now.addingTimeInterval(-7_200),
                endedAt: nil
            ),
            metadata(
                id: "recent-completion",
                state: .recentlyCompleted,
                updatedAt: now.addingTimeInterval(-1_740),
                endedAt: now.addingTimeInterval(-1_740)
            ),
            metadata(
                id: "expired-completion",
                state: .recentlyCompleted,
                updatedAt: now.addingTimeInterval(-1_860),
                endedAt: now.addingTimeInterval(-1_860)
            ),
        ]
        let retained = SessionMetadataRetentionPolicy(retentionMinutes: 30)
            .retainedSessions(from: sessions, now: now)

        guard retained.map(\.sessionID.rawValue) == ["active-old", "recent-completion"] else {
            fatalError("Retention must remove only terminal metadata older than the selected window")
        }
    }

    private static func retentionAcceptsAnExtremePublicInputWithoutOverflow() {
        let active = metadata(
            id: "extreme-active",
            state: .working,
            updatedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: nil
        )
        let retained = SessionMetadataRetentionPolicy(retentionMinutes: .max)
            .retainedSessions(
                from: [active],
                now: Date(timeIntervalSince1970: 2_000)
            )
        guard retained == [active] else {
            fatalError("Extreme retention input must not overflow or remove active metadata")
        }
    }

    private static func retentionSchedulesCleanupWithoutWaitingForAnotherAgentEvent() {
        let endedAt = Date(timeIntervalSince1970: 10_000)
        let terminal = metadata(
            id: "scheduled-cleanup",
            state: .recentlyCompleted,
            updatedAt: endedAt,
            endedAt: endedAt
        )
        let active = metadata(
            id: "active-not-scheduled",
            state: .working,
            updatedAt: endedAt.addingTimeInterval(-7_200),
            endedAt: nil
        )

        guard SessionMetadataRetentionPolicy(retentionMinutes: 30)
            .nextExpirationDate(for: [active, terminal])
            == endedAt.addingTimeInterval(1_800),
              SessionMetadataRetentionPolicy(retentionMinutes: 0)
                .nextExpirationDate(for: [terminal]) == nil else {
            fatalError("Retention must schedule terminal cleanup even without a later provider event")
        }
    }

    private static func legacyFeaturePreferencesMapWithoutExpandingTheImportBoundary() {
        let legacy = CodeIslandLegacyFeaturePreferences(
            sessionGrouping: .provider,
            smartSuppressionEnabled: false,
            completionPresentation: .glance,
            mascotSpeedPercent: 275,
            soundEffectsEnabled: true,
            soundVolumePercent: 80,
            defaultMascotProvider: .codex
        )
        let imported = CodeIslandFeaturePreferences.defaults.importing(legacy)

        guard imported.dashboardGrouping == .provider,
              imported.retentionMinutes == 30,
              imported.presentation.smartSuppressionEnabled == false,
              imported.presentation.completionPresentation == .glance,
              imported.mascotsEnabled,
              imported.mascotSpeedPercent == 275,
              imported.soundEffectsEnabled,
              imported.soundVolumePercent == 80,
              imported.sessionStartSoundEnabled,
              imported.completionSoundEnabled,
              imported.failureSoundEnabled,
              imported.attentionSoundEnabled else {
            fatalError("Guided adoption must map only compatible feature preferences")
        }
    }

    private static func codexOnlyDefaultProviderDoesNotOfferANoOpImport() {
        let legacy = CodeIslandLegacyFeaturePreferences(
            defaultMascotProvider: .codex
        )
        guard !legacy.hasImportableFeaturePreferences else {
            fatalError("Codex-only adoption must not offer a preference import that changes nothing")
        }
    }

    private static func smartSuppressionPreferenceAppliesToEveryHandoffPopOut() {
        let preferences = CodeIslandPresentationPreferences(
            smartSuppressionEnabled: false
        )
        let context = CodeIslandPresentationContext(
            occupancy: .available,
            supportsSecondaryIndicator: false,
            originMatch: .exactSession
        )
        let cases: [(CodeIslandActivityIntentKind, CodeIslandPresentationDisposition)] = [
            (.attentionRequired(.approval), .present(.attention(.approval))),
            (.failed, .present(.failed)),
        ]

        for (kind, expected) in cases {
            let intent = CodeIslandActivityIntent(
                kind: kind,
                subject: CodeIslandActivitySubject(metadata: metadata()),
                occurredAt: Date(timeIntervalSince1970: 1_100)
            )
            guard CodeIslandPresentationPolicy().disposition(
                for: intent,
                context: context,
                preferences: preferences
            ) == expected else {
                fatalError("The smart suppression preference must apply consistently")
            }
        }
    }

    private static func smartSuppressionCanBeDisabled() {
        let intent = CodeIslandActivityIntent(
            kind: .completed,
            subject: CodeIslandActivitySubject(metadata: metadata()),
            occurredAt: Date(timeIntervalSince1970: 1_100)
        )
        let preferences = CodeIslandPresentationPreferences(
            smartSuppressionEnabled: false
        )
        let disposition = CodeIslandPresentationPolicy().disposition(
            for: intent,
            context: CodeIslandPresentationContext(
                occupancy: .available,
                supportsSecondaryIndicator: false,
                originMatch: .exactSession
            ),
            preferences: preferences
        )

        guard disposition == .present(.completed) else {
            fatalError("Disabling smart suppression must preserve the completion pop-out")
        }
    }

    private static func completionPresentationCanBeDisabled() {
        let intent = CodeIslandActivityIntent(
            kind: .completed,
            subject: CodeIslandActivitySubject(metadata: metadata()),
            occurredAt: Date(timeIntervalSince1970: 1_100)
        )
        let preferences = CodeIslandPresentationPreferences(
            completionPresentation: .off
        )
        let disposition = CodeIslandPresentationPolicy().disposition(
            for: intent,
            context: CodeIslandPresentationContext(
                occupancy: .available,
                supportsSecondaryIndicator: false,
                originMatch: .different
            ),
            preferences: preferences
        )

        guard disposition == .stateOnly else {
            fatalError("A disabled completion presentation must update state without a pop-out")
        }
    }

    private static func metadata() -> SessionMetadata {
        metadata(
            id: "phase-seven",
            state: .recentlyCompleted,
            updatedAt: Date(timeIntervalSince1970: 1_100),
            endedAt: Date(timeIntervalSince1970: 1_100)
        )
    }

    private static func metadata(
        id: String,
        state: SessionState,
        updatedAt: Date,
        endedAt: Date?
    ) -> SessionMetadata {
        SessionMetadata(
            provider: .codex,
            sessionID: OpaqueSessionID(id)!,
            project: ProjectIdentity(displayName: "Atoll")!,
            origin: nil,
            state: state,
            startedAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: updatedAt,
            endedAt: endedAt
        )
    }
}

private final class RecordingMetadataStore: SessionMetadataStoring, @unchecked Sendable {
    private let loadedSessions: [SessionMetadata]
    private(set) var savedSessions: [SessionMetadata] = []

    init(sessions: [SessionMetadata]) {
        loadedSessions = sessions
    }

    func load() throws -> [SessionMetadata] { loadedSessions }
    func save(_ sessions: [SessionMetadata]) throws { savedSessions = sessions }
}

private final class FailingMetadataStore: SessionMetadataStoring, @unchecked Sendable {
    private let sessions: [SessionMetadata]

    init(sessions: [SessionMetadata]) {
        self.sessions = sessions
    }

    func load() throws -> [SessionMetadata] { sessions }
    func save(_ sessions: [SessionMetadata]) throws { throw CocoaError(.fileWriteUnknown) }
}

private struct NoopPreflight: CodeIslandActivationPreflighting {
    func validate(plan: CodeIslandInstallationPlan) throws {}
}

private struct NoopListener: CodeIslandListenerControlling {
    func start(at socketURL: URL) throws {}
    func enterPassThrough() {}
    func drain(timeout: TimeInterval) {}
    func stop() {}
}

private struct NoopInstaller: CodeIslandManagedInstalling {
    func install(plan: CodeIslandInstallationPlan) throws -> CodeIslandManagedInstallationReceipt {
        throw CodeIslandActivationError.invalidPlan
    }
    func verify(receipt: CodeIslandManagedInstallationReceipt) throws {}
    func remove(receipt: CodeIslandManagedInstallationReceipt) throws {}
}
