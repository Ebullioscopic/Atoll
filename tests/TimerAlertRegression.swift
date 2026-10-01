import Foundation

// Run with:
// swiftc DynamicIsland/managers/TimerAlertController.swift tests/TimerAlertRegression.swift -o /tmp/atoll-timer-alert-tests
// /tmp/atoll-timer-alert-tests
@main
struct TimerAlertRegression {
    /// Exercises phase timing and lifecycle behavior with simulated playback.
    static func main() {
        var date = Date(timeIntervalSince1970: 0)
        var duration = 30
        var interval = 5
        var playing = false
        var playCount = 0
        var controller = TimerAlertController()
        func start() {
            controller.start(at: date)
            playing = true
            playCount += 1
        }
        func stop() {
            controller.stop()
            playing = false
        }
        func advance(_ seconds: TimeInterval) {
            date.addTimeInterval(seconds)
            if let ringing = controller.update(at: date, duration: duration, interval: interval) {
                playing = ringing
                if ringing { playCount += 1 }
            }
        }

        start()
        precondition(playing && playCount == 1)
        advance(29.9)
        precondition(playing)
        advance(0.1)
        precondition(!playing)
        advance(299.9)
        precondition(!playing)
        advance(0.1)
        precondition(playing && playCount == 2)
        advance(30)
        precondition(!playing)

        // Stopping during silence must cancel every subsequent reminder.
        stop()
        advance(3600)
        precondition(!playing && playCount == 2)

        // Settings edits affect the ongoing ringing and waiting phases.
        start()
        duration = 40
        advance(30)
        precondition(playing)
        advance(10)
        precondition(!playing)
        interval = 2
        advance(119)
        precondition(!playing)
        advance(1)
        precondition(playing && playCount == 4)
        duration = 5
        advance(5)
        precondition(!playing)

        // Replacing an alert resets its deadline; old deadlines cannot stop it.
        start()
        advance(4)
        start()
        advance(1)
        precondition(playing)
        advance(4)
        precondition(!playing)

        // Sleep during ringing immediately silences playback. A long sleep
        // produces one reminder on wake, not a burst of missed reminders.
        start()
        controller.prepareForSleep(at: date)
        playing = controller.isRinging
        precondition(!playing)
        let beforeWake = playCount
        advance(7200)
        precondition(playing && playCount == beforeWake + 1)
        advance(0)
        precondition(playCount == beforeWake + 1)
        stop()
        precondition(!playing)
        advance(7200)
        precondition(playCount == beforeWake + 1)

        // A delayed run-loop tick still gives the user a full silent interval.
        start()
        advance(10000)
        precondition(!playing)
        advance(119)
        precondition(!playing)
        advance(1)
        precondition(playing)
        stop()

        // Invalid persisted values are bounded before scheduling.
        duration = Int.min
        interval = Int.min
        start()
        advance(0.9)
        precondition(playing)
        advance(0.1)
        precondition(!playing)
        advance(60)
        precondition(playing)
        stop()
        duration = Int.max
        interval = Int.max
        start()
        advance(3599)
        precondition(playing)
        advance(1)
        precondition(!playing)
        advance(1440 * 60 - 1)
        precondition(!playing)
        advance(1)
        precondition(playing)
        stop()
        print("Timer alert regression checks passed")
    }
}
