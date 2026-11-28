import Foundation
import Security

// MARK: - DeepSeek Usage

/// DeepSeek is prepaid: `GET /user/balance` reports the remaining credit per currency,
/// which is the number that matters before a long task runs out of money.
protocol DeepSeekAPIKeyProviding {
    func apiKey() -> String?
}

enum DeepSeekKeychain {
    private static let service = "com.Ebullioscopic.Atoll.deepseek"
    private static let account = "api-key"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Checks for a saved key without loading the secret.
    static func hasKey() -> Bool {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func save(_ apiKey: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(apiKey.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecSuccess || updateStatus == errSecItemNotFound else {
            throw DeepSeekKeychainError(status: updateStatus)
        }
        if updateStatus == errSecItemNotFound {
            let item = baseQuery.merging(attributes) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw DeepSeekKeychainError(status: addStatus) }
        }
    }

    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DeepSeekKeychainError(status: status)
        }
    }
}

struct DeepSeekKeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { String(localized: "Unable to store the DeepSeek key (Keychain status \(status)).") }
}

struct DeepSeekAPIKeyStore: DeepSeekAPIKeyProviding {
    func apiKey() -> String? { DeepSeekKeychain.read() }
}

struct DeepSeekBalance: Equatable, Identifiable, Decodable {
    let currency: String
    let total: Double
    let granted: Double
    let toppedUp: Double
    var id: String { currency }

    enum CodingKeys: String, CodingKey {
        case currency
        case total = "total_balance"
        case granted = "granted_balance"
        case toppedUp = "topped_up_balance"
    }

    init(currency: String, total: Double, granted: Double, toppedUp: Double) {
        self.currency = currency
        self.total = total
        self.granted = granted
        self.toppedUp = toppedUp
    }

    /// Amounts arrive as decimal strings ("12.34"); numbers are accepted too.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currency = try container.decode(String.self, forKey: .currency)
        total = Self.decodeAmount(.total, from: container)
        granted = Self.decodeAmount(.granted, from: container)
        toppedUp = Self.decodeAmount(.toppedUp, from: container)
    }

    private static func decodeAmount(_ key: CodingKeys, from container: KeyedDecodingContainer<CodingKeys>) -> Double {
        if let value = try? container.decode(String.self, forKey: key), let amount = Double(value) { return amount }
        return (try? container.decode(Double.self, forKey: key)) ?? 0
    }
}

struct DeepSeekBalanceResponse: Decodable, Equatable {
    /// False when the balance is too low to serve API calls.
    let isAvailable: Bool
    let balances: [DeepSeekBalance]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balances = "balance_infos"
    }

    init(isAvailable: Bool, balances: [DeepSeekBalance]) {
        self.isAvailable = isAvailable
        self.balances = balances
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .isAvailable) ?? true
        balances = try container.decodeIfPresent([DeepSeekBalance].self, forKey: .balances) ?? []
    }
}

struct DeepSeekClient {
    typealias RequestHandler = (URLRequest) async throws -> (Data, URLResponse)

    private let requestHandler: RequestHandler
    private let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.requestHandler = { request in try await session.data(for: request) }
    }

    init(requestHandler: @escaping RequestHandler) {
        self.requestHandler = requestHandler
    }

    func fetchSnapshot(apiKey: String, now: Date) async throws -> UsageSnapshot {
        let response = try await fetchBalance(apiKey: apiKey)
        var snapshot = UsageSnapshot()
        snapshot.deepSeekBalance = response
        snapshot.lastUpdated = now
        return snapshot
    }

    func fetchBalance(apiKey: String) async throws -> DeepSeekBalanceResponse {
        var request = URLRequest(url: balanceURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await requestHandler(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DeepSeekClientError.httpFailure
        }
        do { return try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data) }
        catch { throw DeepSeekClientError.invalidResponse }
    }
}

enum DeepSeekClientError: LocalizedError {
    case httpFailure
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .httpFailure: return String(localized: "DeepSeek request failed. Check the saved API key.")
        case .invalidResponse: return String(localized: "DeepSeek returned an invalid response")
        }
    }
}

struct DeepSeekUsageProvider: UsageProvider {
    let id: ProviderID = .deepseek
    let keySource: DeepSeekAPIKeyProviding
    let client: DeepSeekClient

    init(keySource: DeepSeekAPIKeyProviding = DeepSeekAPIKeyStore(), client: DeepSeekClient = DeepSeekClient()) {
        self.keySource = keySource
        self.client = client
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        guard let apiKey = keySource.apiKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty else {
            throw UsageError.notConfigured(String(localized: "DeepSeek API key not configured"))
        }
        return try await client.fetchSnapshot(apiKey: apiKey, now: now)
    }
}
