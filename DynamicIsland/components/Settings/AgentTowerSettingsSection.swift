/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Defaults
import SwiftUI

/// Settings pane for Agent Tower.
///
/// Lives outside `SettingsView.swift` so the monolith does not grow; `SettingsView`
/// only gains a tab case and one call site.
///
/// `SettingsTab` is file-private to `SettingsView.swift`, so the search-highlight
/// id cannot be built here — the caller passes a builder instead.
struct AgentTowerSettings: View {
    /// Builds a search-highlight id for a control title. Defaults to the title
    /// itself, which is harmless when highlighting is not wired up.
    var highlightID: (String) -> String = { $0 }

    @ObservedObject private var manager = AgentTowerManager.shared

    @Default(.enableAgentTower) private var enableAgentTower
    @Default(.agentTowerApprovalsEnabled) private var approvalsEnabled
    @Default(.agentTowerEnabledKinds) private var enabledKinds
    @Default(.agentTowerMaxHeightFraction) private var maxHeightFraction
    @Default(.agentTowerSessionPruneHours) private var pruneHours
    @Default(.agentTowerRunningEmoji) private var runningEmoji

    @State private var isConfirmingRemoval = false

    var body: some View {
        Form {
            generalSection
            if enableAgentTower {
                agentsSection
                approvalsSection
                notificationsSection
                statusSection
                appearanceSection
                housekeepingSection
            }
        }
        .onAppear { manager.refreshInstallationState() }
    }

    // MARK: - General

