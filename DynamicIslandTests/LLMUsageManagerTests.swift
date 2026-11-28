import Combine
import XCTest
@testable import Atoll

final class LLMUsageManagerTests: XCTestCase {
    @MainActor
    func testForcedRefreshDuringActiveRequestIsCoalescedAndUsesNewConnection() async throws {
        let firstStarted = expectation(description: "First connection requested")
        let secondStarted = expectation(description: "Saved connection requested")
        let finished = expectation(description: "Queued refresh completed")
        let source = SuspendedUsageSource { call in
            if call == 1 { firstStarted.fulfill() }
            if call == 2 { secondStarted.fulfill() }
        }
        let manager = LLMUsageManager(providers: [SuspendedUsageProvider(source: source)])
        manager.refreshAll()
        await fulfillment(of: [firstStarted], timeout: 2)
        await source.setConnection("saved")
        manager.refreshAll(force: true)
        manager.refreshAll(force: true)
        manager.refreshAll() // An ordinary request must not clear the pending forced one.
        let beforeRelease = await source.state()
        XCTAssertEqual(beforeRelease.calls, 1, "Refreshes must stay serialized")
        await source.release(1)
        await fulfillment(of: [secondStarted], timeout: 2)
        XCTAssertTrue(manager.isRefreshing)
        let observation = manager.$isRefreshing.dropFirst().filter { !$0 }.first().sink { _ in finished.fulfill() }
        await source.release(2)
        await fulfillment(of: [finished], timeout: 2)
        withExtendedLifetime(observation) {}
        let final = await source.state()
        XCTAssertEqual(final.calls, 2, "Repeated forced requests coalesce into one follow-up")
        XCTAssertEqual(final.maximumActive, 1)
        guard case .success(let snapshot) = manager.results[.copilot] else {
            return XCTFail("Expected quota for the saved connection")
        }
        XCTAssertEqual(snapshot.plan, "saved")
        manager.refreshAll()
        XCTAssertFalse(manager.isRefreshing, "Ordinary refreshes still respect the throttle")
    }
}

private struct SuspendedUsageProvider: UsageProvider {
    let id = ProviderID.copilot
    let source: SuspendedUsageSource

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        await source.fetch(now: now)
    }
}

private actor SuspendedUsageSource {
    private var connection = "original"
    private var calls = 0
    private var active = 0
    private var maximumActive = 0
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    private let started: (Int) -> Void

    init(started: @escaping (Int) -> Void) { self.started = started }

    func setConnection(_ value: String) { connection = value }
    func state() -> (calls: Int, maximumActive: Int) { (calls, maximumActive) }
    func release(_ call: Int) { pending.removeValue(forKey: call)?.resume() }

    func fetch(now: Date) async -> UsageSnapshot {
        calls += 1
        let call = calls
        let requestedConnection = connection
        active += 1
        maximumActive = max(maximumActive, active)
        await withCheckedContinuation { continuation in
            pending[call] = continuation
            started(call)
        }
        active -= 1
        return UsageSnapshot(plan: requestedConnection, lastUpdated: now)
    }
}
