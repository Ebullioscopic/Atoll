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

/// The card that asks the user to approve or deny what an agent wants to do.
///
/// ## Focus
/// Buttons work without the notch taking key focus, so approving never pulls the
/// user out of their terminal. The denial-note field is the one control that
/// needs focus, and it only gets it when the user explicitly clicks into it —
/// which is why it is revealed by a button rather than always present.
struct AgentApprovalRequestView: View {
    let request: AgentPendingRequest
    let projectName: String?
    let onDecide: (AgentDecision) -> Void

    @Default(.agentTowerAllowAlwaysAllowRules) private var allowPersistentRules
    @Default(.agentTowerFlagDangerousCommands) private var showDangerousCommandWarnings

    @State private var isWritingNote = false
    @State private var note = ""
    @FocusState private var isNoteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            riskBanner
            subject
            if isWritingNote { noteField } else { actions }
        }
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(request.risk >= .high ? 0.55 : 0.22), lineWidth: 1)
        )
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
            Text(request.toolLabel)
                .font(.system(size: 12, weight: .semibold))
            if let projectName, !projectName.isEmpty {
                Text(projectName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            countdown
        }
    }

    /// Shows how long the agent will keep waiting, so an unattended request does
    /// not look like it will hang forever.
    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, request.expiresAt.timeIntervalSince(context.date))
            Text(AgentSessionCard.elapsedText(remaining))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(remaining < 30 ? .orange : .secondary)
                .help(Text("Time left before Atoll stops waiting and the agent asks you itself"))
        }
    }

    @ViewBuilder
    private var riskBanner: some View {
        if showDangerousCommandWarnings, let worst = request.riskFlags.first {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: request.risk >= .high ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(worst.summary)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                    if request.riskFlags.count > 1 {
                        Text(request.riskFlags.dropFirst().map(\.summary).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var subject: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(subjectText)
                .font(.system(size: 11, design: subjectIsCode ? .monospaced : .default))
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: 92)
        .padding(7)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var actions: some View {
        HStack(spacing: 6) {
            button(String(localized: "Approve"), tint: .green, prominent: true) {
                onDecide(.allowOnce)
            }
            if request.allowsPersistentRule {
                button(String(localized: "This session"), tint: .green) {
                    onDecide(.allowForSession)
                }
            }
            if allowPersistentRules, request.allowsPersistentRule {
                button(String(localized: "Always"), tint: .green) {
                    onDecide(.alwaysAllow)
                }
            }
            Spacer(minLength: 0)
            button(String(localized: "Deny"), tint: .red) {
                onDecide(.deny(reason: nil))
            }
            Button {
                isWritingNote = true
                // Focus only once the user has asked for the field.
                DispatchQueue.main.async { isNoteFocused = true }
            } label: {
                Image(systemName: "text.bubble")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(Text("Deny with a note explaining what to do instead"))
            .accessibilityLabel(Text("Deny with a note"))
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(String(localized: "What should it do instead?"), text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .lineLimit(1...3)
                .focused($isNoteFocused)
                .padding(6)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .onSubmit { submitNote() }

            HStack(spacing: 6) {
                Text("Typing here gives the notch keyboard focus.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                button(String(localized: "Cancel"), tint: .secondary) {
                    isWritingNote = false
                    isNoteFocused = false
                    note = ""
                }
                button(String(localized: "Send"), tint: .red, prominent: true) {
                    submitNote()
                }
            }
        }
    }

    private func submitNote() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onDecide(.deny(reason: trimmed.isEmpty ? nil : trimmed))
        isWritingNote = false
        isNoteFocused = false
        note = ""
    }

    private func button(
        _ title: String,
        tint: Color,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(prominent ? .black : tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.16)))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Presentation helpers

    private var subjectText: String {
        switch request.detail {
        case .shellCommand(let command): return command
        case .fileEdit(let path, let preview):
            guard let preview, !preview.isEmpty else { return path }
            return "\(path)\n\(preview)"
        case .plan(let text): return text
        case .generic(let text): return text
        }
    }

    private var subjectIsCode: Bool {
        switch request.detail {
        case .shellCommand, .fileEdit: return true
        case .plan, .generic: return false
        }
    }

    private var symbol: String {
        switch request.detail {
        case .shellCommand: return "terminal"
        case .fileEdit: return "square.and.pencil"
        case .plan: return "list.bullet.rectangle"
        case .generic: return "questionmark.circle"
        }
    }

    private var accent: Color {
        switch request.risk {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        case .none: return .blue
        }
    }
}
