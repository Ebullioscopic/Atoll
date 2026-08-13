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

#if canImport(AppKit)
import AppKit
typealias PlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
#endif

struct TimerLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var lockScreenManager = LockScreenManager.shared
    @State private var isHovering: Bool = false
    @State private var showTransientLabel: Bool = false
    @State private var labelHideTask: DispatchWorkItem?
    @Default(.timerShowsCountdown) private var showsCountdown
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerShowsLabel) private var showsLabel
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerPresets) private var timerPresets
    @Default(.timerControlWindowEnabled) private var showInlineControls
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    
    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
    }

    private var wingPadding: CGFloat { 22 }
    private var ringStrokeWidth: CGFloat { 3 }
    private var transientLabelDuration: TimeInterval { 4 }

    private var ringWrapsIcon: Bool {
        showsRingProgress && showsCountdown
    }

    private var ringOnRight: Bool {
        showsRingProgress && !ringWrapsIcon
    }

    private var iconWidth: CGFloat {
        ringWrapsIcon ? max(notchContentHeight - 6, 28) : max(0, notchContentHeight)
    }

    private var infoContentWidth: CGFloat {
        guard showsInfoSection else { return 0 }
        if shouldDisplayLabel {
            let textWidth = min(max(titleTextWidth, 44), 220)
            return textWidth
        } else {
            return min(max(notchContentHeight * 1.4, 64), 220)
        }
    }

    private var infoWidth: CGFloat {
        guard showsInfoSection else { return 0 }
        return infoContentWidth + 18
    }

    private var leftWingWidth: CGFloat {
        // Only reserve the outer half of the wing padding so the icon sits flush
        // against the notch (matching the album-art / Toggl layout) instead of
        // leaving an empty gap between the icon and the notch body.
        var width = iconWidth + wingPadding / 2
        if showsInfoSection {
            width += 8 + infoWidth
        }
        return width
    }

    private var ringWidth: CGFloat {
        ringOnRight ? 30 : 0
    }

    private var inlineButtonSize: CGFloat {
        min(max(notchContentHeight - 4, 20), 26)
    }

    private var inlineIconSize: CGFloat {
        max(inlineButtonSize * 0.6, 12)
    }

    private var inlineControlSpacing: CGFloat { 10 }

    private var inlineControlsWidth: CGFloat {
        guard shouldShowInlineControls else { return 0 }
        let count = timerManager.isOvertime ? 1 : 2
        return CGFloat(count) * inlineButtonSize + CGFloat(max(0, count - 1)) * inlineControlSpacing
    }

    private var rightWingWidth: CGFloat {
        var width = wingPadding
        if ringOnRight {
            width += ringWidth
        }
        if ringOnRight && showsCountdown {
            width += 8
        }
        if showsCountdown {
            width += countdownWidth
        }
        if shouldShowInlineControls {
            if ringOnRight || showsCountdown {
                width += inlineControlSpacing
            }
            width += inlineControlsWidth
        }
        return width
    }

    private var titleTextWidth: CGFloat {
        measureTextWidth(timerManager.timerName, font: systemFont(size: 12, weight: .medium))
    }

    private var countdownTextWidth: CGFloat {
        measureTextWidth(timerManager.formattedRemainingTime(), font: monospacedFont(size: 13, weight: .semibold))
    }

    private var countdownWidth: CGFloat {
        guard showsCountdown else { return 0 }
        return max(countdownTextWidth + 16, 72)
    }

    private var clampedProgress: Double {
        min(max(timerManager.progress, 0), 1)
    }

    private var glyphColor: Color {
        switch colorMode {
        case .adaptive:
            return activePresetColor ?? timerManager.timerColor
        case .solid:
            return solidColor
        }
    }

    private var showsRingProgress: Bool {
        showsProgress && progressStyle == .ring
    }

    private var showsBarProgress: Bool {
        showsProgress && progressStyle == .bar
    }

    private var shouldDisplayLabel: Bool {
        showsLabel || showTransientLabel
    }

    private var showsInfoSection: Bool {
        shouldDisplayLabel || (showsBarProgress && !showsCountdown)
    }

    private var activePresetColor: Color? {
        guard let presetId = timerManager.activePresetId else { return nil }
        return timerPresets.first { $0.id == presetId }?.color
    }

    private var middleSectionWidth: CGFloat {
        vm.closedNotchSize.width + (isHovering ? 8 : 0)
    }

    private var adjustedNotchHeight: CGFloat {
        vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)
    }

    private var shouldShowInlineControls: Bool {
        guard showInlineControls else { return false }
        guard timerManager.allowsManualInteraction else { return false }
        guard !lockScreenManager.isLocked else { return false }
        return true
    }

    private func measureTextWidth(_ text: String, font: PlatformFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let width = NSAttributedString(string: text, attributes: attributes).size().width
        return CGFloat(ceil(width))
    }

    private func systemFont(size: CGFloat, weight: PlatformFont.Weight) -> PlatformFont {
        #if canImport(AppKit)
        return NSFont.systemFont(ofSize: size, weight: weight)
        #else
        return UIFont.systemFont(ofSize: size, weight: weight)
        #endif
    }

    // Fully monospaced font matching the countdown's `.monospaced` design so the
    // measured width equals the rendered width (digit-only monospacing under-measures
    // separators, clipping hour-format times like 1:00:00).
    private func monospacedFont(size: CGFloat, weight: PlatformFont.Weight) -> PlatformFont {
        #if canImport(AppKit)
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        #else
        return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        #endif
    }

    var body: some View {
        baseTimerLayout
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.18)) {
                isHovering = hovering
            }
        }
        .onDisappear {
            cancelTransientLabel()
        }
        .onChange(of: timerManager.isTimerActive) { _, isActive in
            if isActive {
                if !timerManager.isFinished && !timerManager.isOvertime {
                    triggerTransientLabel()
                }
            } else {
                cancelTransientLabel()
                showTransientLabel = false
                isHovering = false
            }
        }
        .onChange(of: timerManager.timerName) { _, _ in
            if timerManager.isTimerActive && !timerManager.isFinished && !timerManager.isOvertime {
                triggerTransientLabel()
            }
        }
        .onChange(of: timerManager.isFinished) { _, finished in
            if finished {
                cancelTransientLabel()
                withAnimation(.smooth) {
                    showTransientLabel = true
                    isHovering = false
                }
            }
        }
        .onChange(of: timerManager.isOvertime) { _, overtime in
            if overtime {
                cancelTransientLabel()
                withAnimation(.smooth) {
                    showTransientLabel = true
                    isHovering = false
                }
            }
        }
    }

    private var baseTimerLayout: some View {
        HStack(spacing: 0) {
            leftWingView()
            middleSectionView()
            rightWingView()
        }
        .frame(height: adjustedNotchHeight, alignment: .center)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func leftWingView() -> some View {
        Color.clear
            .frame(width: leftWingWidth, height: notchContentHeight)
            .background(alignment: .leading) {
                HStack(spacing: showsInfoSection ? 8 : 0) {
                    iconSection
                    if showsInfoSection {
                        infoSection
                    }
                }
                .padding(.leading, wingPadding / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
    }

    @ViewBuilder
    private func middleSectionView() -> some View {
        Rectangle()
            .fill(.black)
            .frame(width: middleSectionWidth, height: notchContentHeight)
    }

    @ViewBuilder
    private func rightWingView() -> some View {
        Color.clear
            .frame(width: rightWingWidth, height: notchContentHeight)
            .background(alignment: .trailing) {
                HStack(spacing: 0) {
                    if ringOnRight {
                        ringSection
                    }
                    if showsCountdown {
                        countdownSection
                            .padding(.leading, ringOnRight ? inlineControlSpacing : 0)
                    }
                    if shouldShowInlineControls {
                        inlineControlsSection
                            .padding(.leading, (ringOnRight || showsCountdown) ? inlineControlSpacing : 0)
                    }
                }
                // Tighter trailing margin so the countdown clears the notch region.
                .padding(.trailing, wingPadding / 2 - 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
    }
    
    private var iconSection: some View {
        let baseDiameter = ringWrapsIcon ? iconWidth : iconWidth
        let ringDiameter = ringWrapsIcon ? max(min(baseDiameter, notchContentHeight - 2), 22) : iconWidth
        let iconSize = ringWrapsIcon ? max(ringDiameter - 12, 16) : max(18, iconWidth - 6)

        return ZStack {
            if ringWrapsIcon {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: ringStrokeWidth)
                    .frame(width: ringDiameter, height: ringDiameter)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(glyphColor, style: StrokeStyle(lineWidth: ringStrokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.25), value: clampedProgress)
                    .frame(width: ringDiameter, height: ringDiameter)
            }

            Image(systemName: "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: iconSize, height: iconSize)
        }
        .frame(width: ringWrapsIcon ? ringDiameter : iconWidth,
               height: notchContentHeight,
               alignment: .center)
    }
    
    private var infoSection: some View {
    let availableWidth = max(0, infoWidth - 10)
    let safeWidth = max(44, availableWidth - 6)
    let resolvedTextWidth = min(max(titleTextWidth, 44), safeWidth)
        let marqueeLabel = shouldDisplayLabel && (timerManager.isFinished || timerManager.isOvertime || titleTextWidth > availableWidth)
        let showsBarHere = showsBarProgress && !showsCountdown
        let barWidth = shouldDisplayLabel ? resolvedTextWidth : availableWidth

        return Rectangle()
            .fill(.black)
            .frame(width: infoWidth, height: notchContentHeight)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: showsBarHere ? 4 : 0) {
                    if shouldDisplayLabel {
                        if marqueeLabel {
                            MarqueeText(
                                .constant(timerManager.timerName),
                                font: .system(size: 12, weight: .medium),
                                nsFont: .callout,
                                textColor: .white,
                                minDuration: 0.25,
                                frameWidth: resolvedTextWidth
                            )
                        } else {
                            Text(timerManager.timerName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .frame(width: resolvedTextWidth, alignment: .leading)
                        }
                    }

                    if showsBarHere {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: barWidth, height: 3)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(glyphColor)
                                    .frame(width: barWidth * max(0, CGFloat(clampedProgress)))
                                    .animation(.smooth(duration: 0.25), value: clampedProgress)
                            }
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
            }
            .animation(.smooth, value: timerManager.isFinished)
    }
    
    private var ringSection: some View {
        let diameter = max(min(notchContentHeight - 4, 26), 20)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: ringStrokeWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(glyphColor, style: StrokeStyle(lineWidth: ringStrokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: clampedProgress)
        }
        .frame(width: diameter, height: diameter)
        .frame(width: ringWidth, height: notchContentHeight, alignment: .center)
    }
    
    private var countdownSection: some View {
        let barWidth = max(countdownTextWidth, 1)
        return VStack(spacing: 4) {
            Text(timerManager.formattedRemainingTime())
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(timerManager.isOvertime ? .red : .white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: timerManager.remainingTime)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if showsBarProgress {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: barWidth, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(glyphColor)
                            .frame(width: barWidth * max(0, CGFloat(clampedProgress)))
                            .animation(.smooth(duration: 0.25), value: clampedProgress)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
     // Note: rightWingView already applies a trailing wing padding, so no extra
     // trailing padding here — a second one pushes the digits left and clips the
     // hour under the notch while wasting space on the right.
     .frame(width: countdownWidth,
         height: notchContentHeight, alignment: .center)
    }

    @ViewBuilder
    private var inlineControlsSection: some View {
        HStack(spacing: inlineControlSpacing) {
            if !timerManager.isOvertime {
                inlineControlButton(
                    icon: timerManager.isPaused ? "play.fill" : "pause.fill",
                    foreground: .white,
                    background: Color.white.opacity(0.14),
                    help: timerManager.isPaused ? "Resume" : "Pause",
                    action: togglePause
                )
            }

            inlineControlButton(
                icon: timerManager.isOvertime ? "stop.fill" : "xmark",
                foreground: timerManager.isOvertime ? Color.white : Color.white,
                background: timerManager.isOvertime ? Color.red.opacity(0.24) : Color.white.opacity(0.14),
                help: timerManager.isOvertime ? "Stop" : "Cancel",
                action: stopTimer
            )
        }
        .frame(height: notchContentHeight, alignment: .center)
    }

    private func inlineControlButton(
        icon: String,
        foreground: Color,
        background: Color,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: inlineIconSize, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: inlineButtonSize, height: inlineButtonSize)
                .background(background)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
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
        timerManager.stopTimer()
    }

    private func triggerTransientLabel() {
        guard !showsLabel else { return }
        guard !enableMinimalisticUI else { return }
        cancelTransientLabel()
        withAnimation(.smooth) {
            showTransientLabel = true
        }
        let task = DispatchWorkItem {
            withAnimation(.smooth) {
                showTransientLabel = false
            }
        }
        labelHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + transientLabelDuration, execute: task)
    }

    private func cancelTransientLabel() {
        labelHideTask?.cancel()
        labelHideTask = nil
    }
}

#Preview {
    TimerLiveActivity()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 300, height: 32)
        .background(.black)
        .onAppear {
            TimerManager.shared.startDemoTimer(duration: 300)
        }
}
