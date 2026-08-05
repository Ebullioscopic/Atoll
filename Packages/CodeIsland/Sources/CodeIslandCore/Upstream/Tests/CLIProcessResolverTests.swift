import XCTest
@testable import CodeIslandCore

final class CLIProcessResolverTests: XCTestCase {

    // MARK: - resolvedSessionPID

    /// #148 core repro: Cursor IDE spawns N sub-agent processes, each runs
    /// its own hook subprocess with a different immediate ppid. All those
    /// sub-agents share the same root Cursor binary in their ancestry, so
    /// `resolvedSessionPID` must collapse them onto the same PID.
    func testParallelSubAgentsCollapseToRootSourcePID() {
        // Sub-agent #1 ancestry: hook → sub-agent A (12345) → cursor-agent main (5000)
        let subA: [(pid: Int32, executablePath: String?)] = [
            (12345, "/Users/u/.cursor/agent/sub-agent"),
            (5000, "/Users/u/.local/share/cursor-agent/versions/1.0/cursor-agent"),
        ]
        // Sub-agent #2 ancestry: hook → sub-agent B (67890) → cursor-agent main (5000)
        let subB: [(pid: Int32, executablePath: String?)] = [
            (67890, "/Users/u/.cursor/agent/sub-agent"),
            (5000, "/Users/u/.local/share/cursor-agent/versions/1.0/cursor-agent"),
        ]

        let pidA = CLIProcessResolver.resolvedSessionPID(
            immediateParentPID: 12345, source: "cursor-cli", ancestry: subA
        )
        let pidB = CLIProcessResolver.resolvedSessionPID(
            immediateParentPID: 67890, source: "cursor-cli", ancestry: subB
        )

        XCTAssertEqual(pidA, 5000)
        XCTAssertEqual(pidB, 5000, "Different sub-agent ppids must resolve to the same root cursor-agent PID for session grouping (#148)")
    }

    /// When multiple binaries of the same source appear in the ancestry,
    /// pick the *root-most* (last) one. Distinguishes resolvedSessionPID
    /// from resolvedTrackedPID, which picks the nearest (first).
    func testResolvedSessionPIDPicksRootMostMatch() {
        let ancestry: [(pid: Int32, executablePath: String?)] = [
            (1001, "/Users/u/.local/share/cursor-agent/versions/1.0/cursor-agent"),  // nearest
            (2002, "/Users/u/.local/share/cursor-agent/versions/1.0/cursor-agent"),  // intermediate
            (3003, "/Users/u/.local/share/cursor-agent/versions/1.0/cursor-agent"),  // root-most
        ]
        let session = CLIProcessResolver.resolvedSessionPID(
            immediateParentPID: 1001, source: "cursor-cli", ancestry: ancestry
        )
        let tracked = CLIProcessResolver.resolvedTrackedPID(
            immediateParentPID: 1001, source: "cursor-cli", ancestry: ancestry
        )
        XCTAssertEqual(session, 3003, "session pid is the root-most matching binary")
        XCTAssertEqual(tracked, 1001, "tracked pid stays the nearest matching binary")
    }

    /// No binary in the ancestry matches the declared source — fall back
    /// to the immediate ppid (preserves prior behavior for everything but
    /// sub-agent CLIs).
    func testResolvedSessionPIDFallsBackToImmediateParentWhenNoMatch() {
        let ancestry: [(pid: Int32, executablePath: String?)] = [
            (12345, "/bin/sh"),
            (5000, "/usr/bin/login"),
        ]
        let pid = CLIProcessResolver.resolvedSessionPID(
            immediateParentPID: 12345, source: "cursor-cli", ancestry: ancestry
        )
        XCTAssertEqual(pid, 12345)
    }

