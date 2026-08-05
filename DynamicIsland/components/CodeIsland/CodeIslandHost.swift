/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import CodeIslandCore
import CodeIslandRuntime
import CodeIslandUI
import Combine
import Foundation

/// Atoll's lifecycle state for the embedded feature host, not provider state.
enum CodeIslandHostLifecycleState: Equatable {
    case stopped
    case running
}

enum CodeIslandHostOperationState: Equatable {
    case idle
    case activating
    case repairing
    case deactivating
    case failed(String)
}

/// One Atoll-selected Code Island presentation. It contains only the sanitized
/// subject and content-free style emitted across the package boundary.
struct CodeIslandHostPresentation: Equatable, Identifiable {
    var id: String {
        "\(intent.subject.provider.rawValue):\(intent.subject.sessionID.rawValue):\(intent.occurredAt.timeIntervalSince1970):\(style.identity)"
    }

    let style: CodeIslandPresentationStyle
    let intent: CodeIslandActivityIntent

    var subject: CodeIslandActivitySubject { intent.subject }
    var isAttention: Bool {
        if case .attention = style { return true }
        return false
    }
    var isCompact: Bool {
        if case .compact = style { return true }
        return false
    }
}

private extension CodeIslandPresentationStyle {
    var identity: String {
        switch self {
        case .compact(let isSecondary): return isSecondary ? "compact-secondary" : "compact"
        case .sessionStarted: return "started"
        case .attention(.approval): return "attention-approval"
        case .attention(.question): return "attention-question"
        case .completed: return "completed"
        case .failed: return "failed"
        }
    }
}

/// Owns the Code Island feature shell and explicit provider activation in Atoll.
@MainActor
final class CodeIslandHost: ObservableObject {
    static let shared = CodeIslandHost()

    @Published private(set) var lifecycleState: CodeIslandHostLifecycleState = .stopped
    @Published private(set) var dashboardState: CodeIslandDashboardState = .setupRequired(provider: .codex)
    @Published private(set) var pendingActivityIntent: CodeIslandActivityIntent?
    @Published private(set) var activePresentation: CodeIslandHostPresentation?
    @Published private(set) var compactPresentation: CodeIslandHostPresentation?
    @Published private(set) var queuedPresentationCount = 0
    @Published private(set) var discoveryAssessment: CodeIslandAdoptionAssessment?
    @Published private(set) var operationState: CodeIslandHostOperationState = .idle

    private let activityIntentAdapter: CodeIslandActivityIntentAdapter
    private let presentationPolicy: CodeIslandPresentationPolicy
    private let discovery: CodeIslandReadOnlyDiscovery
    private let originAdapter: CodeIslandOriginAdapter
    private let featurePreferences: CodeIslandFeaturePreferenceStore
    private var occupancy: CodeIslandNotchOccupancy = .available
    private var supportsSecondaryIndicator = false
    private var queuedIntents: [CodeIslandActivityIntent] = []
    private var presentationExpirationTask: Task<Void, Never>?
    private var retentionExpirationTask: Task<Void, Never>?
    private var evaluationTokens: [String: Int] = [:]
    private lazy var runtime: CodeIslandRuntime = CodeIslandRuntime.live {
        [weak self] current, previous in
        DispatchQueue.main.async { [weak self] in
            self?.consumeSanitizedSession(current, previous: previous)
        }
    }

    private init(
        activityIntentAdapter: CodeIslandActivityIntentAdapter = CodeIslandActivityIntentAdapter(),
        presentationPolicy: CodeIslandPresentationPolicy = CodeIslandPresentationPolicy(),
        discovery: CodeIslandReadOnlyDiscovery = CodeIslandReadOnlyDiscovery(),
        featurePreferences: CodeIslandFeaturePreferenceStore? = nil
    ) {
        self.activityIntentAdapter = activityIntentAdapter
        self.presentationPolicy = presentationPolicy
        self.discovery = discovery
        self.featurePreferences = featurePreferences ?? CodeIslandFeaturePreferenceStore.shared
        originAdapter = CodeIslandOriginAdapter()
    }

