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
import Sparkle
import SwiftUI

/// SwiftUI view shown when a Sparkle update is available.
/// Displays app icon with animated glow, version comparison with channel badge,
/// release notes, and action buttons.
struct UpdateFoundView: View {
    @ObservedObject var state: UpdateUIState
    @State private var glowOpacity: Double = 0.4
    @State private var showNotes: Bool = false

    private var channel: UpdateChannel {
        Defaults[.updateChannel]
    }

    private var newVersion: String {
        state.appcastItem?.displayVersionString ?? String(localized: "Unknown")
    }

    private var currentVersion: String {
        Bundle.main.releaseVersionNumber ?? String(localized: "Unknown")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with icon and version info
            VStack(spacing: 16) {
                // App icon with animated glow
                ZStack {
                    Circle()
                        .fill(Color(channel.badgeColor).opacity(glowOpacity))
                        .frame(width: 100, height: 100)
                        .blur(radius: 20)

                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: Color(channel.badgeColor).opacity(0.3), radius: 8, y: 4)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        glowOpacity = 0.8
                    }
                }

                // Title
                Text("A new version of Atoll is available!")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                // Version comparison
                HStack(spacing: 12) {
                    versionBadge(label: "Current", version: currentVersion)

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    versionBadge(label: "New", version: newVersion, highlighted: true)
                }

                // Channel badge
                HStack(spacing: 4) {
                    Image(systemName: channel.badgeIcon)
                        .font(.caption2)
                    Text(channel.displayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(channel.badgeColor).opacity(0.15))
                .foregroundStyle(Color(channel.badgeColor))
                .clipShape(Capsule())
            }
            .padding(.top, 28)
            .padding(.horizontal, 24)

            // Release notes (expandable)
            if showNotes, let html = state.releaseNotesHTML {
                ScrollView {
                    Text(html.strippingHTML)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary.opacity(0.5))
                )
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                withAnimation(.spring(response: 0.3)) {
                    showNotes.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(showNotes ? "Hide Release Notes" : "Show Release Notes")
                    Image(systemName: showNotes ? "chevron.up" : "chevron.down")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)

            Spacer()

            // Action buttons
            VStack(spacing: 8) {
                Button {
                    state.updateReply?(.install)
                } label: {
                    Text("Install Update")
                        .font(.system(.body, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(channel.badgeColor))
                .controlSize(.large)

                HStack(spacing: 16) {
                    Button("Remind Me Later") {
                        state.updateReply?(.dismiss)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)

                    Button("Skip This Version") {
                        state.updateReply?(.skip)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 460, height: 380)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func versionBadge(label: String, version: String, highlighted: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(version)
                .font(.system(.callout, design: .monospaced, weight: .medium))
                .foregroundStyle(highlighted ? Color(channel.badgeColor) : .primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(highlighted ? Color(channel.badgeColor).opacity(0.1) : Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - HTML Stripping Helper

private extension String {
    var strippingHTML: String {
        guard let data = self.data(using: .utf8),
              let attrStr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else {
            return self
        }
        return attrStr.string
    }
}

// MARK: - Preview

#Preview("Update Found") {
    UpdateFoundView(state: {
        let s = UpdateUIState()
        s.phase = .updateFound
        s.releaseNotesHTML = "<h3>What's New</h3><ul><li>Multi-channel update support</li><li>Custom updater UI</li><li>Bug fixes and improvements</li></ul>"
        return s
    }())
}
