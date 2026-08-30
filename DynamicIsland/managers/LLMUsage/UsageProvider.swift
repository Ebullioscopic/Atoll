import Foundation
import Defaults

enum ProviderID: String, CaseIterable, Identifiable {
    case claude, codex, cursor, antigravity, newAPI
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .antigravity: return "Antigravity"
        case .newAPI: return "New API"
        }
    }
    var enabledKey: Defaults.Key<Bool> {
        switch self {
        case .claude: return .enableClaudeProvider
        case .codex: return .enableCodexProvider
        case .cursor: return .enableCursorProvider
        case .antigravity: return .enableAntigravityProvider
        case .newAPI: return .enableNewAPIProvider
        }
    }
}

struct UsageTotals: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var costUSD: Double = 0
    var hasUnpricedModel: Bool = false
    var isPercentage: Bool = false
    var totalTokens: Int { inputTokens + outputTokens }
}

struct ModelUsage: Equatable, Identifiable {
    let model: String
    let totals: UsageTotals
    let pool: String? // "gemini" or "claude" for Antigravity
    var id: String { model }
}

struct UsageLimit: Equatable {
    let used: Double
    let limit: Double
    var resetsAt: Date? = nil
    var fraction: Double { limit > 0 ? min(used / limit, 1) : 0 }
}

struct UsageSnapshot: Equatable {
    var session: UsageTotals = .init()
    var today: UsageTotals = .init()
    var week: UsageTotals = .init()
    var sessionLimit: UsageLimit? = nil // 5h window quota
    var weekLimit: UsageLimit? = nil // 7d window quota
    var models: [ModelUsage] = []
    var plan: String? = nil // Subscription plan label (e.g. "Max 5x"); provided by Claude only, nil otherwise.
    var newAPIAccounts: [NewAPIAccountSnapshot] = []
    var lastUpdated: Date = .distantPast
}

enum UsageResult {
    case loading
    case success(UsageSnapshot)
    case failure(String)
}

protocol UsageProvider {
    var id: ProviderID { get }
    func fetchSnapshot(now: Date) async throws -> UsageSnapshot
}
