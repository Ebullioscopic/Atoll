import Foundation
import Defaults

@MainActor
final class CodexPresentationCoordinator {
    private let builder: CodexPresentationBuilder
    private let liveActivityManager: ExtensionLiveActivityManager
    private let notchExperienceManager: ExtensionNotchExperienceManager
    private var latestSnapshot: CodexTaskStoreSnapshot = .empty
    private var latestIgnoredSessionIDs: Set<String> = []
    private var pulseGeneration = 0
    private var restoreTask: Task<Void, Never>?
    private let completionPulseDuration = CodexPresentationConstants.completionPulseDuration

    init(
        builder: CodexPresentationBuilder = CodexPresentationBuilder(),
        liveActivityManager: ExtensionLiveActivityManager = .shared,
        notchExperienceManager: ExtensionNotchExperienceManager = .shared
    ) {
        self.builder = builder
        self.liveActivityManager = liveActivityManager
        self.notchExperienceManager = notchExperienceManager
    }

    func update(
        snapshot: CodexTaskStoreSnapshot,
        completionSessionIDs: [String] = [],
        ignoredSessionIDs: Set<String> = []
    ) {
        latestSnapshot = snapshot
        latestIgnoredSessionIDs = ignoredSessionIDs
        if let sessionID = completionSessionIDs.last {
            pulseGeneration += 1
            let generation = pulseGeneration
            apply(
                snapshot: snapshot,
                context: .completionPulse(
                    sessionID: sessionID,
                    completedCount: completionSessionIDs.count
                ),
                ignoredSessionIDs: ignoredSessionIDs
            )
            scheduleSteadyRestore(generation: generation)
        } else {
            apply(
                snapshot: snapshot,
                context: .steady,
                ignoredSessionIDs: ignoredSessionIDs
            )
        }
    }

    func dismiss() {
        restoreTask?.cancel()
        restoreTask = nil
        liveActivityManager.dismissBuiltIn(
            activityID: CodexPresentationConstants.liveActivityID,
            bundleIdentifier: builder.bundleIdentifier
        )
        notchExperienceManager.dismissBuiltIn(
            experienceID: CodexPresentationConstants.experienceID,
            bundleIdentifier: builder.bundleIdentifier
        )
    }

    private func apply(
        snapshot: CodexTaskStoreSnapshot,
        context: CodexPresentationContext,
        ignoredSessionIDs: Set<String>? = nil
    ) {
        let presentation = builder.build(
            from: snapshot,
            context: context,
            ignoredSessionIDs: ignoredSessionIDs ?? latestIgnoredSessionIDs
        )

        if Defaults[.codexShowClosedStatus], let live = presentation.liveActivity {
            try? liveActivityManager.presentBuiltIn(
                descriptor: live,
                bundleIdentifier: builder.bundleIdentifier
            )
        } else {
            liveActivityManager.dismissBuiltIn(
                activityID: CodexPresentationConstants.liveActivityID,
                bundleIdentifier: builder.bundleIdentifier
            )
        }

        if Defaults[.codexShowTaskTab], let notch = presentation.notchExperience {
            try? notchExperienceManager.presentBuiltIn(
                descriptor: notch,
                bundleIdentifier: builder.bundleIdentifier
            )
        } else {
            notchExperienceManager.dismissBuiltIn(
                experienceID: CodexPresentationConstants.experienceID,
                bundleIdentifier: builder.bundleIdentifier
            )
        }
    }

    private func scheduleSteadyRestore(generation: Int) {
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: .seconds(
                        self?.completionPulseDuration
                            ?? CodexPresentationConstants.completionPulseDuration
                    )
                )
            } catch {
                return
            }
            guard let self, generation == self.pulseGeneration else { return }
            self.apply(snapshot: self.latestSnapshot, context: .steady)
        }
    }
}
