import Foundation
import Defaults

@MainActor
final class CodexPresentationCoordinator {
    private let builder: CodexPresentationBuilder
    private let liveActivityManager: ExtensionLiveActivityManager
    private let notchExperienceManager: ExtensionNotchExperienceManager
    private var latestSnapshot: CodexTaskStoreSnapshot = .empty
    private var pulseGeneration = 0
    private var restoreTask: Task<Void, Never>?
    private let completionPulseDuration: TimeInterval = 3.5

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
        completionSessionIDs: [String] = []
    ) {
        latestSnapshot = snapshot
        if let sessionID = completionSessionIDs.last {
            pulseGeneration += 1
            let generation = pulseGeneration
            apply(
                snapshot: snapshot,
                context: .completionPulse(
                    sessionID: sessionID,
                    completedCount: completionSessionIDs.count
                )
            )
            scheduleSteadyRestore(generation: generation)
        } else {
            apply(snapshot: snapshot, context: .steady)
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
        context: CodexPresentationContext
    ) {
        let presentation = builder.build(from: snapshot, context: context)

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
                try await Task.sleep(for: .seconds(self?.completionPulseDuration ?? 3.5))
            } catch {
                return
            }
            guard let self, generation == self.pulseGeneration else { return }
            self.apply(snapshot: self.latestSnapshot, context: .steady)
        }
    }
}
