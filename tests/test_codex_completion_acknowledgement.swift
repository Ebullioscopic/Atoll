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

        var exposureSnapshot = CodexTaskStoreSnapshot(
            savedAt: now,
            recentCompletions: [first]
        )
        let exposureEffects = reducer.recordCompletionPresentations(
            completionIDs: [first.id],
            state: &exposureSnapshot,
            now: now
        )
        try expect(
            exposureEffects == [.persist]
                && exposureSnapshot.presentedCompletionIDs == [first.id]
                && exposureSnapshot.unacknowledgedCompletions == [first],
            "the first presentation persists exposure without clearing the unread completion"
        )
        try expect(
            reducer.recordCompletionPresentations(
                completionIDs: [first.id],
                state: &exposureSnapshot,
                now: now
            ).isEmpty,
            "repeated exposure recording is idempotent within one presentation"
        )
        _ = reducer.acknowledgeCompletion(
            sessionID: first.sessionID,
            state: &exposureSnapshot,
            now: now
        )
        try expect(
            exposureSnapshot.unacknowledgedCompletions.isEmpty
                && exposureSnapshot.presentedCompletionIDs?.isEmpty == true,
            "the second presentation acknowledgement clears both unread and exposure state"
        )

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
        legacyObject.removeValue(forKey: "presentedCompletionIDs")
        let legacySnapshot = try decoder.decode(
            CodexTaskStoreSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )
        try expect(
            legacySnapshot.acknowledgedCompletionIDs == nil
                && legacySnapshot.presentedCompletionIDs == nil
                && legacySnapshot.unacknowledgedCompletions == [first],
            "state written before acknowledgement and exposure support remains readable"
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

        let third = CodexCompletionRecord(
            sessionID: "completed-3",
            projectName: "Atoll-CodexAtoll",
            promptPreview: "验证按会话清除",
            resultPreview: "第三条完成",
            completedAt: now.addingTimeInterval(2)
        )
        var perSessionSnapshot = CodexTaskStoreSnapshot(
            savedAt: now,
            recentCompletions: [first, second, third]
        )
        let perSessionEffects = reducer.acknowledgeCompletion(
            sessionID: second.sessionID,
            state: &perSessionSnapshot,
            now: now
        )
        try expect(
            perSessionEffects == [.persist, .refreshPresentation],
            "acknowledging one session persists and refreshes presentation"
        )
        try expect(
            perSessionSnapshot.unacknowledgedCompletions.map(\.sessionID)
                == [first.sessionID, third.sessionID],
            "acknowledging one session leaves other completion counts visible"
        )
        try expect(
            perSessionSnapshot.recentCompletions.count == 3,
            "acknowledging one session keeps all recent conversation history"
        )
        try expect(
            reducer.acknowledgeCompletion(
                sessionID: second.sessionID,
                state: &perSessionSnapshot,
                now: now
            ).isEmpty,
            "repeated per-session acknowledgement is idempotent"
        )

        var resumedSnapshot = CodexTaskStoreSnapshot(
            savedAt: now,
            recentCompletions: [third]
        )
        let resumeEnvelope = CodexHookEnvelope(
            receivedAt: now.addingTimeInterval(3),
            payload: CodexHookEvent(
                hookEventName: "SessionStart",
                sessionID: third.sessionID,
                source: "resume",
                cwd: "/tmp/atoll-codex"
            )
        )
        let resumeEffects = reducer.reduce(
            state: &resumedSnapshot,
            envelope: resumeEnvelope,
            preferences: AppPreferences()
        )
        try expect(
            resumeEffects.contains(.refreshPresentation),
            "resuming a completed Codex session refreshes the presentation"
        )
        try expect(
            resumedSnapshot.unacknowledgedCompletions.isEmpty,
            "resuming a completed Codex session acknowledges only that session"
        )

        let continuedCompletion = CodexCompletionRecord(
            sessionID: "continued-session",
            projectName: "Atoll-CodexAtoll",
            promptPreview: "上一轮任务",
            resultPreview: "上一轮已完成",
            completedAt: now
        )
        var continuedSnapshot = CodexTaskStoreSnapshot(
            savedAt: now,
            tasks: [
                CodexTaskRecord(
                    sessionID: continuedCompletion.sessionID,
                    projectName: continuedCompletion.projectName,
                    status: .completed,
                    lastActivityAt: now,
                    completedAt: now
                )
            ],
            recentCompletions: [continuedCompletion]
        )
        let continuedPrompt = CodexHookEnvelope(
            receivedAt: now.addingTimeInterval(4),
            payload: CodexHookEvent(
                hookEventName: "UserPromptSubmit",
                sessionID: continuedCompletion.sessionID,
                turnID: "continued-turn",
                cwd: "/tmp/atoll-codex",
                prompt: "继续当前对话"
            )
        )
        let continuedEffects = reducer.reduce(
            state: &continuedSnapshot,
            envelope: continuedPrompt,
            preferences: AppPreferences()
        )
        try expect(
            continuedEffects.contains(.showRunning(sessionID: continuedCompletion.sessionID)),
            "a new prompt emits an explicit running reminder even when completion history exists"
        )
        try expect(
            continuedSnapshot.tasks.first?.status == .running,
            "a new prompt in a completed session returns the task to running"
        )
        try expect(
            continuedSnapshot.unacknowledgedCompletions.isEmpty,
            "a new prompt acknowledges the previous completion for that session"
        )
        try expect(
            continuedSnapshot.recentCompletions == [continuedCompletion],
            "continuing a session keeps the previous completion in history"
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
