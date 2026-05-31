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

struct MultiSourceMediaList: View {
    @ObservedObject private var musicManager = MusicManager.shared

    private let rowHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            if musicManager.isMultiSourceListExpanded {
                ForEach(musicManager.secondarySources) { source in
                    mediaSourceRow(source)
                    if source.id != musicManager.secondarySources.last?.id {
                        Divider()
                            .opacity(0.3)
                    }
                }
            }
        }
        .clipped()
        .animation(.smooth(duration: 0.25), value: musicManager.isMultiSourceListExpanded)
    }

    @ViewBuilder
    private func mediaSourceRow(_ source: MediaSource) -> some View {
        HStack(spacing: 10) {
            appIcon(for: source)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(source.artistName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                musicManager.promoteSource(source)
            } label: {
                Image(systemName: source.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            musicManager.promoteSource(source)
        }
    }

    private func appIcon(for source: MediaSource) -> Image {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier)?.path {
            let nsImage = NSWorkspace.shared.icon(forFile: path)
            return Image(nsImage: nsImage)
        }
        return Image(systemName: "music.note")
    }
}
