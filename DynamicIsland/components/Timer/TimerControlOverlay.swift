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

    @ObservedObject private var timerManager = TimerManager.shared

    private var pauseIcon: String {
        timerManager.isPaused ? "play.fill" : "pause.fill"
    }

    private var pauseForeground: Color { .white }

    private var helpText: String {
        timerManager.isPaused ? "Resume" : "Pause"
    }

    private var secondaryIcon: String {
        timerManager.isOvertime ? "stop.fill" : "xmark"
    }

    private var secondaryHelp: String {
        timerManager.isOvertime ? "Stop" : "Cancel"
    }

    private var buttonSize: CGFloat {
        max(notchHeight - 20, 22)
    }

    private var iconSize: CGFloat {
        14
    }

    private var windowCornerRadius: CGFloat {
        max(cornerRadius - 6, 12)
    }

    var body: some View {
        let verticalPadding = max(8, notchHeight * 0.12)

        HStack(spacing: 12) {
            if !timerManager.isOvertime {
                ControlButton(
                    icon: pauseIcon,
                    foreground: pauseForeground,
                    background: Color.white.opacity(0.14),
                    help: helpText,
                    action: togglePause
                )
                .disabled(!timerManager.allowsManualInteraction)
            }

            ControlButton(
                icon: secondaryIcon,
                foreground: timerManager.isOvertime ? Color.white : Color.white,
                background: timerManager.isOvertime ? Color.red.opacity(0.24) : Color.white.opacity(0.14),
                help: secondaryHelp,
                action: stopTimer
            )
            .disabled(!timerManager.allowsManualInteraction)
        }
        .padding(.vertical, verticalPadding)
        .padding(.horizontal, 12)
        .frame(height: notchHeight)
        .frame(minWidth: buttonSize * 2 + 32)
        .background {
            RoundedRectangle(cornerRadius: windowCornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.9))
        }
        .compositingGroup()
        .animation(.smooth(duration: 0.2), value: timerManager.isPaused)
        .animation(.smooth(duration: 0.2), value: timerManager.isFinished)
        .animation(.smooth(duration: 0.2), value: timerManager.isOvertime)
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

private struct ControlButton: View {
    let icon: String
    let foreground: Color
    let background: Color
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(foreground)
                .background(background.opacity(isHovering ? 1 : 0.7))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in isHovering = hovering }
    }
}

#Preview {
    TimerControlOverlay(notchHeight: 34, cornerRadius: 14)
        .padding()
        .background(Color.gray.opacity(0.2))
}
