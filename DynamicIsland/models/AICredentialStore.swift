import Combine
import Foundation
import Security

/// Accounts are also the legacy preference names, used only during migration.
enum AICredentialProvider: String, CaseIterable {
    case gemini = "geminiApiKey"
    case openai = "openaiApiKey"
    case claude = "claudeApiKey"
    case deepseek = "deepseekApiKey"
    case groq = "groqApiKey"
}

/// Injectable persistence keeps migration tests away from the user's Keychain.
protocol AICredentialBackend {
    func read(_ provider: AICredentialProvider) throws -> String?
    func write(_ value: String, for provider: AICredentialProvider) throws
    func delete(_ provider: AICredentialProvider) throws
}

struct AICredentialError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        String(localized: "Could not access the API key in Keychain. Unlock your login keychain and try again.")
    }
}

enum AICredentialSaveError: LocalizedError {
    case conflict
    case partial(Error)

    var errorDescription: String? {
        switch self {
        case .conflict:
            return String(localized: "An API key changed in another window. Reopen model settings before saving to avoid overwriting it.")
        case .partial(let error):
            return String(format: String(localized: "Some API keys were already saved. The remaining configuration was not saved; cancelling will not undo those keys. %@"), error.localizedDescription)
        }
    }
}

/// Generic-password items are isolated by application identifier, including QA builds.
struct AIKeychainBackend: AICredentialBackend {
    let service: String

    private func query(_ provider: AICredentialProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }

    func read(_ provider: AICredentialProvider) throws -> String? {
        var attributes = query(provider)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AICredentialError(status: status) }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw AICredentialError(status: errSecDecode)
        }
        return value
    }

    func write(_ value: String, for provider: AICredentialProvider) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(provider) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query(provider)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw AICredentialError(status: added) }
        } else if status != errSecSuccess {
            throw AICredentialError(status: status)
        }
    }

    func delete(_ provider: AICredentialProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AICredentialError(status: status)
        }
    }
}

/// Serializes UI/request access and publishes only credentials successfully persisted.
/// Legacy provider callbacks synchronously read the cache off the main actor; all
/// backend operations and cache accesses therefore share one recursive lock.
/// A failed migration leaves the legacy value intact and reports a recoverable error.
final class AICredentialStore: ObservableObject, @unchecked Sendable {
    static let shared = AICredentialStore(
        backend: AIKeychainBackend(service: (Bundle.main.bundleIdentifier ?? "com.Ebullioscopic.Atoll") + ".AI"),
        preferences: .standard
    )

    let objectWillChange = ObservableObjectPublisher()
    private var keys: [AICredentialProvider: String] = [:]
    private var errorMessage: String?
    var lastError: String? {
        lock.lock()
        defer { lock.unlock() }
        return errorMessage
    }
    private let lock = NSRecursiveLock()
    private let backend: any AICredentialBackend
    private let preferences: UserDefaults

    init(backend: any AICredentialBackend, preferences: UserDefaults) {
        self.backend = backend
        self.preferences = preferences
        reload()
    }

    /// Retries unavailable Keychain reads and migrates all five old preference keys.
    func reload() {
        lock.lock()
        defer { lock.unlock() }
        objectWillChange.send()
        errorMessage = nil
        for provider in AICredentialProvider.allCases {
            do {
                let stored = try backend.read(provider)
                let legacy = preferences.string(forKey: provider.rawValue)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if let stored {
                    keys[provider] = stored
                } else if !legacy.isEmpty {
                    try backend.write(legacy, for: provider)
                    keys[provider] = legacy
                } else {
                    keys[provider] = ""
                }
                // A read failure must never look like a missing item and overwrite it.
                preferences.removeObject(forKey: provider.rawValue)
            } catch {
                keys.removeValue(forKey: provider)
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Returns a memory snapshot; SwiftUI rendering never starts a Keychain operation.
    func key(for provider: AICredentialProvider) -> String {
        lock.lock()
        defer { lock.unlock() }
        return keys[provider] ?? ""
    }

    /// Commits only edited fields, rejecting stale snapshots before any writes.
    /// Keychain has no multi-item transaction: a later failure explicitly reports
    /// partial persistence, and retrying skips values that were already saved.
    func saveChanges(_ values: [AICredentialProvider: String], original: [AICredentialProvider: String]) throws {
        lock.lock()
        defer { lock.unlock() }
        let changes = AICredentialProvider.allCases.compactMap { provider -> (AICredentialProvider, String)? in
            guard let input = values[provider] else { return nil }
            let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
            return value == (original[provider] ?? "") ? nil : (provider, value)
        }
        for (provider, value) in changes {
            let current = keys[provider] ?? ""
            guard current == (original[provider] ?? "") || current == value else {
                objectWillChange.send()
                errorMessage = AICredentialSaveError.conflict.localizedDescription
                throw AICredentialSaveError.conflict
            }
        }
        var saved = false
        do {
            for (provider, value) in changes where value != (keys[provider] ?? "") {
                try setKey(value, for: provider)
                saved = true
            }
        } catch {
            let reported = saved ? AICredentialSaveError.partial(error) : error
            objectWillChange.send()
            errorMessage = reported.localizedDescription
            throw reported
        }
    }

    /// Empty input deletes the item. Failed writes/deletes keep the prior value intact.
    func setKey(_ value: String, for provider: AICredentialProvider) throws {
        lock.lock()
        defer { lock.unlock() }
        objectWillChange.send()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty { try backend.delete(provider) }
            else { try backend.write(trimmed, for: provider) }
            keys[provider] = trimmed
            preferences.removeObject(forKey: provider.rawValue)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}
