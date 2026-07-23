import XCTest
@testable import CodeIsland

/// Regression: async XCTest / background ARC must be able to release AppState
/// without trapping in deinit (previous MainActor.assumeIsolated path), including
/// when session discovery's FSEventStream was started.
final class AppStateDeinitTests: XCTestCase {
    func testDeinitOffMainActorAfterDiscoveryDoesNotTrap() async {
        final class Holder: @unchecked Sendable {
            var state: AppState?
        }
        let holder = Holder()
        await MainActor.run {
            let state = AppState()
            state.startSessionDiscovery()
            holder.state = state
        }

        await Task.detached {
            holder.state = nil
        }.value

        // Give the main-queue box drain a turn so teardown completes cleanly.
        await MainActor.run { }
    }
}
