import Foundation

#if os(watchOS)
enum WatchStateStore {
    static let appGroupIdentifier = "group.top.fengye.CodeIslandCompanion"
    private static let latestStateKey = "latestCompanionState"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func save(_ state: CompanionStatePayload) {
        guard let data = try? encoder.encode(state) else { return }
        defaults.set(data, forKey: latestStateKey)
    }

    static func load() -> CompanionStatePayload? {
        guard let data = defaults.data(forKey: latestStateKey) else { return nil }
        return try? decoder.decode(CompanionStatePayload.self, from: data)
    }

    /// Drop the persisted snapshot. Called when an incoming state fails to decode so a
    /// poisoned payload can't put the app or widget into a relaunch crash loop (#246).
    static func clear() {
        defaults.removeObject(forKey: latestStateKey)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
#endif
