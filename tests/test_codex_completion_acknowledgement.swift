import Foundation

@main
struct CodexCompletionAcknowledgementTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_787_305_200)
        let first = CodexCompletionRecord(
            sessionID: "completed-1",
            projectName: "Atoll-CodexAtoll",
            promptPreview: "实现已完成计数",
            resultPreview: "完成",
            completedAt: now.addingTimeInterval(-10)
        )
        var snapshot = CodexTaskStoreSnapshot(
            savedAt: now,
            recentCompletions: [first]
        )
        let reducer = CodexEventReducer()

        let effects = reducer.acknowledgeCompletions(state: &snapshot, now: now)
        try expect(
            effects == [.persist, .refreshPresentation],
            "acknowledging visible completions persists and refreshes presentation"
        )
        try expect(
            snapshot.recentCompletions == [first],
            "acknowledging completion count keeps recent conversation history"
        )
        try expect(
            snapshot.unacknowledgedCompletions.isEmpty,
            "acknowledging completion count clears every currently visible completion"
        )
        try expect(
            reducer.acknowledgeCompletions(state: &snapshot, now: now).isEmpty,
            "repeated acknowledgement is idempotent"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let restored = try decoder.decode(
            CodexTaskStoreSnapshot.self,
            from: encoder.encode(snapshot)
        )
        try expect(
            restored.acknowledgedCompletionIDs == [first.id],
            "acknowledgement survives persisted state round trips"
        )

        var legacyObject = try JSONSerialization.jsonObject(
            with: encoder.encode(snapshot)
        ) as? [String: Any] ?? [:]
        legacyObject.removeValue(forKey: "acknowledgedCompletionIDs")
        let legacySnapshot = try decoder.decode(
            CodexTaskStoreSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )
        try expect(
            legacySnapshot.acknowledgedCompletionIDs == nil
                && legacySnapshot.unacknowledgedCompletions == [first],
            "state written before acknowledgement support remains readable"
        )

        let second = CodexCompletionRecord(
            sessionID: "completed-2",
            projectName: "Atoll-CodexAtoll",
            promptPreview: "验证新完成任务",
            resultPreview: "再次完成",
            completedAt: now.addingTimeInterval(1)
        )
        snapshot.recentCompletions.append(second)
        try expect(
            snapshot.unacknowledgedCompletions == [second],
            "a completion created after acknowledgement becomes visible again"
        )

        print("CodexCompletionAcknowledgementTests: PASS")
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
