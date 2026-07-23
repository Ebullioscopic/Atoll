import Foundation

@main
struct TimerLifecycleRegression {
    static func main() {
        var lifecycle = TimerLifecycle()

        let completedTimer = lifecycle.beginSession()
        precondition(lifecycle.isCurrent(completedTimer))
        precondition(lifecycle.completeSession() == completedTimer)
        precondition(lifecycle.completedSessionID == completedTimer)
        var islandIsVisible = true

        // Reusing the same duration or external timer ID must still create a
        // different run. Cleanup captured for completedTimer is now stale.
        let replacementTimer = lifecycle.beginSession()
        precondition(replacementTimer != completedTimer)
        precondition(!lifecycle.isCurrent(completedTimer))
        precondition(lifecycle.isCurrent(replacementTimer))
        precondition(lifecycle.completedSessionID == nil)

        // This is the guard used by delayed Island cleanup. The stale closure
        // must leave the replacement timer visible.
        if lifecycle.isCurrent(completedTimer) {
            islandIsVisible = false
        }
        precondition(islandIsVisible)

        lifecycle.endSession()
        precondition(!lifecycle.isCurrent(replacementTimer))
    }
}