    var isActivated: Bool { runtime.isRunning }

    /// Starts read-only discovery, then resumes only a receipt-owned activation.
    func start() {
        guard lifecycleState == .stopped else { return }
        lifecycleState = .running
        refreshDiscovery()
        guard let plan = discoveryAssessment?.installationPlan else {
            updateDashboardState()
            return
        }
        do {
            try runtime.start(plan: plan)
            applyRetentionAndScheduleNextCleanup()
            operationState = .idle
        } catch {
            runtime.shutdown()
            operationState = .failed(message(for: error))
        }
        updateDashboardState()
        refreshCompactPresentation()
    }

    /// Refreshes provider and standalone-CodeIsland state without mutating it.
    func refreshDiscovery() {
        discoveryAssessment = discovery.assessCodex()
    }

    /// Applies local feature changes immediately without altering provider
    /// activation or configuration. This is primarily observable for retention
    /// and compact-presentation preferences.
    func refreshFeaturePreferences() {
        applyRetentionAndScheduleNextCleanup()
        updateDashboardState()
        refreshCompactPresentation()
    }

    /// Activates only the exact plan the user reviewed in the confirmation UI.
    func activateCodex(
        planID: UUID,
        importCompatiblePreferences: Bool = false
    ) {
        guard lifecycleState == .running,
              !runtime.isRunning,
              ProviderCapabilityRegistry.phaseFive.profile(for: .codex)?.isActivationAvailable == true,
              let assessment = discoveryAssessment else {
            operationState = .failed(ci("Refresh Code Island setup and review the current plan again."))
            return
        }
        let plan = assessment.installationPlan
        guard plan.id == planID,
              plan.blockers.isEmpty,
              let consent = plan.consent(confirmedByUser: true) else {
            operationState = .failed(ci("Refresh Code Island setup and review the current plan again."))
            return
        }

        operationState = .activating
        do {
            try runtime.activate(plan: plan, consent: consent)
            if importCompatiblePreferences,
               assessment.compatiblePreferences.hasImportableFeaturePreferences {
                featurePreferences.replace(
                    with: featurePreferences.snapshot.importing(
                        assessment.compatiblePreferences
                    )
                )
            }
            applyRetentionAndScheduleNextCleanup()
            operationState = .idle
            updateDashboardState()
            refreshCompactPresentation()
            refreshDiscovery()
        } catch {
            operationState = .failed(message(for: error))
            updateDashboardState()
            refreshDiscovery()
        }
    }

    /// Removes only the active Atoll receipt and restores adopted legacy hooks.
    func deactivateCodex() {
        guard runtime.isRunning else { return }
        operationState = .deactivating
        do {
            try runtime.deactivate()
            operationState = .idle
            resetPresentationState()
        } catch {
            operationState = .failed(message(for: error))
        }
        updateDashboardState()
        refreshCompactPresentation()
        refreshDiscovery()
    }

    /// Verifies and repairs only the already-consented Atoll-owned entries.
    func repairCodex() {
        guard runtime.isRunning,
              let plan = discoveryAssessment?.installationPlan else { return }
        operationState = .repairing
        do {
            try runtime.repair(plan: plan)
            operationState = .idle
        } catch {
            operationState = .failed(message(for: error))
        }
        updateDashboardState()
        refreshCompactPresentation()
        refreshDiscovery()
    }

    /// Clears transient host state during Atoll shutdown.
    func stop() {
        runtime.shutdown()
        resetPresentationState()
        discoveryAssessment = nil
        operationState = .idle
        dashboardState = .setupRequired(provider: .codex)
        lifecycleState = .stopped
    }

    private func resetPresentationState() {
        presentationExpirationTask?.cancel()
        presentationExpirationTask = nil
        retentionExpirationTask?.cancel()
        retentionExpirationTask = nil
        queuedIntents.removeAll()
        evaluationTokens.removeAll()
        pendingActivityIntent = nil
        activePresentation = nil
        compactPresentation = nil
        queuedPresentationCount = 0
    }

