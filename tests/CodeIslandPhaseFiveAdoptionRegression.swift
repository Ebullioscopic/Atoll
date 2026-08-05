import CodeIslandCore
import CodeIslandRuntime
import Foundation

private enum AdoptionRegressionFailure: Error {
    case failed(String)
}

private func assertThat(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw AdoptionRegressionFailure.failed(message) }
}

@main
private struct CodeIslandPhaseFiveAdoptionRegression {
    static func main() throws {
        try verifyReversibleLegacyAdoption()
        try verifyMissingConfigurationStillRestoresAdoptedHooks()
        try verifyReceiptOwnedRepairAndModifiedHelperRefusal()
    }

    private static func verifyReversibleLegacyAdoption() throws {
        let fixture = try AdoptionFixture()
        defer { fixture.remove() }
        let installer = CodexManagedInstallation(managedRootURL: fixture.managedRoot)

        let receipt = try installer.install(plan: fixture.plan)
        try installer.verify(receipt: receipt)
        var installed = try fixture.readHooks()
        let managedRootPermissions = try permissions(at: fixture.managedRoot)
        let managedBridgePermissions = try permissions(at: fixture.managedBridge)
        let managedReceiptPermissions = try permissions(at: fixture.managedReceipt)

        try assertThat(
            managedRootPermissions == 0o700,
            "Atoll's managed integration directory must be user-only"
        )
        try assertThat(
            managedBridgePermissions == 0o700,
            "Atoll's installed helper must be user-executable only"
        )
        try assertThat(
            managedReceiptPermissions == 0o600,
            "the ownership receipt and legacy-hook backup must be user-only"
        )
        try assertThat(
            receipt.managedCommand.contains("--socket '\(fixture.socket.path)'"),
            "managed helper must receive the exact disclosed listener path"
        )
        try assertThat(legacyCommandCount(in: installed) == 0, "recognized legacy handlers must not run concurrently")
        try assertThat(commandCount("/usr/local/bin/user-hook", in: installed) == 1, "unrelated hooks must be preserved")

        var hooks = installed["hooks"] as! [String: Any]
        var groups = hooks["SessionStart"] as! [[String: Any]]
        groups.append(["hooks": [[
            "type": "command",
            "command": "/usr/local/bin/added-after-activation",
        ]]])
        hooks["SessionStart"] = groups
        installed["hooks"] = hooks
        try fixture.writeHooks(installed)

        try installer.remove(receipt: receipt)
        let restored = try fixture.readHooks()
        try assertThat(legacyCommandCount(in: restored) == 2, "deactivation must restore each adopted legacy handler")
        try assertThat(commandCount("/usr/local/bin/user-hook", in: restored) == 1, "pre-existing unrelated hook must survive")
        try assertThat(
            commandCount("/usr/local/bin/added-after-activation", in: restored) == 1,
            "deactivation must preserve concurrent user changes"
        )
        try assertThat(commandCount(receipt.managedCommand, in: restored) == 0, "Atoll handler must be removed exactly")
    }

    private static func verifyMissingConfigurationStillRestoresAdoptedHooks() throws {
        let fixture = try AdoptionFixture()
        defer { fixture.remove() }
        let installer = CodexManagedInstallation(managedRootURL: fixture.managedRoot)
        let receipt = try installer.install(plan: fixture.plan)

        try FileManager.default.removeItem(at: fixture.hooks)
        try installer.remove(receipt: receipt)

        let restored = try fixture.readHooks()
        try assertThat(
            legacyCommandCount(in: restored) == 2,
            "deactivation must not discard the receipt-owned legacy backup when hooks.json is missing"
        )
        try assertThat(
            !FileManager.default.fileExists(atPath: fixture.managedReceipt.path),
            "successful restoration must retire the Atoll ownership receipt"
        )
    }

    private static func verifyReceiptOwnedRepairAndModifiedHelperRefusal() throws {
        let fixture = try AdoptionFixture()
        defer { fixture.remove() }
        let installer = CodexManagedInstallation(managedRootURL: fixture.managedRoot)
        let receipt = try installer.install(plan: fixture.plan)

        var root = try fixture.readHooks()
        var hooks = root["hooks"] as! [String: Any]
        var groups = hooks["SessionStart"] as! [[String: Any]]
        groups.removeAll { commandCount(receipt.managedCommand, in: $0) > 0 }
        hooks["SessionStart"] = groups
        root["hooks"] = hooks
        try fixture.writeHooks(root)
        try FileManager.default.removeItem(at: fixture.managedBridge)
        let updatedBridge = Data("#!/bin/sh\n# updated\nexit 0\n".utf8)
        try updatedBridge.write(to: fixture.bundledBridge)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: fixture.bundledBridge.path
        )

