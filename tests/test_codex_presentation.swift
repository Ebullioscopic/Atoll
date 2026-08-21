import Foundation

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
              let populatedTab = populatedExperience.tab,
              let recentSection = populatedTab.sections.first(where: { $0.id == "recent" }) else {
            throw TestFailure(message: "populated Codex task tab exposes recent conversations")
        }

        try expect(populatedExperience.isValid, "expanded Codex task tab remains a valid descriptor")
        try expect(populatedTab.preferredHeight == 420, "expanded Codex task tab requests the taller supported height")
        try expect(recentSection.elements.count == 6, "expanded Codex task tab shows six recent conversations")
        for index in 0..<6 {
            try expect(
                populatedExperience.metadata["atoll.openCodexThread.recent.\(index)"]
                    == "codex://threads/session-\(index)",
                "recent conversation \(index) keeps its Codex thread jump"
            )
        }
        try expect(
            populatedExperience.metadata["atoll.openCodexThread.recent.6"] == nil,
            "only rendered recent conversations publish jump metadata"
        )

        print("CodexPresentationTests: PASS")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error {
    let message: String
}
