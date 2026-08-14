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

/// Contents of the floating prompter window.
struct TeleprompterPanelView: View {
    @ObservedObject private var manager = TeleprompterManager.shared

    @Default(.teleprompterFontSize) private var fontSize
    @Default(.teleprompterFontChoice) private var fontChoice
    @Default(.teleprompterCustomFontFamily) private var customFontFamily
    @Default(.teleprompterOpacity) private var opacity
    @Default(.teleprompterMirrored) private var isMirrored
    @Default(.teleprompterHideFromScreenCapture) private var hiddenFromCapture

    @State private var isShowingControls = true

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 14)
                .fill(.black.opacity(opacity))

            if let script = manager.currentScript {
                TeleprompterScriptTextView(
                    script: script,
                    confirmedTokenIndex: manager.confirmedTokenIndex,
                    fontSize: fontSize,
                    fontChoice: fontChoice,
                    customFontFamily: customFontFamily,
                    isMirrored: isMirrored,
                    coveredSectionIndices: manager.coveredSectionIndices
                )
                .padding(.top, isShowingControls ? 34 : 8)
            } else {
                emptyState
            }

            if isShowingControls {
                controls
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .environment(\.colorScheme, .dark)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isShowingControls = hovering }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text("No script yet")
                .font(.system(size: 14, weight: .semibold))
            Text("Add one from Settings, or paste text into the Prompter tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                manager.toggleTake()
            } label: {
                Image(systemName: manager.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .help(Text(manager.isRunning ? "Pause (space)" : "Play (space)"))

            Button {
                manager.restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help(Text("Back to the start (R)"))

            if let script = manager.currentScript {
                Text(script.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                progressLabel(script)
            }

            Spacer(minLength: 0)

            if !hiddenFromCapture {
                // The prompter's whole point is being unseen; say so when it is not.
                Image(systemName: "eye")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .help(Text("This window is visible to screen sharing and recording"))
            }

            Button {
                TeleprompterPanelManager.shared.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .background(.white.opacity(0.10), in: Circle())
            }
            .buttonStyle(.plain)
            .help(Text("Close the prompter (esc)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55))
    }

    private func progressLabel(_ script: TeleprompterScript) -> some View {
        HStack(spacing: 5) {
            Text("\(min(manager.confirmedTokenIndex, script.wordCount))/\(script.wordCount)")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .monospacedDigit()
            if manager.takeStartedAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(TeleprompterScriptTextView.durationText(manager.elapsed))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .monospacedDigit()
                }
            }
        }
    }
}
