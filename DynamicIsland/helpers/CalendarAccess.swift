import EventKit

/// EventKit grants calendar and reminder access independently. A missing
/// permission must not hide settings for the other, readable source.
struct CalendarAccess {
    let calendarStatus: EKAuthorizationStatus
    let reminderStatus: EKAuthorizationStatus

    var hasCalendarAccess: Bool { Self.canRead(calendarStatus) }
    var hasReminderAccess: Bool { Self.canRead(reminderStatus) }
    var canShowSettings: Bool { hasCalendarAccess || hasReminderAccess }

    static func canRead(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .fullAccess: return true
        default: return false
        }
    }

    static func canRequest(_ status: EKAuthorizationStatus) -> Bool {
        switch status {
        case .notDetermined, .writeOnly: return true
        default: return false
        }
    }
}
