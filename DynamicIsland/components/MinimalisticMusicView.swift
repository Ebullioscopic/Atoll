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

// Note: lyrics display is shown in a dedicated block below the compact main row and is controlled by Defaults[.enableLyrics]

struct MinimalisticMusicView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.enableLyrics) var enableLyrics
    @State private var isHovering: Bool = false

    private var lyricsExtraHeight: CGFloat {
        guard enableLyrics else { return 0 }
        return MusicLyricsLayoutMetrics.compactReservedAreaHeight
    }
    
    var body: some View {
        VStack(spacing: 2) {
            // Main content row
            HStack(spacing: 0) {
                // Left: Album Art
                albumArtView

                // Middle: Song Title and Artist
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
                            }
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        }
                    )
                    .frame(width: vm.closedNotchSize.width)

                // Right: Music Visualizer
                visualizerView
            }

            if enableLyrics {
                lyricsLineView
                    .padding(.top, 2)
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight + lyricsExtraHeight + (isHovering ? 8 : 0), alignment: .top)
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

        return HStack(alignment: .top, spacing: 6) {
            if !line.isEmpty {
                Image(systemName: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .symbolRenderingMode(.monochrome)

                TwoLineFittingText(
                    text: line,
                    fontSize: MusicLyricsLayoutMetrics.compactFontSize,
                    minimumFontSize: MusicLyricsLayoutMetrics.compactMinimumFontSize,
                    weight: MusicLyricsLayoutMetrics.compactWeight,
                    nsWeight: MusicLyricsLayoutMetrics.compactNSWeight,
                    textColor: .white.opacity(0.88),
                    alignment: .top,
                    multilineTextAlignment: .center
                )
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
        .frame(height: MusicLyricsLayoutMetrics.compactReservedTextHeight, alignment: .center)
        .animation(.smooth(duration: 0.32), value: line)
    }
}
