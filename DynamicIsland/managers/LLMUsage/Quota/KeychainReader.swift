import Foundation
import Security

enum KeychainReader {
    static func genericPassword(service: String, account: String? = nil) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let account { query[kSecAttrAccount as String] = account } // only filter by account when given
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // Read the secret of the most-recently-modified generic password whose service starts
    // with `servicePrefix`. Claude Code namespaces its credential item by a per-install hash
    // ("Claude Code-credentials-<hash>") and rotates it, leaving the un-suffixed item stale;
    // following the freshest item keeps quota working across that migration without hardcoding
    // a hash. The enumeration requests attributes only (no kSecReturnData), so decrypting — and
    // the Keychain access prompt it triggers — happens exactly once, for the chosen item.
    static func freshestGenericPassword(servicePrefix: String) -> (service: String, secret: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return nil }

        let freshest = items
            .compactMap { attrs -> (service: String, modified: Date)? in
                guard let service = attrs[kSecAttrService as String] as? String,
                      service.hasPrefix(servicePrefix),
                      let modified = attrs[kSecAttrModificationDate as String] as? Date
                else { return nil }
                return (service, modified)
            }
            .max { $0.modified < $1.modified }

        guard let freshest, let secret = genericPassword(service: freshest.service) else { return nil }
        return (freshest.service, secret)
    }

    /// Replace the secret of an existing generic password. Returns nil on success, else the
    /// OSStatus — errSecItemNotFound when the item is gone, errSecAuthFailed /
    /// errSecInteractionNotAllowed when its ACL does not admit this app. Never adds an item:
    /// a second item under the same service would not be the one Claude Code reads.
    static func updateGenericPassword(service: String, secret: String) -> OSStatus? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let attributes: [String: Any] = [kSecValueData as String: Data(secret.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        return status == errSecSuccess ? nil : status
    }
}
