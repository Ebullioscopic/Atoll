import Foundation
import Security

// MARK: - OpenRouter Usage

protocol OpenRouterAPIKeyProviding {
    func apiKey() -> String?
}

enum OpenRouterKeychain {
    private static let service = "com.Ebullioscopic.Atoll.openrouter"
    private static let account = "management-key"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ apiKey: String) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecSuccess || updateStatus == errSecItemNotFound else {
            throw OpenRouterKeychainError(status: updateStatus)
        }
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw OpenRouterKeychainError(status: addStatus) }
        }
    }

    static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenRouterKeychainError(status: status)
        }
    }
}

struct OpenRouterKeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Unable to store the OpenRouter management key (Keychain status \(status))." }
}

struct OpenRouterAPIKeyStore: OpenRouterAPIKeyProviding {
    func apiKey() -> String? { OpenRouterKeychain.read() }
}

struct OpenRouterClient {
    typealias RequestHandler = (URLRequest) async throws -> (Data, URLResponse)

    private let requestHandler: RequestHandler
    private let baseURL = URL(string: "https://openrouter.ai/api/v1")!

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.requestHandler = { request in try await session.data(for: request) }
    }

    init(requestHandler: @escaping RequestHandler) {
        self.requestHandler = requestHandler
    }

    func fetchSnapshot(apiKey: String, now: Date, calendar: Calendar = .current) async throws -> UsageSnapshot {
        async let credits = fetchCredits(apiKey: apiKey)
        async let today = fetchAnalytics(apiKey: apiKey, start: calendar.startOfDay(for: now), end: now)
        async let week = fetchAnalytics(
            apiKey: apiKey,
            start: calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now),
            end: now
        )

        let creditSummary = try await credits
        let todaySummary = try await today
        let weekSummary = try await week

        var snapshot = UsageSnapshot()
        snapshot.today = todaySummary.totals
        snapshot.week = weekSummary.totals
        snapshot.models = weekSummary.models
        snapshot.sessionLimit = UsageLimit(
            used: creditSummary.totalUsage,
            limit: max(creditSummary.totalCredits, creditSummary.totalUsage)
        )
        snapshot.lastUpdated = now
        return snapshot
    }

    func fetchCredits(apiKey: String) async throws -> OpenRouterCredits {
        let data = try await request(path: "credits", method: "GET", apiKey: apiKey)
        return try decode(OpenRouterEnvelope<OpenRouterCredits>.self, from: data).data
    }

    func fetchAnalytics(apiKey: String, start: Date, end: Date) async throws -> OpenRouterAnalyticsSummary {
        let payload: [String: Any] = [
            "metrics": ["total_usage", "tokens_total", "request_count"],
            "dimensions": ["model"],
            "time_range": [
                "start": Self.iso8601.string(from: start),
                "end": Self.iso8601.string(from: end)
            ],
            "limit": 100
        ]
        let data = try await request(path: "analytics/query", method: "POST", apiKey: apiKey, jsonBody: payload)
        let response = try decode(OpenRouterAnalyticsResponse.self, from: data)
        return OpenRouterAnalyticsSummary(rows: response.data.data)
    }

    private func request(path: String, method: String, apiKey: String, jsonBody: [String: Any]? = nil) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        let (data, response) = try await requestHandler(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw OpenRouterClientError.httpFailure
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw OpenRouterClientError.invalidResponse }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct OpenRouterEnvelope<T: Decodable>: Decodable {
    let data: T
}

struct OpenRouterCredits: Decodable, Equatable {
    let totalCredits: Double
    let totalUsage: Double

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }

    init(totalCredits: Double, totalUsage: Double) {
        self.totalCredits = totalCredits
        self.totalUsage = totalUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalCredits = try Self.decodeDouble(forKey: .totalCredits, from: container)
        totalUsage = try Self.decodeDouble(forKey: .totalUsage, from: container)
    }

    private static func decodeDouble(forKey key: CodingKeys, from container: KeyedDecodingContainer<CodingKeys>) throws -> Double {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? container.decode(String.self, forKey: key), let double = Double(value) { return double }
        throw DecodingError.typeMismatch(
            Double.self,
            DecodingError.Context(codingPath: container.codingPath + [key], debugDescription: "Expected a number or numeric string")
        )
    }
}

struct OpenRouterAnalyticsRow: Decodable, Equatable {
    let model: String?
    let totalUsage: Double
    let tokensTotal: Int
    let requestCount: Int

    enum CodingKeys: String, CodingKey {
        case model
        case totalUsage = "total_usage"
        case tokensTotal = "tokens_total"
        case requestCount = "request_count"
    }

    init(model: String?, totalUsage: Double, tokensTotal: Int, requestCount: Int) {
        self.model = model
        self.totalUsage = totalUsage
        self.tokensTotal = tokensTotal
        self.requestCount = requestCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try? container.decodeIfPresent(String.self, forKey: .model)
        totalUsage = try Self.decodeDouble(forKey: .totalUsage, from: container)
        tokensTotal = try Self.decodeInt(forKey: .tokensTotal, from: container)
        requestCount = try Self.decodeInt(forKey: .requestCount, from: container)
    }

    private static func decodeDouble(forKey key: CodingKeys, from container: KeyedDecodingContainer<CodingKeys>) throws -> Double {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? container.decode(String.self, forKey: key), let double = Double(value) { return double }
        return 0
    }

    private static func decodeInt(forKey key: CodingKeys, from container: KeyedDecodingContainer<CodingKeys>) throws -> Int {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key), let int = Int(value) { return int }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(value) }
        return 0
    }
}

private struct OpenRouterAnalyticsResponse: Decodable {
    let data: OpenRouterAnalyticsPayload
}

private struct OpenRouterAnalyticsPayload: Decodable {
    let data: [OpenRouterAnalyticsRow]
}

struct OpenRouterAnalyticsSummary: Equatable {
    let rows: [OpenRouterAnalyticsRow]

    var totals: UsageTotals {
        UsageTotals(
            inputTokens: rows.reduce(0) { $0 + $1.tokensTotal },
            outputTokens: 0,
            costUSD: rows.reduce(0) { $0 + $1.totalUsage },
            requestCount: rows.reduce(0) { $0 + $1.requestCount }
        )
    }

    var models: [ModelUsage] {
        rows
            .filter { $0.model?.isEmpty == false }
            .sorted { $0.totalUsage > $1.totalUsage }
            .map { row in
                ModelUsage(
                    model: row.model ?? "Unknown",
                    totals: UsageTotals(inputTokens: row.tokensTotal, outputTokens: 0, costUSD: row.totalUsage, requestCount: row.requestCount),
                    pool: nil
                )
            }
    }
}

enum OpenRouterClientError: LocalizedError {
    case httpFailure
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .httpFailure: return "OpenRouter request failed. Check that the saved key is a management key."
        case .invalidResponse: return "OpenRouter returned an invalid response"
        }
    }
}

struct OpenRouterUsageProvider: UsageProvider {
    let id: ProviderID = .openrouter
    let keySource: OpenRouterAPIKeyProviding
    let client: OpenRouterClient

    init(keySource: OpenRouterAPIKeyProviding = OpenRouterAPIKeyStore(), client: OpenRouterClient = OpenRouterClient()) {
        self.keySource = keySource
        self.client = client
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        guard let apiKey = keySource.apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw UsageError.notConfigured("OpenRouter management key not configured")
        }
        return try await client.fetchSnapshot(apiKey: apiKey, now: now)
    }
}
