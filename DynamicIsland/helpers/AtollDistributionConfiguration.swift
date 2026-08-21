import Foundation

enum AtollDistributionConfiguration {
    /// Custom builds must not consume the official Atoll appcast because doing
    /// so can replace the native Codex integration with an upstream release.
    static var updateFeedURL: URL? {
        if let environmentValue = ProcessInfo.processInfo.environment["ATOLL_UPDATE_FEED_URL"],
           let url = URL(string: environmentValue),
           !environmentValue.isEmpty {
            return url
        }
        if let configuredValue = Bundle.main.object(forInfoDictionaryKey: "AtollUpdateFeedURL") as? String,
           let url = URL(string: configuredValue),
           !configuredValue.isEmpty {
            return url
        }
        return nil
    }

    static var automaticUpdatesEnabled: Bool {
        updateFeedURL != nil && !AppRuntimeEnvironment.isUITesting
    }
}
