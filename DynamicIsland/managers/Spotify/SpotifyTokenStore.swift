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

enum SpotifyTokenAccount: String {
    case accessToken = "spotify-library-access-token"
    case refreshToken = "spotify-library-refresh-token"
}

protocol SpotifyTokenStoring: Sendable {
    func read(_ account: SpotifyTokenAccount) -> String?
    func write(_ value: String, account: SpotifyTokenAccount)
    func delete(_ account: SpotifyTokenAccount)
}

/// Keychain-backed storage for the OAuth token pair. The client ID and token
/// expiration are not secrets and stay in Defaults.
struct KeychainSpotifyTokenStore: SpotifyTokenStoring {
    private static let service = "com.Ebullioscopic.Atoll.SpotifyLibrary"

    private func baseQuery(for account: SpotifyTokenAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account.rawValue
        ]
    }

    func read(_ account: SpotifyTokenAccount) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String, account: SpotifyTokenAccount) {
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(for: account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = baseQuery(for: account)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    func delete(_ account: SpotifyTokenAccount) {
        SecItemDelete(baseQuery(for: account) as CFDictionary)
    }
}
