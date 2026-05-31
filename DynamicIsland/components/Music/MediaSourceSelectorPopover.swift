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

struct MediaSourceSelectorPopover: View {
    @ObservedObject private var musicManager = MusicManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            if !musicManager.secondarySources.isEmpty {
                Divider().opacity(0.3)
                MultiSourceMediaList()
            } else {
                Text("No other sources playing")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            }
        }
        .frame(width: 280)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private var header: some View {
        HStack {
            Text("Now Playing")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                withAnimation(.smooth(duration: 0.25)) {
                    musicManager.isMultiSourceListExpanded.toggle()
                }
            } label: {
                Image(systemName: musicManager.isMultiSourceListExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
