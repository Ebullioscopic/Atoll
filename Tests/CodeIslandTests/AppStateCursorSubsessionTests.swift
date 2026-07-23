import XCTest
@testable import CodeIsland
import CodeIslandCore

@MainActor
final class AppStateCursorSubsessionTests: XCTestCase {
    func testKnownCursorSubagentSessionMergesIntoParentFromTranscriptPath() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.providerSessionId = parentId
        parent.transcriptPath = transcriptPath

        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .running
        child.currentTool = "Read"
        child.transcriptPath = transcriptPath
        child.lastActivity = Date()

        appState.sessions[parentId] = parent
        appState.sessions[childId] = child

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertEqual(appState.sessions[parentId]?.subagents[childId]?.agentType, "cursor-subagent")
        XCTAssertEqual(appState.sessions[parentId]?.subagents[childId]?.currentTool, "Read")
        XCTAssertEqual(appState.activeSessionId, parentId)
    }

    func testSeparateModeSplitsMergedCursorSubagent() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("separate", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.currentTool = "Agent"
        parent.toolDescription = "cursor-subagent"
        parent.providerSessionId = parentId
        parent.transcriptPath = transcriptPath
        parent.cwd = "/tmp/project"
        parent.cliPid = 11_111
        parent.cliStartTime = Date(timeIntervalSince1970: 1_700_000_000)
        var subagent = SubagentState(agentId: childId, agentType: "cursor-subagent")
        subagent.status = .running
        subagent.currentTool = "Read"
        parent.subagents[childId] = subagent
        appState.sessions[parentId] = parent

        appState.applyCurrentPluginSessionMode(persist: false)

        XCTAssertTrue(appState.sessions[parentId]?.subagents.isEmpty == true)
        XCTAssertNil(appState.sessions[parentId]?.currentTool)
        XCTAssertEqual(appState.sessions[parentId]?.cliPid, 11_111)
        XCTAssertEqual(appState.sessions[childId]?.source, "cursor")
        XCTAssertEqual(appState.sessions[childId]?.providerSessionId, childId)
        XCTAssertEqual(appState.sessions[childId]?.currentTool, "Read")
        // Parent path kept for fold identity when switching back to merge.
        XCTAssertEqual(appState.sessions[childId]?.transcriptPath, transcriptPath)
        // Split cards must not inherit the parent IDE process identity.
        XCTAssertNil(appState.sessions[childId]?.cliPid)
        XCTAssertNil(appState.sessions[childId]?.cliStartTime)
        XCTAssertEqual(appState.activeSessionId, childId)
    }

    func testSeparateModeTailsOnlyDistinctChildTranscript() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("separate", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let parentTranscript = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"
        let childTranscript = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/subagents/\(childId).jsonl"

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.providerSessionId = parentId
        parent.transcriptPath = parentTranscript
        var subagent = SubagentState(agentId: childId, agentType: "cursor-subagent")
        subagent.status = .running
        parent.subagents[childId] = subagent
        appState.sessions[parentId] = parent

        var existingChild = SessionSnapshot()
        existingChild.source = "cursor"
        existingChild.transcriptPath = childTranscript
        appState.sessions[childId] = existingChild

        appState.applyCurrentPluginSessionMode(persist: false)

        XCTAssertEqual(appState.sessions[childId]?.transcriptPath, childTranscript)
        XCTAssertEqual(appState.sessions[parentId]?.transcriptPath, parentTranscript)
    }

    func testSeparateModeDoesNotFoldKnownCursorChildCards() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("separate", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .running
        child.transcriptPath = transcriptPath
        appState.sessions[childId] = child

        XCTAssertFalse(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNotNil(appState.sessions[childId])
        XCTAssertNil(appState.sessions[parentId])
    }

    func testHideModeRemovesCursorSubagentCard() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("hide", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var child = SessionSnapshot()
        child.source = "cursor"
        child.transcriptPath = transcriptPath
        appState.sessions[childId] = child

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertNil(appState.sessions[parentId])
    }

    func testHideModeClearsMergedCursorSubagentsOnParent() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("hide", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.currentTool = "Agent"
        parent.toolDescription = "cursor-subagent"
        parent.providerSessionId = parentId
        parent.subagents[childId] = SubagentState(agentId: childId, agentType: "cursor-subagent")
        appState.sessions[parentId] = parent

        appState.applyCurrentPluginSessionMode(persist: false)

        XCTAssertTrue(appState.sessions[parentId]?.subagents.isEmpty == true)
        XCTAssertNil(appState.sessions[parentId]?.currentTool)
        XCTAssertNil(appState.sessions[parentId]?.toolDescription)
        XCTAssertEqual(appState.sessions[parentId]?.status, .processing)
    }

    func testFoldDoesNotResurrectIdleStoppedCursorSubagent() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .processing
        parent.providerSessionId = parentId
        parent.transcriptPath = transcriptPath
        // Stop already removed this child from the parent.
        appState.sessions[parentId] = parent

        var staleChild = SessionSnapshot()
        staleChild.source = "cursor"
        staleChild.status = .idle
        staleChild.transcriptPath = transcriptPath
        appState.sessions[childId] = staleChild

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertTrue(appState.sessions[parentId]?.subagents.isEmpty == true)
        XCTAssertEqual(appState.sessions[parentId]?.status, .processing)
    }

    func testFoldDoesNotResurrectRunningChildAfterStopTombstone() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .processing
        parent.providerSessionId = parentId
        parent.transcriptPath = transcriptPath
        parent.closedSubagentIds = [childId]
        appState.sessions[parentId] = parent

        var staleChild = SessionSnapshot()
        staleChild.source = "cursor"
        staleChild.status = .running
        staleChild.currentTool = "Shell"
        staleChild.transcriptPath = transcriptPath
        appState.sessions[childId] = staleChild

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertTrue(appState.sessions[parentId]?.subagents.isEmpty == true)
        XCTAssertEqual(appState.sessions[parentId]?.closedSubagentIds, [childId])
        XCTAssertEqual(appState.sessions[parentId]?.status, .processing)
    }

    func testFoldHonorsClosedTombstoneOnChildCardWhenSwitchingToMerge() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.providerSessionId = parentId
        parent.transcriptPath = transcriptPath
        appState.sessions[parentId] = parent

        // Separate-mode Stop stored closedSubagentIds on the child card.
        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .running
        child.currentTool = "Shell"
        child.transcriptPath = transcriptPath
        child.closedSubagentIds = [childId]
        appState.sessions[childId] = child

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertTrue(appState.sessions[parentId]?.subagents.isEmpty == true)
        XCTAssertTrue(appState.sessions[parentId]?.closedSubagentIds.contains(childId) == true)
    }

    func testFoldFallbackUsesCardKeyWhenProviderSessionIdIsParent() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .running
        child.currentTool = "Shell"
        child.providerSessionId = parentId
        child.transcriptPath = transcriptPath
        child.lastActivity = Date()
        appState.sessions[childId] = child

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertNotNil(appState.sessions[parentId])
        XCTAssertEqual(appState.sessions[parentId]?.providerSessionId, parentId)
        XCTAssertEqual(appState.sessions[parentId]?.transcriptPath, transcriptPath)
        // Subagent key must be the child card id, not providerSessionId (parent).
        XCTAssertNil(appState.sessions[parentId]?.subagents[parentId])
        XCTAssertEqual(appState.sessions[parentId]?.subagents[childId]?.currentTool, "Shell")
    }

    func testSynthesizedParentKeepsTranscriptPathAfterChildFold() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .running
        child.transcriptPath = transcriptPath
        child.cwd = "/tmp/project"
        child.cliPid = 4242
        child.cliStartTime = Date(timeIntervalSince1970: 1_700_000_000)
        child.lastActivity = Date()
        appState.sessions[childId] = child

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertEqual(appState.sessions[parentId]?.transcriptPath, transcriptPath)
        XCTAssertEqual(appState.sessions[parentId]?.cwd, "/tmp/project")
        XCTAssertNil(appState.sessions[parentId]?.cliPid)
        XCTAssertNil(appState.sessions[parentId]?.cliStartTime)
        XCTAssertEqual(appState.sessions[parentId]?.subagents[childId]?.agentType, "cursor-subagent")
        XCTAssertEqual(appState.sessions[parentId]?.subagents[childId]?.status, .running)
    }

    func testMergeDropsIdleChildWithoutInventingTombstoneParent() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .idle
        child.transcriptPath = transcriptPath
        appState.sessions[childId] = child

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        // Plain idle (AfterAgentResponse) must not synthesize a ghost parent / tombstone.
        XCTAssertNil(appState.sessions[parentId])
    }

    func testStoppedChildWithoutParentKeepsClosedIdsOnSynthesizedParent() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .running
        child.transcriptPath = transcriptPath
        child.closedSubagentIds = [childId]
        appState.sessions[childId] = child

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertNotNil(appState.sessions[parentId])
        XCTAssertTrue(appState.sessions[parentId]?.subagents.isEmpty == true)
        XCTAssertEqual(appState.sessions[parentId]?.closedSubagentIds, [childId])
        XCTAssertEqual(appState.sessions[parentId]?.transcriptPath, transcriptPath)
        XCTAssertNil(appState.sessions[parentId]?.cliPid)
        XCTAssertEqual(appState.sessions[parentId]?.status, .idle)
    }

    func testMergeDropsIdleChildEvenWhenProcessIsStillLive() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.providerSessionId = parentId
        parent.transcriptPath = transcriptPath
        appState.sessions[parentId] = parent

        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .idle
        child.transcriptPath = transcriptPath
        // Shared Cursor IDE `_ppid` is still live — must not revive a finished idle Task.
        child.cliPid = getpid()
        appState.sessions[childId] = child

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertTrue(appState.sessions[parentId]?.subagents.isEmpty == true)
        XCTAssertTrue(appState.sessions[parentId]?.closedSubagentIds.isEmpty == true)
        XCTAssertEqual(appState.sessions[parentId]?.status, .running)
    }

    func testMergeIdleChildWithOwnTombstonePromotesOntoParent() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .idle
        child.transcriptPath = transcriptPath
        child.closedSubagentIds = [childId]
        appState.sessions[childId] = child

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertNotNil(appState.sessions[parentId])
        XCTAssertTrue(appState.sessions[parentId]?.subagents.isEmpty == true)
        XCTAssertEqual(appState.sessions[parentId]?.closedSubagentIds, [childId])
        XCTAssertEqual(appState.sessions[parentId]?.status, .idle)
        XCTAssertEqual(appState.sessions[parentId]?.transcriptPath, transcriptPath)
    }

    func testMergeDoesNotResurrectIdleLiveChildAfterSeparateStop() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.providerSessionId = parentId
        parent.transcriptPath = transcriptPath
        appState.sessions[parentId] = parent

        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .idle
        child.transcriptPath = transcriptPath
        // Separate-mode Stop self-tombstone + live IDE `_ppid` must not revive as running.
        child.closedSubagentIds = [childId]
        child.cliPid = getpid()
        appState.sessions[childId] = child

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertTrue(appState.sessions[parentId]?.subagents.isEmpty == true)
        XCTAssertEqual(appState.sessions[parentId]?.closedSubagentIds, [childId])
    }

    func testShouldKeepRestoredIdleCursorSessionWithTombstone() {
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        XCTAssertTrue(
            AppState.shouldKeepRestoredIdleCursorSession(
                source: "cursor",
                sessionId: childId,
                providerSessionId: nil,
                transcriptPath: nil,
                closedSubagentIds: [childId]
            )
        )
        XCTAssertFalse(
            AppState.shouldKeepRestoredIdleCursorSession(
                source: "cursor",
                sessionId: childId,
                providerSessionId: nil,
                transcriptPath: nil,
                closedSubagentIds: []
            )
        )
        XCTAssertFalse(
            AppState.shouldKeepRestoredIdleCursorSession(
                source: "claude",
                sessionId: childId,
                providerSessionId: nil,
                transcriptPath: nil,
                closedSubagentIds: [childId]
            )
        )
    }

    func testShouldKeepRestoredIdleCursorSessionWithFoldableTranscript() {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"
        // Foldable path alone is not enough — requires a Stop tombstone.
        XCTAssertFalse(
            AppState.shouldKeepRestoredIdleCursorSession(
                source: "cursor",
                sessionId: childId,
                providerSessionId: nil,
                transcriptPath: transcriptPath,
                closedSubagentIds: []
            )
        )
        XCTAssertTrue(
            AppState.shouldKeepRestoredIdleCursorSession(
                source: "cursor",
                sessionId: childId,
                providerSessionId: nil,
                transcriptPath: transcriptPath,
                closedSubagentIds: [childId]
            )
        )
    }

    func testClosedSubagentPermissionRequestIsDeniedWithoutQueueing() async throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .processing
        parent.closedSubagentIds = [childId]
        appState.sessions[parentId] = parent

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "tool_name": "Bash",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))

        let response = await withCheckedContinuation { continuation in
            appState.handlePermissionRequest(event, continuation: continuation)
        }

        XCTAssertTrue(appState.permissionQueue.isEmpty)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
        let hook = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(hook["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "deny")
        XCTAssertEqual(appState.sessions[parentId]?.status, .processing)
    }

    func testClosedSubagentQuestionIsDroppedWithoutQueueing() async throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .processing
        parent.closedSubagentIds = [childId]
        appState.sessions[parentId] = parent

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Notification",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "question": "Still asking after stop?",
            "options": ["Yes", "No"],
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))

        let response = await withCheckedContinuation { continuation in
            appState.handleQuestion(event, continuation: continuation)
        }

        XCTAssertTrue(appState.questionQueue.isEmpty)
        XCTAssertEqual(response, Data("{}".utf8))
        XCTAssertEqual(appState.sessions[parentId]?.status, .processing)
    }

    func testClosedSubagentAskUserQuestionIsDeniedWithoutQueueing() async throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .processing
        parent.closedSubagentIds = [childId]
        appState.sessions[parentId] = parent

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [
                    ["question": "Continue?", "options": [["label": "Yes"], ["label": "No"]]]
                ]
            ],
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))

        let response = await withCheckedContinuation { continuation in
            appState.handleAskUserQuestion(event, continuation: continuation)
        }

        XCTAssertTrue(appState.questionQueue.isEmpty)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
        let hook = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(hook["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "deny")
        XCTAssertEqual(appState.sessions[parentId]?.status, .processing)
    }

    func testMergedPermissionMarksSubagentWaitingApproval() async throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        appState.sessions[parentId] = parent

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "tool_name": "Bash",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }

        await Task.yield()
        XCTAssertEqual(appState.permissionQueue.count, 1)
        XCTAssertEqual(appState.sessions[parentId]?.status, .waitingApproval)
        XCTAssertEqual(appState.sessions[parentId]?.subagents[childId]?.status, .waitingApproval)

        appState.handleBuddyControlCommand(.denyCurrentPermission)
        let response = await responseTask.value

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
        let hook = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(hook["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "deny")
        XCTAssertTrue(appState.permissionQueue.isEmpty)
        // Denying a folded Task must not idle the parent chat.
        XCTAssertEqual(appState.sessions[parentId]?.status, .running)
        XCTAssertEqual(appState.sessions[parentId]?.subagents[childId]?.status, .processing)
        XCTAssertEqual(appState.sessions[parentId]?.currentTool, "Agent")
    }

    func testMergeDoesNotOverwriteLiveSubagentWithIdleOrphan() {
        let previousMode = UserDefaults.standard.object(forKey: SettingsKey.pluginSessionMode)
        UserDefaults.standard.set("merge", forKey: SettingsKey.pluginSessionMode)
        defer {
            if let previousMode {
                UserDefaults.standard.set(previousMode, forKey: SettingsKey.pluginSessionMode)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsKey.pluginSessionMode)
            }
        }

        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let transcriptPath = "/Users/u/.cursor/projects/x/agent-transcripts/\(parentId)/\(parentId).jsonl"

        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        parent.providerSessionId = parentId
        parent.transcriptPath = transcriptPath
        var live = SubagentState(agentId: childId, agentType: "cursor-subagent")
        live.status = .running
        live.currentTool = "Read"
        parent.subagents[childId] = live
        appState.sessions[parentId] = parent

        var orphan = SessionSnapshot()
        orphan.source = "cursor"
        orphan.status = .idle
        orphan.transcriptPath = transcriptPath
        appState.sessions[childId] = orphan

        XCTAssertTrue(appState.applyCursorSubsessionModeToKnownSessions())
        XCTAssertNil(appState.sessions[childId])
        XCTAssertEqual(appState.sessions[parentId]?.subagents[childId]?.status, .running)
        XCTAssertEqual(appState.sessions[parentId]?.subagents[childId]?.currentTool, "Read")
    }

    func testDenyPermissionWithAgentIdButMissingSubagentDoesNotIdleParent() async throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        appState.sessions[parentId] = parent

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "tool_name": "Bash",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handlePermissionRequest(event, continuation: continuation)
            }
        }
        await Task.yield()
        XCTAssertEqual(appState.permissionQueue.count, 1)

        // Simulate Stop removing the Task between enqueue and deny.
        appState.sessions[parentId]?.subagents.removeValue(forKey: childId)
        appState.sessions[parentId]?.closedSubagentIds.insert(childId)

        appState.handleBuddyControlCommand(.denyCurrentPermission)
        _ = await responseTask.value

        XCTAssertTrue(appState.permissionQueue.isEmpty)
        XCTAssertNotEqual(appState.sessions[parentId]?.status, .idle)
        XCTAssertEqual(appState.sessions[parentId]?.status, .processing)
    }

    func testAnswerFoldedQuestionClearsSubagentWaitingQuestion() async throws {
        let parentId = "e1247fd5-d9a0-48ef-8457-0304606b1833"
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let appState = AppState()
        var parent = SessionSnapshot()
        parent.source = "cursor"
        parent.status = .running
        appState.sessions[parentId] = parent

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "Notification",
            "session_id": parentId,
            "_source": "cursor",
            "agent_id": childId,
            "question": "Ship it?",
            "options": ["Yes", "No"],
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))

        let responseTask = Task<Data, Never> {
            await withCheckedContinuation { continuation in
                appState.handleQuestion(event, continuation: continuation)
            }
        }
        await Task.yield()
        XCTAssertEqual(appState.sessions[parentId]?.subagents[childId]?.status, .waitingQuestion)

        appState.answerQuestion("Yes")
        _ = await responseTask.value

        XCTAssertTrue(appState.questionQueue.isEmpty)
        XCTAssertEqual(appState.sessions[parentId]?.subagents[childId]?.status, .running)
        XCTAssertEqual(appState.sessions[parentId]?.status, .running)
        XCTAssertEqual(appState.sessions[parentId]?.currentTool, "Agent")
    }

    func testSeparateSelfTombstoneDeniesPermissionWithoutAgentId() async throws {
        let childId = "2528cb91-6379-48f2-aff8-40f4b804dafa"
        let appState = AppState()
        var child = SessionSnapshot()
        child.source = "cursor"
        child.status = .idle
        child.closedSubagentIds = [childId]
        appState.sessions[childId] = child

        let data = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest",
            "session_id": childId,
            "_source": "cursor",
            "tool_name": "Bash",
        ] as [String: Any])
        let event = try XCTUnwrap(HookEvent(from: data))

        let response = await withCheckedContinuation { continuation in
            appState.handlePermissionRequest(event, continuation: continuation)
        }

        XCTAssertTrue(appState.permissionQueue.isEmpty)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
        let hook = try XCTUnwrap(json["hookSpecificOutput"] as? [String: Any])
        let decision = try XCTUnwrap(hook["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "deny")
    }
}
