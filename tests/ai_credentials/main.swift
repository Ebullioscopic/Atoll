import Foundation
import Security

final class MemoryBackend: AICredentialBackend {
    var values: [AICredentialProvider: String] = [:]
    var failRead = false
    var failWrite = false
    var failDelete = false
    var failedProvider: AICredentialProvider?
    var writes = 0
    func read(_ provider: AICredentialProvider) throws -> String? {
        if failRead { throw AICredentialError(status: errSecInteractionNotAllowed) }
        return values[provider]
    }
    func write(_ value: String, for provider: AICredentialProvider) throws {
        writes += 1
        if failWrite || provider == failedProvider { throw AICredentialError(status: errSecAuthFailed) }
        values[provider] = value
    }
    func delete(_ provider: AICredentialProvider) throws {
        if failDelete { throw AICredentialError(status: errSecAuthFailed) }
        values.removeValue(forKey: provider)
    }
}

var checks = 0
func check(_ value: Bool, _ message: String) {
    checks += 1
    precondition(value, message)
}

MainActor.assumeIsolated {
    let suite = "atoll-credential-tests-" + UUID().uuidString
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    let backend = MemoryBackend()
    for provider in AICredentialProvider.allCases {
        preferences.set("  fixture-\(provider.rawValue)  ", forKey: provider.rawValue)
    }
    let store = AICredentialStore(backend: backend, preferences: preferences)
    for provider in AICredentialProvider.allCases {
        check(backend.values[provider] == "fixture-\(provider.rawValue)", "Every provider migrates")
        check(store.key(for: provider) == backend.values[provider], "Cache follows persisted value")
        check(preferences.object(forKey: provider.rawValue) == nil, "Plaintext removed after persistence")
    }
    check(store.lastError == nil, "Successful migration has no error")
    preferences.set("stale", forKey: AICredentialProvider.deepseek.rawValue)
    store.reload()
    check(store.key(for: .deepseek) == "fixture-deepseekApiKey", "Existing Keychain item wins over stale preferences")
    check(preferences.object(forKey: "deepseekApiKey") == nil, "Stale copy removed")
    backend.values.removeValue(forKey: .deepseek)
    preferences.set("keep-on-failure", forKey: "deepseekApiKey")
    backend.failWrite = true
    store.reload()
    check(preferences.string(forKey: "deepseekApiKey") == "keep-on-failure", "Failed migration preserves the only copy")
    check(store.lastError != nil, "Migration failure surfaced")
    check(store.key(for: .deepseek).isEmpty, "Failed migration isn't published as persisted")
    backend.failWrite = false
    store.reload()
    check(store.key(for: .deepseek) == "keep-on-failure", "Migration retries after unlock")
    check(preferences.object(forKey: "deepseekApiKey") == nil, "Retry removes migrated preference")
    backend.failRead = true
    preferences.set("must-not-overwrite", forKey: "deepseekApiKey")
    let writes = backend.writes
    store.reload()
    check(backend.writes == writes, "Unavailable Keychain must not be treated as missing")
    check(preferences.string(forKey: "deepseekApiKey") == "must-not-overwrite", "Read error preserves fallback")
    check(store.lastError != nil, "Read error visible")
    backend.failRead = false
    store.reload()
    try! store.setKey(" new-value \n", for: .deepseek)
    check(backend.values[.deepseek] == "new-value", "Save trims input")
    check(preferences.object(forKey: "deepseekApiKey") == nil, "Save never writes plaintext")
    backend.failWrite = true
    do { try store.setKey("lost-value", for: .deepseek); preconditionFailure("Write should fail") } catch {}
    check(store.key(for: .deepseek) == "new-value", "Failed save retains cache")
    check(backend.values[.deepseek] == "new-value", "Failed save retains durable value")
    check(store.lastError != nil, "Failed save reported")
    backend.failWrite = false
    backend.failDelete = true
    do { try store.setKey("", for: .deepseek); preconditionFailure("Delete should fail") } catch {}
    check(store.key(for: .deepseek) == "new-value", "Failed delete keeps key")
    backend.failDelete = false
    try! store.setKey(" \n", for: .deepseek)
    check(backend.values[.deepseek] == nil && store.key(for: .deepseek).isEmpty, "Clear deletes item")
    check(store.lastError == nil, "Successful retry clears error")
    let relaunched = AICredentialStore(backend: backend, preferences: preferences)
    check(relaunched.key(for: .deepseek).isEmpty, "Deleted key stays deleted after restart")
    check(relaunched.key(for: .openai) == "fixture-openaiApiKey", "Other credentials survive restart")
    func snapshot() -> [AICredentialProvider: String] {
        Dictionary(uniqueKeysWithValues: AICredentialProvider.allCases.map { ($0, store.key(for: $0)) })
    }
    let initial = snapshot()
    try! store.setKey("other-window", for: .gemini)
    var form = initial
    form[.deepseek] = "edited-deepseek"
    try! store.saveChanges(form, original: initial)
    check(store.key(for: .gemini) == "other-window", "Untouched stale fields never overwrite another window")
    check(store.key(for: .deepseek) == "edited-deepseek", "Edited field is saved")
    let beforeConflict = snapshot()
    try! store.setKey("newer-openai", for: .openai)
    var conflicting = beforeConflict
    conflicting[.gemini] = "must-not-partially-save"
    conflicting[.openai] = "stale-openai-edit"
    do {
        try store.saveChanges(conflicting, original: beforeConflict)
        preconditionFailure("Conflicting edit should fail")
    } catch AICredentialSaveError.conflict {} catch { preconditionFailure("Expected conflict") }
    check(store.key(for: .gemini) == "other-window", "All conflicts checked before any write")
    check(store.key(for: .openai) == "newer-openai", "Conflicting key preserved")
    let beforePartial = snapshot()
    var partial = beforePartial
    partial[.gemini] = "applied-gemini"
    partial[.openai] = "pending-openai"
    backend.failedProvider = .openai
    do {
        try store.saveChanges(partial, original: beforePartial)
        preconditionFailure("Second item should fail")
    } catch AICredentialSaveError.partial {} catch { preconditionFailure("Partial save must be explicit") }
    check(store.key(for: .gemini) == "applied-gemini", "Partial save reports actual persisted first item")
    check(store.key(for: .openai) == "newer-openai", "Failed second item unchanged")
    backend.failedProvider = nil
    let writesBeforeRetry = backend.writes
    try! store.saveChanges(partial, original: beforePartial)
    check(backend.writes == writesBeforeRetry + 1, "Retry skips already-applied fields")
    check(store.key(for: .openai) == "pending-openai", "Retry persists remaining item")
    try! store.setKey("fixture-openaiApiKey", for: .openai)
    // Legacy networking reads concurrently with settings updates; every snapshot
    // must be a complete persisted value. The fake backend is accessed only by the store.
    let group = DispatchGroup()
    for _ in 0..<4 {
        DispatchQueue.global().async(group: group) {
            for _ in 0..<500 {
                let value = store.key(for: .openai)
                precondition(value == "fixture-openaiApiKey" || value == "replacement")
                _ = store.lastError
            }
        }
    }
    try! store.setKey("replacement", for: .openai)
    group.wait()
    check(store.key(for: .openai) == "replacement", "Concurrent readers and settings writes share a lock")
}
print("AI credentials: \(checks) checks passed (isolated fake backend)")
