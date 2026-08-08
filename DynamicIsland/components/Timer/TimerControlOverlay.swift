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

struct TimerControlOverlay: View {
    let notchHeight: CGFloat
    let cornerRadius: CGFloat
    var tracksHoverForAutoHide: Bool = false

    @ObservedObject private var timerManager = TimerManager.shared

    private var buttonHeight: CGFloat { ClosedNotchSatelliteChrome.buttonHeight(for: notchHeight) }

    private var pauseIcon: String {
        timerManager.isPaused ? "play.fill" : "pause.fill"
    }

    private var pauseHelp: String {
        timerManager.isPaused ? "Resume" : "Pause"
    }

    private var stopIcon: String {
        timerManager.isOvertime ? "stop.fill" : "xmark"
    }

    private var stopHelp: String {
        timerManager.isOvertime ? "Stop" : "Cancel"
    }

    var body: some View {
        HStack(spacing: 6) {
            if !timerManager.isOvertime {
                ClosedNotchChipButton(
                    help: pauseHelp,
                    height: buttonHeight
                ) {
                    Image(systemName: pauseIcon)
                        .font(.system(size: 11, weight: .semibold))
                } action: {
                    togglePause()
                }
                .disabled(!timerManager.allowsManualInteraction)
            }

            ClosedNotchChipButton(
                help: stopHelp,
                height: buttonHeight,
                emphasized: timerManager.isOvertime
            ) {
                Image(systemName: stopIcon)
                    .font(.system(size: 11, weight: .semibold))
            } action: {
                stopTimer()
            }
            .disabled(!timerManager.allowsManualInteraction)
        }
        .padding(.horizontal, 10)
        .frame(height: notchHeight)
        .background { ClosedNotchSatelliteChrome.pillBackground(cornerRadius: cornerRadius) }
        .fixedSize(horizontal: true, vertical: false)
        .compositingGroup()
        .animation(.smooth(duration: 0.2), value: timerManager.isPaused)
        .animation(.smooth(duration: 0.2), value: timerManager.isFinished)
        .animation(.smooth(duration: 0.2), value: timerManager.isOvertime)
        .onHover { hovering in
#if os(macOS)
            guard tracksHoverForAutoHide else { return }
            TimerControlWindowManager.shared.notePointerHover(hovering)
#endif
        }
    }

    private func togglePause() {
        guard timerManager.allowsManualInteraction else { return }
        if timerManager.isPaused {
            timerManager.resumeTimer()
        } else {
            timerManager.pauseTimer()
        }
    }

    private func stopTimer() {
        guard timerManager.allowsManualInteraction else {
            timerManager.endExternalTimer(triggerSmoothClose: false)
            return
        }
#if os(macOS)
        TimerControlWindowManager.shared.hide(animated: true)
#endif
        timerManager.stopTimer()
    }
}

#Preview {
    TimerControlOverlay(notchHeight: 34, cornerRadius: 14)
        .padding()
        .background(Color.gray.opacity(0.2))
}
