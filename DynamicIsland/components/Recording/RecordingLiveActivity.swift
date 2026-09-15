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

struct RecordingLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @Default(.recordingHoverStyle) private var recordingHoverStyle
    @Default(.recordingControlMode) private var recordingControlMode

    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if presentation == .expanded {
                expandedDetails
                    .frame(width: hudWidth, height: hudHeight)
                    .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    recordingBadge
                        .frame(width: leadingWidth, height: rowHeight)

                    Rectangle()
                        .fill(.black)
                        .frame(width: centerWidth, height: vm.effectiveClosedNotchHeight)

                    trailingStatus
                        .frame(width: trailingWidth, height: rowHeight)
                }
                .frame(width: hudWidth, height: vm.effectiveClosedNotchHeight)
            }
        }
        .frame(width: hudWidth, height: hudHeight, alignment: .bottom)
        .accessibilityElement(children: .contain)
        .onAppear {
            withAnimation(.smooth(duration: 0.32)) {
                isVisible = true
            }
        }
        .onChange(of: recordingManager.isRecording) { _, isRecording in
            withAnimation(.smooth(duration: isRecording ? 0.32 : 0.2)) {
                isVisible = isRecording
            }
        }
    }

    private var presentation: RecordingHUDPresentation {
        guard !recordingManager.isScreenSharingAppActive else { return .compact }
        guard hoverAnimation, stopControlsEnabled else { return .compact }
        return effectiveRecordingHoverStyle == .default ? .expanded : .inline
    }

    private var stopControlsEnabled: Bool {
        recordingControlMode == .withStopButton && recordingManager.shouldShowStopControlsInHUD
    }

    private var effectiveRecordingHoverStyle: RecordingHoverStyle {
        recordingHoverStyle
    }

    private var hudWidth: CGFloat {
        vm.closedNotchSize.width + presentation.extraWidth
    }

    private var hudHeight: CGFloat {
        vm.effectiveClosedNotchHeight + presentation.extraHeight
    }

    private var centerWidth: CGFloat {
        vm.closedNotchSize.width + (hoverAnimation ? 8 : 0)
    }

    private var rowHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var leadingWidth: CGFloat {
        guard isVisible else { return 0 }
        return max(0, vm.effectiveClosedNotchHeight - 12 + gestureProgress / 2)
    }

    private var trailingWidth: CGFloat {
        guard isVisible else { return 0 }
        return max(0, hudWidth - centerWidth - leadingWidth)
    }

    private var inlineStopButtonSize: CGFloat {
        min(max(vm.effectiveClosedNotchHeight - 8, 22), 30)
    }

    private var recordingStatusText: String {
        recordingManager.stopFailureMessage ?? String(localized: "Recording in progress.")
    }

    @ViewBuilder
    private var recordingBadge: some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.red.opacity(0.15))

                recordingDot(size: 10)
            }
            .frame(width: rowHeight, height: rowHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .opacity(isVisible ? 1 : 0)
    }

    @ViewBuilder
    private var trailingStatus: some View {
        HStack(spacing: 10) {
            Text(recordingManager.stopFailureMessage == nil ? recordingManager.formattedDuration : String(localized: "Failed"))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.red)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())

            if presentation == .inline {
                stopButton(size: inlineStopButtonSize, lineWidth: 1.6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 10)
        .opacity(isVisible ? 1 : 0)
    }

    private var expandedDetails: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: String(localized: "Screen Recording"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)

                    Text(recordingManager.formattedDuration)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }

                Text(recordingStatusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(recordingManager.stopFailureMessage == nil ? .gray.opacity(0.6) : .red.opacity(0.78))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            stopButton(size: 54, lineWidth: 2.4)
        }
        .padding(.leading, 35)
        .padding(.trailing, 40)
        .padding(.top, 29)
        .padding(.bottom, 20)
    }

    private func recordingDot(size: CGFloat) -> some View {
        Circle()
            .fill(Color.red)
            .frame(width: size, height: size)
            .modifier(PulsingModifier())
    }

    private func stopButton(size: CGFloat, lineWidth: CGFloat) -> some View {
        Button {
            recordingManager.stopActiveRecording()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(recordingManager.isSendingStopRequest ? 0.5 : 0.95), lineWidth: lineWidth)

                RoundedRectangle(cornerRadius: max(3, size * 0.1), style: .continuous)
                    .fill(Color.red)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .scaleEffect(recordingManager.isSendingStopRequest ? 0.84 : 1.0)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!recordingManager.canStopFromHUD)
        .help(String(localized: "Stop recording"))
        .accessibilityLabel(String(localized: "Stop recording"))
    }
}
