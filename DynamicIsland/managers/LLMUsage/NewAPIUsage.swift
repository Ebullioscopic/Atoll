import Foundation
import Defaults
import Security

struct NewAPIAccount: Codable, Defaults.Serializable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var baseURL: String

    init(id: UUID = UUID(), name: String, baseURL: String) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
    }
}

struct NewAPIAccountSnapshot: Equatable, Identifiable {
    let id: UUID
    let name: String
    let balanceQuota: Int?
    let usedQuota: Int?
    let requestCount: Int?
    let todayQuota: Int?
    let weekQuota: Int?
    let currentRPM: Int?
    let currentTPM: Int?
    let errorMessage: String?

    var isSuccessful: Bool { errorMessage == nil }
}

protocol NewAPIAccountProviding {
    func accounts() -> [NewAPIAccount]
    func apiKey(for account: NewAPIAccount) -> String?
}

enum NewAPIKeychain {
    private static let service = "com.Ebullioscopic.Atoll.new-api"

    static func read(accountID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ apiKey: String, accountID: UUID) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecSuccess || updateStatus == errSecItemNotFound else {
            throw NewAPIKeychainError(status: updateStatus)
        }
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw NewAPIKeychainError(status: addStatus) }
        }
    }

    static func delete(accountID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NewAPIKeychainError(status: status)
        }
    }
}

struct NewAPIKeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Unable to store the New API key (Keychain status \(status))." }
}

struct NewAPIAccountStore: NewAPIAccountProviding {
    func accounts() -> [NewAPIAccount] { Defaults[.newAPIAccounts] }

    func apiKey(for account: NewAPIAccount) -> String? {
        NewAPIKeychain.read(accountID: account.id)
    }

    static func upsert(_ account: NewAPIAccount, apiKey: String) throws {
        var account = account
        account.name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.baseURL = account.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.name.isEmpty else {
            throw NewAPIStoreError.invalidName
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = Defaults[.newAPIAccounts].contains { $0.id == account.id }
        let storedKey = NewAPIKeychain.read(accountID: account.id)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty && (!existing || storedKey?.isEmpty != false) {
            throw NewAPIStoreError.missingAPIKey
        }
        guard NewAPIClient.normalizedBaseURL(account.baseURL) != nil else {
            throw NewAPIStoreError.invalidBaseURL
        }
        if !trimmedKey.isEmpty {
            try NewAPIKeychain.save(trimmedKey, accountID: account.id)
        }
        var accounts = Defaults[.newAPIAccounts]
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        Defaults[.newAPIAccounts] = accounts
    }

    static func delete(_ account: NewAPIAccount) throws {
        try NewAPIKeychain.delete(accountID: account.id)
        var accounts = Defaults[.newAPIAccounts]
        accounts.removeAll { $0.id == account.id }
        Defaults[.newAPIAccounts] = accounts
    }
}

enum NewAPIStoreError: LocalizedError {
    case invalidName
    case missingAPIKey
    case invalidBaseURL

    var errorDescription: String? {
        switch self {
        case .invalidName: return "Enter a name for this account."
        case .missingAPIKey: return "Enter an API key for this account."
        case .invalidBaseURL: return "Enter a valid New API URL, including http:// or https://."
        }
    }
}

struct NewAPIClient {
    typealias RequestHandler = (URLRequest) async throws -> (Data, URLResponse)

    private let requestHandler: RequestHandler

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.requestHandler = { request in try await session.data(for: request) }
    }

    init(requestHandler: @escaping RequestHandler) {
        self.requestHandler = requestHandler
    }

    static func normalizedBaseURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil,
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        components?.path = path.isEmpty ? "" : "/\(path)"
        return components?.url
    }

    func fetchAccount(_ account: NewAPIAccount, apiKey: String, now: Date, calendar: Calendar = .current) async throws -> NewAPIAccountSnapshot {
        guard let baseURL = Self.normalizedBaseURL(account.baseURL) else {
            throw NewAPIClientError.invalidBaseURL
        }
        let selfData = try await request(path: "/api/user/self", baseURL: baseURL, apiKey: apiKey)
        let user = try decode(NewAPIEnvelope<NewAPIUser>.self, from: selfData)
        guard user.success, let userData = user.data else { throw NewAPIClientError.apiRequestFailed }

        let end = Int64(now.timeIntervalSince1970)
        let todayStart = Int64(calendar.startOfDay(for: now).timeIntervalSince1970)
        let weekStart = Int64(calendar.dateInterval(of: .weekOfYear, for: now)?.start.timeIntervalSince1970 ?? now.timeIntervalSince1970)
        let throughputStart = max(0, end - 60)

        async let todayStat = fetchStat(baseURL: baseURL, apiKey: apiKey, start: todayStart, end: end)
        async let weekStat = fetchStat(baseURL: baseURL, apiKey: apiKey, start: weekStart, end: end)
        async let throughputStat = fetchStat(baseURL: baseURL, apiKey: apiKey, start: throughputStart, end: end)

        var todayQuota: Int?
        var weekQuota: Int?
        var currentRPM: Int?
        var currentTPM: Int?
        var errorMessage: String?

        do {
            let stat = try await todayStat
            todayQuota = stat.quota
        } catch {
            errorMessage = "Daily usage unavailable"
        }

        do {
            let stat = try await weekStat
            weekQuota = stat.quota
        } catch {
            errorMessage = errorMessage ?? "Weekly usage unavailable"
        }

        do {
            let stat = try await throughputStat
            currentRPM = stat.rpm
            currentTPM = stat.tpm
        } catch {
            errorMessage = errorMessage ?? "Current throughput unavailable"
        }

        return NewAPIAccountSnapshot(
            id: account.id,
            name: account.name,
            balanceQuota: userData.quota,
            usedQuota: userData.usedQuota,
            requestCount: userData.requestCount,
            todayQuota: todayQuota,
            weekQuota: weekQuota,
            currentRPM: currentRPM,
            currentTPM: currentTPM,
            errorMessage: errorMessage
        )
    }

    private func fetchStat(baseURL: URL, apiKey: String, start: Int64, end: Int64) async throws -> NewAPIStat {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/log/self/stat"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "type", value: "2"),
            URLQueryItem(name: "start_timestamp", value: String(start)),
            URLQueryItem(name: "end_timestamp", value: String(end))
        ]
        guard let url = components?.url else { throw NewAPIClientError.invalidURL }
        let data = try await request(url: url, apiKey: apiKey)
        let response = try decode(NewAPIEnvelope<NewAPIStat>.self, from: data)
        guard response.success, let stat = response.data else { throw NewAPIClientError.apiRequestFailed }
        return stat
    }

    private func request(path: String, baseURL: URL, apiKey: String) async throws -> Data {
        try await request(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), apiKey: apiKey)
    }

    private func request(url: URL, apiKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await requestHandler(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NewAPIClientError.httpFailure
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw NewAPIClientError.invalidResponse }
    }
}

