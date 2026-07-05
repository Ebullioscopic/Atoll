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
    @ObservedObject var togglManager = TogglManager.shared
    @Default(.timerPresets) private var timerPresets
    @Default(.timerShowsCountdown) private var showsCountdown
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.togglEnabled) private var togglEnabled
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
                ActiveTimerSection(
                    timerManager: timerManager,
                    togglManager: togglManager,
                    togglEnabled: togglEnabled
                )
            } else {
                if togglEnabled && togglManager.isReady {
                    TogglInputSection(
                        togglManager: togglManager,
                        timerManager: timerManager
                    )

                    if !togglManager.recentEntries.isEmpty {
                        TogglRecentSection(togglManager: togglManager)
                    }
                }

                CustomTimerSection(
                    hours: $customHours,
                    minutes: $customMinutes,
                    seconds: $customSeconds,
                    startAction: startCustomTimer
                )
                .onChange(of: customHours)   { _, _ in updateStoredCustomDuration() }
                .onChange(of: customMinutes) { _, _ in updateStoredCustomDuration() }
                .onChange(of: customSeconds) { _, _ in updateStoredCustomDuration() }
            }

            // Persistent Toggl error banner (shown in both active and idle states)
            if togglEnabled, let error = togglManager.saveError {
                TogglErrorBanner(
                    error: error,
                    isRetrying: togglManager.isSavingEntry
                ) {
                    Task { await togglManager.retryPendingEntry() }
                }
            }

            // Saving indicator shown while the POST is in-flight after stop
            if togglEnabled && togglManager.isSavingEntry && !timerManager.isTimerActive {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                    Text("Saving to Toggl…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
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
        customHours   = components.hours
        customMinutes = components.minutes
        customSeconds = components.seconds
    }

    private func updateStoredCustomDuration() {
        customTimerDuration = customDurationInSeconds
    }

    private func startCustomTimer() {
        let duration = customDurationInSeconds
        guard duration > 0 else { return }
        togglManager.clearSaveError()
        withAnimation(.smooth) {
            timerManager.startTimer(duration: duration, name: String(localized: "Custom Timer"))
        }
        dismiss()
    }

    private func startPreset(_ preset: TimerPreset) {
        togglManager.clearSaveError()
        withAnimation(.smooth) {
            timerManager.startTimer(duration: preset.duration, name: preset.name, preset: preset)
        }
        dismiss()
    }
}

// MARK: - Header

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

// MARK: - Active Timer

private struct ActiveTimerSection: View {
    @ObservedObject var timerManager: TimerManager
    @ObservedObject var togglManager: TogglManager
    let togglEnabled: Bool
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
            timerManager.isPaused ? timerManager.resumeTimer() : timerManager.pauseTimer()
        }
    }

    private func stopTimer() {
        guard timerManager.allowsManualInteraction else {
            timerManager.endExternalTimer(triggerSmoothClose: false)
            return
        }
        withAnimation(.smooth) { timerManager.stopTimer() }
    }

    private var progressTint: Color {
        switch colorMode {
        case .adaptive: return activePresetColor ?? timerManager.timerColor
        case .solid:    return solidColor
        }
    }

    private var activePresetColor: Color? {
        guard let id = timerManager.activePresetId else { return nil }
        return timerPresets.first { $0.id == id }?.color
    }
}

// MARK: - Toggl Input

private struct TogglInputSection: View {
    @ObservedObject var togglManager: TogglManager
    @ObservedObject var timerManager: TimerManager
    @State private var noActiveTimerVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Description
            TextField("Description (optional)", text: $togglManager.pendingDescription)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))

            // Project picker + refresh
            HStack(spacing: 6) {
                Picker(selection: $togglManager.pendingProjectId, label: EmptyView()) {
                    Text("No Project").tag(Optional<Int>(nil))
                    ForEach(togglManager.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: { Task { await togglManager.fetchProjects() } }) {
                    if togglManager.isFetchingProjects {
                        ProgressView().scaleEffect(0.65).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .frame(width: 28, height: 24)
                .buttonStyle(.bordered)
                .help("Refresh projects")
                .disabled(togglManager.isFetchingProjects)
            }

            // Sync from Toggl
            HStack(spacing: 8) {
                Button(action: syncFromToggl) {
                    HStack(spacing: 4) {
                        if togglManager.isFetchingCurrentTimer {
                            ProgressView().scaleEffect(0.65).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11))
                        }
                        Text("Sync from Toggl")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(togglManager.isFetchingCurrentTimer)

                if noActiveTimerVisible {
                    Text("No active timer on Toggl")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: noActiveTimerVisible)
        }
        .padding(10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func syncFromToggl() {
        Task {
            guard let entry = await togglManager.fetchCurrentTimer(),
                  let parsedStart = entry.parsedStart else {
                withAnimation { noActiveTimerVisible = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { noActiveTimerVisible = false }
                }
                return
            }

            let elapsed = max(0, Date().timeIntervalSince(parsedStart))
            togglManager.pendingDescription = entry.description ?? ""
            togglManager.pendingProjectId   = entry.projectId
            togglManager.setSyncedStart(parsedStart)

            withAnimation(.smooth) {
                timerManager.startTimerFromOffset(elapsed, name: entry.description ?? "Timer")
            }
        }
    }
}

// MARK: - Toggl Recent Entries

private struct TogglRecentSection: View {
    @ObservedObject var togglManager: TogglManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(togglManager.recentEntries) { entry in
                        RecentEntryChip(entry: entry) {
                            togglManager.pendingDescription = entry.description
                            togglManager.pendingProjectId   = entry.projectId
                        }
                    }
                }
            }
        }
    }
}

private struct RecentEntryChip: View {
    let entry: TogglRecentEntry
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.description.isEmpty ? "(no description)" : entry.description)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let name = entry.projectName {
                    Text(name)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isHovering ? Color.white.opacity(0.12) : Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Toggl Error Banner

private struct TogglErrorBanner: View {
    let error: String
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 13))

            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isRetrying {
                ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
            } else {
                Button("Retry", action: onRetry)
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Custom Timer

private struct CustomTimerSection: View {
    @Binding var hours: Int
    @Binding var minutes: Int
    @Binding var seconds: Int
    let startAction: () -> Void

    private var totalSeconds: Int { hours * 3600 + minutes * 60 + seconds }

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

// MARK: - Preset List

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
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))

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
