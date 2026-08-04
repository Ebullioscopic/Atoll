import XCTest
@testable import CodeIsland

/// #243 — CodeIsland must never SIGTERM launchd-managed daemons (e.g. the Hermes
/// gateway, KeepAlive=true). Only processes that were reparented to launchd AFTER
/// we attached (i.e. their terminal closed) count as orphans.
final class AppStateOrphanCleanupTests: XCTestCase {

    func testLaunchdManagedDaemonIsNeverAnOrphan() {
        // Hermes gateway: ppid was already 1 when the monitor attached.
        XCTAssertFalse(AppState.isReparentedOrphan(currentParentPid: 1, attachParentPid: 1))
    }

    func testTerminalOrphanIsDetected() {
        // Normal CLI: attached under a shell (ppid 812), later reparented to launchd.
        XCTAssertTrue(AppState.isReparentedOrphan(currentParentPid: 1, attachParentPid: 812))
    }

    func testProcessWithLiveParentIsNotAnOrphan() {
        XCTAssertFalse(AppState.isReparentedOrphan(currentParentPid: 812, attachParentPid: 812))
    }

    func testUnknownAttachParentStaysSafe() {
        // If we never learned the attach-time ppid, do not kill.
        XCTAssertFalse(AppState.isReparentedOrphan(currentParentPid: 1, attachParentPid: nil))
    }

    func testDeadProcessIsNotAnOrphan() {
        // proc_pidinfo failed (process already gone) — nothing to terminate.
        XCTAssertFalse(AppState.isReparentedOrphan(currentParentPid: nil, attachParentPid: 812))
    }

    func testParentPidOfCurrentProcessMatchesGetppid() {
        XCTAssertEqual(AppState.parentPid(of: getpid()), getppid())
    }

    func testParentPidOfDeadPidIsNil() {
        // PID 0 is the kernel; proc_pidinfo on -1 must fail cleanly.
        XCTAssertNil(AppState.parentPid(of: -1))
    }
}
