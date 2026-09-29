import Foundation

// Run with:
// swiftc DynamicIsland/managers/TimerAlertController.swift tests/TimerAlertRegression.swift -o /tmp/atoll-timer-alert-tests
// /tmp/atoll-timer-alert-tests
@main
struct TimerAlertRegression {
    static func main() {
        precondition(TimerAlertController.duration(minutes: 0, seconds: 30) == 30)
        precondition(TimerAlertController.duration(minutes: 1, seconds: 30) == 90)
        precondition(TimerAlertController.duration(minutes: 2, seconds: 0) == 120)
        precondition(TimerAlertController.duration(minutes: 0, seconds: 0) == 1)
        precondition(TimerAlertController.duration(minutes: 60, seconds: 59) == 3600)
        precondition(TimerAlertController.duration(minutes: Int.max, seconds: Int.max) == 3600)
        var date = Date(timeIntervalSince1970: 0)
        var duration = 30
        var interval = 5
        var playing = false
        var playCount = 0
        let controller = TimerAlertController(
            now: { date },
            ringDuration: { duration },
            repeatIntervalMinutes: { interval },
            playSound: { playing = true; playCount += 1 },
            stopSound: { playing = false }
        )
        func advance(_ seconds: TimeInterval) {
            date.addTimeInterval(seconds)
            controller.update()
        }

        controller.start()
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
        controller.stop()
        advance(3600)
        precondition(!playing && playCount == 2)

        // Settings edits affect the ongoing ringing and waiting phases.
        controller.start()
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
        controller.start()
        advance(4)
        controller.start()
        advance(1)
        precondition(playing)
        advance(4)
        precondition(!playing)

        // Sleep during ringing immediately silences playback. A long sleep
        // produces one reminder on wake, not a burst of missed reminders.
        controller.start()
        controller.prepareForSleep()
        precondition(!playing)
        let beforeWake = playCount
        advance(7200)
        precondition(playing && playCount == beforeWake + 1)
        controller.update()
        precondition(playCount == beforeWake + 1)
        controller.stop()
        precondition(!playing)
        advance(7200)
        precondition(playCount == beforeWake + 1)

        // A delayed run-loop tick still gives the user a full silent interval.
        controller.start()
        advance(10000)
        precondition(!playing)
        advance(119)
        precondition(!playing)
        advance(1)
        precondition(playing)
        controller.stop()

        // Invalid persisted values are bounded before scheduling.
        duration = Int.min
        interval = Int.min
        controller.start()
        advance(0.9)
        precondition(playing)
        advance(0.1)
        precondition(!playing)
        advance(60)
        precondition(playing)
        controller.stop()
        precondition(TimerAlertController.clamp(Int.max, to: TimerAlertController.ringDurationRange) == 3600)
        precondition(TimerAlertController.clamp(Int.max, to: TimerAlertController.repeatIntervalRange) == 1440)

        // Exercise the real RunLoop scheduling path, not only manual ticks.
        var scheduledPlaying = false
        var scheduled: TimerAlertController? = TimerAlertController(
            ringDuration: { 1 },
            repeatIntervalMinutes: { 1 },
            playSound: { scheduledPlaying = true },
            stopSound: { scheduledPlaying = false }
        )
        scheduled?.start()
        precondition(scheduledPlaying)
        RunLoop.main.run(until: Date().addingTimeInterval(1.3))
        precondition(!scheduledPlaying)
        scheduled?.start()
        precondition(scheduledPlaying)
        scheduled = nil
        precondition(!scheduledPlaying)
        print("Timer alert regression checks passed")
    }
}
