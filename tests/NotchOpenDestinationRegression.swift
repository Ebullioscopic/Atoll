import Foundation

@main
struct NotchOpenDestinationRegression {
    static func main() {
        precondition(NotchOpenDestination.selected("", rememberLast: false) == .automatic)
        precondition(NotchOpenDestination.selected("", rememberLast: true) == .lastUsed)
        precondition(NotchOpenDestination.selected("future-value", rememberLast: true) == .automatic)
        precondition(NotchOpenDestination.selected("stats", rememberLast: false) == .stats)
        let availability = StandardNotchTabAvailability(home: true, shelf: true, timer: false, stats: true, llmUsage: false, notes: true, terminal: false)
        precondition(availability.available == [.home, .shelf, .stats, .notes])
        precondition(NotchOpenDestination.stats.resolved(available: availability.available) == .stats)
        precondition(NotchOpenDestination.terminal.resolved(available: availability.available) == .home)
        precondition(NotchOpenDestination.terminal.resolved(available: [.shelf, .stats]) == .shelf)
        precondition(NotchOpenDestination.terminal.resolved(available: []) == nil)
        precondition(NotchOpenDestination.automatic.resolved(available: [.stats]) == nil)
        precondition(NotchOpenDestination.lastUsed.resolved(available: [.stats]) == nil)
        print("Notch destination regression checks passed")
    }
}
