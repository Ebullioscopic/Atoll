import Foundation

@main
struct CodexNativeCoreTests {
    static func main() throws {
        try expect(
            AppPaths.default.root.path.hasSuffix("Library/Application Support/Atoll/Codex"),
            "native Codex data lives under Atoll Application Support"
        )

        try expect(
            HookConfigMerger.standardHelperCommand.contains("Application Support/Atoll/Codex/bin/CodexHookHelper"),
            "hooks target the Atoll-managed helper"
        )

        let legacyCommand = "\"$HOME/Library/Application Support/CodexAtoll/bin/codex-atoll-hook\""
        let existing: JSONValue = .object([
            "hooks": .object([
                "SessionStart": .array([
                    .object([
                        "hooks": .array([
                            .object([
                                "type": .string("command"),
                                "command": .string(legacyCommand),
                                "timeout": .number(2),
                            ])
                        ])
                    ])
                ])
            ])
        ])

        let merged = try HookConfigMerger.merge(existing: existing, events: ["SessionStart"])
        try expect(merged.addedCount == 0, "legacy hook is upgraded instead of duplicated")
        try expect(merged.updatedCount == 1, "legacy hook command is replaced")

        let command = merged.document.objectValue?["hooks"]?.objectValue?["SessionStart"]?
            .arrayValue?.first?.objectValue?["hooks"]?.arrayValue?.first?.objectValue?["command"]?.stringValue
        try expect(command == HookConfigMerger.standardHelperCommand, "upgraded hook uses native helper path")

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-codex-migration-tests-\(UUID().uuidString)", isDirectory: true)
        let legacyPaths = AppPaths(root: temporaryRoot.appendingPathComponent("legacy", isDirectory: true))
        let nativePaths = AppPaths(root: temporaryRoot.appendingPathComponent("native", isDirectory: true))
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        try legacyPaths.prepareDirectories()
        let legacyState = Data("{\"saved_at\":\"2026-08-21T00:00:00Z\",\"tasks\":[],\"recent_completions\":[],\"processed_event_ids\":[]}".utf8)
        try AtomicFileWriter().write(legacyState, to: legacyPaths.stateFile)

        let migrator = CodexDataMigrator(paths: nativePaths, legacyPaths: legacyPaths)
        let firstMigration = try migrator.migrateIfNeeded()
        try expect(firstMigration.importedLegacyState, "legacy task state is imported once")
        let migratedState = try Data(contentsOf: nativePaths.stateFile)
        try expect(migratedState == legacyState, "legacy state contents are preserved")

        let secondMigration = try migrator.migrateIfNeeded()
        try expect(!secondMigration.importedLegacyState, "migration is idempotent")

        let isolatedInstaller = HookInstaller(
            paths: nativePaths,
            hooksConfigURL: temporaryRoot.appendingPathComponent("hooks.json")
        )
        try expect(
            isolatedInstaller.helperCommand == "\"\(nativePaths.root.path)/bin/CodexHookHelper\"",
            "hook command follows the installer's actual helper destination"
        )

        try expect(
            CodexPresentationVisibilityPolicy.canShow(
                isBuiltInCodex: true,
                codexEnabled: true,
                thirdPartyEnabled: false,
                hideOnClosed: true,
                showCodexInFullscreen: true
            ),
            "built-in Codex can remain visible in fullscreen independently of third-party extensions"
        )
        try expect(
            !CodexPresentationVisibilityPolicy.canShow(
                isBuiltInCodex: true,
                codexEnabled: true,
                thirdPartyEnabled: true,
                hideOnClosed: true,
                showCodexInFullscreen: false
            ),
            "Codex fullscreen preference can suppress built-in presentation"
        )
        try expect(
            !CodexPresentationVisibilityPolicy.canShow(
                isBuiltInCodex: false,
                codexEnabled: true,
                thirdPartyEnabled: false,
                hideOnClosed: false,
                showCodexInFullscreen: true
            ),
            "third-party activities still honor the third-party master toggle"
        )
        try expect(
            CodexPresentationConstants.isLegacyExternalCodex(bundleIdentifier: "com.codexatoll.app"),
            "legacy standalone CodexAtoll identity is recognized for retirement"
        )

        print("CodexNativeCoreTests: PASS")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else { throw TestFailure(message: message) }
    }
}

private struct TestFailure: Error {
    let message: String
}
