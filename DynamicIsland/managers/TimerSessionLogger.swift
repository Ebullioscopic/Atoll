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

// MARK: - Model

struct TimerSessionLog: Codable, Identifiable {
    let id: UUID
    let label: String
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval // actual focus time in seconds (excludes pauses)
    let totalDuration: TimeInterval // original timer duration set by user
    let completedFully: Bool // did it reach zero (vs manual stop)

    init(label: String, startDate: Date, endDate: Date, duration: TimeInterval, totalDuration: TimeInterval, completedFully: Bool) {
        self.id = UUID()
        self.label = label
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
        self.totalDuration = totalDuration
        self.completedFully = completedFully
    }
}

// MARK: - Logger

class TimerSessionLogger: ObservableObject {
    static let shared = TimerSessionLogger()

    @Published private(set) var sessions: [TimerSessionLog] = []

    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Atoll", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("timer_sessions.json")
    }()

    private init() {
        load()
    }

    // MARK: - Public API

    func logSession(_ session: TimerSessionLog) {
        sessions.append(session)
        save()
    }

    func clearAll() {
        sessions.removeAll()
        save()
    }

    // MARK: - Statistics

    func sessionsToday() -> [TimerSessionLog] {
        let start = Calendar.current.startOfDay(for: Date())
        return sessions.filter { $0.endDate >= start }
    }

    func sessionsThisWeek() -> [TimerSessionLog] {
        guard let weekStart = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else { return [] }
        return sessions.filter { $0.endDate >= weekStart }
    }

    func totalFocusTimeToday() -> TimeInterval {
        sessionsToday().reduce(0) { $0 + $1.duration }
    }

    func totalFocusTimeThisWeek() -> TimeInterval {
        sessionsThisWeek().reduce(0) { $0 + $1.duration }
    }

    func sessionCountToday() -> Int {
        sessionsToday().count
    }

    func sessionCountThisWeek() -> Int {
        sessionsThisWeek().count
    }

    /// Current streak: consecutive days with at least one session
    func currentStreak() -> Int {
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())

        while true {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: checkDate)!
            let hasSession = sessions.contains { $0.endDate >= checkDate && $0.endDate < dayEnd }
            if hasSession {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
                checkDate = prev
            } else {
                break
            }
        }
        return streak
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[TimerSessionLogger] Failed to save: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            sessions = try JSONDecoder().decode([TimerSessionLog].self, from: data)
        } catch {
            print("[TimerSessionLogger] Failed to load: \(error)")
        }
    }
}
