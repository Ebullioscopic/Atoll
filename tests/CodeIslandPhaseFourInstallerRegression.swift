import CodeIslandCore
import CodeIslandRuntime
import Foundation

@main
struct CodeIslandPhaseFourInstallerRegression {
    static func main() throws {
        try verifyExactManagedInstallAndRemoval()
        try verifyMissingBridgeLeavesConfigurationUntouched()
        try verifyManagedRootSymlinkIsRejected()
    }

    private static func verifyExactManagedInstallAndRemoval() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let installer = CodexManagedInstallation(managedRootURL: fixture.managedRoot)

        let receipt = try installer.install(plan: fixture.plan)
        try installer.verify(receipt: receipt)

        precondition(receipt.planID == fixture.plan.id)
        precondition(receipt.managedCommand.contains("--managed-by-atoll"))
        precondition(receipt.managedCommand.contains(fixture.plan.id.uuidString.lowercased()))
        precondition(FileManager.default.isExecutableFile(atPath: fixture.managedBridge.path))
        let managedBridgeData = try Data(contentsOf: fixture.managedBridge)
        let bundledBridgeData = try Data(contentsOf: fixture.bundledBridge)
        precondition(managedBridgeData == bundledBridgeData)

        let installedRoot = try fixture.readHooks()
        precondition(commandCount(receipt.managedCommand, in: installedRoot) == 2)
        precondition(commandCount("/usr/local/bin/user-session-hook", in: installedRoot) == 1)
        precondition(
            commandCount(
                "/Users/example/.codeisland/codeisland-bridge --source codex",
                in: installedRoot
            ) == 0
        )

        let secondReceipt = try installer.install(plan: fixture.plan)
        precondition(secondReceipt == receipt)
        let reinstalledHooks = try fixture.readHooks()
        precondition(commandCount(receipt.managedCommand, in: reinstalledHooks) == 2)

        try installer.remove(receipt: receipt)
        precondition(!FileManager.default.fileExists(atPath: fixture.managedBridge.path))
        precondition(!FileManager.default.fileExists(atPath: fixture.managedReceipt.path))
        let restoredHooks = try fixture.readHooks()
        precondition(
            NSDictionary(dictionary: restoredHooks)
                .isEqual(to: fixture.originalHooks)
        )
    }

    private static func verifyMissingBridgeLeavesConfigurationUntouched() throws {
        let fixture = try Fixture(includeBundledBridge: false)
        defer { fixture.remove() }
        let installer = CodexManagedInstallation(managedRootURL: fixture.managedRoot)
        let originalData = try Data(contentsOf: fixture.hooks)

        do {
            _ = try installer.install(plan: fixture.plan)
            preconditionFailure("A missing bundled helper must fail before writes")
        } catch let error as CodexManagedInstallationError {
            precondition(error == .bundledBridgeMissing)
        }

        let finalData = try Data(contentsOf: fixture.hooks)
        precondition(finalData == originalData)
        precondition(!FileManager.default.fileExists(atPath: fixture.managedBridge.path))
        precondition(!FileManager.default.fileExists(atPath: fixture.managedReceipt.path))
    }

    private static func verifyManagedRootSymlinkIsRejected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let fileManager = FileManager.default
        let redirectedRoot = fixture.root.appendingPathComponent("redirected", isDirectory: true)
        try fileManager.createDirectory(at: redirectedRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: fixture.managedRoot.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createSymbolicLink(
            at: fixture.managedRoot,
            withDestinationURL: redirectedRoot
        )
        let installer = CodexManagedInstallation(managedRootURL: fixture.managedRoot)
        let originalData = try Data(contentsOf: fixture.hooks)

        do {
            _ = try installer.install(plan: fixture.plan)
            preconditionFailure("A symlinked managed root must not redirect writes")
        } catch let error as CodexManagedInstallationError {
            precondition(error == .invalidPlan)
        }

        let finalData = try Data(contentsOf: fixture.hooks)
        precondition(finalData == originalData)
        let redirectedContents = try fileManager.contentsOfDirectory(
            atPath: redirectedRoot.path
        )
        precondition(redirectedContents.isEmpty)
    }

    private static func commandCount(_ command: String, in value: Any) -> Int {
        if let dictionary = value as? [String: Any] {
            let own = dictionary["type"] as? String == "command"
                && dictionary["command"] as? String == command ? 1 : 0
            return own + dictionary.values.reduce(0) {
                $0 + commandCount(command, in: $1)
            }
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + commandCount(command, in: $1) }
        }
        return 0
    }
}

private final class Fixture {
    let root: URL
    let codexHome: URL
    let hooks: URL
    let bundledBridge: URL
    let managedRoot: URL
    let managedBridge: URL
    let managedReceipt: URL
    let socket: URL
    let originalHooks: [String: Any]
    let plan: CodeIslandInstallationPlan

    init(includeBundledBridge: Bool = true) throws {
        let fileManager = FileManager.default
        root = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        hooks = codexHome.appendingPathComponent("hooks.json")
        bundledBridge = root
            .appendingPathComponent("Atoll.app/Contents/Helpers", isDirectory: true)
            .appendingPathComponent("codeisland-bridge")
        managedRoot = root
            .appendingPathComponent("Library/Application Support/Atoll/CodeIsland", isDirectory: true)
        managedBridge = managedRoot.appendingPathComponent("codeisland-bridge")
        managedReceipt = managedRoot.appendingPathComponent("codex-installation.json")
        socket = root.appendingPathComponent("codeisland.sock")
        originalHooks = [
            "description": "keep this metadata",
            "custom": ["enabled": true],
            "hooks": [
                "SessionStart": [
                    ["hooks": [[
                        "type": "command",
                        "command": "/usr/local/bin/user-session-hook",
                        "timeout": 9,
                    ]]],
                    ["hooks": [[
                        "type": "command",
                        "command": "/Users/example/.codeisland/codeisland-bridge --source codex",
                    ]]],
                ],
            ],
        ]

        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        let hookData = try JSONSerialization.data(
            withJSONObject: originalHooks,
            options: [.prettyPrinted, .sortedKeys]
        )
        try hookData.write(to: hooks)
        if includeBundledBridge {
            try fileManager.createDirectory(
                at: bundledBridge.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: bundledBridge)
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: bundledBridge.path
            )
        }

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
        let data = try Data(contentsOf: hooks)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
