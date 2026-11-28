import EventKit

@main
struct CalendarAccessRegression {
    static func main() {
        let statuses: [EKAuthorizationStatus] = [.notDetermined, .restricted, .denied, .writeOnly, .fullAccess]
        for calendar in statuses {
            for reminder in statuses {
                let access = CalendarAccess(calendarStatus: calendar, reminderStatus: reminder)
                precondition(access.hasCalendarAccess == (calendar == .fullAccess))
                precondition(access.hasReminderAccess == (reminder == .fullAccess))
                precondition(access.canShowSettings == (calendar == .fullAccess || reminder == .fullAccess))
            }
        }
        // Denied/restricted statuses should direct the user to the right
        // System Settings pane; write-only must allow a read-access upgrade.
        for status in statuses {
            precondition(CalendarAccess.canRequest(status) == (status == .notDetermined || status == .writeOnly))
        }
        print("Calendar/Reminder access: 25 permission combinations passed")
    }
}
