/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import Defaults
import AppKit

struct EventModel: Equatable, Identifiable {
    let id: String
    let start: Date
    let end: Date
    let title: String
    let location: String?
    let notes: String?
    let url: URL?
    let isAllDay: Bool
    let type: EventType
    let calendar: CalendarModel
    let participants: [Participant]
    let timeZone: TimeZone?
    let hasRecurrenceRules: Bool
    let priority: Priority?
    let conferenceURL: URL?
}

enum AttendanceStatus: Comparable {
    case accepted
    case maybe
    case pending
    case declined
    case unknown

    private var comparisonValue: Int {
        switch self {
        case .accepted: return 1
        case .maybe: return 2
        case .declined: return 3
        case .pending: return 4
        case .unknown: return 5
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.comparisonValue < rhs.comparisonValue
    }
}

enum EventType: Equatable {
    case event(AttendanceStatus)
    case birthday
    case reminder(completed: Bool)
}

enum EventStatus: Equatable {
    case upcoming
    case inProgress
    case ended
}

extension EventType {
    var isEvent: Bool { if case .event = self { return true } else { return false } }
    var isBirthday: Bool { self ~= .birthday }
    var isReminder: Bool { if case .reminder = self { return true } else { return false } }
}

extension EventModel {
    
    var eventStatus: EventStatus {
        if start > Date() {
            return .upcoming
        } else if end > Date() {
            return .inProgress
        } else {
            return .ended
        }
    }
        
    var attendance: AttendanceStatus { if case .event(let attendance) = type { return attendance } else { return .unknown } }

    var isMeeting: Bool { !participants.isEmpty }

    func calendarAppURL() -> URL? {
        // Check if a third-party calendar app is enabled
        if Defaults[.enableThirdPartyCalendarApp] {
            switch Defaults[.selectedCalendarApp] {
            case .fantastical:
                return fantasticalURL()
            case .notionCalendar:
                return notionCalendarURL()
            case .busyCal:
                return busyCalURL()
            case .custom:
                return customCalendarAppURL()
            }
        }
        return appleCalendarURL()
    }
    
    /// Returns URL to open event in Apple Calendar
    private func appleCalendarURL() -> URL? {
        guard let id = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        guard !type.isReminder else {
            return URL(string: "x-apple-reminderkit://remcdreminder/\(id)")
        }

        let date: String
        if hasRecurrenceRules {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            if !isAllDay {
                formatter.timeZone = .init(secondsFromGMT: 0)
            }
            if let formattedDate = formatter.string(for: start) {
                date = "/\(formattedDate)"
            } else {
                return nil
            }
        } else {
            date =  ""
        }
        return URL(string: "ical://ekevent\(date)/\(id)?method=show&options=more")
    }
    
    /// Returns URL to open date in Fantastical
    private func fantasticalURL() -> URL? {
        // Reminders still use Apple's Reminders app
        guard !type.isReminder else {
            return URL(string: "x-apple-reminderkit://remcdreminder/\(id)")
        }
        
        let viewStyle = Defaults[.fantasticalDefaultView]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: start)
        
        // x-fantastical3://show/mini/yyyy-MM-dd or x-fantastical3://show/calendar/yyyy-MM-dd
        return URL(string: "x-fantastical3://show/\(viewStyle.rawValue)/\(dateString)")
    }
    
    /// Returns URL to open Fantastical at current date (for general calendar access)
    static func fantasticalShowURL(for date: Date? = nil) -> URL? {
        let viewStyle = Defaults[.fantasticalDefaultView]
        if let date = date {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: date)
            return URL(string: "x-fantastical3://show/\(viewStyle.rawValue)/\(dateString)")
        }
        return URL(string: "x-fantastical3://show/\(viewStyle.rawValue)")
    }
    
    /// Returns URL to open event in Notion Calendar (formerly Cron)
    private func notionCalendarURL() -> URL? {
        // Reminders still use Apple's Reminders app
        guard !type.isReminder else {
            return URL(string: "x-apple-reminderkit://remcdreminder/\(id)")
        }
        
        let formatter = ISO8601DateFormatter()
        
        var components = URLComponents()
        components.scheme = "cron"
        components.host = "showEvent"
        components.queryItems = [
            URLQueryItem(name: "accountEmail", value: calendar.accountName),
            URLQueryItem(name: "iCalUID", value: id),
            URLQueryItem(name: "startDate", value: formatter.string(from: start)),
            URLQueryItem(name: "endDate", value: formatter.string(from: end)),
            URLQueryItem(name: "title", value: title)
        ]
        
        if let url = components.url {
            return url
        }
        
        // Fallback: just launch Notion Calendar app
        Self.launchNotionCalendar()
        return nil
    }
    
    /// Launches Notion Calendar app directly (fallback or general access)
    static func launchNotionCalendar() {
        // Launch via bundle identifier (Notion Calendar's bundle ID is "com.cron.electron")
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.cron.electron") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error = error {
                    print("Error launching Notion Calendar: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Returns URL to open event in BusyCal
    private func busyCalURL() -> URL? {
        // Reminders still use Apple's Reminders app
        guard !type.isReminder else {
            return URL(string: "x-apple-reminderkit://remcdreminder/\(id)")
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: start)
        
        // busycal:// URL scheme to show a specific date
        return URL(string: "busycal://show/\(dateString)")
    }
    
    /// Returns URL to open event in a custom calendar app via its bundle identifier
    private func customCalendarAppURL() -> URL? {
        // Reminders still use Apple's Reminders app
        guard !type.isReminder else {
            return URL(string: "x-apple-reminderkit://remcdreminder/\(id)")
        }
        
        let bundleID = Defaults[.customCalendarAppBundleID]
        guard !bundleID.isEmpty else {
            // No custom app configured, fall back to Apple Calendar
            return appleCalendarURL()
        }
        
        // Launch the custom app by bundle identifier
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                if let error = error {
                    print("Error launching custom calendar app (\(bundleID)): \(error.localizedDescription)")
                }
            }
        }
        return nil
    }
}

struct Participant: Hashable {
    let name: String
    let status: AttendanceStatus
    let isOrganizer: Bool
    let isCurrentUser: Bool
}

enum Priority {
    case high
    case medium
    case low
}
