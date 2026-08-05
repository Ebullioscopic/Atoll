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
import SwiftUI

/// Read-only Phase 3 status for the embedded Code Island feature.
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
            } header: {
                Text("Code Island")
            } footer: {
                Text("Code Island is built into Atoll. The host shell is ready, but provider setup is not available yet.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                LabeledContent("Provider") {
                    Text("Codex")
                }

                LabeledContent("Verified capability") {
                    Text(capabilityLabel)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Activation") {
                    Text(codexProfile?.isActivationAvailable == true ? "Available" : "Unavailable")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Codex")
            } footer: {
                Text("Monitoring means lifecycle and meaningful state changes only. It does not move Codex decisions into Atoll.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                Label("Questions and approvals stay in Codex", systemImage: "arrow.up.forward.app")

                if codexProfile?.limitations.contains(.interactiveQuestionObservationUnavailable) == true {
                    Label("Interactive question observation is unavailable", systemImage: "info.circle")
                }

                if codexProfile?.limitations.contains(.toolFailureObservationUnavailable) == true {
                    Label("Tool failure observation is unavailable", systemImage: "info.circle")
                }

                Label("No Codex files or settings have been changed", systemImage: "checkmark.shield")
            } header: {
                Text("Current boundaries")
            }
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
