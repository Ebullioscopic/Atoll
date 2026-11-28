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

// Note: lyrics display is inlined into the main minimalistic view below and is controlled by Defaults[.enableLyrics]

struct MinimalisticMusicView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.enableLyrics) var enableLyrics
    @State private var isHovering: Bool = false
    
    var body: some View {
        VStack(spacing: 2) {
            // Main content row
            HStack(spacing: 0) {
                // Left: Album Art
                albumArtView

                // Middle: Song Title, Artist and Lyrics (lyrics shown under artist when enabled)
                Rectangle()
                    .fill(.black)
                    .overlay(
                        GeometryReader { geo in
                            VStack(alignment: .center, spacing: 2) {
                                if !musicManager.songTitle.isEmpty {
                                    MusicTitleMarqueeView(
                                        text: musicManager.songTitle,
                                        isExplicit: musicManager.isCurrentTrackExplicit,
                                        font: .system(size: 12, weight: .semibold),
                                        nsFont: .subheadline,
                                        textColor: Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                        minDuration: 0.4,
                                        frameWidth: max(0, geo.size.width - 8),
                                        alignment: .center,
                                        badgeHeight: 13
                                    )
                                }

                                // Artist name
                                if !musicManager.artistName.isEmpty {
                                    Text(musicManager.artistName)
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }

                                // Lyrics under the author name (same font size as author)
                                if enableLyrics {
                                    lyricsLineView
                                        .font(.system(size: 11, weight: .regular))
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        }
                    )
                    .frame(width: vm.closedNotchSize.width)

                // Right: Music Visualizer
                visualizerView
            }

            // (lyrics are displayed inline under the artist name)
        }
        // reserve extra height when lyrics are enabled
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    // MARK: - Album Art
    
    private var albumArtView: some View {
        HStack {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .background(
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: musicManager.albumArt.size.width/musicManager.albumArt.size.height > 1.0 ? 4 : 12))

                )
                .clipped()
                .albumArtFlip(angle: musicManager.flipAngle)
                .frame(width: max(0, vm.effectiveClosedNotchHeight - 12), height: max(0, vm.effectiveClosedNotchHeight - 12))
        }
        .frame(width: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)), height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)))
    }
    
    // MARK: - Visualizer
    
    private var visualizerView: some View {
        let width = CGFloat(Defaults[.visualizerBarCount]) * 4
        return HStack {
            Rectangle()
                .fill((Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray).spectrogramGradient())
                .frame(width: width, alignment: .center)
                .mask {
                    AudioVisualizerView(isPlaying: $musicManager.isPlaying)
                        .frame(width: width, height: 12)
                }
                .frame(width: width, height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)), alignment: .center)
        }
        .frame(width: width, height: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)), alignment: .center)
    }
}

private extension MinimalisticMusicView {
    var lyricsLineView: some View {
        let line = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(spacing: 6) {
            if !line.isEmpty {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .symbolRenderingMode(.monochrome)

                Text(line)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 6)
                    .id(line)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.smooth(duration: 0.32), value: line)
    }
}
