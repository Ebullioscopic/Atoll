import CodeIslandCore
import CodeIslandRuntime
import Foundation

@main
struct CodeIslandPhaseFourDiscoveryRegression {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let binDirectory = root.appendingPathComponent("bin", isDirectory: true)
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let legacySupport = root.appendingPathComponent(".codeisland", isDirectory: true)
        let preferences = root
            .appendingPathComponent("Library/Preferences", isDirectory: true)
            .appendingPathComponent("com.codeisland.app.plist")
        let hooks = codexHome.appendingPathComponent("hooks.json")
        let executable = binDirectory.appendingPathComponent("codex")
        let managedRoot = root
            .appendingPathComponent("Library/Application Support/Atoll/CodeIsland", isDirectory: true)
        let managedBridge = managedRoot.appendingPathComponent("codeisland-bridge")
        let managedReceipt = managedRoot.appendingPathComponent("codex-installation.json")
        let bundledBridge = root.appendingPathComponent("Atoll.app/Contents/Helpers/codeisland-bridge")
        let socket = root.appendingPathComponent("codeisland.sock")

        try fileManager.createDirectory(at: binDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: legacySupport, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: preferences.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let legacyPreferenceData = try PropertyListSerialization.data(
            fromPropertyList: [
                "sessionGroupingMode": "status",
                "smartSuppress": true,
                "completionNotificationStyle": "glance",
                "mascotSpeed": 140,
                "soundEnabled": true,
                "soundVolume": 65,
                "defaultSource": "codex",
                "webhookURL": "https://must-not-be-imported.example",
                "autoApproveTools": "Bash",
            ],
            format: .binary,
            options: 0
        )
        try legacyPreferenceData.write(to: preferences)

        let hookObject: [String: Any] = [
            "description": "keep this metadata",
            "hooks": [
                "SessionStart": [
                    ["hooks": [[
                        "type": "command",
                        "command": "/Users/example/.codeisland/codeisland-bridge --source codex",
                    ]]],
                    ["hooks": [[
                        "type": "command",
                        "command": "'/Applications/Atoll.app/Contents/Helpers/codeisland-bridge' --source codex --managed-by-atoll existing-plan",
                    ]]],
                    ["hooks": [[
                        "type": "command",
                        "command": "/usr/local/bin/unrelated-observer",
                    ]]],
                ],
            ],
        ]
        let hookData = try JSONSerialization.data(withJSONObject: hookObject, options: [.prettyPrinted])
        try hookData.write(to: hooks)
        let originalHookData = try Data(contentsOf: hooks)

        let paths = CodeIslandDiscoveryPaths(
            codexExecutableCandidates: [executable],
            codexHooksURL: hooks,
            legacySupportDirectoryURL: legacySupport,
            legacyPreferencesURL: preferences,
            legacySocketURL: socket,
            bundledBridgeURL: bundledBridge,
            managedBridgeURL: managedBridge,
            managedReceiptURL: managedReceipt
        )
        let discovery = CodeIslandReadOnlyDiscovery(
            paths: paths,
            socketInspector: FixedSocketInspector(state: .occupied),
            applicationInspector: FixedApplicationInspector(isRunning: true)
        )

        let assessment = discovery.assessCodex()

        precondition(assessment.provider == .codex)
        precondition(assessment.toolPresence == .detected(executable))
        precondition(
            assessment.hookState
                == .readable(atollManagedHandlerCount: 1, legacyHandlerCount: 1)
        )
        precondition(assessment.legacyApplicationState == .running)
        precondition(assessment.legacySocketState == .occupied)
        precondition(
            assessment.compatiblePreferences
                == CodeIslandLegacyFeaturePreferences(
                    sessionGrouping: .status,
                    smartSuppressionEnabled: true,
                    completionPresentation: .glance,
                    mascotSpeedPercent: 140,
                    soundEffectsEnabled: true,
                    soundVolumePercent: 65,
                    defaultMascotProvider: .codex
                )
        )
        precondition(
            assessment.legacyFootprints
                == [.preferences, .supportDirectory, .codexHooks]
        )
        precondition(
            assessment.blockers
                == [.legacyApplicationRunning, .legacySocketOccupied]
        )
        precondition(
            assessment.installationPlan.changes.map(\.url)
                == [hooks, hooks, managedBridge, managedReceipt, socket]
        )
        precondition(
            assessment.installationPlan.changes.map(\.kind)
                == [
                    .modifyProviderHooks,
                    .replaceLegacyProviderHooks,
                    .installManagedBridge,
                    .writeManagedReceipt,
                    .resolveLegacySocketConflict,
                ]
        )

        let finalHookData = try Data(contentsOf: hooks)
        precondition(finalHookData == originalHookData)
        precondition(fileManager.fileExists(atPath: legacySupport.path))
        precondition(fileManager.fileExists(atPath: preferences.path))
        precondition(!fileManager.fileExists(atPath: managedBridge.path))
        precondition(!fileManager.fileExists(atPath: managedReceipt.path))
    }
}

private struct FixedSocketInspector: CodeIslandSocketInspecting {
    let state: CodeIslandSocketState

    func state(at socketURL: URL) -> CodeIslandSocketState {
        state
    }
}

private struct FixedApplicationInspector: CodeIslandLegacyApplicationInspecting {
    let isRunning: Bool

    func isApplicationRunning(bundleIdentifier: String) -> Bool {
        precondition(bundleIdentifier == "com.codeisland.app")
        return isRunning
    }
}
