import Foundation
import Security

/// An explicitly supplied token, scoped to its GitHub host. Never stored in Defaults.
enum CopilotTokenStore {
    private static let service = "com.Ebullioscopic.Atoll.copilot-usage"
    private static func query(host: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrSynchronizable as String: false,
         kSecAttrAccount as String: host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
    static func read(host: String) -> String? {
        var query = query(host: host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String, host: String) throws {
        _ = try CopilotEndpoint.url(host: host)
        guard CopilotTokenValidation.isValid(token) else { throw CopilotQuotaError.notConfigured }
        let query = query(host: host)
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw StoreError(status: added) }
        } else if status != errSecSuccess { throw StoreError(status: status) }
    }
    static func delete(host: String) throws {
        let status = SecItemDelete(query(host: host) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError(status: status) }
    }
    private struct StoreError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { String(localized: "Copilot credential storage failed (Keychain status \(status)).") }
    }
}
