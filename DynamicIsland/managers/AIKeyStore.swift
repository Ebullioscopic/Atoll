/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import Security

/// The AI providers whose API keys Atoll stores. `.local` needs no key and is
/// deliberately absent.
enum AIKeyAccount: String, CaseIterable {
    case gemini = "gemini-api-key"
    case openai = "openai-api-key"
    case claude = "claude-api-key"
    case groq = "groq-api-key"
}

extension AIModelProvider {
    /// The Keychain account holding this provider's API key, or `nil` for
    /// providers that need none.
    var keyAccount: AIKeyAccount? {
        switch self {
        case .gemini: return .gemini
        case .openai: return .openai
        case .claude: return .claude
        case .groq: return .groq
        case .local: return nil
        }
    }
}

protocol AIKeyStoring: Sendable {
    func read(_ account: AIKeyAccount) -> String?
    /// Returns the Keychain status; `errSecSuccess` means the value is stored.
    /// Callers that then discard the source (the Defaults migration) must check
    /// this before dropping the only remaining copy of the key.
    @discardableResult func write(_ value: String, account: AIKeyAccount) -> OSStatus
    @discardableResult func delete(_ account: AIKeyAccount) -> OSStatus
}

extension AIKeyStoring {
    /// Convenience for the many call sites that treat "no key" and "empty key"
    /// identically.
    func value(_ account: AIKeyAccount) -> String {
        read(account) ?? ""
    }

    func hasKey(_ account: AIKeyAccount) -> Bool {
        !value(account).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Stores a trimmed key, or removes the item when the value is blank, so
    /// clearing a field in the UI does not leave a stale secret behind.
    @discardableResult
    func save(_ value: String, account: AIKeyAccount) -> OSStatus {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? delete(account) : write(trimmed, account: account)
    }
}

/// Keychain-backed storage for the AI provider API keys. Mirrors
/// `KeychainSpotifyTokenStore`; the selected provider and model are not secrets
/// and stay in Defaults.
struct KeychainAIKeyStore: AIKeyStoring {
    static let shared = KeychainAIKeyStore()

    private static let service = "com.Ebullioscopic.Atoll.AIProviderKeys"

    private func baseQuery(for account: AIKeyAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account.rawValue
        ]
    }

    func read(_ account: AIKeyAccount) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func write(_ value: String, account: AIKeyAccount) -> OSStatus {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(for: account) as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else {
            return status
        }
        var attributes = baseQuery(for: account)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    @discardableResult
    func delete(_ account: AIKeyAccount) -> OSStatus {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        // Nothing stored is a successful end state for a delete.
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}
