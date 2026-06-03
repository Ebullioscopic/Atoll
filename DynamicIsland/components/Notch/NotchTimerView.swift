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
#endif

struct NotchTimerView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    @Default(.timerPresets) private var timerPresets
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.showTimerPresetsInNotchTab) private var showTimerPresetsInNotchTab

    @AppStorage("customTimerDuration") private var customTimerDuration: Double = 600
    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 10
    @State private var customSeconds: Int = 0
    @State private var isSyncingCustomDuration = false
    @State private var lockedAccentColor: Color?

    var body: some View {
        Group {
            if enableTimerFeature {
                HStack(alignment: .top, spacing: timerManager.isTimerActive ? 0 : 20) {
                    leftColumn
                    if shouldShowPresetColumn {
                        Divider()
                            .frame(height: max(0, maxTabContentHeight - 8))
                            .opacity(0.2)
                        presetColumn
                    }
                }
                .frame(maxHeight: maxTabContentHeight, alignment: .top)
                .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                .transition(.opacity.combined(with: .blurReplace))
                .onAppear { syncCustomDuration(with: customTimerDuration) }
                .onChange(of: customTimerDuration) { _, newValue in syncCustomDuration(with: newValue) }
                .onChange(of: customHours) { _, _ in updateStoredCustomDuration() }
                .onChange(of: customMinutes) { _, _ in updateStoredCustomDuration() }
                .onChange(of: customSeconds) { _, _ in updateStoredCustomDuration() }
            } else {
                disabledState
            }
        }
        .onAppear {
            lockAccentColorIfNeeded()
        }
        .onChange(of: timerManager.isTimerActive) { _, isActive in
            if isActive {
                lockAccentColorIfNeeded()
            } else {
                lockedAccentColor = nil
            }
        }
        .onChange(of: timerManager.activePresetId) { _, _ in
            if timerManager.isTimerActive && lockedAccentColor == nil {
                lockAccentColorIfNeeded()
            }
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            if timerManager.isTimerActive {
                Spacer(minLength: 0)
                activeTimerCard
                Spacer(minLength: 0)
            } else {
                customTimerComposer
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: maxTabContentHeight, alignment: .top)
        .padding(.bottom, 2)
    }

    private var presetColumn: some View {
        VStack(spacing: 6) {
            if timerPresets.isEmpty {
                Text("Configure presets in Settings to see them here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                let computedHeight = CGFloat(timerPresets.count) * 60 + 4
                let listHeight = min(max(0, maxTabContentHeight - 16), computedHeight)
                ZStack {
                    List {
                        ForEach(timerPresets) { preset in
                            TimerPresetCard(preset: preset, isActive: timerManager.activePresetId == preset.id) {
                                timerManager.startTimer(duration: preset.duration, name: preset.name, preset: preset)
                                if !enableMinimalisticUI {
                                    coordinator.currentView = .timer
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)

                    LinearGradient(colors: [Color.black.opacity(0.65), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .allowsHitTesting(false)
                        .alignmentGuide(.top) { d in d[.top] }
                        .frame(maxHeight: .infinity, alignment: .top)

                    LinearGradient(colors: [.clear, Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 16)
                        .allowsHitTesting(false)
                        .alignmentGuide(.bottom) { d in d[.bottom] }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: listHeight)
            }
        }
        .frame(width: 210, alignment: .leading)
        .frame(maxHeight: maxTabContentHeight, alignment: .top)
        .padding(.bottom, 2)
    }

    private var activeTimerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                leadingControlSection
                    .frame(width: 128, alignment: .leading)

                timerTitleSection

                countdownSection
            }

            progressSection
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var leadingControlSection: some View {
        if timerManager.allowsManualInteraction {
            HStack(spacing: 10) {
                if !timerManager.isOvertime {
                    TimerControlButton(
                        icon: pauseIconName,
                        foreground: .white.opacity(0.95),
                        background: timerAccentColor.opacity(0.32),
                        accessibilityLabel: pauseAccessibilityLabel,
                        action: togglePauseAction
                    )

                    TimerControlButton(
                        icon: "xmark",
                        foreground: .white.opacity(0.95),
                        background: Color.white.opacity(0.16),
                        accessibilityLabel: String(localized: "Cancel"),
                        action: stopTimerAction
                    )
                } else {
                    TimerControlButton(
                        icon: "stop.fill",
                        foreground: .white.opacity(0.95),
                        background: Color.white.opacity(0.16),
                        accessibilityLabel: String(localized: "Stop"),
                        action: stopTimerAction
                    )
                }
            }
        } else {
            inactiveTimerPlaceholder
        }
    }

    private var timerTitleSection: some View {
        GeometryReader { geometry in
            let status = timerStatusText
            let spacing: CGFloat = status == nil ? 0 : 8
            let badgeWidth: CGFloat = status.map(statusBadgeWidth) ?? 0
            let marqueeWidth = max(48, geometry.size.width - badgeWidth - spacing)

            HStack(alignment: .center, spacing: spacing) {
                MarqueeText(
                    .constant(timerDisplayName),
                    font: .system(size: 20, weight: .semibold),
                    nsFont: .title3,
                    textColor: .white,
                    minDuration: 0.2,
                    frameWidth: marqueeWidth
                )
                .frame(width: marqueeWidth, height: 24, alignment: .leading)

                if let status {
                    statusBadge(status)
                        .frame(width: badgeWidth)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 32)
    }

    @ViewBuilder
    private var countdownSection: some View {
        if showsProgress && progressStyle == .ring {
            TimerProgressRing(
                progress: timerManager.progress,
                tint: timerAccentColor,
                timeText: timerManager.formattedRemainingTime(),
                isOvertime: timerManager.isOvertime,
                remainingTime: timerManager.remainingTime
            )
        } else {
            VStack(alignment: .trailing, spacing: 4) {
                Text(timerManager.formattedRemainingTime())
                    .font(.system(size: 36, weight: .black, design: .monospaced))
                    .foregroundStyle(timerManager.isOvertime ? Color.red : .white)
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.25), value: timerManager.remainingTime)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if timerManager.isOvertime {
                    Text(String(localized: "Overtime"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 190, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if showsProgress && progressStyle == .bar {
            Capsule()
                .fill(Color.white.opacity(0.12))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(timerAccentColor)
                        .frame(height: 4)
                        .scaleEffect(x: normalizedProgress, y: 1, anchor: .leading)
                        .animation(.smooth(duration: 0.25), value: timerManager.progress)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 2)
        }
    }

    private func togglePauseAction() {
        guard timerManager.allowsManualInteraction else { return }
        timerManager.isPaused ? timerManager.resumeTimer() : timerManager.pauseTimer()
    }

    private func stopTimerAction() {
        if timerManager.allowsManualInteraction {
            timerManager.stopTimer()
        } else {
            timerManager.endExternalTimer(triggerSmoothClose: false)
        }
    }

    private var customTimerComposer: some View {
        Group {
            if showTimerPresetsInNotchTab {
                VStack(alignment: .leading, spacing: 12) {
                    DurationInputRow(
                        hours: $customHours,
                        minutes: $customMinutes,
                        seconds: $customSeconds,
                        fieldWidth: durationFieldWidth
                    )

                    HStack(spacing: 10) {
                        startButton
                        resetButton
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    DurationInputRow(
                        hours: $customHours,
                        minutes: $customMinutes,
                        seconds: $customSeconds,
                        fieldWidth: durationFieldWidth
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 10) {
                        startButton
                        resetButton
                    }
                    .frame(width: buttonColumnWidth, alignment: .top)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var inactiveTimerPlaceholder: some View {
        Color.clear
            .frame(height: 46)
    }

    private var disabledState: some View {
        VStack(spacing: 16) {
            Image(systemName: "timer.slash")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Timer Disabled")
                .font(.title2)
                .fontWeight(.medium)

            Text("Enable the timer feature in Settings to access this tab.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shouldShowPresetColumn: Bool {
        !timerManager.isTimerActive && showTimerPresetsInNotchTab
    }

    private var resolvedNotchHeight: CGFloat {
        let height = vm.notchSize.height
        return height > 0 ? height : openNotchSize.height
    }

    private var headerHeight: CGFloat {
        max(24, vm.effectiveClosedNotchHeight)
    }

    private var maxTabContentHeight: CGFloat {
        let available = resolvedNotchHeight - headerHeight - 36
        return max(130, available)
    }

    private func lockAccentColorIfNeeded() {
        if timerManager.isTimerActive {
            lockedAccentColor = resolvedAccentColor
        }
    }

    private var timerAccentColor: Color {
        lockedAccentColor ?? resolvedAccentColor
    }

    private var resolvedAccentColor: Color {
        switch colorMode {
        case .adaptive:
            return timerManager.activePreset?.color ?? timerManager.timerColor
        case .solid:
            return solidColor
        }
    }

    private var normalizedProgress: CGFloat {
        CGFloat(max(0, min(timerManager.progress, 1)))
    }

    private var timerDisplayName: String {
        timerManager.timerName.isEmpty ? "Timer" : timerManager.timerName
    }

    private var timerStatusText: String? {
        if timerManager.isOvertime {
            return String(localized: "Overtime")
        } else if timerManager.isPaused {
            return String(localized: "Paused")
        } else if timerManager.isFinished {
            return "Completed"
        }
        return nil
    }

    private var timerStatusColor: Color {
        timerManager.isOvertime ? .red : timerAccentColor
    }

    private func statusBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(timerStatusColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(timerStatusColor.opacity(0.18))
            .clipShape(Capsule())
    }

    private func statusBadgeWidth(for text: String) -> CGFloat {
#if canImport(AppKit)
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
#elseif canImport(UIKit)
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
#else
        return 80
#endif
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        return width + 24
    }

    private var pauseIconName: String {
        timerManager.isPaused ? "play.fill" : "pause.fill"
    }

    private var pauseAccessibilityLabel: String {
        timerManager.isPaused ? String(localized: "Resume") : String(localized: "Pause")
    }

    private var startButtonColor: Color {
        Color(red: 0.142, green: 0.633, blue: 0.265)
    }

    private var isStartDisabled: Bool {
        customDurationInSeconds == 0
    }

    private var durationFieldWidth: CGFloat {
        showTimerPresetsInNotchTab ? 64 : 78
    }

    private var buttonColumnWidth: CGFloat { 210 }

    private var startButton: some View {
        Button {
            withAnimation(.smooth) {
                timerManager.startTimer(duration: customDurationInSeconds, name: String(localized: "Custom Timer"))
                if !enableMinimalisticUI {
                    coordinator.currentView = .timer
                }
            }
        } label: {
            Label(String(localized: "Start"), systemImage: "play.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(startButtonColor.opacity(isStartDisabled ? 0.5 : 1))
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .opacity(isStartDisabled ? 0.7 : 1)
        .disabled(isStartDisabled)
    }

    private var resetButton: some View {
        Button(action: resetCustomTimerInputs) {
            Label(String(localized: "Reset"), systemImage: "arrow.counterclockwise")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var customDurationInSeconds: TimeInterval {
        TimeInterval(customHours * 3600 + customMinutes * 60 + customSeconds)
    }

    private func resetCustomTimerInputs() {
        withAnimation(.smooth(duration: 0.2)) {
            customHours = 0
            customMinutes = 0
            customSeconds = 0
        }
        customTimerDuration = 0
    }

    private func syncCustomDuration(with value: Double) {
        isSyncingCustomDuration = true
        let components = TimerPreset.components(for: value)
        customHours = components.hours
        customMinutes = components.minutes
        customSeconds = components.seconds
        isSyncingCustomDuration = false
    }

    private func updateStoredCustomDuration() {
        guard !isSyncingCustomDuration else { return }
        customTimerDuration = customDurationInSeconds
    }
}

private struct TimerControlButton: View {
    let icon: String
    let foreground: Color
    let background: Color
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: 46, height: 46)
                .background(background.opacity(isHovering ? 0.95 : 0.8))
                .clipShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(accessibilityLabel)
        .onHover { hovering in isHovering = hovering }
    }
}

private struct TimerProgressRing: View {
    let progress: Double
    let tint: Color
    let timeText: String
    let isOvertime: Bool
    let remainingTime: TimeInterval

    private var clampedProgress: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 8)

            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.3), value: clampedProgress)

            Text(timeText)
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundStyle(isOvertime ? Color.red : .white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: remainingTime)
        }
        .frame(width: 110, height: 110)
    }
}

private struct DurationInputRow: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    let fieldWidth: CGFloat

    init(
        hours: Binding<Int>,
        minutes: Binding<Int>,
        seconds: Binding<Int>,
        fieldWidth: CGFloat = 64
    ) {
        _hours = hours
        _minutes = minutes
        _seconds = seconds
        self.fieldWidth = fieldWidth
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            DurationField(label: String(localized: "Hours"), value: $hours, range: 0...23, width: fieldWidth)
            colon
            DurationField(label: String(localized: "Minutes"), value: $minutes, range: 0...59, width: fieldWidth)
            colon
            DurationField(label: String(localized: "Seconds"), value: $seconds, range: 0...59, width: fieldWidth)
        }
    }

    private var colon: some View {
        Text(":")
            .font(.system(size: 26, weight: .black, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.65))
    }
}

private struct DurationField: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let width: CGFloat

    init(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        width: CGFloat = 64
    ) {
        self.label = label
        _value = value
        self.range = range
        self.width = width
    }

    var body: some View {
        VStack(spacing: 6) {
            TextField("00", text: binding)
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .tint(.white)
                .frame(width: width, height: 46)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(label)
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.65))
        }
    }

    private var binding: Binding<String> {
        Binding<String>(
            get: { String(format: "%02d", value) },
            set: { newValue in
                let digits = newValue.filter { $0.isNumber }
                let number = min(max(range.lowerBound, Int(digits) ?? 0), range.upperBound)
                value = number
            }
        )
    }
}

private struct TimerPresetCard: View {
    let preset: TimerPreset
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(preset.color.gradient)
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(preset.formattedDuration)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(preset.color)

                Spacer()

                Image(systemName: isActive ? "checkmark" : "play.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isActive ? preset.color : Color.secondary)
                    .padding(6)
                    .background(isActive ? preset.color.opacity(0.2) : Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isActive ? preset.color.opacity(0.12) : Color.white.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NotchTimerView()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 600, height: 320)
        .background(.black)
}
