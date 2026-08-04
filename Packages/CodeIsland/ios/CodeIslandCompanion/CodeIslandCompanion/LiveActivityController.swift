import ActivityKit
import Foundation

@MainActor
final class LiveActivityController: ObservableObject {
    private static let layoutVersionKey = "CodeIslandLiveActivityLayoutVersion"
    private static let currentLayoutVersion = "2026-05-29-compact-multi-session-v3"

    @Published private(set) var activityID: String?
    @Published private(set) var lastError: String?
    @Published private(set) var existingActivityCount = 0

    private var activity: Activity<CodeIslandActivityAttributes>?
    private var lastContentState: CodeIslandActivityAttributes.ContentState?
    private var activityStateTask: Task<Void, Never>?

    var isRunning: Bool {
        activity != nil
    }

    deinit {
        activityStateTask?.cancel()
    }

    init() {
        Task {
            await migrateLiveActivityLayoutIfNeeded()
            recoverExistingActivity()
        }
    }

    func updateIfRunning(with payload: CompanionStatePayload) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        Task {
            let shouldRecreate = await migrateLiveActivityLayoutIfNeeded()
            await recoverExistingActivity(endingDuplicates: true)
            guard activity != nil || shouldRecreate else { return }
            await apply(payload, createIfNeeded: shouldRecreate)
        }
    }

    func startOrUpdate(with payload: CompanionStatePayload) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = L10n.t(zh: "这台 iPhone 没有开启实时活动。", en: "Live Activities are turned off on this iPhone.")
            return
        }

        Task {
            await migrateLiveActivityLayoutIfNeeded()
            await recoverExistingActivity(endingDuplicates: true)
            await apply(payload, createIfNeeded: true)
        }
    }

    func stop() {
        stopAll()
    }

    func stopAll() {
        Task {
            for activity in Activity<CodeIslandActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            clearActivity(id: activityID)
            existingActivityCount = 0
            lastError = nil
        }
    }

    private func recoverExistingActivity() {
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
        guard activity == nil, let existing = newestExistingActivity() else { return }
        activity = existing
        activityID = existing.id
        lastContentState = existing.content.state
        observeState(of: existing)
    }

    private func recoverExistingActivity(endingDuplicates: Bool) async {
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
        guard let existing = newestExistingActivity() else {
            if activity != nil {
                clearActivity(id: activityID)
            }
            return
        }

        if activityID != existing.id {
            activity = existing
            activityID = existing.id
            lastContentState = existing.content.state
            observeState(of: existing)
        }

        guard endingDuplicates else { return }
        for duplicate in Activity<CodeIslandActivityAttributes>.activities where duplicate.id != existing.id {
            await duplicate.end(nil, dismissalPolicy: .immediate)
        }
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
    }

    private func newestExistingActivity() -> Activity<CodeIslandActivityAttributes>? {
        Activity<CodeIslandActivityAttributes>.activities.max {
            $0.content.state.updatedAt < $1.content.state.updatedAt
        }
    }

    @discardableResult
    private func migrateLiveActivityLayoutIfNeeded() async -> Bool {
        let storedVersion = UserDefaults.standard.string(forKey: Self.layoutVersionKey)
        guard storedVersion != Self.currentLayoutVersion else { return false }

        let existingActivities = Activity<CodeIslandActivityAttributes>.activities
        for activity in existingActivities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        if !existingActivities.isEmpty {
            clearActivity(id: activityID)
        }
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
        UserDefaults.standard.set(Self.currentLayoutVersion, forKey: Self.layoutVersionKey)
        return !existingActivities.isEmpty
    }

    private func apply(_ payload: CompanionStatePayload, createIfNeeded: Bool) async {
        do {
            let contentState = CodeIslandActivityAttributes.ContentState(payload: payload)
            lastContentState = contentState

            if let activity {
                await update(activity, with: contentState, status: payload.status)
                lastError = nil
                return
            }

            guard createIfNeeded else { return }
            let attributes = CodeIslandActivityAttributes(sessionId: payload.sessionId)
            let content = ActivityContent(
                state: contentState,
                staleDate: Date().addingTimeInterval(90),
                relevanceScore: relevanceScore(for: payload.status)
            )
            let existing = try Activity.request(attributes: attributes, content: content)
            activity = existing
            activityID = existing.id
            observeState(of: existing)
            lastError = nil
            existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
        } catch {
            lastError = error.localizedDescription
            recoverExistingActivity()
        }
    }

    private func update(
        _ activity: Activity<CodeIslandActivityAttributes>,
        with contentState: CodeIslandActivityAttributes.ContentState,
        status: CompanionStatus
    ) async {
        await activity.update(ActivityContent(
            state: contentState,
            staleDate: Date().addingTimeInterval(90),
            relevanceScore: relevanceScore(for: status)
        ))
    }

    private func observeState(of activity: Activity<CodeIslandActivityAttributes>) {
        activityStateTask?.cancel()
        activityStateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard state == .ended || state == .dismissed else { continue }
                self?.clearActivity(id: activity.id)
                break
            }
        }
    }

    private func clearActivity(id: String?) {
        guard activityID == nil || activityID == id else { return }
        activity = nil
        activityID = nil
        lastContentState = nil
        existingActivityCount = Activity<CodeIslandActivityAttributes>.activities.count
        activityStateTask?.cancel()
        activityStateTask = nil
    }

    private func relevanceScore(for status: CompanionStatus) -> Double {
        switch status {
        case .waitingApproval, .waitingQuestion:
            return 1
        case .processing, .running:
            return 0.7
        case .idle:
            return 0.25
        }
    }
}
