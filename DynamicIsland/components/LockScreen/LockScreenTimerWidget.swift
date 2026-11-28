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

struct LockScreenTimerWidget: View {
    static let defaultWidth: Double = 420
    static let preferredHeight: CGFloat = 96
    static var preferredSize: CGSize {
        CGSize(width: CGFloat(Defaults[.lockScreenTimerWidgetWidth]), height: preferredHeight)
    }
    static let cornerRadius: CGFloat = 26

    @ObservedObject private var animator: LockScreenTimerWidgetAnimator
    @ObservedObject private var timerManager = TimerManager.shared
    @Default(.lockScreenTimerGlassStyle) private var timerGlassStyle
    @Default(.lockScreenTimerGlassCustomizationMode) private var timerGlassCustomizationMode
    @Default(.lockScreenTimerLiquidGlassVariant) private var timerGlassVariant
    @Default(.lockScreenTimerWidgetUsesBlur) private var timerGlassModeIsGlass
    @Default(.timerPresets) private var timerPresets
    @Default(.lockScreenTimerWidgetWidth) private var widgetWidth
    @Default(.lockScreenWidgetAppearance) private var appearance

    @MainActor
    init(animator: LockScreenTimerWidgetAnimator? = nil) {
        if let animator {
            _animator = ObservedObject(wrappedValue: animator)
        } else {
            _animator = ObservedObject(wrappedValue: LockScreenTimerWidgetAnimator(isPresented: true))
        }
    }

    private var hasHoursComponent: Bool {
        abs(timerManager.remainingTime) >= 3600
    }

    private var hasDoubleDigitHours: Bool {
        abs(timerManager.remainingTime) >= 36_000 // 10 hours or more
    }

    private var countdownFrameWidth: CGFloat {
        if hasDoubleDigitHours { return 200 }
        if hasHoursComponent { return 185 }
        return 160
    }

    private var countdownFont: Font {
        let baseSize: CGFloat = hasDoubleDigitHours ? 42 : 46
        return .system(size: baseSize, weight: .bold, design: .rounded)
    }

    private var countdownText: String {
        timerManager.formattedRemainingTime()
    }

    private var activePresetColor: Color? {
        guard let presetId = timerManager.activePresetId else { return nil }
        return timerPresets.first { $0.id == presetId }?.color
    }

    private var accentColor: Color {
        (activePresetColor ?? timerManager.timerColor)
            .ensureMinimumBrightness(factor: 0.75)
    }

    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [
                accentColor.opacity(0.35),
                accentColor.ensureMinimumBrightness(factor: 0.5)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var timerSurfaceMode: LockScreenTimerSurfaceMode {
        timerGlassModeIsGlass ? .glass : .classic
    }

    private var usesGlassBackground: Bool {
        timerSurfaceMode == .glass
    }

    private var usesCustomLiquidGlass: Bool {
        guard usesGlassBackground else { return false }
        return timerGlassStyle == .liquid && timerGlassCustomizationMode == .customLiquid
    }

    private var usesStandardLiquidGlass: Bool {
        guard usesGlassBackground else { return false }
        guard timerGlassStyle == .liquid else { return false }
        if #available(macOS 26.0, *) {
            return timerGlassCustomizationMode == .standard
        }
        return false
    }

    @ViewBuilder
    private var widgetBackground: some View {
        if usesGlassBackground {
            if usesCustomLiquidGlass {
                customLiquidBackground
            } else if timerGlassStyle == .liquid {
                standardLiquidBackground
            } else {
                frostedBackground
            }
        } else {
            classicBackground
        }
    }

