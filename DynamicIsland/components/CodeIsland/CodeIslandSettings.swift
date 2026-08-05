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
import Foundation
import SwiftUI

/// Atoll-owned activation and adoption settings for Code Island.
struct CodeIslandSettings: View {
    @ObservedObject private var host = CodeIslandHost.shared
    @ObservedObject private var featurePreferences = CodeIslandFeaturePreferenceStore.shared
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

            sessionBehaviorSection
            mascotSection
            soundSection
            boundariesSection
        }
        .sheet(item: $activationPreview) { preview in
            CodeIslandActivationConsentSheet(
                plan: preview.plan,
                hasLegacyHooks: preview.hasLegacyHooks,
                compatiblePreferences: preview.compatiblePreferences,
                confirm: { importPreferences in
                    host.activateCodex(
                        planID: preview.id,
                        importCompatiblePreferences: importPreferences
                    )
                }
            )
        }
        .confirmationDialog(
            ci("Deactivate Codex Monitoring?"),
            isPresented: $showDeactivationConfirmation
        ) {
            Button(ci("Deactivate"), role: .destructive) {
                host.deactivateCodex()
            }
            Button(ci("Cancel"), role: .cancel) {}
        } message: {
            Text(ci("Atoll will remove only its managed helper and hooks, restore adopted legacy CodeIsland hooks, and leave unrelated Codex configuration unchanged."))
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent(ci("Status")) {
                Text(host.isActivated ? ci("Connected") : ci("Not connected"))
                    .foregroundStyle(.secondary)
            }

            LabeledContent(ci("Atoll host")) {
                Text(host.lifecycleState == .running ? ci("Ready") : ci("Stopped"))
                    .foregroundStyle(.secondary)
            }

            LabeledContent(ci("Discovery")) {
                HStack(spacing: 8) {
                    Text(host.discoveryAssessment == nil ? ci("Pending") : ci("Current"))
                        .foregroundStyle(.secondary)
                    Button {
                        host.refreshDiscovery()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(ci("Refresh Code Island discovery"))
                    .accessibilityLabel(ci("Refresh Code Island discovery"))
                }
            }

            switch host.operationState {
            case .idle:
                EmptyView()
            case .activating:
                Label(ci("Activating Codex Monitoring…"), systemImage: "progress.indicator")
            case .repairing:
                Label(ci("Verifying Codex Monitoring…"), systemImage: "progress.indicator")
            case .deactivating:
                Label(ci("Deactivating Codex Monitoring…"), systemImage: "progress.indicator")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text(ci("Code Island"))
        } footer: {
            Text(ci("Code Island is part of Atoll. It runs no provider listener and changes no Codex configuration until you confirm setup."))
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var providerSection: some View {
        Section {
            LabeledContent(ci("Provider")) { Text(ci("Codex")) }
            LabeledContent(ci("Detected")) {
                Text(toolPresenceLabel)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            LabeledContent(ci("Verified capability")) {
                Text(capabilityLabel)
                    .foregroundStyle(.secondary)
            }
            LabeledContent(ci("Hook state")) {
                Text(hookStateLabel)
                    .foregroundStyle(.secondary)
            }

            if host.isActivated {
                HStack {
                    Button(ci("Verify & Repair")) {
                        host.repairCodex()
                    }
                    Button(ci("Deactivate"), role: .destructive) {
                        showDeactivationConfirmation = true
                    }
                }
                .disabled(operationInProgress)
            } else {
                Button(ci("Activate Codex Monitoring")) {
                    guard let assessment = host.discoveryAssessment else { return }
                    activationPreview = ActivationPreview(
                        plan: assessment.installationPlan,
                        hasLegacyHooks: hasLegacyHooks(assessment),
                        compatiblePreferences: assessment.compatiblePreferences
                    )
                }
                .disabled(!canActivate)
            }
        } header: {
            Text(ci("Codex"))
        } footer: {
            Text(ci("Monitoring covers lifecycle and meaningful state changes. It does not move questions or decisions into Atoll."))
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func adoptionSection(_ assessment: CodeIslandAdoptionAssessment) -> some View {
        Section {
            LabeledContent(ci("Standalone app")) {
                Text(
                    assessment.legacyApplicationState == .running
                        ? ci("Running")
                        : ci("Not running")
                )
                    .foregroundStyle(.secondary)
            }
            LabeledContent(ci("Legacy artifacts")) {
                Text(legacyFootprintLabel(assessment))
                    .foregroundStyle(.secondary)
            }
            LabeledContent(ci("Listener socket")) {
                Text(host.isActivated ? ci("Owned by Atoll") : socketStateLabel(assessment.legacySocketState))
                    .foregroundStyle(.secondary)
            }

            if assessment.compatiblePreferences.hasImportableFeaturePreferences {
                LabeledContent(ci("Compatible preferences")) {
                    Text(compatiblePreferencesLabel(assessment.compatiblePreferences))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            if assessment.legacyApplicationState == .running, !host.isActivated {
                Label(ci("Quit CodeIsland before setup"), systemImage: "exclamationmark.triangle")
            }
            if assessment.legacySocketState == .occupied, !host.isActivated {
                Label(ci("Refresh after CodeIsland releases its socket"), systemImage: "arrow.clockwise")
            }
            if assessment.hookState == .unreadable {
                Label(ci("Repair hooks.json before setup"), systemImage: "doc.badge.exclamationmark")
            }
            if hasLegacyHooks(assessment), !host.isActivated {
                Label(ci("Setup will replace and reversibly back up recognized legacy hooks"), systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text(ci("Existing CodeIsland"))
        } footer: {
            Text(ci("Atoll never quits or deletes the old app. Unrelated Codex hooks and security-sensitive standalone settings are not imported."))
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
            Text(host.isActivated ? ci("Managed paths") : ci("Paths setup would change"))
        } footer: {
            Text(
                host.isActivated
                    ? ci("Deactivation targets only the receipt-owned entries shown here.")
                    : ci("The confirmation sheet repeats this exact plan before any write occurs.")
            )
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private var sessionBehaviorSection: some View {
        Section {
            Picker(ci("Session grouping"), selection: preferenceBinding(\.dashboardGrouping)) {
                Text(ci("All sessions")).tag(CodeIslandDashboardGrouping.all)
                Text(ci("By status")).tag(CodeIslandDashboardGrouping.status)
                Text(ci("By provider")).tag(CodeIslandDashboardGrouping.provider)
            }

            Picker(ci("Keep completed sessions"), selection: preferenceBinding(\.retentionMinutes)) {
                Text(ci("Until removed")).tag(0)
                Text(ci("10 minutes")).tag(10)
                Text(ci("30 minutes")).tag(30)
                Text(ci("1 hour")).tag(60)
                Text(ci("2 hours")).tag(120)
            }

            Toggle(ci("Smart suppression"), isOn: preferenceBinding(\.presentation.smartSuppressionEnabled))
            Text(ci("Suppress a pop-out only after Atoll positively matches the exact visible origin session."))
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(ci("Completion pop-out"), selection: preferenceBinding(\.presentation.completionPresentation)) {
                Text(ci("Full")).tag(CodeIslandCompletionPresentation.expand)
                Text(ci("Glance")).tag(CodeIslandCompletionPresentation.glance)
                Text(ci("Off")).tag(CodeIslandCompletionPresentation.off)
            }
        } header: {
            Text(ci("Session behavior"))
        }
    }

    private var mascotSection: some View {
        Section {
            Toggle(ci("Show Dex mascot"), isOn: preferenceBinding(\.mascotsEnabled))

            if featurePreferences.snapshot.mascotsEnabled {
                HStack {
                    Text(ci("Animation speed"))
                    Slider(
                        value: percentageBinding(\.mascotSpeedPercent),
                        in: 0...300,
                        step: 25
                    )
                    .accessibilityLabel(ci("Animation speed"))
                    .accessibilityValue(animationSpeedAccessibilityValue)
                    Text(verbatim: "\(featurePreferences.snapshot.mascotSpeedPercent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        } header: {
            Text(ci("Mascot"))
        } footer: {
            Text(ci("Reduce Motion always pauses mascot animation, regardless of this speed."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var soundSection: some View {
        Section {
            Toggle(ci("Enable feature sounds"), isOn: preferenceBinding(\.soundEffectsEnabled))

            if featurePreferences.snapshot.soundEffectsEnabled {
                HStack {
                    Text(ci("Volume"))
                    Slider(
                        value: percentageBinding(\.soundVolumePercent),
                        in: 0...100,
                        step: 5
                    )
                    .accessibilityLabel(ci("Volume"))
                    .accessibilityValue(soundVolumeAccessibilityValue)
                    Text(verbatim: "\(featurePreferences.snapshot.soundVolumePercent)%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }

                soundPreferenceRow(
                    ci("Session started"),
                    effect: .sessionStarted,
                    keyPath: \.sessionStartSoundEnabled
                )
                soundPreferenceRow(
                    ci("Approval needed"),
                    effect: .attentionRequired,
                    keyPath: \.attentionSoundEnabled
                )
                soundPreferenceRow(
                    ci("Completed"),
                    effect: .completed,
                    keyPath: \.completionSoundEnabled
                )
                soundPreferenceRow(
                    ci("Failure (when supported)"),
                    effect: .failed,
                    keyPath: \.failureSoundEnabled
                )
            }
        } header: {
            Text(ci("Feature sounds"))
        } footer: {
            Text(ci("Sounds play only for an Atoll-selected presentation; suppressed and routine events stay silent."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func soundPreferenceRow(
        _ title: String,
        effect: CodeIslandSoundEffect,
        keyPath: WritableKeyPath<CodeIslandFeaturePreferences, Bool>
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                CodeIslandSoundPlayer.shared.play(
                    effect,
                    volumePercent: featurePreferences.snapshot.soundVolumePercent
                )
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .help("\(ci("Preview")) \(title.lowercased()) \(ci("sound"))")
            .accessibilityLabel("\(ci("Preview")) \(title) \(ci("sound"))")

            Toggle(isOn: preferenceBinding(keyPath)) {
                EmptyView()
            }
            .labelsHidden()
            .accessibilityLabel(title)
        }
    }

    private func preferenceBinding<Value>(
        _ keyPath: WritableKeyPath<CodeIslandFeaturePreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { featurePreferences.snapshot[keyPath: keyPath] },
            set: { value in
                featurePreferences.update { $0[keyPath: keyPath] = value }
                host.refreshFeaturePreferences()
            }
        )
    }

    private func percentageBinding(
        _ keyPath: WritableKeyPath<CodeIslandFeaturePreferences, Int>
    ) -> Binding<Double> {
        Binding(
            get: { Double(featurePreferences.snapshot[keyPath: keyPath]) },
            set: { value in
                featurePreferences.update { $0[keyPath: keyPath] = Int(value) }
                host.refreshFeaturePreferences()
            }
        )
    }

    private var animationSpeedAccessibilityValue: String {
        "\(featurePreferences.snapshot.mascotSpeedPercent)%"
    }

    private var soundVolumeAccessibilityValue: String {
        "\(featurePreferences.snapshot.soundVolumePercent)%"
    }

    private var boundariesSection: some View {
        Section {
            Label(ci("Questions and approvals stay in Codex"), systemImage: "arrow.up.forward.app")

            if codexProfile?.limitations.contains(.interactiveQuestionObservationUnavailable) == true {
                Label(ci("Interactive question observation is unavailable"), systemImage: "info.circle")
            }
            if codexProfile?.limitations.contains(.toolFailureObservationUnavailable) == true {
                Label(ci("Tool failure observation is unavailable"), systemImage: "info.circle")
            }

            Label(ci("Run /hooks in Codex to review and trust Atoll's command"), systemImage: "checkmark.shield")
            Label(
                host.isActivated
                    ? ci("Atoll stores only session metadata")
                    : ci("Codex Monitoring is inactive"),
                systemImage: "lock.shield"
            )
        } header: {
            Text(ci("Boundaries"))
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
        guard let assessment = host.discoveryAssessment else { return ci("Checking…") }
        switch assessment.toolPresence {
        case .notDetected: return ci("Not found")
        case .detected(let url): return codeIslandDisplayPath(url)
        }
    }

    private var hookStateLabel: String {
        guard let assessment = host.discoveryAssessment else { return ci("Checking…") }
        switch assessment.hookState {
        case .missing: return ci("No hooks.json")
        case .unreadable: return ci("Needs attention")
        case .readable(let managedCount, let legacyCount):
            if managedCount == 0, legacyCount == 0 { return ci("No Code Island hooks") }
            return "Atoll \(managedCount), \(ci("legacy")) \(legacyCount)"
        }
    }

    private var capabilityLabel: String {
        switch codexProfile?.verifiedCapability {
        case .monitoring: return ci("Monitoring")
        case .nativeAttention: return ci("Native attention")
        case nil: return ci("Unverified")
        }
    }

    private func legacyFootprintLabel(_ assessment: CodeIslandAdoptionAssessment) -> String {
        guard !assessment.legacyFootprints.isEmpty else { return ci("None found") }
        return assessment.legacyFootprints.map { footprint in
            switch footprint {
            case .preferences: return ci("preferences")
            case .supportDirectory: return ci("support directory")
            case .codexHooks: return ci("Codex hooks")
            }
        }.sorted().joined(separator: ", ")
    }

    private func socketStateLabel(_ state: CodeIslandSocketState) -> String {
        switch state {
        case .absent: return ci("Clear")
        case .stale: return ci("Stale; reclaimable after consent")
        case .occupied: return ci("In use")
        case .unexpectedFile: return ci("Unexpected file")
        case .inaccessible: return ci("Cannot inspect")
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
            labels.append("\(ci("Grouping")): \(legacyGroupingLabel(grouping))")
        }
        if let suppression = preferences.smartSuppressionEnabled {
            labels.append("\(ci("Smart suppression")): \(suppression ? ci("on") : ci("off"))")
        }
        if let completion = preferences.completionPresentation {
            labels.append("\(ci("Completion")): \(legacyCompletionLabel(completion))")
        }
        if let speed = preferences.mascotSpeedPercent { labels.append("\(ci("Mascot")): \(speed)%") }
        if let sound = preferences.soundEffectsEnabled {
            labels.append("\(ci("Sound")): \(sound ? ci("on") : ci("off"))")
        }
        if let volume = preferences.soundVolumePercent { labels.append("\(ci("Volume")): \(volume)%") }
        return labels.joined(separator: " · ")
    }

    private func legacyGroupingLabel(
        _ grouping: CodeIslandLegacySessionGrouping
    ) -> String {
        switch grouping {
        case .all: return ci("All sessions")
        case .status: return ci("By status")
        case .provider: return ci("By provider")
        }
    }

    private func legacyCompletionLabel(
        _ completion: CodeIslandLegacyCompletionPresentation
    ) -> String {
        switch completion {
        case .expand: return ci("Full")
        case .glance: return ci("Glance")
        case .off: return ci("Off")
        }
    }
}

private struct ActivationPreview: Identifiable {
    let plan: CodeIslandInstallationPlan
    let hasLegacyHooks: Bool
    let compatiblePreferences: CodeIslandLegacyFeaturePreferences
    var id: UUID { plan.id }
}

private struct CodeIslandActivationConsentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let plan: CodeIslandInstallationPlan
    let hasLegacyHooks: Bool
    let compatiblePreferences: CodeIslandLegacyFeaturePreferences
    let confirm: (Bool) -> Void
    @State private var importPreferences: Bool

    init(
        plan: CodeIslandInstallationPlan,
        hasLegacyHooks: Bool,
        compatiblePreferences: CodeIslandLegacyFeaturePreferences,
        confirm: @escaping (Bool) -> Void
    ) {
        self.plan = plan
        self.hasLegacyHooks = hasLegacyHooks
        self.compatiblePreferences = compatiblePreferences
        self.confirm = confirm
        _importPreferences = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(ci("Confirm Codex Monitoring"))
                    .font(.title2.weight(.semibold))
                Text(ci("Atoll will observe lifecycle metadata only. Questions, approvals, and all decisions remain in Codex."))
                    .foregroundStyle(.secondary)
            }

            GroupBox(ci("Verified capability")) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(ci("Monitoring"), systemImage: "waveform.path.ecg")
                    Label(ci("Interactive questions are not observed"), systemImage: "info.circle")
                    Label(ci("Tool failures are not inferred from rich output"), systemImage: "info.circle")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox(ci("Exact changes")) {
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
                Text(ci("Recognized legacy CodeIsland commands will be backed up in Atoll's ownership receipt, replaced to prevent duplicate raw delivery, and restored on deactivation."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if compatiblePreferences.hasImportableFeaturePreferences {
                Toggle(ci("Import compatible feature preferences"), isOn: $importPreferences)
                Text(ci("Only grouping, smart suppression, completion style, mascot speed, sound enablement, and sound volume are eligible."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Label(ci("Run /hooks in Codex after activation to review and trust the Atoll-managed command."), systemImage: "checkmark.shield")
                .font(.caption)

            HStack {
                Spacer()
                Button(ci("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(ci("Activate Codex Monitoring")) {
                    confirm(importPreferences)
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
    case .modifyProviderHooks: return ci("Modify Codex hooks")
    case .replaceLegacyProviderHooks: return ci("Replace legacy CodeIsland hooks")
    case .installManagedBridge: return ci("Install Atoll-managed bridge")
    case .writeManagedReceipt: return ci("Write ownership receipt and adoption backup")
    case .createListenerSocket: return ci("Create listener socket")
    case .replaceStaleListenerSocket: return ci("Replace stale listener socket")
    case .resolveLegacySocketConflict: return ci("Resolve legacy socket conflict")
    }
}

private func ci(_ key: String.LocalizationValue) -> String {
    CodeIslandLocalization.string(key)
}