    /// Accepts only the sanitized projection emitted by the active listener.
    func consumeSanitizedSession(
        _ current: SessionMetadata,
        previous: SessionMetadata?
    ) {
        guard lifecycleState == .running else { return }
        applyRetentionAndScheduleNextCleanup()
        updateDashboardState()
        refreshCompactPresentation()
        guard runtime.sessions.contains(where: {
            $0.provider == current.provider && $0.sessionID == current.sessionID
        }) else { return }
        guard let intent = activityIntentAdapter.intent(
            for: current,
            previous: previous
        ) else { return }
        pendingActivityIntent = intent
        evaluate(intent)
    }

    /// Receives Atoll's current notch occupancy. Code Island never infers
    /// priority by reaching into another feature manager from its runtime.
    func updatePresentationEnvironment(
        occupancy: CodeIslandNotchOccupancy,
        supportsSecondaryIndicator: Bool
    ) {
        let occupancyChanged = self.occupancy != occupancy
            || self.supportsSecondaryIndicator != supportsSecondaryIndicator
        self.occupancy = occupancy
        self.supportsSecondaryIndicator = supportsSecondaryIndicator
        guard occupancyChanged else { return }

        if let activePresentation,
           !activePresentation.isAttention,
           !activePresentation.isCompact,
           occupancy != .available {
            enqueue(activePresentation.intent)
            clearActivePresentation()
        }

        refreshCompactPresentation()
        drainQueueIfPossible()
    }

    /// Atoll-owned handoff action used by dashboard rows and attention cards.
    func openOrigin(_ origin: OriginNavigation?) {
        originAdapter.open(origin)
    }

    /// User-initiated navigation from the compact activity into the dashboard.
    func showDashboard() {
        originAdapter.presentAttentionHandoff()
    }

    private func updateDashboardState() {
        guard runtime.isRunning else {
            dashboardState = .setupRequired(provider: .codex)
            return
        }

        let projection = CodeIslandDashboardProjection(sessions: runtime.sessions)
        dashboardState = projection.items.isEmpty
            ? .idle(provider: .codex)
            : .sessions(provider: .codex, items: projection.items)
    }

    /// Retention must advance even when the provider becomes quiet. A failed
    /// archive replacement is retried later without dropping the in-memory
    /// projection or spinning on an already-expired timestamp.
    private func applyRetentionAndScheduleNextCleanup() {
        retentionExpirationTask?.cancel()
        retentionExpirationTask = nil
        guard runtime.isRunning else { return }

        let retentionMinutes = featurePreferences.snapshot.retentionMinutes
        let policy = SessionMetadataRetentionPolicy(
            retentionMinutes: retentionMinutes
        )
        guard runtime.applyRetentionPolicy(
            retentionMinutes: retentionMinutes
        ) else {
            scheduleRetentionCleanup(after: 60)
            return
        }

        discardExpiredPresentationState()
        guard let expirationDate = policy.nextExpirationDate(for: runtime.sessions) else {
            return
        }
        scheduleRetentionCleanup(
            after: max(0, expirationDate.timeIntervalSinceNow)
        )
    }

