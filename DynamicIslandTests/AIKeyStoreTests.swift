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

import Defaults
import Security
import XCTest
@testable import Atoll

/// Covers the one-time Defaults → Keychain move for the AI provider keys. The
/// store is injectable, so none of this touches the real Keychain.
@MainActor
final class AIKeyStoreTests: XCTestCase {

    // MARK: - Fake

    private final class FakeAIKeyStore: AIKeyStoring, @unchecked Sendable {
        var storage: [AIKeyAccount: String] = [:]
        /// When non-nil, write() reports this status and stores nothing, so tests
        /// can exercise the failed-Keychain-write path.
        var writeFailure: OSStatus?

        func read(_ account: AIKeyAccount) -> String? { storage[account] }

        @discardableResult
        func write(_ value: String, account: AIKeyAccount) -> OSStatus {
            if let writeFailure { return writeFailure }
            storage[account] = value
            return errSecSuccess
        }

        @discardableResult
        func delete(_ account: AIKeyAccount) -> OSStatus {
            storage[account] = nil
            return errSecSuccess
        }
    }

    private let legacyKeys: [Defaults.Key<String>] = [
        .geminiApiKey, .openaiApiKey, .claudeApiKey, .groqApiKey
    ]

    /// The test host is the real app, so these tests share the user's Defaults
    /// domain. Whatever was there is put back, or running the suite on a machine
    /// that has not migrated yet would destroy real API keys.
    private var savedLegacyValues: [String] = []

    override func setUp() {
        super.setUp()
        savedLegacyValues = legacyKeys.map { Defaults[$0] }
        legacyKeys.forEach { Defaults[$0] = "" }
    }

    override func tearDown() {
        for (key, saved) in zip(legacyKeys, savedLegacyValues) {
            Defaults[key] = saved
        }
        savedLegacyValues = []
        super.tearDown()
    }

    // MARK: - Migration

    func testMigrationMovesEveryLegacyKeyAndClearsDefaults() {
        Defaults[.geminiApiKey] = "gemini-secret"
        Defaults[.openaiApiKey] = "openai-secret"
        Defaults[.claudeApiKey] = "claude-secret"
        Defaults[.groqApiKey] = "groq-secret"
        let store = FakeAIKeyStore()

        Defaults.Keys.migrateAIProviderKeysToKeychain(store: store)

        XCTAssertEqual(store.read(.gemini), "gemini-secret")
        XCTAssertEqual(store.read(.openai), "openai-secret")
        XCTAssertEqual(store.read(.claude), "claude-secret")
        XCTAssertEqual(store.read(.groq), "groq-secret")
        for key in legacyKeys {
            XCTAssertEqual(Defaults[key], "", "the plaintext copy must not survive a successful move")
        }
    }

    /// Migration runs on every launch, so a stale Defaults value left over from a
    /// partial migration would otherwise restore an old credential over the
    /// working one — once per launch, silently.
    func testMigrationNeverOverwritesAKeyAlreadyInTheKeychain() {
        let store = FakeAIKeyStore()
        XCTAssertEqual(store.write("current-key", account: .gemini), errSecSuccess)
        Defaults[.geminiApiKey] = "stale-key"

        Defaults.Keys.migrateAIProviderKeysToKeychain(store: store)

        XCTAssertEqual(store.read(.gemini), "current-key", "the Keychain copy is the current one")
        XCTAssertEqual(Defaults[.geminiApiKey], "", "the stale plaintext copy must still be cleared")
    }

    /// The whole point of checking the Keychain status: a failed write must never
    /// leave the user with no copy of their key at all.
    func testMigrationKeepsDefaultsCopyWhenKeychainWriteFails() {
        Defaults[.geminiApiKey] = "gemini-secret"
        let store = FakeAIKeyStore()
        store.writeFailure = errSecIO

        Defaults.Keys.migrateAIProviderKeysToKeychain(store: store)

        XCTAssertNil(store.read(.gemini))
        XCTAssertEqual(Defaults[.geminiApiKey], "gemini-secret")
    }

    /// A failed migration is retried on the next launch rather than being latched
    /// off by a completion flag.
    func testMigrationRetriesAfterAnEarlierFailure() {
        Defaults[.geminiApiKey] = "gemini-secret"
        let store = FakeAIKeyStore()
        store.writeFailure = errSecIO
        Defaults.Keys.migrateAIProviderKeysToKeychain(store: store)

        store.writeFailure = nil
        Defaults.Keys.migrateAIProviderKeysToKeychain(store: store)

        XCTAssertEqual(store.read(.gemini), "gemini-secret")
        XCTAssertEqual(Defaults[.geminiApiKey], "")
    }

    func testMigrationSkipsBlankLegacyValues() {
        Defaults[.openaiApiKey] = "   \n "
        let store = FakeAIKeyStore()

        Defaults.Keys.migrateAIProviderKeysToKeychain(store: store)

        XCTAssertTrue(store.storage.isEmpty, "whitespace is not a key and must not be written")
    }

    func testMigrationTrimsSurroundingWhitespace() {
        Defaults[.claudeApiKey] = "  claude-secret\n"
        let store = FakeAIKeyStore()

        Defaults.Keys.migrateAIProviderKeysToKeychain(store: store)

        XCTAssertEqual(store.read(.claude), "claude-secret")
    }

    func testMigrationIsANoOpOnAFreshInstall() {
        let store = FakeAIKeyStore()

        Defaults.Keys.migrateAIProviderKeysToKeychain(store: store)

        XCTAssertTrue(store.storage.isEmpty)
    }

    // MARK: - Store conveniences

    func testSaveTrimsTheValue() {
        let store = FakeAIKeyStore()

        store.save("  groq-secret  ", account: .groq)

        XCTAssertEqual(store.read(.groq), "groq-secret")
        XCTAssertTrue(store.hasKey(.groq))
    }

    /// Clearing the field in the UI must remove the item, not leave the previous
    /// secret behind.
    func testSaveWithABlankValueDeletesTheStoredKey() {
        let store = FakeAIKeyStore()
        store.save("gemini-secret", account: .gemini)

        store.save("   ", account: .gemini)

        XCTAssertNil(store.read(.gemini))
        XCTAssertFalse(store.hasKey(.gemini))
    }

    func testValueReportsAnEmptyStringForAMissingKey() {
        let store = FakeAIKeyStore()

        XCTAssertEqual(store.value(.openai), "")
        XCTAssertFalse(store.hasKey(.openai))
    }

    // MARK: - Provider mapping

    func testEveryKeyedProviderMapsToItsOwnAccount() {
        XCTAssertEqual(AIModelProvider.gemini.keyAccount, .gemini)
        XCTAssertEqual(AIModelProvider.openai.keyAccount, .openai)
        XCTAssertEqual(AIModelProvider.claude.keyAccount, .claude)
        XCTAssertEqual(AIModelProvider.groq.keyAccount, .groq)
    }

    /// Local models run without a key; a nil account is what lets the send path
    /// skip the "no API key" alert.
    func testLocalProviderHasNoKeyAccount() {
        XCTAssertNil(AIModelProvider.local.keyAccount)
    }

    func testKeyAccountsAreDistinct() {
        let accounts = AIKeyAccount.allCases.map(\.rawValue)
        XCTAssertEqual(Set(accounts).count, accounts.count)
    }
}
