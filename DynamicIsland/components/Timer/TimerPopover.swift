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

struct TimerPopover: View {
    @ObservedObject var timerManager = TimerManager.shared
    @Default(.timerPresets) private var timerPresets
    @Default(.timerShowsCountdown) private var showsCountdown
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @AppStorage("customTimerDuration") private var customTimerDuration: Double = 600
    @Environment(\.dismiss) private var dismiss
    
    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 10
    @State private var customSeconds: Int = 0
    
    private var customDurationInSeconds: TimeInterval {
        TimeInterval(customHours * 3600 + customMinutes * 60 + customSeconds)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            HeaderView(statusText: statusText)
            
            if timerManager.isTimerActive {
                ActiveTimerSection(timerManager: timerManager)
            } else {
                CustomTimerSection(hours: $customHours, minutes: $customMinutes, seconds: $customSeconds, startAction: startCustomTimer)
                    .onChange(of: customHours) { _, _ in updateStoredCustomDuration() }
                    .onChange(of: customMinutes) { _, _ in updateStoredCustomDuration() }
                    .onChange(of: customSeconds) { _, _ in updateStoredCustomDuration() }
            }
            
            Divider()
                .padding(.horizontal, -8)
            
            PresetList(presets: timerPresets, activePresetId: timerManager.activePresetId, startAction: startPreset)
                .animation(.smooth, value: timerManager.activePresetId)
                .frame(maxHeight: 200)
        }
        .padding(16)
        .frame(width: 300)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(12)
        )
        .onAppear {
            syncCustomDuration(with: customTimerDuration)
        }
        .onChange(of: customTimerDuration) { _, newValue in
            syncCustomDuration(with: newValue)
        }
    }
    
    private var statusText: String {
        if timerManager.isOvertime {
            return String(localized: "Overtime")
        } else if timerManager.isPaused {
            return String(localized: "Paused")
        } else if timerManager.isTimerActive {
            return String(localized: "Running")
        } else {
            return "Ready"
        }
    }
    
    private func syncCustomDuration(with value: Double) {
        let components = TimerPreset.components(for: value)
        customHours = components.hours
        customMinutes = components.minutes
        customSeconds = components.seconds
    }
    
    private func updateStoredCustomDuration() {
        let newValue = customDurationInSeconds
        customTimerDuration = newValue
    }
    
    private func startCustomTimer() {
        let duration = customDurationInSeconds
        guard duration > 0 else { return }
        withAnimation(.smooth) {
            timerManager.startTimer(duration: duration, name: String(localized: "Custom Timer"))
        }
        dismiss()
    }
    
    private func startPreset(_ preset: TimerPreset) {
        withAnimation(.smooth) {
            timerManager.startTimer(duration: preset.duration, name: preset.name, preset: preset)
        }
        dismiss()
    }
}

private struct HeaderView: View {
    let statusText: String
    
    var body: some View {
        HStack(spacing: 12) {
            TimerIconAnimation()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Timer"))
                    .font(.system(size: 14, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

private struct ActiveTimerSection: View {
    @ObservedObject var timerManager: TimerManager
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerPresets) private var timerPresets
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(timerManager.timerName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                Text(timerManager.formattedRemainingTime())
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(timerManager.isOvertime ? Color.red : Color.primary)
                    .contentTransition(.numericText())
            }
            
            if showsProgress && progressStyle == .bar {
                ProgressView(value: min(timerManager.progress, 1.0))
                    .progressViewStyle(LinearProgressViewStyle(tint: progressTint))
                    .animation(.smooth(duration: 0.2), value: timerManager.progress)
            }
            
            HStack(spacing: 8) {
                if !timerManager.isOvertime {
                    Button(action: togglePause) {
                        Label(timerManager.isPaused ? String(localized: "Resume") : String(localized: "Pause"), systemImage: timerManager.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 12, weight: .medium))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!timerManager.allowsManualInteraction)
                }

                Button(role: .destructive, action: stopTimer) {
                    Label(String(localized: "Stop"), systemImage: "stop.fill")
                        .font(.system(size: 12, weight: .medium))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!timerManager.allowsManualInteraction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .animation(.smooth, value: timerManager.isPaused)
    }
    
    private func togglePause() {
        guard timerManager.allowsManualInteraction else { return }
        withAnimation(.smooth) {
            if timerManager.isPaused {
                timerManager.resumeTimer()
            } else {
                timerManager.pauseTimer()
            }
        }
    }
    
    private func stopTimer() {
        guard timerManager.allowsManualInteraction else {
            timerManager.endExternalTimer(triggerSmoothClose: false)
            return
        }
        withAnimation(.smooth) {
            timerManager.stopTimer()
        }
    }

    private var progressTint: Color {
        switch colorMode {
        case .adaptive:
            return activePresetColor ?? timerManager.timerColor
        case .solid:
            return solidColor
        }
    }

    private var activePresetColor: Color? {
        guard let presetId = timerManager.activePresetId else { return nil }
        return timerPresets.first { $0.id == presetId }?.color
    }
}

private struct CustomTimerSection: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    let startAction: () -> Void
    
    private var totalSeconds: Int {
        hours * 3600 + minutes * 60 + seconds
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Custom Timer"))
                .font(.system(size: 14, weight: .semibold))
            
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 8) {
                GridRow {
                    DurationStepper(title: String(localized: "Hours"), value: $hours, range: 0...23)
                    DurationStepper(title: String(localized: "Minutes"), value: $minutes, range: 0...59)
                    DurationStepper(title: String(localized: "Seconds"), value: $seconds, range: 0...59)
                }
            }
            
            Text(formattedDuration)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            
            Button(action: startAction) {
                Label("Start Custom Timer", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .medium))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(totalSeconds == 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    
    private var formattedDuration: String {
        let components = TimerPreset.DurationComponents(hours: hours, minutes: minutes, seconds: seconds)
        let interval = TimerPreset.duration(from: components)
        return TimerPreset(name: "", duration: interval, color: .clear).formattedDuration
    }
}

private struct DurationStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    
    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(title)
                    .font(.system(size: 8.5, weight: .medium))
                Spacer()
                Text("\(value)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        }
        .frame(width: 88)
    }
}

private struct PresetList: View {
    let presets: [TimerPreset]
    let activePresetId: UUID?
    let startAction: (TimerPreset) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Presets"))
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 4)
            
            if presets.isEmpty {
                Text("Configure presets in Settings")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(presets) { preset in
                            TimerPresetRow(preset: preset, isActive: activePresetId == preset.id) {
                                startAction(preset)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct TimerPresetRow: View {
    let preset: TimerPreset
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(preset.color.gradient)
                    .frame(width: 20, height: 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(preset.formattedDuration)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isActive ? "checkmark" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isActive ? preset.color : Color.secondary)
                    .padding(6)
                    .background(isActive ? preset.color.opacity(0.2) : Color.clear)
                    .clipShape(Circle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? preset.color.opacity(0.18) : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TimerPopover()
    .frame(width: 300)
        .padding()
        .background(Color.black)
}
