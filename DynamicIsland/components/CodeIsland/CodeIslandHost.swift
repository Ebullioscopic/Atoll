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

/// Owns the Code Island feature shell and explicit provider activation in Atoll.
@MainActor
final class CodeIslandHost: ObservableObject {
    static let shared = CodeIslandHost()

    @Published private(set) var lifecycleState: CodeIslandHostLifecycleState = .stopped
    @Published private(set) var dashboardState: CodeIslandDashboardState = .setupRequired(provider: .codex)
    @Published private(set) var pendingActivityIntent: CodeIslandActivityIntent?
    @Published private(set) var discoveryAssessment: CodeIslandAdoptionAssessment?
    @Published private(set) var operationState: CodeIslandHostOperationState = .idle

    private let activityIntentAdapter: CodeIslandActivityIntentAdapter
    private let discovery: CodeIslandReadOnlyDiscovery
    private lazy var runtime: CodeIslandRuntime = CodeIslandRuntime.live {
        [weak self] current, previous in
        DispatchQueue.main.async { [weak self] in
            self?.consumeSanitizedSession(current, previous: previous)
        }
    }

    private init(
        activityIntentAdapter: CodeIslandActivityIntentAdapter = CodeIslandActivityIntentAdapter(),
        discovery: CodeIslandReadOnlyDiscovery = CodeIslandReadOnlyDiscovery()
    ) {
        self.activityIntentAdapter = activityIntentAdapter
        self.discovery = discovery
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
            operationState = .idle
        } catch {
            runtime.shutdown()
            operationState = .failed(message(for: error))
        }
        updateDashboardState()
    }

    /// Refreshes provider and standalone-CodeIsland state without mutating it.
    func refreshDiscovery() {
        discoveryAssessment = discovery.assessCodex()
    }

    /// Activates only the exact plan the user reviewed in the confirmation UI.
    func activateCodex(planID: UUID) {
        guard lifecycleState == .running,
              !runtime.isRunning,
              ProviderCapabilityRegistry.phaseFive.profile(for: .codex)?.isActivationAvailable == true,
              let plan = discoveryAssessment?.installationPlan,
              plan.id == planID,
              plan.blockers.isEmpty,
              let consent = plan.consent(confirmedByUser: true) else {
            operationState = .failed("Refresh Code Island setup and review the current plan again.")
            return
        }

        operationState = .activating
        do {
            try runtime.activate(plan: plan, consent: consent)
            operationState = .idle
            updateDashboardState()
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
        } catch {
            operationState = .failed(message(for: error))
        }
        updateDashboardState()
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
        refreshDiscovery()
    }

    /// Clears transient host state during Atoll shutdown.
    func stop() {
        runtime.shutdown()
        pendingActivityIntent = nil
        discoveryAssessment = nil
        operationState = .idle
        dashboardState = .setupRequired(provider: .codex)
        lifecycleState = .stopped
    }

    /// Accepts only the sanitized projection emitted by the active listener.
    /// Presentation remains an Atoll-owned decision deferred to Phase 6.
    func consumeSanitizedSession(
        _ current: SessionMetadata,
        previous: SessionMetadata?
    ) {
        guard lifecycleState == .running else { return }
        guard let intent = activityIntentAdapter.intent(
            for: current,
            previous: previous
        ) else { return }
        pendingActivityIntent = intent
    }

    private func updateDashboardState() {
        dashboardState = runtime.isRunning
            ? .idle(provider: .codex)
            : .setupRequired(provider: .codex)
    }

    private func message(for error: Error) -> String {
        if let activationError = error as? CodeIslandActivationError {
            switch activationError {
            case .consentRequired, .staleConsent:
                return "The setup plan changed. Refresh and review it again."
            case .blocked:
                return "Resolve the listed CodeIsland or Codex conflict, then refresh."
            case .invalidPlan:
                return "The disclosed setup paths no longer match. Refresh before retrying."
            case .alreadyActive:
                return "Codex Monitoring is already active."
            case .notActive:
                return "Codex Monitoring is not active."
            }
        }
        if let preflightError = error as? CodeIslandActivationPreflightError {
            switch preflightError {
            case .legacyApplicationRunning:
                return "Quit the standalone CodeIsland app, then refresh."
            case .legacySocketOccupied:
                return "The legacy CodeIsland listener is still running. Quit it, then refresh."
            default:
                return "The listener path changed or is unsafe. Refresh before retrying."
            }
        }
        if let installationError = error as? CodexManagedInstallationError {
            switch installationError {
            case .bundledBridgeMissing, .bundledBridgeNotExecutable:
                return "Atoll's signed Code Island helper is unavailable. Reinstall Atoll."
            case .managedBridgeModified, .managedBridgeConflict, .managedReceiptConflict:
                return "Atoll's managed Code Island files need attention before setup can continue."
            default:
                return "Codex Monitoring could not be verified. No provider decision was taken over."
            }
        }
        return "Code Island could not complete this operation safely."
    }
}
