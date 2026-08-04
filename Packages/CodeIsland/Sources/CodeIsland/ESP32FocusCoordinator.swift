import AppKit
import Foundation
import os
import CodeIslandCore

/// Turns a button press from Buddy (1-byte `sourceId`) into a real
/// "focus that agent's terminal/window" action.
///
/// This keeps focus routing aligned with the mascot currently shown on Buddy.
/// We pick the best session belonging to the requested mascot (preferring
/// ones with pending work) and hand it to `TerminalActivator`, whose tab-level
/// matchers already know how to land inside the exact iTerm2 session / Ghostty
/// tab / Kitty window / tmux pane / Cursor project window / etc.
@MainActor
enum ESP32FocusCoordinator {
    private static let log = Logger(subsystem: "com.codeisland", category: "esp32-focus")

    /// Ordered status priority — richer statuses win the tiebreak so that a
    /// button press preferentially lands on the session actually needing
    /// attention, not a forgotten idle one.
    private static func priority(_ status: AgentStatus) -> Int {
        switch status {
        case .waitingApproval: return 5
        case .waitingQuestion: return 4
        case .running:         return 3
        case .processing:      return 2
        case .idle:            return 1
        }
    }

    static func handle(mascot: MascotID, appState: AppState) {
        let targetSource = mascot.sourceName

        let candidates = appState.sessions
            .filter { $0.value.source == targetSource }
            .sorted { a, b in
                let pa = priority(a.value.status)
                let pb = priority(b.value.status)
                if pa != pb { return pa > pb }
                return a.value.lastActivity > b.value.lastActivity
            }

        if let (sessionId, session) = candidates.first {
            log.info("Focus \(targetSource): session=\(sessionId) status=\(String(describing: session.status))")
            TerminalActivator.activate(session: session, sessionId: sessionId)
            return
        }

        if let bundleId = TerminalActivator.sourceToNativeAppBundleId[targetSource],
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) {
            log.info("Focus \(targetSource): no session, activating desktop app \(bundleId)")
            if app.isHidden { app.unhide() }
            app.activate()
            return
        }

        log.info("Focus \(targetSource): no active session, no desktop app running — ignored")
    }
}
