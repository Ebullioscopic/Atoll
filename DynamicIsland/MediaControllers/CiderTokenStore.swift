//
//  CiderTokenStore.swift
//  DynamicIsland
//
//  Keychain storage for the Cider app token.
//

import Foundation
import Security
import Defaults

/// The Cider app token, kept in the Keychain rather than in `Defaults`.
///
/// It is a credential: anything holding it can drive the user's Cider, and the
/// `Defaults` backend is a preferences plist that any process running as the
/// user can read. Spotify's tokens already live in the Keychain for the same
/// reason.
///
/// The value is cached in memory because it is read on the way out of every
/// favourite request, and a Keychain round trip per request would put a lock
/// on whichever thread the request happened to start from.
final class CiderTokenStore: @unchecked Sendable {
    static let shared = CiderTokenStore()

    private static let service = "com.Ebullioscopic.Atoll.Cider"
    private static let account = "appToken"

    private let lock = NSLock()
    private var cached: String?

    private init() {
        cached = Self.readFromKeychain()

        // Anyone who entered a token before it moved to the Keychain has it
        // sitting in the preferences plist. Carry it across and clear it there
        // -- leaving the plaintext copy behind would make the move pointless.
        let legacy = Defaults[.ciderAPIToken].trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacy.isEmpty {
            if cached == nil {
                cached = legacy
                Self.writeToKeychain(legacy)
            }
            Defaults[.ciderAPIToken] = ""
        }
    }

    var token: String {
        lock.lock()
        defer { lock.unlock() }
        return cached ?? ""
    }

    /// Writing an empty string removes the item rather than storing a blank
    /// one, so clearing the field in settings actually forgets the token.
    func setToken(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        cached = trimmed.isEmpty ? nil : trimmed
        lock.unlock()

        if trimmed.isEmpty {
            Self.deleteFromKeychain()
        } else {
            Self.writeToKeychain(trimmed)
        }
    }

    // MARK: - Keychain

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readFromKeychain() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    @discardableResult
    private static func writeToKeychain(_ value: String) -> OSStatus {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]

        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return status }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    @discardableResult
    private static func deleteFromKeychain() -> OSStatus {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}
