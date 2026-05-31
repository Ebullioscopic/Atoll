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

import Foundation
import Combine
import SwiftUI
import UserNotifications
import AVFoundation
import AppKit
import Defaults

@MainActor
class AlarmManager: ObservableObject {
    static let shared = AlarmManager()

    @Published var alarms: [Alarm] = []
    @Published var activeAlarmId: UUID?
    @Published var isAlarmFiring: Bool = false

    private var checkTimer: Timer?
    private var soundPlayer: AVAudioPlayer?

    private init() {
        alarms = Defaults[.alarms]
        startMonitoring()
        requestNotificationPermission()
    }

    deinit {
        checkTimer?.invalidate()
        soundPlayer?.stop()
    }

    // MARK: - Notification Permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[AlarmManager] Notification permission error: \(error)")
            }
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAlarms()
            }
        }
    }

    private func checkAlarms() {
        let now = Date()
        for index in alarms.indices {
            guard alarms[index].isEnabled else { continue }
            guard !alarms[index].isExpired else { continue }

            let fireDate = alarms[index].fireDate
            let diff = fireDate.timeIntervalSince(now)

            if diff <= 0 && diff > -2 {
                fireAlarm(alarms[index])

                if alarms[index].repeatDaily {
                    // Reschedule for tomorrow
                    alarms[index].fireDate = Calendar.current.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate.addingTimeInterval(86400)
                } else {
                    alarms[index].isEnabled = false
                }
                persist()
            }
        }
    }

    // MARK: - Alarm Actions

    func addAlarm(label: String, fireDate: Date, repeatDaily: Bool = false) {
        let alarm = Alarm(label: label, fireDate: fireDate, repeatDaily: repeatDaily)
        alarms.append(alarm)
        persist()
        scheduleLocalNotification(for: alarm)
    }

    func removeAlarm(id: UUID) {
        alarms.removeAll { $0.id == id }
        persist()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    func toggleAlarm(id: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[index].isEnabled.toggle()
        persist()

        if alarms[index].isEnabled {
            scheduleLocalNotification(for: alarms[index])
        } else {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        }
    }

    func dismissAlarm() {
        isAlarmFiring = false
        activeAlarmId = nil
        soundPlayer?.stop()
        soundPlayer = nil
    }

    // MARK: - Fire

    private func fireAlarm(_ alarm: Alarm) {
        isAlarmFiring = true
        activeAlarmId = alarm.id
        playAlarmSound()

        // Auto-dismiss after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            if self?.activeAlarmId == alarm.id {
                self?.dismissAlarm()
            }
        }
    }

    private func playAlarmSound() {
        if let url = Bundle.main.url(forResource: "timer", withExtension: "mp3")
            ?? Bundle.main.url(forResource: "dynamic", withExtension: "m4a") {
            do {
                soundPlayer = try AVAudioPlayer(contentsOf: url)
                soundPlayer?.numberOfLoops = 3
                soundPlayer?.play()
            } catch {
                NSSound.beep()
            }
        } else {
            NSSound.beep()
        }
    }

    // MARK: - Local Notifications

    private func scheduleLocalNotification(for alarm: Alarm) {
        let content = UNMutableNotificationContent()
        content.title = "Alarm"
        content.body = alarm.label.isEmpty ? "Time's up!" : alarm.label
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alarm.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: alarm.repeatDaily)

        let request = UNNotificationRequest(identifier: alarm.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[AlarmManager] Failed to schedule notification: \(error)")
            }
        }
    }

    // MARK: - Persistence

    private func persist() {
        Defaults[.alarms] = alarms
    }
}
