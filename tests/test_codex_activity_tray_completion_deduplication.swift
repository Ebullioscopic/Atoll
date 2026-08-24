import CoreGraphics
import Foundation

@main
struct CodexActivityTrayCompletionDeduplicationTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let earlierTurn = CodexCompletionRecord(
            sessionID: "multi-turn-session",
            projectName: "Multi-turn Project",
            promptPreview: "第一轮问题",
            resultPreview: "第一轮完成",
            completedAt: now.addingTimeInterval(-60)
        )
        let latestTurn = CodexCompletionRecord(
            sessionID: "multi-turn-session",
            projectName: "Multi-turn Project",
            promptPreview: "第二轮问题",
            resultPreview: "第二轮完成",
            completedAt: now
        )

        let unreadTray = CodexActivityTrayBuilder().build(
            from: CodexTaskStoreSnapshot(
                savedAt: now,
                recentCompletions: [earlierTurn, latestTurn]
            )
        )
        try expect(
            unreadTray.buckets.count == 1
                && unreadTray.buckets.first?.bucket == .unreadCompleted
                && unreadTray.buckets.first?.itemCount == 1
                && unreadTray.buckets.first?.items.first?.title == "第二轮问题",
            "multiple completed turns in one conversation occupy one unread card with the latest content"
        )

        let readTray = CodexActivityTrayBuilder().build(
            from: CodexTaskStoreSnapshot(
                savedAt: now,
                recentCompletions: [earlierTurn, latestTurn],
                acknowledgedCompletionIDs: [earlierTurn.id, latestTurn.id]
            )
        )
        try expect(
            readTray.buckets.count == 1
                && readTray.buckets.first?.bucket == .readHistory
                && readTray.buckets.first?.itemCount == 1
                && readTray.buckets.first?.items.first?.title == "第二轮问题",
            "viewing a multi-turn conversation greys one latest history card without duplicates"
        )

        let latestUnreadTray = CodexActivityTrayBuilder().build(
            from: CodexTaskStoreSnapshot(
                savedAt: now,
                recentCompletions: [earlierTurn, latestTurn],
                acknowledgedCompletionIDs: [earlierTurn.id]
            )
        )
        try expect(
            latestUnreadTray.buckets.count == 1
                && latestUnreadTray.buckets.first?.bucket == .unreadCompleted
                && latestUnreadTray.buckets.first?.itemCount == 1
                && latestUnreadTray.buckets.first?.items.first?.title == "第二轮问题",
            "a new completed turn refreshes the same conversation card back to unread"
        )

        let visibleIDs = CodexActivityTrayVisibilityPolicy.visibleItemIDs(
            itemFrames: [
                "visible": CGRect(x: 0, y: 20, width: 240, height: 80),
                "clipped-edge": CGRect(x: 0, y: 180, width: 240, height: 80),
                "offscreen": CGRect(x: 0, y: 220, width: 240, height: 80),
            ],
            viewportBounds: CGRect(x: 0, y: 0, width: 240, height: 200)
        )
        try expect(
            visibleIDs == ["visible"],
            "only completion cards that are materially visible in the drawer count as read"
        )

        let visibleCompletionItems = unreadTray.buckets.first?.items ?? []
        let firstPresentation = CodexActivityTrayExposurePolicy.decision(
            for: visibleCompletionItems,
            previouslyPresentedIDs: [],
            handledCompletionIDs: []
        )
        try expect(
            firstPresentation.completionIDsToRecord == [latestTurn.id]
                && firstPresentation.sessionIDsToAcknowledge.isEmpty,
            "the first visible presentation records exposure without acknowledging the completion"
        )
        let repeatedLayoutInSamePresentation = CodexActivityTrayExposurePolicy.decision(
            for: visibleCompletionItems,
            previouslyPresentedIDs: [latestTurn.id],
            handledCompletionIDs: firstPresentation.handledCompletionIDs
        )
        try expect(
            repeatedLayoutInSamePresentation.completionIDsToRecord.isEmpty
                && repeatedLayoutInSamePresentation.sessionIDsToAcknowledge.isEmpty,
            "layout updates during one open drawer never count as a second presentation"
        )
        let secondPresentation = CodexActivityTrayExposurePolicy.decision(
            for: visibleCompletionItems,
            previouslyPresentedIDs: [latestTurn.id],
            handledCompletionIDs: []
        )
        try expect(
            secondPresentation.completionIDsToRecord.isEmpty
                && secondPresentation.sessionIDsToAcknowledge.isEmpty,
            "reopening the drawer does not acknowledge a completion before the prior presentation is dismissed"
        )
        try expect(
            CodexActivityTrayExposurePolicy.sessionIDsToAcknowledgeOnDismiss(
                for: visibleCompletionItems
            ) == [latestTurn.sessionID],
            "dismissing the drawer acknowledges the completion that was browsed during the presentation"
        )
        print("CodexActivityTrayCompletionDeduplicationTests: PASS")
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
