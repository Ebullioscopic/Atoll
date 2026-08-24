import Foundation
import Defaults

@MainActor
final class CodexPresentationCoordinator {
    private let builder: CodexPresentationBuilder
    private let liveActivityManager: ExtensionLiveActivityManager
    private let notchExperienceManager: ExtensionNotchExperienceManager
    private var latestSnapshot: CodexTaskStoreSnapshot = .empty
    private var latestIgnoredSessionIDs: Set<String> = []
    private var pulseGate = CodexPresentationPulseGate()
    private var restoreTask: Task<Void, Never>?

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
        runningSessionIDs: [String] = [],
        completionSessionIDs: [String] = [],
        ignoredSessionIDs: Set<String> = [],
        interruptActivePulse: Bool = false
    ) {
        latestSnapshot = snapshot
        latestIgnoredSessionIDs = ignoredSessionIDs
        if interruptActivePulse {
            restoreTask?.cancel()
            restoreTask = nil
            pulseGate.cancel()
        }
        if let sessionID = completionSessionIDs.last {
            let generation = pulseGate.begin()
            apply(
                snapshot: snapshot,
                context: .completionPulse(
                    sessionID: sessionID,
                    completedCount: completionSessionIDs.count
                ),
                ignoredSessionIDs: ignoredSessionIDs
            )
            scheduleSteadyRestore(
                generation: generation,
                duration: CodexPresentationConstants.completionPulseDuration
            )
        } else if let sessionID = runningSessionIDs.last {
            let generation = pulseGate.begin()
            apply(
                snapshot: snapshot,
                context: .runningPulse(sessionID: sessionID),
                ignoredSessionIDs: ignoredSessionIDs
            )
            scheduleSteadyRestore(
                generation: generation,
                duration: CodexPresentationConstants.runningSneakPeekDuration
            )
        } else {
            guard !pulseGate.isActive else { return }
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
        pulseGate.cancel()
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

    private func scheduleSteadyRestore(generation: Int, duration: TimeInterval) {
        restoreTask?.cancel()
        restoreTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            guard let self, self.pulseGate.finish(generation: generation) else { return }
            self.restoreTask = nil
            self.apply(snapshot: self.latestSnapshot, context: .steady)
        }
    }
}