    @ViewBuilder
    private var standardLiquidBackground: some View {
        if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .glassEffect(
                    .clear.tint(accentColor.opacity(0.18)).interactive(),
                    in: .rect(cornerRadius: Self.cornerRadius)
                )
        } else {
            frostedBackground
        }
    }

    private var customLiquidBackground: some View {
        LiquidGlassBackground(variant: timerGlassVariant, cornerRadius: Self.cornerRadius) {
            Color.black.opacity(0.12)
        }
    }

    private var frostedBackground: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
    }

    private var classicBackground: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(appearance.usesLightGlyphs ? Color.black.opacity(0.65) : Color.white.opacity(0.7))
    }

    private var widgetSize: CGSize {
        CGSize(width: CGFloat(widgetWidth), height: Self.preferredHeight)
    }

    private var pauseIcon: String {
        timerManager.isPaused ? "play.fill" : "pause.fill"
    }

    private var pauseLabel: String {
        timerManager.isPaused ? "Resume" : "Pause"
    }

    private var secondaryIcon: String {
        timerManager.isOvertime ? "stop.fill" : "xmark"
    }

    private var secondaryLabel: String {
        timerManager.isOvertime ? "Stop" : "Cancel"
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 0) {
                controlButtons
                    .padding(.trailing, 12)

                Spacer()

                countdownSection
                    .padding(.leading, 12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(width: widgetSize.width, height: widgetSize.height)
        .background {
            widgetBackground
                .environment(\.colorScheme, appearance.materialColorScheme)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(appearance.primary(opacity: 0.08), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 16)
        .overlay(alignment: .topLeading) {
            accentRibbon
        }
        .scaleEffect(animator.isPresented ? 1 : 0.9)
        .opacity(animator.isPresented ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.85, blendDuration: 0.22), value: animator.isPresented)
    }

    private var controlButtons: some View {
        HStack(spacing: 10) {
            if !timerManager.isOvertime {
                CircleButton(
                    icon: pauseIcon,
                    foreground: appearance.primary(opacity: 0.95),
                    background: accentColor.opacity(0.32),
                    action: togglePause,
                    isEnabled: timerManager.allowsManualInteraction,
                    helpText: pauseLabel
                )
            }

            CircleButton(
                icon: secondaryIcon,
                foreground: appearance.primary(opacity: 0.95),
                background: appearance.usesLightGlyphs ? Color.black.opacity(0.35) : Color.black.opacity(0.12),
                action: stopTimer,
                isEnabled: timerManager.allowsManualInteraction,
                helpText: secondaryLabel
            )
        }
    }

    private var countdownSection: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(countdownText)
                .font(countdownFont)
                .monospacedDigit()
                .foregroundStyle(timerManager.isOvertime ? Color.red : accentColor)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: timerManager.remainingTime)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: countdownFrameWidth, alignment: .center)
        .padding(.trailing, 2)
        .layoutPriority(2)
    }

    private var accentRibbon: some View {
        Capsule()
            .fill(accentGradient)
            .frame(width: 110, height: 26)
            .blur(radius: 12)
            .offset(x: 18, y: -6)
            .opacity(0.45)
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
        let allowsManualInteraction = timerManager.allowsManualInteraction

        LockScreenTimerWidgetPanelManager.shared.hide()

        Task.detached(priority: .userInitiated) { [allowsManualInteraction] in
            try? await Task.sleep(nanoseconds: LockScreenTimerWidgetPanelManager.hideAnimationDurationNanoseconds)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if allowsManualInteraction {
                    TimerManager.shared.stopTimer()
                } else {
                    TimerManager.shared.endExternalTimer(triggerSmoothClose: false)
                }
            }
        }
    }

    private struct CircleButton: View {
        let icon: String
        let foreground: Color
        let background: Color
        let action: () -> Void
        let isEnabled: Bool
        let helpText: String

        @State private var isHovering = false

        private var effectiveBackground: Color {
            background.opacity(isHovering ? 0.9 : 0.7)
        }

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(foreground)
                    .frame(width: 48, height: 48)
                    .background(effectiveBackground.opacity(isEnabled ? 1 : 0.25))
                    .clipShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .help(helpText)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering in isHovering = hovering }
        }
    }
}

#Preview {
    LockScreenTimerWidget()
        .frame(width: LockScreenTimerWidget.preferredSize.width, height: LockScreenTimerWidget.preferredSize.height)
        .padding()
        .background(Color.black)
        .onAppear {
            TimerManager.shared.startDemoTimer(duration: 1783)
        }
}
