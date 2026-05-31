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

struct AlarmSettingsView: View {
    @ObservedObject var alarmManager = AlarmManager.shared
    @State private var showingAddAlarm = false
    @State private var newAlarmLabel = ""
    @State private var newAlarmDate = Date().addingTimeInterval(300)
    @State private var newAlarmRepeatDaily = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Label("Alarms", systemImage: "alarm")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddAlarm.toggle() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }

            if alarmManager.isAlarmFiring {
                AlarmFiringBanner(alarmManager: alarmManager)
            }

            if showingAddAlarm {
                AddAlarmForm(
                    label: $newAlarmLabel,
                    date: $newAlarmDate,
                    repeatDaily: $newAlarmRepeatDaily,
                    onAdd: addAlarm,
                    onCancel: { showingAddAlarm = false }
                )
            }

            if alarmManager.alarms.isEmpty {
                Text("No alarms set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                AlarmListView(alarms: alarmManager.alarms, alarmManager: alarmManager)
            }
        }
        .padding(12)
    }

    private func addAlarm() {
        let label = newAlarmLabel.isEmpty ? "Reminder" : newAlarmLabel
        alarmManager.addAlarm(label: label, fireDate: newAlarmDate, repeatDaily: newAlarmRepeatDaily)
        newAlarmLabel = ""
        newAlarmDate = Date().addingTimeInterval(300)
        newAlarmRepeatDaily = false
        showingAddAlarm = false
    }
}

// MARK: - Subviews

private struct AlarmFiringBanner: View {
    @ObservedObject var alarmManager: AlarmManager

    var body: some View {
        HStack {
            Image(systemName: "bell.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
            Text(firingLabel)
                .font(.subheadline.bold())
            Spacer()
            Button("Dismiss") {
                alarmManager.dismissAlarm()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    private var firingLabel: String {
        guard let id = alarmManager.activeAlarmId,
              let alarm = alarmManager.alarms.first(where: { $0.id == id }) else {
            return "Alarm!"
        }
        return alarm.label
    }
}

private struct AddAlarmForm: View {
    @Binding var label: String
    @Binding var date: Date
    @Binding var repeatDaily: Bool
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            TextField("Label (e.g. Stand up)", text: $label)
                .textFieldStyle(.roundedBorder)

            DatePicker("Time", selection: $date, displayedComponents: [.hourAndMinute, .date])
                .labelsHidden()

            Toggle("Repeat daily", isOn: $repeatDaily)
                .font(.caption)

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                Spacer()
                Button("Add Alarm", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(date < Date())
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

private struct AlarmListView: View {
    let alarms: [Alarm]
    @ObservedObject var alarmManager: AlarmManager

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(sortedAlarms) { alarm in
                    AlarmRow(alarm: alarm, alarmManager: alarmManager)
                }
            }
        }
        .frame(maxHeight: 180)
    }

    private var sortedAlarms: [Alarm] {
        alarms.sorted { $0.fireDate < $1.fireDate }
    }
}

private struct AlarmRow: View {
    let alarm: Alarm
    @ObservedObject var alarmManager: AlarmManager

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(alarm.label)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(alarm.formattedTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if alarm.repeatDaily {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { _ in alarmManager.toggleAlarm(id: alarm.id) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            Button(action: { alarmManager.removeAlarm(id: alarm.id) }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .opacity(alarm.isEnabled ? 1.0 : 0.5)
    }
}