    private var generalSection: some View {
        Section {
            Defaults.Toggle(key: .enableAgentTower) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch AI coding agents")
                    Text("Shows a card in the notch for every coding agent running in a terminal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Watch AI coding agents"))
        } header: {
            Text("Agent Tower")
        } footer: {
            Text("Turning this on adds a hook to each selected agent's own configuration file. Atoll backs the file up first, only touches its `hooks` section, and removes its entries again when you turn this off.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Agents

    private var agentsSection: some View {
        Section {
            let available = manager.availableKinds
            if available.isEmpty {
                Text("No supported agent was found in your home folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(available) { kind in
                    Toggle(isOn: binding(for: kind)) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(kind.displayName)
                                if let descriptor = AgentHookInstaller.descriptor(for: kind, includeApprovals: false),
                                   let badge = verificationBadge(descriptor.verification) {
                                    Text(badge.label)
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(badge.tint.opacity(0.2), in: Capsule())
                                        .foregroundStyle(badge.tint)
                                        .help(Text(badge.explanation))
                                }
                            }
                            if let error = manager.installErrors[kind] {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else if let descriptor = AgentHookInstaller.descriptor(for: kind, includeApprovals: false) {
                                Text(abbreviated(descriptor.configURL.path))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if AgentKind.allCases.contains(where: { !$0.supportsHookInstallation }) {
                Text("opencode is not supported: it customises behaviour through JavaScript plugins rather than a hook configuration, so there is nothing for Atoll to add.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Agents to watch")
        } footer: {
            Text("\"Monitoring only\" means the agent's config shape is confirmed but Atoll has not observed it acting on an approval — approvals may simply do nothing there. \"Experimental\" means the agent is not installed here, so nothing has been confirmed. In both cases Atoll's hook fails silently, so your agent's own prompt appears as usual rather than anything interfering.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func binding(for kind: AgentKind) -> Binding<Bool> {
        Binding(
            get: { enabledKinds.contains(kind) },
            set: { isOn in
                var updated = enabledKinds
                if isOn {
                    guard !updated.contains(kind) else { return }
                    updated.append(kind)
                } else {
                    updated.removeAll { $0 == kind }
                }
                enabledKinds = updated
            }
        )
    }

    // MARK: - Approvals

    private var approvalsSection: some View {
        Section {
            Defaults.Toggle(key: .agentTowerApprovalsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Answer permission prompts from the notch")
                    Text("Adds a blocking hook so you can approve or deny a command without switching to the terminal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .settingsHighlight(id: highlightID("Answer permission prompts from the notch"))

            if approvalsEnabled {
                Defaults.Toggle(key: .agentTowerFlagDangerousCommands) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Flag destructive commands")
                        Text("Warns before approving things like recursive deletes, force pushes, or piping a download into a shell.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Defaults.Toggle(key: .agentTowerAllowAlwaysAllowRules) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offer \"Always allow\"")
                        Text("Lets an approval be remembered for this project for a week. Never offered for a command flagged as destructive.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !manager.approvalRules.isEmpty {
                    ForEach(manager.approvalRules) { rule in
                        LabeledContent {
                            Button(role: .destructive) {
                                manager.removeRule(id: rule.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.displaySubject)
                                    .font(.system(size: 11, design: .monospaced))
                                    .lineLimit(2)
                                Text(scopeDescription(rule))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(role: .destructive) {
                        manager.removeAllRules()
                    } label: {
                        Text("Forget all remembered approvals")
                    }
                }
            }
        } header: {
            Text("Approvals")
        } footer: {
            Text("If Atoll is closed, busy, or unsure, it stays silent and your agent's own prompt appears as usual — it can never approve something by failing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The badge for an agent's verification level, or `nil` when everything is
    /// confirmed and no caveat is needed.
    private func verificationBadge(
        _ level: VerificationLevel
    ) -> (label: String, tint: Color, explanation: String)? {
        switch level {
        case .verified:
            return nil
        case .schemaOnly:
            return (
                String(localized: "monitoring only"),
                .yellow,
                String(localized: "Session tracking is confirmed for this agent. Whether it acts on an approval from Atoll has not been observed.")
            )
        case .unverified:
            return (
                String(localized: "experimental"),
                .orange,
                String(localized: "This agent is not installed here, so its hook contract is written from documentation and has not been confirmed.")
            )
        }
    }

    private func scopeDescription(_ rule: AgentApprovalRule) -> String {
        switch rule.scope {
        case .session:
            return String(localized: "This session only")
        case .project(let path):
            let name = URL(fileURLWithPath: path).lastPathComponent
            if let expiresAt = rule.expiresAt {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                return name + " · " + formatter.localizedString(for: expiresAt, relativeTo: Date())
            }
            return name
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 5) {
                    Circle()
                        .fill(manager.isArmed ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(manager.isArmed ? String(localized: "Watching") : String(localized: "Not watching"))
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text("Status")
            }

            if let error = manager.setupError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            LabeledContent {
                Text(manager.installedKinds.isEmpty
                     ? String(localized: "None")
                     : manager.installedKinds.map(\.displayName).sorted().joined(separator: ", "))
                    .foregroundStyle(.secondary)
            } label: {
                Text("Hooks installed for")
            }

            LabeledContent {
                Text("\(manager.sessions.count)")
                    .foregroundStyle(.secondary)
            } label: {
                Text("Sessions tracked")
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Atoll keeps a small folder at ~/.atoll/agent-hooks. Deleting it, or setting ATOLL_HOOKS_DISABLED=1 in your shell, switches every hook off without touching any agent configuration.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Notifications

    /// The badge shown beside your track while agents are running.
    ///
    /// Presets rather than only a text field, because the point is to pick one
    /// in a second — but the field stays, so any emoji works, and emptying it
    /// means "use the plain symbol" rather than "show nothing".
    private var runningEmojiRow: some View {
        LabeledContent {
            HStack(spacing: 6) {
                ForEach(Self.emojiPresets, id: \.self) { preset in
                    Button {
                        runningEmoji = preset
                    } label: {
                        Text(preset)
                            .font(.system(size: 15))
                            .frame(width: 26, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(runningEmoji == preset
                                          ? Color.accentColor.opacity(0.25)
                                          : Color.secondary.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .help(Text("Use this one"))
                }

                TextField("", text: $runningEmoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 52)
                    .multilineTextAlignment(.center)
                    .onChange(of: runningEmoji) { _, new in
                        // One character: the badge is a 20-point circle, and a
                        // pasted sentence would render as a smear.
                        let first = new.first.map(String.init) ?? ""
                        if new != first { runningEmoji = first }
                    }

                Button {
                    runningEmoji = ""
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help(Text("Use the plain symbol instead"))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Badge for running agents")
                Text("Shown next to your track in the closed notch, beside the number of agents running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static let emojiPresets = ["🤖", "✨", "⚡️", "🧠", "🛠️"]

    private var notificationsSection: some View {
        Section {
            Defaults.Toggle(key: .agentTowerShowLiveActivity) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show waiting agents in the closed notch")
                    Text("A waiting approval takes the notch over music. A merely-running agent shows as a small count beside your track instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            runningEmojiRow

            Defaults.Toggle(key: .agentTowerEscalationEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remind me while an agent waits")
                    Text("Nudges immediately, then after 8 seconds, 1, 5 and 15 minutes — widening so an unattended request does not become a stream of alerts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Defaults.Toggle(key: .agentTowerPlaySound) {
                Text("Play a sound with each reminder")
            }

            Defaults.Toggle(key: .agentTowerPrivacyMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Privacy mode")
                    Text("Silences reminders without hiding the request, so nothing pops up while you are sharing your screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Reminders are also silenced automatically while a Focus mode is on.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent {
                    Text("\(Int(maxHeightFraction * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } label: {
                    Text("Tab height")
                }
                Slider(value: $maxHeightFraction, in: 0.25...0.7, step: 0.05)
            }
            .settingsHighlight(id: highlightID("Tab height"))
        } header: {
            Text("Appearance")
        } footer: {
            Text("How much of the screen the Agents tab may use when the notch is open.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Housekeeping

    private var housekeepingSection: some View {
        Section {
            Picker(selection: $pruneHours) {
                Text("6 hours").tag(6)
                Text("24 hours").tag(24)
                Text("3 days").tag(72)
                Text("A week").tag(168)
            } label: {
                Text("Forget sessions after")
            }

            Button(role: .destructive) {
                isConfirmingRemoval = true
            } label: {
                Text("Remove all Atoll hooks")
            }
            .confirmationDialog(
                Text("Remove Atoll's hooks from every agent?"),
                isPresented: $isConfirmingRemoval,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Remove"), role: .destructive) {
                    manager.removeAllHooks()
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text("Your own hooks and every other setting in those files are left untouched. Backups stay in Atoll's application support folder.")
            }
        } header: {
            Text("Housekeeping")
        }
    }

    private func abbreviated(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
