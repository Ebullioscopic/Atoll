import Foundation

/// Account-wide billing quotas, not session token totals or estimated API costs.
struct CopilotQuota: Equatable, Identifiable {
    let id: String
    let title: String
    let usedPercent: Double?
    let entitlement: Double?
    let remaining: Double?
    let unlimited: Bool
    let resetsAt: Date?
}

struct CopilotQuotaPayload: Decodable {
    let copilot_plan: String?
    let quota_reset_date: String?
    let quota_reset_date_utc: String?
    let token_based_billing: Bool?
    let quota_snapshots: [String: Bucket]?

    struct Bucket: Decodable {
        let entitlement: Double?
        let remaining: Double?
        let quota_remaining: Double?
        let percent_remaining: Double?
        let unlimited: Bool?
        let quota_reset_at: Double?
        let token_based_billing: Bool?
    }

    var quotas: [CopilotQuota] {
        let reset = Self.date(quota_reset_date_utc ?? quota_reset_date)
        return ["premium_interactions", "chat", "completions"].compactMap { key in
            guard let bucket = quota_snapshots?[key] else { return nil }
            let unlimited = bucket.unlimited == true || bucket.entitlement == -1
            let entitlement = bucket.entitlement.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
            let remaining = (bucket.quota_remaining ?? bucket.remaining).flatMap { $0.isFinite ? max(0, $0) : nil }
            let percent: Double?
            if unlimited { percent = nil }
            else if let reported = bucket.percent_remaining, reported.isFinite {
                percent = min(100, max(0, 100 - reported))
            } else if let entitlement, let remaining {
                percent = min(100, max(0, 100 * (1 - remaining / entitlement)))
            } else { percent = nil }
            let title: String
            switch key {
            case "premium_interactions": title = (bucket.token_based_billing ?? token_based_billing) == true ? "AI credits" : "Premium requests"
            case "chat": title = "Chat"
            default: title = "Completions"
            }
            return CopilotQuota(id: key, title: title, usedPercent: percent,
                                entitlement: entitlement, remaining: remaining,
                                unlimited: unlimited,
                                resetsAt: bucket.quota_reset_at.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0) : nil } ?? reset)
        }
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }
}

/// Only GitHub-hosted account endpoints are accepted; never send a token to an
/// arbitrary URL entered by mistake. Data residency tenants use api.<tenant>.ghe.com.
enum CopilotEndpoint {
    static func url(host: String) throws -> URL {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tenant = host.range(of: #"^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.ghe\.com$"#, options: .regularExpression) != nil
        guard host == "github.com" || tenant,
              let url = URL(string: "https://api.\(host)/copilot_internal/user") else {
            throw CopilotQuotaError.invalidHost
        }
        return url
    }
}

/// RFC 6750 bearer-token characters only. Reject pasted files, control characters,
/// and oversized input before it can reach Keychain or an HTTP header.
enum CopilotTokenValidation {
    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 8192 else { return false }
        return value.range(of: #"\A[A-Za-z0-9._~+/-]+=*\z"#, options: .regularExpression) != nil
    }
}

enum CopilotQuotaError: LocalizedError {
    case invalidHost, notConfigured, unauthorized, unavailable(Int), invalidResponse, networkUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidHost: return "Use github.com or your tenant.ghe.com GitHub host."
        case .notConfigured: return "Connect GitHub Copilot in Settings → Stats."
        case .unauthorized: return "Copilot access denied. Check the GitHub token and enterprise authorization."
        case .unavailable(let code): return "GitHub Copilot quota unavailable (HTTP \(code))."
        case .invalidResponse: return "GitHub did not return usable Copilot quota information."
        case .networkUnavailable: return "Unable to connect to GitHub Copilot. Check your network and try again."
        }
    }
}