    private func scheduleRetentionCleanup(after duration: TimeInterval) {
        retentionExpirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            retentionExpirationTask = nil
            applyRetentionAndScheduleNextCleanup()
            updateDashboardState()
            refreshCompactPresentation()
        }
    }

    private func discardExpiredPresentationState() {
        let retainedKeys = Set(runtime.sessions.map {
            "\($0.provider.rawValue):\($0.sessionID.rawValue)"
        })
        queuedIntents.removeAll { !retainedKeys.contains(sessionKey($0.subject)) }
        queuedPresentationCount = queuedIntents.count
        if let pendingActivityIntent,
           !retainedKeys.contains(sessionKey(pendingActivityIntent.subject)) {
            self.pendingActivityIntent = nil
        }
        let didClearActivePresentation: Bool
        if let activePresentation,
           !retainedKeys.contains(sessionKey(activePresentation.subject)) {
            clearActivePresentation()
            didClearActivePresentation = true
        } else {
            didClearActivePresentation = false
        }
        evaluationTokens = evaluationTokens.filter { retainedKeys.contains($0.key) }
        if didClearActivePresentation {
            drainQueueIfPossible()
        }
    }

    private func evaluate(_ intent: CodeIslandActivityIntent) {
        let key = sessionKey(intent.subject)
        evaluationTokens[key, default: 0] += 1
        let token = evaluationTokens[key] ?? 0
        discardQueuedIntents(for: intent.subject)

        if case .dismissed = intent.kind {
            dismissPresentations(for: intent.subject)
            return
        }

        if activePresentation?.subject.provider == intent.subject.provider,
           activePresentation?.subject.sessionID == intent.subject.sessionID,
           activePresentation?.isAttention == true {
            clearActivePresentation()
        }

        switch intent.kind {
        case .attentionRequired, .completed, .failed:
            Task { [weak self] in
                guard let self else { return }
                let match = await originAdapter.exactMatch(for: intent.subject.origin)
                guard evaluationTokens[key] == token else { return }
                apply(intent, originMatch: match)
            }
        case .sessionStarted, .processing:
            apply(intent, originMatch: .unknown)
        case .dismissed:
            break
        }
    }

    private func apply(
        _ intent: CodeIslandActivityIntent,
        originMatch: CodeIslandExactOriginMatch
    ) {
        let context = CodeIslandPresentationContext(
            occupancy: occupancy,
            supportsSecondaryIndicator: supportsSecondaryIndicator,
            originMatch: originMatch
        )

        switch presentationPolicy.disposition(
            for: intent,
            context: context,
            preferences: featurePreferences.snapshot.presentation
        ) {
        case .present(let style):
            if case .compact = style {
                refreshCompactPresentation()
                return
            }

            if let activePresentation {
                if case .attention = style, !activePresentation.isAttention {
                    enqueue(activePresentation.intent)
                    clearActivePresentation()
                } else {
                    enqueue(intent)
                    return
                }
            }
            present(style: style, intent: intent)

        case .enqueue:
            enqueue(intent)
        case .suppress, .stateOnly:
            drainQueueIfPossible()
        case .dismiss:
            dismissPresentations(for: intent.subject)
        }
    }

    private func present(
        style: CodeIslandPresentationStyle,
        intent: CodeIslandActivityIntent
    ) {
        activePresentation = CodeIslandHostPresentation(style: style, intent: intent)
        playSoundIfEnabled(for: style)
        presentationExpirationTask?.cancel()
        presentationExpirationTask = nil

        switch style {
        case .attention:
            originAdapter.presentAttentionHandoff()
        case .sessionStarted:
            schedulePresentationExpiration(after: 2.0)
        case .completed:
            let duration = featurePreferences.snapshot.presentation.completionPresentation == .glance
                ? 2.0
                : 5.0
            schedulePresentationExpiration(after: duration)
        case .failed:
            schedulePresentationExpiration(after: 4.0)
        case .compact:
            break
        }
    }

    private func schedulePresentationExpiration(after duration: TimeInterval) {
        presentationExpirationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            clearActivePresentation()
            drainQueueIfPossible()
        }
    }

    private func clearActivePresentation() {
        presentationExpirationTask?.cancel()
        presentationExpirationTask = nil
        activePresentation = nil
    }

    private func enqueue(_ intent: CodeIslandActivityIntent) {
        discardQueuedIntents(for: intent.subject)
        queuedIntents.append(intent)
        queuedIntents = presentationPolicy.orderedQueue(queuedIntents)
        queuedPresentationCount = queuedIntents.count
    }

    /// A newer transition for one session always supersedes its deferred UI.
    private func discardQueuedIntents(for subject: CodeIslandActivitySubject) {
        queuedIntents.removeAll { queued in
            queued.subject.provider == subject.provider
                && queued.subject.sessionID == subject.sessionID
        }
        queuedPresentationCount = queuedIntents.count
    }

    private func drainQueueIfPossible() {
        guard activePresentation == nil, !queuedIntents.isEmpty else { return }
        let next = queuedIntents.removeFirst()
        queuedPresentationCount = queuedIntents.count
        evaluate(next)
    }

    private func dismissPresentations(for subject: CodeIslandActivitySubject) {
        let key = sessionKey(subject)
        evaluationTokens[key, default: 0] += 1
        discardQueuedIntents(for: subject)
        if activePresentation?.subject.provider == subject.provider,
           activePresentation?.subject.sessionID == subject.sessionID {
            clearActivePresentation()
        }
        refreshCompactPresentation()
        drainQueueIfPossible()
    }

    private func refreshCompactPresentation() {
        guard runtime.isRunning else {
            compactPresentation = nil
            return
        }
        let workingSessions = runtime.sessions
            .filter { $0.state == .working }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.sessionID.rawValue < $1.sessionID.rawValue
            }
        guard let metadata = workingSessions.first else {
            compactPresentation = nil
            return
        }

        let intent = CodeIslandActivityIntent(
            kind: .processing,
            subject: CodeIslandActivitySubject(metadata: metadata),
            occurredAt: metadata.updatedAt
        )
        let disposition = presentationPolicy.disposition(
            for: intent,
            context: CodeIslandPresentationContext(
                occupancy: occupancy,
                supportsSecondaryIndicator: supportsSecondaryIndicator,
                originMatch: .unknown
            ),
            preferences: featurePreferences.snapshot.presentation
        )
        if case .present(let style) = disposition {
            compactPresentation = CodeIslandHostPresentation(style: style, intent: intent)
        } else {
            compactPresentation = nil
        }
    }

    private func sessionKey(_ subject: CodeIslandActivitySubject) -> String {
        "\(subject.provider.rawValue):\(subject.sessionID.rawValue)"
    }

    private func playSoundIfEnabled(for style: CodeIslandPresentationStyle) {
        let preferences = featurePreferences.snapshot
        guard preferences.soundEffectsEnabled else { return }

        let effect: CodeIslandSoundEffect?
        switch style {
        case .sessionStarted where preferences.sessionStartSoundEnabled:
            effect = .sessionStarted
        case .attention where preferences.attentionSoundEnabled:
            effect = .attentionRequired
        case .completed where preferences.completionSoundEnabled:
            effect = .completed
        case .failed where preferences.failureSoundEnabled:
            effect = .failed
        case .compact, .sessionStarted, .attention, .completed, .failed:
            effect = nil
        }

        if let effect {
            CodeIslandSoundPlayer.shared.play(
                effect,
                volumePercent: preferences.soundVolumePercent
            )
        }
    }

    private func message(for error: Error) -> String {
        if let activationError = error as? CodeIslandActivationError {
            switch activationError {
            case .consentRequired, .staleConsent:
                return ci("The setup plan changed. Refresh and review it again.")
            case .blocked:
                return ci("Resolve the listed CodeIsland or Codex conflict, then refresh.")
            case .invalidPlan:
                return ci("The disclosed setup paths no longer match. Refresh before retrying.")
            case .alreadyActive:
                return ci("Codex Monitoring is already active.")
            case .notActive:
                return ci("Codex Monitoring is not active.")
            }
        }
        if let preflightError = error as? CodeIslandActivationPreflightError {
            switch preflightError {
            case .legacyApplicationRunning:
                return ci("Quit the standalone CodeIsland app, then refresh.")
            case .legacySocketOccupied:
                return ci("The legacy CodeIsland listener is still running. Quit it, then refresh.")
            default:
                return ci("The listener path changed or is unsafe. Refresh before retrying.")
            }
        }
        if let installationError = error as? CodexManagedInstallationError {
            switch installationError {
            case .bundledBridgeMissing, .bundledBridgeNotExecutable:
                return ci("Atoll's signed Code Island helper is unavailable. Reinstall Atoll.")
            case .managedBridgeModified, .managedBridgeConflict, .managedReceiptConflict:
                return ci("Atoll's managed Code Island files need attention before setup can continue.")
            default:
                return ci("Codex Monitoring could not be verified. No provider decision was taken over.")
            }
        }
        return ci("Code Island could not complete this operation safely.")
    }
}

private func ci(_ key: String.LocalizationValue) -> String {
    CodeIslandLocalization.string(key)
}
