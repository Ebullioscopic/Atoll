import EventKit
import SwiftUI

struct CalendarPermissionRow: View {
    let entity: EKEntityType
    let status: EKAuthorizationStatus
    let requestAccess: () async -> Void
    @State private var requesting = false

    private var settingsURL: URL {
        URL(string: entity == .event
            ? "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
            : "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!
    }

    private var statusText: String {
        switch status {
        case .authorized, .fullAccess: return String(localized: "Full Access")
        case .notDetermined: return String(localized: "Not Determined")
        case .writeOnly: return String(localized: "Write Only")
        case .denied: return String(localized: "Denied")
        case .restricted: return String(localized: "Restricted")
        @unknown default: return String(localized: "Unknown")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entity == .event ? String(localized: "Calendars") : String(localized: "Reminders"))
                Spacer()
                Text(statusText)
                    .foregroundStyle(CalendarAccess.canRead(status) ? Color.green : Color.secondary)
            }
            if !CalendarAccess.canRead(status) {
                Text(entity == .event
                    ? String(localized: "Allow access to show events and choose calendars.")
                    : String(localized: "Allow access to show reminders and choose lists."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if CalendarAccess.canRequest(status) {
                        Button("Request Access") {
                            requesting = true
                            Task {
                                await requestAccess()
                                requesting = false
                            }
                        }
                        .disabled(requesting)
                    }
                    Button("Open System Settings") { NSWorkspace.shared.open(settingsURL) }
                }
            }
        }
    }
}
