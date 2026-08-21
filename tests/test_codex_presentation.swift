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
                conversationSection.title == "Project \(index)",
                "recent conversation \(index) keeps its project title"
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
            runningOnlyCompactStatus.lines.map(\.displayText) == ["2 进行中"],
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
            mixedTab.sections[0].title == "Atoll-CodexAtoll"
                && mixedTab.sections[0].subtitle == "运行中 · 01:30"
                && textValue(in: mixedTab.sections[0]) == "修复关闭态任务摘要",
            "running conversation block keeps its status and related prompt"
        )
        try expect(
            mixedTab.sections[2].title == "Atoll-CodexAtoll"
                && mixedTab.sections[2].subtitle == "已完成"
                && textValue(in: mixedTab.sections[2]) == "已完成纵向展示",
            "completed conversation block keeps its status and related result"
        )
        try expect(
            mixedLiveActivity.metadata["codex_compact_line_count"] == "2",
            "closed status publishes two native compact rows"
        )
        try expect(
            mixedLiveActivity.metadata["codex_compact_line_0_label"] == "2 进行中",
            "running status stays on the first compact row"
        )
        try expect(
            mixedLiveActivity.metadata["codex_compact_line_0_detail"] == nil,
            "running compact row omits concrete task context"
        )
        try expect(
            mixedLiveActivity.metadata["codex_compact_line_1_label"] == "1 已完成",
            "completed status stays on a separate second row"
        )
        try expect(
            mixedLiveActivity.metadata["codex_compact_line_1_detail"] == nil,
            "completed compact row omits concrete result context"
        )
        guard case let .text(fallbackText, _, _) = mixedLiveActivity.trailingContent else {
            throw TestFailure(message: "compact status uses native text instead of Lottie text layers")
        }
        try expect(
            fallbackText == "2 进行中  1 已完成",
            "native fallback text contains only compact status counts"
        )
        guard let decodedCompactStatus = CodexCompactStatus(
            metadata: mixedLiveActivity.metadata
        ) else {
            throw TestFailure(message: "native compact status metadata can be decoded by the host view")
        }
        try expect(
            decodedCompactStatus.lines.map(\.displayText) == [
                "2 进行中",
                "1 已完成",
            ],
            "host view receives vertically ordered count-only rows"
        )
        try expect(
            decodedCompactStatus.preferredTrailingWidth == 84,
            "count-only closed status requests a compact right wing"
        )
        try expect(
            decodedCompactStatus.additionalClosedHeight == 16,
            "the completed row adds one compact row of notch height"
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