    /// Empty ancestry (e.g. proc lookup failed) — fall back to immediate ppid.
    func testResolvedSessionPIDFallsBackOnEmptyAncestry() {
        let pid = CLIProcessResolver.resolvedSessionPID(
            immediateParentPID: 12345, source: "cursor-cli", ancestry: []
        )
        XCTAssertEqual(pid, 12345)
    }

    /// nil source — nothing to match against, so return immediate ppid.
    func testResolvedSessionPIDFallsBackOnNilSource() {
        let ancestry: [(pid: Int32, executablePath: String?)] = [
            (12345, "/Users/u/.local/share/cursor-agent/versions/1.0/cursor-agent"),
        ]
        let pid = CLIProcessResolver.resolvedSessionPID(
            immediateParentPID: 12345, source: nil, ancestry: ancestry
        )
        XCTAssertEqual(pid, 12345)
    }

    // MARK: - inferSource (#220 / #95)

    /// #220: Claude Code launched inside Cursor's integrated terminal fires the
    /// source-less Claude hook. The real `claude` process is a Node binary (its
    /// path does NOT end in `/claude`), while Cursor's GUI host/helper processes
    /// carry `/cursor` in their path. inferSource must NOT greedily attribute the
    /// session to the desktop `cursor` source — it should return nil so the
    /// bridge falls back to the default "claude".
    func testInferSourceIgnoresCursorIDEHostForSourcelessClaude() {
        let ancestry: [(pid: Int32, executablePath: String?)] = [
            // `claude` is really a Node script; argv0 is node, not .../claude.
            (4321, "/opt/homebrew/bin/node"),
            (4000, "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper"),
            (3000, "/Applications/Cursor.app/Contents/MacOS/Cursor"),
        ]
        XCTAssertNil(
            CLIProcessResolver.inferSource(ancestry: ancestry),
            "Cursor's GUI host must not be inferred as the `cursor` source (#220)"
        )
    }

    /// #95 guard: the omo/OpenCode plugin fires the source-less Claude hook from
    /// inside OpenCode. The real `opencode` binary IS in the ancestry, so
    /// inferSource must still recover "opencode" (the original reason this
    /// inference exists). The #220 fix must not regress this.
    func testInferSourceStillRecoversOpenCodeFromAncestry() {
        let ancestry: [(pid: Int32, executablePath: String?)] = [
            (1234, "/bin/sh"),
            (5678, "/Users/u/.opencode/bin/opencode"),
        ]
        XCTAssertEqual(
            CLIProcessResolver.inferSource(ancestry: ancestry),
            "opencode",
            "Source-less Claude hooks fired from inside OpenCode must still resolve to opencode (#95)"
        )
    }

    /// Cursor's CLI agent (`cursor-agent`) is a real CLI and must still be
    /// recovered as `cursor-cli` — only the desktop IDE *host* is excluded.
    func testInferSourceStillRecoversCursorCliAgent() {
        let ancestry: [(pid: Int32, executablePath: String?)] = [
            (5000, "/Users/u/.local/share/cursor-agent/versions/1.0/cursor-agent"),
        ]
        XCTAssertEqual(
            CLIProcessResolver.inferSource(ancestry: ancestry),
            "cursor-cli"
        )
    }

    // MARK: - resolvedSessionPID

    /// Defensive: invalid (<= 0) immediate ppid is returned unchanged so
    /// callers can still encode it without contortion.
    func testResolvedSessionPIDReturnsImmediateParentWhenZeroOrNegative() {
        let ancestry: [(pid: Int32, executablePath: String?)] = [
            (5000, "/Users/u/.local/share/cursor-agent/versions/1.0/cursor-agent"),
        ]
        XCTAssertEqual(
            CLIProcessResolver.resolvedSessionPID(immediateParentPID: 0, source: "cursor-cli", ancestry: ancestry),
            0
        )
        XCTAssertEqual(
            CLIProcessResolver.resolvedSessionPID(immediateParentPID: -1, source: "cursor-cli", ancestry: ancestry),
            -1
        )
    }
}
