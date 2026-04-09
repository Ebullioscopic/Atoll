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

import SwiftUI

/// Popover that displays all detected media sources in "All Music" mode,
/// allowing the user to switch between them or control playback.
/// Used in Standard Mode (notch). Modeled after AirPlaySelectorPopover.
struct MediaSourceSelectorPopover: View {
    @ObservedObject var musicManager: MusicManager
    var onHoverChanged: (Bool) -> Void
    var dismiss: () -> Void

    private var allSources: [MediaSource] {
        // Build a combined list: primary source first, then secondaries
        var sources: [MediaSource] = []

        if let primaryBundle = musicManager.bundleIdentifier, !primaryBundle.isEmpty {
            let primary = MediaSource(
                id: primaryBundle,
                bundleIdentifier: primaryBundle,
                title: musicManager.songTitle,
                artist: musicManager.artistName,
                artworkData: nil,
                isPlaying: musicManager.isPlaying,
                lastUpdated: Date()
            )
            sources.append(primary)
        }

        sources.append(contentsOf: musicManager.secondarySources)
        return sources
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Media Sources")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            if allSources.isEmpty {
                Text("No active media sources")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(allSources) { source in
                            sourceRow(source)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
    }

    private func sourceRow(_ source: MediaSource) -> some View {
        let isPrimary = source.bundleIdentifier == musicManager.bundleIdentifier

        return Button {
            if !isPrimary {
                musicManager.promoteSource(source)
            }
            dismiss()
        } label: {
            HStack(spacing: 10) {
                // App icon
                sourceIcon(for: source)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                // Track info
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title.isEmpty ? appName(for: source.bundleIdentifier) : source.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(source.artist.isEmpty ? (source.isPlaying ? "Playing" : "Paused") : source.artist)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Playing indicator / controls
                HStack(spacing: 8) {
                    if source.isPlaying {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }

                    if isPrimary {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPrimary ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sourceIcon(for source: MediaSource) -> some View {
        if let artworkData = source.artworkData,
           let nsImage = NSImage(data: artworkData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            AppIcon(for: source.bundleIdentifier)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }

    private func appName(for bundleIdentifier: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleIdentifier.components(separatedBy: ".").last?.capitalized ?? "Unknown"
    }
}
