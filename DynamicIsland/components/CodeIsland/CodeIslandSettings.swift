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
import Foundation
import SwiftUI

/// Atoll-owned activation and adoption settings for Code Island.
struct CodeIslandSettings: View {
    @ObservedObject private var host = CodeIslandHost.shared
    @State private var activationPreview: ActivationPreview?
    @State private var showDeactivationConfirmation = false

    private let codexProfile = ProviderCapabilityRegistry.phaseFive.profile(for: .codex)

    var body: some View {
        Form {
            statusSection
            providerSection

            if let assessment = host.discoveryAssessment {
                adoptionSection(assessment)
                changedPathsSection(assessment)
            }

            boundariesSection
        }
        .sheet(item: $activationPreview) { preview in
            CodeIslandActivationConsentSheet(
                plan: preview.plan,
                hasLegacyHooks: preview.hasLegacyHooks,
                confirm: {
                    host.activateCodex(planID: preview.id)
                }
            )
        }
        .confirmationDialog(
            "Deactivate Codex Monitoring?",
            isPresented: $showDeactivationConfirmation
        ) {
            Button("Deactivate", role: .destructive) {
                host.deactivateCodex()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Atoll will remove only its managed helper and hooks, restore adopted legacy CodeIsland hooks, and leave unrelated Codex configuration unchanged.")
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Status") {
                Text(host.isActivated ? "Connected" : "Not connected")
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
                    .help("Refresh Code Island discovery")
                }
            }

            switch host.operationState {
            case .idle:
                EmptyView()
            case .activating:
                Label("Activating Codex Monitoring…", systemImage: "progress.indicator")
            case .repairing:
                Label("Verifying Codex Monitoring…", systemImage: "progress.indicator")
            case .deactivating:
                Label("Deactivating Codex Monitoring…", systemImage: "progress.indicator")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Code Island")
        } footer: {
            Text("Code Island is part of Atoll. It runs no provider listener and changes no Codex configuration until you confirm setup.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var providerSection: some View {
        Section {
            LabeledContent("Provider") { Text("Codex") }
            LabeledContent("Detected") {
                Text(toolPresenceLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            LabeledContent("Verified capability") {
                Text(capabilityLabel)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Hook state") {
                Text(hookStateLabel)
                    .foregroundStyle(.secondary)
            }

            if host.isActivated {
                HStack {
                    Button("Verify & Repair") {
                        host.repairCodex()
                    }
                    Button("Deactivate", role: .destructive) {
                        showDeactivationConfirmation = true
                    }
                }
                .disabled(operationInProgress)
            } else {
                Button("Activate Codex Monitoring") {
                    guard let assessment = host.discoveryAssessment else { return }
                    activationPreview = ActivationPreview(
                        plan: assessment.installationPlan,
                        hasLegacyHooks: hasLegacyHooks(assessment)
                    )
                }
                .disabled(!canActivate)
            }
        } header: {
            Text("Codex")
        } footer: {
            Text("Monitoring covers lifecycle and meaningful state changes. It does not move questions or decisions into Atoll.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func adoptionSection(_ assessment: CodeIslandAdoptionAssessment) -> some View {
        Section {
            LabeledContent("Standalone app") {
                Text(assessment.legacyApplicationState == .running ? "Running" : "Not running")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Legacy artifacts") {
                Text(legacyFootprintLabel(assessment))
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Listener socket") {
                Text(host.isActivated ? "Owned by Atoll" : socketStateLabel(assessment.legacySocketState))
                    .foregroundStyle(.secondary)
            }

            if !assessment.compatiblePreferences.isEmpty {
                LabeledContent("Compatible preferences") {
                    Text(compatiblePreferencesLabel(assessment.compatiblePreferences))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            if assessment.legacyApplicationState == .running, !host.isActivated {
                Label("Quit CodeIsland before setup", systemImage: "exclamationmark.triangle")
            }
            if assessment.legacySocketState == .occupied, !host.isActivated {
                Label("Refresh after CodeIsland releases its socket", systemImage: "arrow.clockwise")
            }
            if assessment.hookState == .unreadable {
                Label("Repair hooks.json before setup", systemImage: "doc.badge.exclamationmark")
            }
            if hasLegacyHooks(assessment), !host.isActivated {
                Label("Setup will replace and reversibly back up recognized legacy hooks", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("Existing CodeIsland")
        } footer: {
            Text("Atoll never quits or deletes the old app. Unrelated Codex hooks and security-sensitive standalone settings are not imported.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func changedPathsSection(_ assessment: CodeIslandAdoptionAssessment) -> some View {
        Section {
            ForEach(Array(assessment.installationPlan.changes.enumerated()), id: \.offset) { _, change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(codeIslandChangeLabel(change.kind))
                    Text(codeIslandDisplayPath(change.url))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text(host.isActivated ? "Managed paths" : "Paths setup would change")
        } footer: {
            Text(host.isActivated
                 ? "Deactivation targets only the receipt-owned entries shown here."
                 : "The confirmation sheet repeats this exact plan before any write occurs.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var boundariesSection: some View {
        Section {
            Label("Questions and approvals stay in Codex", systemImage: "arrow.up.forward.app")

            if codexProfile?.limitations.contains(.interactiveQuestionObservationUnavailable) == true {
                Label("Interactive question observation is unavailable", systemImage: "info.circle")
            }
            if codexProfile?.limitations.contains(.toolFailureObservationUnavailable) == true {
                Label("Tool failure observation is unavailable", systemImage: "info.circle")
            }

            Label("Run /hooks in Codex to review and trust Atoll's command", systemImage: "checkmark.shield")
            Label(
                host.isActivated
                    ? "Atoll stores only session metadata"
                    : "Codex Monitoring is inactive",
                systemImage: "lock.shield"
            )
        } header: {
            Text("Boundaries")
        }
    }

    private var canActivate: Bool {
        guard codexProfile?.isActivationAvailable == true,
              let assessment = host.discoveryAssessment,
              assessment.blockers.isEmpty,
              !operationInProgress else {
            return false
        }
        if case .detected = assessment.toolPresence { return true }
        return false
    }

    private var operationInProgress: Bool {
        switch host.operationState {
        case .activating, .repairing, .deactivating:
            return true
        case .idle, .failed:
            return false
        }
    }

    private var toolPresenceLabel: String {
        guard let assessment = host.discoveryAssessment else { return "Checking…" }
        switch assessment.toolPresence {
        case .notDetected: return "Not found"
        case .detected(let url): return codeIslandDisplayPath(url)
        }
    }

    private var hookStateLabel: String {
        guard let assessment = host.discoveryAssessment else { return "Checking…" }
        switch assessment.hookState {
        case .missing: return "No hooks.json"
        case .unreadable: return "Needs attention"
        case .readable(let managedCount, let legacyCount):
            if managedCount == 0, legacyCount == 0 { return "No Code Island hooks" }
            return "Atoll \(managedCount), legacy \(legacyCount)"
        }
    }

    private var capabilityLabel: String {
        switch codexProfile?.verifiedCapability {
        case .monitoring: return "Monitoring"
        case .nativeAttention: return "Native attention"
        case nil: return "Unverified"
        }
    }

    private func legacyFootprintLabel(_ assessment: CodeIslandAdoptionAssessment) -> String {
        guard !assessment.legacyFootprints.isEmpty else { return "None found" }
        return assessment.legacyFootprints.map(\.rawValue).sorted().joined(separator: ", ")
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
        if let grouping = preferences.sessionGrouping { labels.append("Grouping: \(grouping.rawValue)") }
        if let suppression = preferences.smartSuppressionEnabled { labels.append("Smart suppression: \(suppression ? "on" : "off")") }
        if let completion = preferences.completionPresentation { labels.append("Completion: \(completion.rawValue)") }
        if let speed = preferences.mascotSpeedPercent { labels.append("Mascot: \(speed)%") }
        if let sound = preferences.soundEffectsEnabled { labels.append("Sound: \(sound ? "on" : "off")") }
        return labels.joined(separator: " · ")
    }
}

private struct ActivationPreview: Identifiable {
    let plan: CodeIslandInstallationPlan
    let hasLegacyHooks: Bool
    var id: UUID { plan.id }
}

private struct CodeIslandActivationConsentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plan: CodeIslandInstallationPlan
    let hasLegacyHooks: Bool
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Confirm Codex Monitoring")
                    .font(.title2.weight(.semibold))
                Text("Atoll will observe lifecycle metadata only. Questions, approvals, and all decisions remain in Codex.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Verified capability") {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Monitoring", systemImage: "waveform.path.ecg")
                    Label("Interactive questions are not observed", systemImage: "info.circle")
                    Label("Tool failures are not inferred from rich output", systemImage: "info.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("Exact changes") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(plan.changes.enumerated()), id: \.offset) { _, change in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(codeIslandChangeLabel(change.kind))
                                Text(codeIslandDisplayPath(change.url))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
                .padding(.vertical, 4)
            }

            if hasLegacyHooks {
                Text("Recognized legacy CodeIsland commands will be backed up in Atoll's ownership receipt, replaced to prevent duplicate raw delivery, and restored on deactivation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Label("Run /hooks in Codex after activation to review and trust the Atoll-managed command.", systemImage: "checkmark.shield")
                .font(.caption)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Activate Codex Monitoring") {
                    confirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

private func codeIslandDisplayPath(_ url: URL) -> String {
    (url.path as NSString).abbreviatingWithTildeInPath
}

private func codeIslandChangeLabel(_ kind: CodeIslandConfigurationChangeKind) -> String {
    switch kind {
    case .modifyProviderHooks: return "Modify Codex hooks"
    case .replaceLegacyProviderHooks: return "Replace legacy CodeIsland hooks"
    case .installManagedBridge: return "Install Atoll-managed bridge"
    case .writeManagedReceipt: return "Write ownership receipt and adoption backup"
    case .createListenerSocket: return "Create listener socket"
    case .replaceStaleListenerSocket: return "Replace stale listener socket"
    case .resolveLegacySocketConflict: return "Resolve legacy socket conflict"
    }
}
