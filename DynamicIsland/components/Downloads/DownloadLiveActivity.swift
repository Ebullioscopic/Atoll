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

struct DownloadLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @State private var downloadManager = DownloadManager.shared
    
    @State private var isHovering: Bool = false
    @State private var gestureProgress: CGFloat = 0
    @State private var isExpanded: Bool = false

    @Default(.showDownloadSpeed) private var showDownloadSpeed
    @Default(.selectedDownloadIndicatorStyle) private var indicatorStyle

    /// Shown only while there is a rate to show: the figure needs two samples
    /// a second apart, and a finished download has no rate at all.
    private var speedText: String? {
        guard showDownloadSpeed,
              !downloadManager.isDownloadCompleted,
              let speed = downloadManager.downloadSpeed else { return nil }
        return Self.speedFormatter.string(fromByteCount: Int64(speed)) + "/s"
    }

    /// How much room the rate needs beside the indicator.
    ///
    /// It is added to the black centre as well as to the right-hand side. The
    /// centre only covers the physical notch while the two sides stay balanced
    /// -- that is what the `isDownloading` widening already compensates for --
    /// so growing one side alone drags the centre's right edge in under the
    /// notch and hides whatever sits next to it.
    private static let speedAllowance: CGFloat = 58

    private var speedAllowance: CGFloat { speedText == nil ? 0 : Self.speedAllowance }

    private static let speedFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.isAdaptive = true
        return formatter
    }()
    
    private var tint: Color {
        .accentColor
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side: download icon capsule
            Color.clear
                .background {
                    if isExpanded {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(tint.opacity(0.14))
                                
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(tint)
                            }
                            .frame(
                                width: vm.effectiveClosedNotchHeight - 12,
                                height: vm.effectiveClosedNotchHeight - 12
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
                .frame(
                    width: isExpanded ? max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2) : 0,
                    height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
                )
            
            // Center: closed notch body (slightly wider during downloads)
            Rectangle()
                .fill(.black)
                .frame(
                    width: vm.closedNotchSize.width
                        + (isHovering ? 8 : 0)
                        + (downloadManager.isDownloading ? 40 : 0)
                        + speedAllowance
                )
                .animation(.smooth(duration: 0.25), value: speedAllowance)
            
            // Right side: indeterminate-style progress bar
            Color.clear
                .background {
                    if isExpanded {
                        HStack {
                            if downloadManager.isDownloadCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(.trailing, 6)
                            } else {
                                HStack(spacing: 6) {
                                    if let speedText {
                                        Text(speedText)
                                            // Monospaced digits so the figure
                                            // does not jitter as it changes.
                                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .fixedSize()
                                            .transition(.opacity)
                                    }

                                    if indicatorStyle == .circle {
                                        SpinningCircleDownloadView()
                                    } else {
                                        ProgressView()
                                            .progressViewStyle(.linear)
                                            .tint(.accentColor)
                                            .frame(width: 40)
                                    }
                                }
                                .padding(.trailing, 6)
                                .animation(.smooth(duration: 0.2), value: speedText)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    }
                }
                .frame(
                    width: isExpanded ? max(60, vm.effectiveClosedNotchHeight) + speedAllowance : 0,
                    height: vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12)
                )
                .animation(.smooth(duration: 0.25), value: speedAllowance)
        }
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0))
        .onAppear {
            withAnimation(.smooth(duration: 0.35)) {
                isExpanded = true
            }
        }
        .onChange(of: downloadManager.isDownloading) { _, newValue in
            withAnimation(.smooth(duration: 0.35)) {
                isExpanded = newValue
            }
        }
    }
}


