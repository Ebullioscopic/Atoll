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
import Defaults

/// Shows detected secondary media sources below the main music player
/// when "All Music" mode is active. Each row displays the source's artwork,
/// title/artist, and compact controls (switch, play/pause, next).
struct MultiSourceMediaList: View {
    @ObservedObject private var musicManager = MusicManager.shared

    private var sources: [MediaSource] {
        musicManager.secondarySources
    }

    private var hasAnySources: Bool {
        !sources.isEmpty
    }

    var body: some View {
        if Defaults[.mediaController] == .all && hasAnySources {
            VStack(spacing: 0) {
                // Toggle bar
                toggleBar

                // Expanded source list
                if musicManager.isMultiSourceListExpanded {
                    VStack(spacing: 1) {
                        ForEach(sources) { source in
                            MediaSourceRow(source: source)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: musicManager.isMultiSourceListExpanded)
            .animation(.smooth(duration: 0.25), value: sources)
        }
    }

    private var toggleBar: some View {
        Button {
            musicManager.toggleMultiSourceList()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.below.rectangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))

                Text("\(sources.count) other source\(sources.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                Spacer()

                Image(systemName: musicManager.isMultiSourceListExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A single compact row representing a secondary media source.
private struct MediaSourceRow: View {
    let source: MediaSource
    @ObservedObject private var musicManager = MusicManager.shared
    @State private var isHovering = false

    private let rowHeight: CGFloat = 56

    var body: some View {
        HStack(spacing: 12) {
            // Artwork / App Icon - Wrapped in a stable container
            ZStack {
                artworkView
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(width: 36, height: 36)

            // Title & Artist
            VStack(alignment: .leading, spacing: 1) {
                Text(source.title.isEmpty ? "Not Playing" : source.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(source.artist.isEmpty ? "Not Playing" : source.artist)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.leading, 2)
            .frame(maxWidth: .infinity, alignment: .leading)

            // Controls
            HStack(spacing: 14) {
                // Switch / promote button
                compactButton(icon: "arrow.right.arrow.left") {
                    musicManager.promoteSource(source)
                }

                // Play / Pause
                compactButton(icon: source.isPlaying ? "pause.fill" : "play.fill") {
                    musicManager.controlSource(source, action: .togglePlay)
                }

                // Next track
                compactButton(icon: "forward.fill") {
                    musicManager.controlSource(source, action: .next)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artworkData = source.artworkData,
           let nsImage = NSImage(data: artworkData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            // Fall back to app icon
            AppIcon(for: source.bundleIdentifier)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private func compactButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .contentShape(Rectangle())
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }
}
