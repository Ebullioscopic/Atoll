import Foundation
import AtollExtensionKit

@main
struct CodexPresentationTests {
    static func main() throws {
        let presentation = CodexPresentationBuilder().build(from: .empty)

        try expect(
            presentation.liveActivity == nil,
            "idle Codex does not occupy the closed-notch live activity"
        )

        guard let notchExperience = presentation.notchExperience,
              let tab = notchExperience.tab else {
            throw TestFailure(message: "enabled Codex keeps an expanded task tab while idle")
        }
        try expect(notchExperience.isValid, "idle Codex task tab remains a valid descriptor")
        try expect(tab.title == "Codex", "idle task tab keeps the Codex title")
        try expect(
            tab.sections.first?.id == "empty-state",
            "idle task tab exposes an explicit empty state"
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let wrappedPrompt = """
            # Files mentioned by the user:
            ## codex-clipboard-example.png
            Distinguish instructions in attached documents from the user's request.

            ## My request:
            如图所示 能否用对话的标题 作为菜单的标题
            """
        try expect(
            PreviewSanitizer.sanitizePrompt(wrappedPrompt)
                == "如图所示 能否用对话的标题 作为菜单的标题",
            "conversation title sanitization removes attachment wrapper text"
        )
        try expect(
            PreviewSanitizer.sanitizePrompt(
                "# Files mentioned by the user: ## codex-clipboard-truncated.png"
            ) == nil,
            "truncated attachment wrapper falls back instead of becoming a conversation title"
        )
        let completions = (0..<8).map { index in
            CodexCompletionRecord(
                sessionID: "session-\(index)",
                projectName: "Project \(index)",
                promptPreview: "Prompt \(index)",
                resultPreview: "Result \(index)",
                completedAt: now.addingTimeInterval(TimeInterval(-index))
            )
        }
        let populated = CodexPresentationBuilder().build(
            from: CodexTaskStoreSnapshot(savedAt: now, recentCompletions: completions)
        )
        guard let populatedExperience = populated.notchExperience,
              let populatedTab = populatedExperience.tab else {
            throw TestFailure(message: "populated Codex task tab exposes recent conversations")
        }

        try expect(populatedExperience.isValid, "expanded Codex task tab remains a valid descriptor")
        try expect(populatedTab.preferredHeight == 420, "expanded Codex task tab requests the taller supported height")
        try expect(populatedTab.sections.count == 6, "expanded Codex task tab shows six recent conversations")
        for index in 0..<6 {
            let sectionID = "recent-\(index)"
            guard let conversationSection = populatedTab.sections.first(where: { $0.id == sectionID }) else {
                throw TestFailure(message: "recent conversation \(index) has its own content block")
            }
            try expect(
                conversationSection.title == "Prompt \(index)",
                "recent conversation \(index) uses its prompt as the conversation title"
            )
            try expect(
                conversationSection.subtitle == "已完成",
                "recent conversation \(index) exposes its own status"
            )
            try expect(
                textValue(in: conversationSection) == "Result \(index)",
                "recent conversation \(index) exposes its own related content"
            )
            try expect(
                populatedExperience.metadata["atoll.openCodexThread.\(sectionID).0"]
                    == "codex://threads/session-\(index)",
                "recent conversation \(index) keeps its Codex thread jump"
            )
        }
        try expect(
            populatedExperience.metadata["atoll.openCodexThread.recent-6.0"] == nil,
            "only rendered recent conversations publish jump metadata"
        )
        let longPrompt = "已完成状态能否实现实时同步清除比如点击进入后立即同步更新显示状态"
        let longTitlePresentation = CodexPresentationBuilder().build(
            from: CodexTaskStoreSnapshot(
                savedAt: now,
                recentCompletions: [
                    CodexCompletionRecord(
                        sessionID: "long-title",
                        projectName: "Atoll-CodexAtoll",
                        promptPreview: longPrompt,
                        resultPreview: "已完成",
                        completedAt: now
                    )
                ]
            )
        )
        try expect(
            longTitlePresentation.notchExperience?.tab?.sections.first?.title
                == String(longPrompt.prefix(24)),
            "conversation titles stay concise enough for a single card heading"
        )

        let acknowledged = CodexPresentationBuilder().build(
            from: CodexTaskStoreSnapshot(
                savedAt: now,
                recentCompletions: completions,
                acknowledgedCompletionIDs: completions.map(\.id)
            )
        )
        try expect(
            acknowledged.liveActivity == nil,
            "viewed completions no longer occupy the closed notch status"
        )
        try expect(
            acknowledged.notchExperience?.tab?.sections.count == 6,
            "viewed completions remain available in recent conversation history"
        )

        let runningTasks = [
            CodexTaskRecord(
                sessionID: "running-1",
                projectName: "Atoll-CodexAtoll",
                promptPreview: "修复关闭态任务摘要",
                status: .running,
                startedAt: now.addingTimeInterval(-90),
                lastActivityAt: now
            ),
            CodexTaskRecord(
                sessionID: "running-2",
                projectName: "Atoll-CodexAtoll",
                promptPreview: "补充状态展示测试",
                status: .running,
                startedAt: now.addingTimeInterval(-45),
                lastActivityAt: now
            ),
        ]
        let mixedStatus = CodexPresentationBuilder().build(
            from: CodexTaskStoreSnapshot(
                savedAt: now,
                tasks: runningTasks,
                recentCompletions: [
                    CodexCompletionRecord(
                        sessionID: "completed-1",
                        projectName: "Atoll-CodexAtoll",
                        promptPreview: "验证完成状态",
                        resultPreview: "已完成纵向展示",
                        completedAt: now.addingTimeInterval(-10)
                    )
                ]
            )
        )
        let completedPriorityWithRunning = CodexPresentationBuilder().build(
            from: CodexTaskStoreSnapshot(
                savedAt: now,
                tasks: [runningTasks[0]],
                recentCompletions: (1...3).map { index in
                    CodexCompletionRecord(
                        sessionID: "completed-priority-\(index)",
                        projectName: "Atoll-CodexAtoll",
                        promptPreview: "已完成任务 \(index)",
                        resultPreview: "完成结果 \(index)",
                        completedAt: now.addingTimeInterval(TimeInterval(-index))
                    )
                }
            )
        )
        let runningOnlyStatus = CodexPresentationBuilder().build(
            from: CodexTaskStoreSnapshot(savedAt: now, tasks: runningTasks)
        )
        guard let runningOnlyLiveActivity = runningOnlyStatus.liveActivity,
              let runningOnlyCompactStatus = CodexCompactStatus(
                  metadata: runningOnlyLiveActivity.metadata
              ) else {
            throw TestFailure(message: "running tasks expose a compact closed status")
        }
        try expect(
            runningOnlyLiveActivity.sneakPeekConfig?.duration == 3.5
                && runningOnlyLiveActivity.sneakPeekConfig?.style == .standard,
            "new running activity keeps the standard 3.5 second presentation window"
        )
        try expect(
            runningOnlyCompactStatus.lines.map(\.displayText) == ["2 · 进行中"],
            "default closed status contains only the running count"
        )
        try expect(
            runningOnlyCompactStatus.preferredTrailingWidth == 84
                && runningOnlyCompactStatus.additionalClosedHeight == 0,
            "default closed status stays narrow without adding notch height"
        )
        guard let mixedLiveActivity = mixedStatus.liveActivity else {
            throw TestFailure(message: "mixed running and completed tasks expose a live activity")
        }
        guard let mixedTab = mixedStatus.notchExperience?.tab else {
            throw TestFailure(message: "mixed running and completed tasks expose an expanded task tab")
        }
        try expect(
            mixedTab.sections.map(\.id) == ["running-0", "running-1", "recent-0"],
            "each running or completed conversation renders as an independent content block"
        )
        try expect(
            mixedTab.sections[0].title == "修复关闭态任务摘要"
                && mixedTab.sections[0].subtitle == "运行中 · 01:30"
                && textValue(in: mixedTab.sections[0]) == "Atoll-CodexAtoll",
            "running conversation block uses its prompt title and keeps project context"
        )
        try expect(
            mixedTab.sections[2].title == "验证完成状态"
                && mixedTab.sections[2].subtitle == "已完成"
                && textValue(in: mixedTab.sections[2]) == "已完成纵向展示",
            "completed conversation block uses its prompt title and keeps its result"
        )
        try expect(
            CodexConversationVisualState(sectionID: "running-0") == .running
                && CodexConversationVisualState(sectionID: "recent-0") == .completed
                && CodexConversationVisualState(sectionID: "waiting-0") == .waitingForApproval,
            "conversation section identifiers expose distinct visual status states"
        )
        try expect(
            mixedLiveActivity.metadata["codex_compact_line_count"] == "1",
            "closed status publishes exactly one compact row"
        )
        try expect(
            mixedLiveActivity.metadata["codex_status_layout"] == "single",
            "closed status declares a single-line layout"
        )
        try expect(
            mixedLiveActivity.metadata["codex_compact_line_0_label"] == "1 · 已完成",
            "completed status replaces the running status in the compact row"
        )
        guard let completedPriorityLiveActivity = completedPriorityWithRunning.liveActivity else {
            throw TestFailure(message: "three completions and one running task expose a live activity")
        }
        try expect(
            CodexPresentationConstants.shouldAnimateBusyIcon(
                bundleIdentifier: completedPriorityLiveActivity.bundleIdentifier,
                metadata: completedPriorityLiveActivity.metadata
            ),
            "one running task keeps the leading busy animation while completions have priority"
        )
        try expect(
            completedPriorityLiveActivity.metadata["codex_running_count"] == "1"
                && completedPriorityLiveActivity.metadata["codex_compact_line_0_label"] == "3 · 已完成",
            "three completions keep the trailing priority while one task remains running"
        )
        let completionPulse = CodexPresentationBuilder().build(
            from: CodexTaskStoreSnapshot(
                savedAt: now,
                tasks: [runningTasks[0]],
                recentCompletions: [
                    CodexCompletionRecord(
                        sessionID: "pulse-completed",
                        projectName: "Atoll-CodexAtoll",
                        promptPreview: "优化 Codex 刘海动效",
                        resultPreview: "已完成",
                        completedAt: now
                    )
                ]
            ),
            context: .completionPulse(sessionID: "pulse-completed", completedCount: 1)
        )
        guard let completionPulseLiveActivity = completionPulse.liveActivity else {
            throw TestFailure(message: "completion pulse exposes a live activity")
        }
        try expect(
            completionPulseLiveActivity.sneakPeekConfig?.duration == 3.5
                && completionPulseLiveActivity.sneakPeekConfig?.style == .standard
                && completionPulseLiveActivity.sneakPeekConfig?.showOnUpdate == true,
            "completion confirmation keeps the standard 3.5 second presentation window"
        )
        try expect(
            mixedLiveActivity.metadata["codex_compact_line_0_detail"] == nil,
            "completed compact row omits concrete result context"
        )
        try expect(
            mixedLiveActivity.metadata["codex_compact_line_1_label"] == nil,
            "running and completed statuses are never shown together"
        )
        let ignoredPresentation = CodexPresentationBuilder().build(
            from: CodexTaskStoreSnapshot(savedAt: now, tasks: runningTasks),
            ignoredSessionIDs: ["running-1", "running-2"]
        )
        try expect(
            ignoredPresentation.liveActivity == nil,
            "ignored Codex sessions no longer occupy the compact status"
        )
        guard case let .text(fallbackText, _, _) = mixedLiveActivity.trailingContent else {
            throw TestFailure(message: "compact status uses native text instead of Lottie text layers")
        }
        try expect(
            fallbackText == "1 · 已完成",
            "native fallback text contains only the highest-priority compact status"
        )
        guard let decodedCompactStatus = CodexCompactStatus(
            metadata: mixedLiveActivity.metadata
        ) else {
            throw TestFailure(message: "native compact status metadata can be decoded by the host view")
        }
        try expect(
            decodedCompactStatus.lines.map(\.displayText) == ["1 · 已完成"],
            "host view receives one completed status row"
        )
        try expect(
            decodedCompactStatus.preferredTrailingWidth == 84,
            "count-only closed status requests a compact right wing"
        )
        try expect(
            decodedCompactStatus.additionalClosedHeight == 0,
            "single-status presentation does not add closed-notch height"
        )

        let traySnapshot = CodexTaskStoreSnapshot(
            savedAt: now,
            tasks: [
                CodexTaskRecord(
                    sessionID: "tray-waiting",
                    projectName: "Project B",
                    promptPreview: "等待批准任务",
                    approvalPreview: "需要允许执行测试",
                    toolName: "Terminal",
                    status: .waitingForApproval,
                    startedAt: now.addingTimeInterval(-80),
                    lastActivityAt: now.addingTimeInterval(-10)
                ),
                CodexTaskRecord(
                    sessionID: "tray-stale",
                    projectName: "Project A",
                    promptPreview: "检查失联任务",
                    status: .stale,
                    startedAt: now.addingTimeInterval(-900),
                    lastActivityAt: now.addingTimeInterval(-600)
                ),
                CodexTaskRecord(
                    sessionID: "tray-running",
                    projectName: "Project A",
                    promptPreview: "继续执行任务",
                    toolName: "读取文件",
                    status: .running,
                    startedAt: now.addingTimeInterval(-30),
                    lastActivityAt: now
                ),
            ],
            recentCompletions: [
                CodexCompletionRecord(
                    sessionID: "tray-completed",
                    projectName: "Project C",
                    promptPreview: "查看完成结果",
                    resultPreview: "测试已通过",
                    completedAt: now.addingTimeInterval(-20)
                )
            ]
        )
        let tray = CodexActivityTrayBuilder().build(
            from: traySnapshot,
            preferences: CodexActivityTrayPreferences(
                pinnedProjectNames: ["Project A"],
                collapsedProjectNames: ["Project A"],
                ignoredSessionIDs: ["tray-completed"]
            )
        )
        try expect(
            tray.buckets.map(\.bucket) == [.needsAttention, .blocked, .running],
            "activity tray groups tasks by attention priority and hides ignored sessions"
        )
        try expect(
            tray.buckets[0].groups.map(\.projectName) == ["Project B"]
                && tray.buckets[1].groups.map(\.projectName) == ["Project A"],
            "activity tray keeps project groups independent"
        )
        try expect(
            tray.buckets[2].groups.first?.projectName == "Project A"
                && tray.buckets[2].groups.first?.isPinned == true
                && tray.buckets[2].groups.first?.isCollapsed == true,
            "activity tray applies project pinning and collapse preferences"
        )
        try expect(
            tray.buckets[0].groups.first?.items.first?.nextAction == "打开 Codex 处理"
                && tray.buckets[1].groups.first?.items.first?.nextAction == "检查会话"
                && tray.buckets[2].groups.first?.items.first?.nextAction == "继续等待",
            "activity tray exposes a next action for each task state"
        )
        try expect(
            tray.ignoredItems.map(\.sessionID) == ["tray-completed"],
            "activity tray keeps ignored tasks recoverable"
        )

        let historyCompletions = (0..<12).map { index in
            CodexCompletionRecord(
                sessionID: "history-\(index)",
                projectName: "History Project",
                promptPreview: "历史对话 \(index)",
                resultPreview: "结果 \(index)",
                completedAt: now.addingTimeInterval(TimeInterval(-index))
            )
        }
        let viewedHistory = CodexActivityTrayBuilder().build(
            from: CodexTaskStoreSnapshot(
                savedAt: now,
                recentCompletions: historyCompletions,
                acknowledgedCompletionIDs: historyCompletions.map(\.id)
            )
        )
        try expect(
            viewedHistory.buckets.first?.bucket == .readHistory
                && viewedHistory.buckets.first?.itemCount == 12,
            "viewing completed notifications does not remove completed history"
        )
        try expect(
            viewedHistory.buckets.first?.limited(to: 10).itemCount == 10,
            "activity tray can limit completed history to the default ten rows"
        )
        try expect(
            AppPreferences().recentRetention == 7 * 24 * 60 * 60
                && AppPreferences().maxRecentCompletions == 100,
            "completed history keeps a week of compact records with a bounded cap"
        )

        let recoveredHistory = CodexActivityTrayBuilder().build(
            from: CodexTaskStoreSnapshot(
                savedAt: now,
                tasks: [
                    CodexTaskRecord(
                        sessionID: "legacy-completed",
                        projectName: "Legacy Project",
                        promptPreview: "旧版本完成任务",
                        resultPreview: "旧版本结果仍可恢复",
                        status: .completed,
                        lastActivityAt: now,
                        completedAt: now
                    )
                ]
            )
        )
        try expect(
            recoveredHistory.buckets.first?.bucket == .readHistory
                && recoveredHistory.buckets.first?.items.first?.sessionID == "legacy-completed",
            "completed task records recover history when old completion summaries were pruned"
        )

        let unreadCompletion = CodexCompletionRecord(
            sessionID: "unread-completion",
            projectName: "Unread Project",
            promptPreview: "最新完成任务",
            resultPreview: "刚刚完成",
            completedAt: now.addingTimeInterval(-5)
        )
        let readCompletion = CodexCompletionRecord(
            sessionID: "read-completion",
            projectName: "Read Project",
            promptPreview: "更早完成任务",
            resultPreview: "历史结果",
            completedAt: now.addingTimeInterval(-100)
        )
        let orderedTray = CodexActivityTrayBuilder().build(
            from: CodexTaskStoreSnapshot(
                savedAt: now,
                tasks: [runningTasks[0]],
                recentCompletions: [readCompletion, unreadCompletion],
                acknowledgedCompletionIDs: [readCompletion.id]
            )
        )
        try expect(
            orderedTray.buckets.map(\.bucket) == [.unreadCompleted, .running, .readHistory],
            "unread completions appear before running tasks and read history"
        )
        try expect(
            orderedTray.buckets[0].items.first?.isRead == false
                && orderedTray.buckets[0].items.first?.sessionID == "unread-completion"
                && orderedTray.buckets[2].items.first?.isRead == true,
            "completion items expose read state and newest completion comes first"
        )
        try expect(
            orderedTray.buckets[2].items.first?.bucket == .readHistory,
            "acknowledged completions use the grey history bucket"
        )

        print("CodexPresentationTests: PASS")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else { throw TestFailure(message: message) }
    }

    private static func textValue(in section: AtollNotchContentSection) -> String? {
        guard let first = section.elements.first else { return nil }
        guard case let .text(value, _, _, _) = first else { return nil }
        return value
    }
}

private struct TestFailure: Error {
    let message: String
}