        let repaired = try installer.repair(receipt: receipt, plan: fixture.plan)
        try installer.verify(receipt: repaired)
        let repairedBridgeData = try Data(contentsOf: fixture.managedBridge)
        try assertThat(repairedBridgeData == updatedBridge, "repair must refresh an Atoll-owned missing helper")
        let repairedHooks = try fixture.readHooks()
        try assertThat(commandCount(repaired.managedCommand, in: repairedHooks) == 2, "repair must restore exact missing handlers")

        try Data("externally modified".utf8).write(to: fixture.managedBridge)
        do {
            _ = try installer.repair(receipt: repaired, plan: fixture.plan)
            throw AdoptionRegressionFailure.failed("repair must not overwrite an externally modified helper")
        } catch let error as CodexManagedInstallationError {
            try assertThat(error == .managedBridgeModified, "modified helper must fail closed")
        }
    }

    private static func legacyCommandCount(in value: Any) -> Int {
        if let dictionary = value as? [String: Any] {
            let own: Int
            if dictionary["type"] as? String == "command",
               let command = dictionary["command"] as? String,
               command.contains("/.codeisland/codeisland-") {
                own = 1
            } else {
                own = 0
            }
            return own + dictionary.values.reduce(0) { $0 + legacyCommandCount(in: $1) }
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + legacyCommandCount(in: $1) }
        }
        return 0
    }

    private static func commandCount(_ command: String, in value: Any) -> Int {
        if let dictionary = value as? [String: Any] {
            let own = dictionary["type"] as? String == "command"
                && dictionary["command"] as? String == command ? 1 : 0
            return own + dictionary.values.reduce(0) { $0 + commandCount(command, in: $1) }
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + commandCount(command, in: $1) }
        }
        return 0
    }

    private static func permissions(at url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions]
        guard let permissions = value as? NSNumber else {
            throw AdoptionRegressionFailure.failed("missing POSIX permissions for \(url.path)")
        }
        return permissions.intValue
    }
}

private final class AdoptionFixture {
    let root: URL
    let hooks: URL
    let bundledBridge: URL
    let managedRoot: URL
    let managedBridge: URL
    let managedReceipt: URL
    let socket: URL
    let plan: CodeIslandInstallationPlan

    init() throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        hooks = root.appendingPathComponent(".codex/hooks.json")
        bundledBridge = root.appendingPathComponent("Atoll.app/Contents/Helpers/codeisland-bridge")
        managedRoot = root.appendingPathComponent("Library/Application Support/Atoll/CodeIsland", isDirectory: true)
        managedBridge = managedRoot.appendingPathComponent("codeisland-bridge")
        managedReceipt = managedRoot.appendingPathComponent("codex-installation.json")
        socket = root.appendingPathComponent("listener path/observations.sock")

        try fileManager.createDirectory(at: hooks.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: bundledBridge.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bundledBridge)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bundledBridge.path)
        let originalHooks: [String: Any] = [
            "description": "preserve",
            "hooks": [
                "SessionStart": [
                    ["matcher": "", "hooks": [[
                        "type": "command",
                        "command": "/Users/example/.codeisland/codeisland-bridge --source codex",
                        "timeout": 2,
                    ], [
                        "type": "command",
                        "command": "/usr/local/bin/user-hook",
                    ]]],
                ],
                "PermissionRequest": [
                    ["hooks": [[
                        "type": "command",
                        "command": "/Users/example/.codeisland/codeisland-hook.sh",
                    ]]],
                ],
            ],
        ]
        let hookData = try JSONSerialization.data(
            withJSONObject: originalHooks,
            options: [.prettyPrinted, .sortedKeys]
        )
        try hookData.write(to: hooks, options: .atomic)

        plan = CodeIslandInstallationPlan(
            provider: .codex,
            bundledBridgeURL: bundledBridge,
            changes: [
                CodeIslandConfigurationChange(kind: .modifyProviderHooks, url: hooks),
                CodeIslandConfigurationChange(kind: .replaceLegacyProviderHooks, url: hooks),
                CodeIslandConfigurationChange(kind: .installManagedBridge, url: managedBridge),
                CodeIslandConfigurationChange(kind: .writeManagedReceipt, url: managedReceipt),
                CodeIslandConfigurationChange(kind: .createListenerSocket, url: socket),
            ],
            blockers: [],
            hookEvents: [.sessionStart, .permissionRequest]
        )
    }

    func readHooks() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: hooks)) as! [String: Any]
    }

    func writeHooks(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: hooks, options: .atomic)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