private struct NewAPIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
}

struct NewAPIUser: Decodable, Equatable {
    let quota: Int
    let usedQuota: Int
    let requestCount: Int

    init(quota: Int, usedQuota: Int, requestCount: Int) {
        self.quota = quota
        self.usedQuota = usedQuota
        self.requestCount = requestCount
    }

    enum CodingKeys: String, CodingKey {
        case quota
        case usedQuota = "used_quota"
        case requestCount = "request_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quota = try Self.decodeInt(forKey: .quota, from: container)
        usedQuota = try Self.decodeInt(forKey: .usedQuota, from: container)
        requestCount = try Self.decodeInt(forKey: .requestCount, from: container)
    }

    private static func decodeInt(forKey key: CodingKeys, from container: KeyedDecodingContainer<CodingKeys>) throws -> Int {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key), let int = Int(value) { return int }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(value) }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(codingPath: container.codingPath + [key], debugDescription: "Expected an integer or numeric string")
        )
    }
}

struct NewAPIStat: Decodable, Equatable {
    let quota: Int
    let rpm: Int
    let tpm: Int

    init(quota: Int, rpm: Int, tpm: Int) {
        self.quota = quota
        self.rpm = rpm
        self.tpm = tpm
    }

    enum CodingKeys: String, CodingKey {
        case quota
        case rpm
        case tpm
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quota = try Self.decodeInt(forKey: .quota, from: container)
        rpm = try Self.decodeInt(forKey: .rpm, from: container)
        tpm = try Self.decodeInt(forKey: .tpm, from: container)
    }

    private static func decodeInt(forKey key: CodingKeys, from container: KeyedDecodingContainer<CodingKeys>) throws -> Int {
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(String.self, forKey: key), let int = Int(value) { return int }
        if let value = try? container.decode(Double.self, forKey: key) { return Int(value) }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(codingPath: container.codingPath + [key], debugDescription: "Expected an integer or numeric string")
        )
    }
}

enum NewAPIClientError: LocalizedError {
    case invalidBaseURL
    case invalidURL
    case httpFailure
    case apiRequestFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "Invalid New API URL"
        case .invalidURL: return "Invalid New API request URL"
        case .httpFailure: return "New API request failed"
        case .apiRequestFailed: return "New API returned an unsuccessful response"
        case .invalidResponse: return "New API returned an invalid response"
        }
    }
}

struct NewAPIUsageProvider: UsageProvider {
    let id: ProviderID = .newAPI
    let accountSource: NewAPIAccountProviding
    let client: NewAPIClient

    init(accountSource: NewAPIAccountProviding = NewAPIAccountStore(), client: NewAPIClient = NewAPIClient()) {
        self.accountSource = accountSource
        self.client = client
    }

    func fetchSnapshot(now: Date) async throws -> UsageSnapshot {
        let accounts = accountSource.accounts()
        guard !accounts.isEmpty else { throw UsageError.notConfigured("No New API accounts configured") }

        let snapshots = await withTaskGroup(of: NewAPIAccountSnapshot.self, returning: [NewAPIAccountSnapshot].self) { group in
            for account in accounts {
                group.addTask {
                    guard let apiKey = accountSource.apiKey(for: account)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                          !apiKey.isEmpty else {
                        return NewAPIAccountSnapshot(id: account.id, name: account.name, balanceQuota: nil, usedQuota: nil, requestCount: nil, todayQuota: nil, weekQuota: nil, currentRPM: nil, currentTPM: nil, errorMessage: "API key not configured")
                    }
                    do {
                        return try await client.fetchAccount(account, apiKey: apiKey, now: now)
                    } catch {
                        return NewAPIAccountSnapshot(id: account.id, name: account.name, balanceQuota: nil, usedQuota: nil, requestCount: nil, todayQuota: nil, weekQuota: nil, currentRPM: nil, currentTPM: nil, errorMessage: error.localizedDescription)
                    }
                }
            }
            var result: [NewAPIAccountSnapshot] = []
            for await snapshot in group { result.append(snapshot) }
            return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        var snapshot = UsageSnapshot()
        snapshot.newAPIAccounts = snapshots
        snapshot.lastUpdated = now
        return snapshot
    }
}
