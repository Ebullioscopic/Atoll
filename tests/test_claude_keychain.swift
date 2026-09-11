import Foundation
import Security
import Darwin

// Run scripts/test_claude_keychain.sh on macOS with an unlocked default login Keychain.
// Uses only UUID-named disposable credentials;
// it does not read, refresh, or modify any Claude login credential.
@main
enum ClaudeKeychainTests {
    static func main() throws {
        if CommandLine.arguments.contains("--closed-pipe") {
            // Do not inherit an ignored SIGPIPE from a shell or test harness.
            signal(SIGPIPE, SIG_DFL)
            let pipe = Pipe()
            try pipe.fileHandleForReading.close()
            try require(!ClaudeKeychainStore.writeInput(Data("fake-input".utf8), to: pipe.fileHandleForWriting),
                        "closed pipe must return failure without terminating the process")
            return
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--closed-pipe"]
        try child.run()
        child.waitUntilExit()
        try require(child.terminationReason == .exit && child.terminationStatus == 0,
                    "closed-pipe subprocess survives with default SIGPIPE handling")
        print("PASS: closed-pipe write returns failure without SIGPIPE termination")
        try requireLoginKeychain()

        let service = "Atoll-keychain-regression-\(UUID().uuidString)"
        let account = "test \"account\" \\ unicode-中文"
        let otherAccount = "other-account"
        defer {
            for name in [account, otherAccount] {
                _ = security(["delete-generic-password", "-s", service, "-a", name])
            }
        }

        for name in [account, otherAccount] {
            try require(security(["add-generic-password", "-s", service, "-a", name, "-w", "fake-seed"]).status == 0,
                    "create disposable credential")
        }
        try require(ClaudeKeychainStore.read(service: service, account: account) == "fake-seed", "initial read")
        let initialPartitions = try partitionIDs(service: service, account: account)
        try require(initialPartitions.contains("apple-tool:"), "initial Apple tool permission")

        let secret = #"{"claudeAiOauth":{"accessToken":"FAKE-not-a-token","refreshToken":"FAKE-refresh","expiresAt":42},"mcpOAuth":{"note":"quotes: \" backslash: \\ unicode: 中文"}}"#
        for cycle in 1...3 {
            let updated = secret + String(repeating: " ", count: cycle)
            try require(ClaudeKeychainStore.update(service: service, account: account, secret: updated) == nil, "Atoll write \(cycle)")
            let actual = ClaudeKeychainStore.read(service: service, account: account)
            try require(actual == updated, "exact round trip \(cycle)")
            try require(try partitionIDs(service: service, account: account) == initialPartitions, "partitions survive Atoll write \(cycle)")

            let ownerValue = "fake-owner-refresh-\(cycle)"
            try require(security(["add-generic-password", "-U", "-s", service, "-a", account, "-w", ownerValue]).status == 0,
                    "Claude-style owner write \(cycle)")
            try require(ClaudeKeychainStore.read(service: service, account: account) == ownerValue, "read owner refresh \(cycle)")
            try require(try partitionIDs(service: service, account: account) == initialPartitions, "partitions survive owner write \(cycle)")
        }
        try require(ClaudeKeychainStore.read(service: service, account: otherAccount) == "fake-seed", "other account unchanged")
        try require(ClaudeKeychainStore.update(service: service, account: "missing", secret: "fake") == errSecItemNotFound,
                "missing account rejected")
        try require(security(["find-generic-password", "-s", service, "-a", "missing"]).status != 0, "missing account not created")
        try require(ClaudeKeychainStore.updateCommand(service: service, account: account, secret: String(repeating: "x", count: 4096)) == nil,
                "oversized input rejected")
        try require(ClaudeKeychainStore.updateCommand(service: service, account: account, secret: "fake\nadd-generic-password") == nil,
                "command injection rejected")
        try require(ClaudeKeychainStore.updateCommand(service: service, account: nil, secret: "fake") == nil,
                "unscoped update rejected")
        print("PASS: three Atoll/owner round trips, unchanged partition permissions, exact payload, account isolation, missing/oversized/invalid input")
    }

    /// Refuses unavailable or locked test environments before creating any item.
    private static func requireLoginKeychain() throws {
        var keychain: SecKeychain?
        try require(SecKeychainCopyDefault(&keychain) == errSecSuccess, "default login Keychain required")
        var path = [CChar](repeating: 0, count: Int(PATH_MAX))
        var length = UInt32(path.count)
        try require(SecKeychainGetPath(keychain, &length, &path) == errSecSuccess, "read default Keychain path")
        let name = URL(fileURLWithPath: String(cString: path)).lastPathComponent
        try require(name == "login.keychain-db" || name == "login.keychain", "default Keychain must be login")
        var status: SecKeychainStatus = 0
        let required = UInt32(kSecUnlockStateStatus | kSecReadPermStatus | kSecWritePermStatus)
        try require(SecKeychainGetStatus(keychain, &status) == errSecSuccess && status & required == required,
                    "login Keychain must be unlocked, readable, and writable")
    }

    private static func partitionIDs(service: String, account: String) throws -> Set<String> {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: account,
                                   kSecReturnRef as String: true]
        var result: CFTypeRef?
        try require(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, "test item metadata")
        var access: SecAccess?
        try require(SecKeychainItemCopyAccess(result as! SecKeychainItem, &access) == errSecSuccess, "test item ACL")
        let acls = SecAccessCopyMatchingACLList(access!, kSecACLAuthorizationPartitionID) as? [SecACL] ?? []
        var ids = Set<String>()
        for acl in acls {
            var apps: CFArray?, description: CFString?
            var prompt = SecKeychainPromptSelector()
            try require(SecACLCopyContents(acl, &apps, &description, &prompt) == errSecSuccess, "partition contents")
            let hex = description! as String
            var data = Data()
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2)
                data.append(UInt8(hex[index..<next], radix: 16)!)
                index = next
            }
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
            ids.formUnion(plist["Partitions"] as? [String] ?? [])
        }
        return ids
    }

    private static func security(_ arguments: [String]) -> (status: Int32, output: Data) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        do { try task.run() } catch { return (-1, Data()) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, data)
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "ClaudeKeychainTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
