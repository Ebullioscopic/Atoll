import Foundation

public enum CodexPresentationConstants {
    public static let liveActivityID = "codex-atoll-summary"
    public static let experienceID = "codex-atoll-dashboard"
    public static let tabID = "codex-atoll-tab"
    public static let expandedTabPreferredHeight: CGFloat = 420
    public static let visibleConversationLimit = 6
    public static let targetExperienceMetadataKey = "atoll.targetNotchExperienceID"
    public static let openCodexThreadMetadataPrefix = "atoll.openCodexThread."
    public static let runningSneakPeekDuration: TimeInterval = 3.5
    public static let completionPulseDuration: TimeInterval = 3.5
    public nonisolated static let defaultBundleIdentifier = "com.Ebullioscopic.Atoll.builtin.codex"
    public nonisolated static let legacyExternalBundleIdentifiers = [
        "com.codexatoll.app",
        "com.example.codexatoll",
    ]

    public nonisolated static func isBuiltInCodex(bundleIdentifier: String) -> Bool {
        bundleIdentifier == defaultBundleIdentifier
    }

    public nonisolated static func isLegacyExternalCodex(bundleIdentifier: String) -> Bool {
        legacyExternalBundleIdentifiers.contains(bundleIdentifier)
    }

    public nonisolated static func shouldAnimateBusyIcon(
        bundleIdentifier: String,
        metadata: [String: String]
    ) -> Bool {
        guard isBuiltInCodex(bundleIdentifier: bundleIdentifier) else { return false }
        return (Int(metadata["codex_running_count"] ?? "0") ?? 0) > 0
    }
}
