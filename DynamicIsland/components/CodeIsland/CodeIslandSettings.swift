/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import CodeIslandRuntime
import Foundation
import SwiftUI

/// Read-only Phase 4 setup and adoption status for Code Island.
struct CodeIslandSettings: View {
    @ObservedObject private var host = CodeIslandHost.shared

    private let codexProfile = ProviderCapabilityRegistry.phaseTwo.profile(for: .codex)

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Text(host.dashboardState.requiresActivation ? "Not connected" : "Connected")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Atoll host") {
                    Text(host.lifecycleState == .running ? "Ready" : "Stopped")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Discovery") {
                    HStack(spacing: 8) {
                        Text(host.discoveryAssessment == nil ? "Pending" : "Current")
                            .foregroundStyle(.secondary)
                        Button {
                            host.refreshDiscovery()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh read-only discovery")
                    }
                }
            } header: {
                Text("Code Island")
            } footer: {
                Text("Code Island is built into Atoll. Provider rollout remains gated; discovery does not change Codex or CodeIsland.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                LabeledContent("Provider") {
                    Text("Codex")
                }

                LabeledContent("Detected") {
                    Text(toolPresenceLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                LabeledContent("Verified capability") {
                    Text(capabilityLabel)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Activation") {
                    Text(codexProfile?.isActivationAvailable == true ? "Available" : "Unavailable")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Hook state") {
                    Text(hookStateLabel)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Codex")
            } footer: {
                Text("Monitoring means lifecycle and meaningful state changes only. Provider rollout remains gated until Phase 5 verifies the complete listener and bridge path.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            if let assessment = host.discoveryAssessment {
                Section {
                    LabeledContent("Standalone app") {
                        Text(assessment.legacyApplicationState == .running ? "Running" : "Not running")
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Legacy artifacts") {
                        Text(legacyFootprintLabel(assessment))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Legacy socket") {
                        Text(socketStateLabel(assessment.legacySocketState))
                            .foregroundStyle(.secondary)
                    }

                    if !assessment.compatiblePreferences.isEmpty {
                        LabeledContent("Compatible preferences") {
                            Text(compatiblePreferencesLabel(assessment.compatiblePreferences))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    if assessment.legacyApplicationState == .running {
                        Label("Quit CodeIsland before setup", systemImage: "exclamationmark.triangle")
                    }

                    if assessment.legacySocketState == .occupied {
                        Label("Refresh after CodeIsland releases its socket", systemImage: "arrow.clockwise")
                    }

                    if assessment.hookState == .unreadable {
                        Label("Repair hooks.json before setup", systemImage: "doc.badge.exclamationmark")
                    }

                    if hasLegacyHooks(assessment) {
                        Label("Existing CodeIsland hooks stay unchanged until adoption is confirmed", systemImage: "checkmark.shield")
                    }
                } header: {
                    Text("Existing CodeIsland")
                } footer: {
                    Text("Atoll never quits or deletes the old app. Compatible feature preferences are shown only; security-sensitive approvals, webhooks, and remote settings are excluded.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Section {
                    ForEach(
                        Array(assessment.installationPlan.changes.enumerated()),
                        id: \.offset
                    ) { _, change in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(changeLabel(change.kind))
                            Text(displayPath(change.url))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("Paths setup would change")
                } footer: {
                    Text("These paths are disclosure only in Phase 4. No consent or activation control is enabled yet.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section {
                Label("Questions and approvals stay in Codex", systemImage: "arrow.up.forward.app")

                if codexProfile?.limitations.contains(.interactiveQuestionObservationUnavailable) == true {
                    Label("Interactive question observation is unavailable", systemImage: "info.circle")
                }

                if codexProfile?.limitations.contains(.toolFailureObservationUnavailable) == true {
                    Label("Tool failure observation is unavailable", systemImage: "info.circle")
                }

                Label("Future Atoll hooks still require Codex trust review", systemImage: "checkmark.shield")

                Label("No Codex files or settings have been changed", systemImage: "checkmark.shield")
            } header: {
                Text("Current boundaries")
            }
        }
    }

    private var toolPresenceLabel: String {
        guard let assessment = host.discoveryAssessment else { return "Checking…" }
        switch assessment.toolPresence {
        case .notDetected:
            return "Not found"
        case .detected(let url):
            return displayPath(url)
        }
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private var hookStateLabel: String {
        guard let assessment = host.discoveryAssessment else { return "Checking…" }
        switch assessment.hookState {
        case .missing:
            return "No hooks.json"
        case .unreadable:
            return "Needs attention"
        case .readable(let managedCount, let legacyCount):
            if managedCount == 0, legacyCount == 0 { return "No Code Island hooks" }
            return "Atoll \(managedCount), legacy \(legacyCount)"
        }
    }

    private func legacyFootprintLabel(_ assessment: CodeIslandAdoptionAssessment) -> String {
        guard !assessment.legacyFootprints.isEmpty else { return "None found" }
        return assessment.legacyFootprints
            .map(\.rawValue)
            .sorted()
            .joined(separator: ", ")
    }

    private func socketStateLabel(_ state: CodeIslandSocketState) -> String {
        switch state {
        case .absent: return "Clear"
        case .stale: return "Stale; reclaimable after consent"
        case .occupied: return "In use"
        case .unexpectedFile: return "Unexpected file"
        case .inaccessible: return "Cannot inspect"
        }
    }

    private func hasLegacyHooks(_ assessment: CodeIslandAdoptionAssessment) -> Bool {
        if case .readable(_, let legacyCount) = assessment.hookState {
            return legacyCount > 0
        }
        return false
    }

    private func compatiblePreferencesLabel(
        _ preferences: CodeIslandLegacyFeaturePreferences
    ) -> String {
        var labels: [String] = []
        if let grouping = preferences.sessionGrouping {
            labels.append("Grouping: \(grouping.rawValue)")
        }
        if let smartSuppression = preferences.smartSuppressionEnabled {
            labels.append("Smart suppression: \(smartSuppression ? "on" : "off")")
        }
        if let completion = preferences.completionPresentation {
            labels.append("Completion: \(completion.rawValue)")
        }
        if let speed = preferences.mascotSpeedPercent {
            labels.append("Mascot: \(speed)%")
        }
        if let sound = preferences.soundEffectsEnabled {
            labels.append("Sound: \(sound ? "on" : "off")")
        }
        return labels.joined(separator: " · ")
    }

    private func changeLabel(_ kind: CodeIslandConfigurationChangeKind) -> String {
        switch kind {
        case .modifyProviderHooks: return "Modify Codex hooks"
        case .installManagedBridge: return "Install Atoll-managed bridge"
        case .writeManagedReceipt: return "Write ownership receipt"
        case .createListenerSocket: return "Create listener socket"
        case .replaceStaleListenerSocket: return "Replace stale listener socket"
        case .resolveLegacySocketConflict: return "Resolve legacy socket conflict"
        }
    }

    private var capabilityLabel: String {
        guard let capability = codexProfile?.verifiedCapability else {
            return "Unverified"
        }
        switch capability {
        case .monitoring:
            return "Monitoring"
        case .nativeAttention:
            return "Native attention"
        }
    }
}
