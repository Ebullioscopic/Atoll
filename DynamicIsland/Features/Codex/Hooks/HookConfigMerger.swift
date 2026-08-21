import Foundation

public struct HookMergeResult: Sendable {
    public let document: JSONValue
    public let modified: Bool
    public let addedCount: Int
    public let updatedCount: Int
    public let removedDuplicateCount: Int
}

public enum HookConfigMerger {
    public static let standardHelperCommand = "\"$HOME/Library/Application Support/Atoll/Codex/bin/CodexHookHelper\""

    public static func merge(
        existing: JSONValue,
        helperCommand: String = standardHelperCommand,
        events: [String]
    ) throws -> HookMergeResult {
        guard case var .object(root) = existing else {
            throw HookConfigError.invalidRoot
        }
        var hooks = root["hooks"]?.objectValue ?? [:]
        var added = 0
        var updated = 0
        var duplicates = 0
        var modified = false

        for event in events {
            var groups = hooks[event]?.arrayValue ?? []
            if groups.isEmpty {
                groups = [.object(["hooks": .array([])])]
                modified = true
            }
            var group = groups[0].objectValue ?? [:]
            var entries = group["hooks"]?.arrayValue ?? []
            var ownIndexes: [Int] = []
            for index in entries.indices {
                if isProjectHook(entries[index], helperCommand: helperCommand) {
                    ownIndexes.append(index)
                }
            }
            if ownIndexes.isEmpty {
                entries.append(commandHook(helperCommand))
                added += 1
                modified = true
            } else {
                let keepIndex = ownIndexes[0]
                var kept = entries[keepIndex]
                if command(of: kept) != helperCommand || timeout(of: kept) != 2 {
                    kept = commandHook(helperCommand)
                    entries[keepIndex] = kept
                    updated += 1
                    modified = true
                }
                for index in ownIndexes.dropFirst().reversed() {
                    entries.remove(at: index)
                    duplicates += 1
                    modified = true
                }
            }
            group["hooks"] = .array(entries)
            groups[0] = .object(group)
            hooks[event] = .array(groups)
        }
        root["hooks"] = .object(hooks)
        return HookMergeResult(
            document: .object(root),
            modified: modified,
            addedCount: added,
            updatedCount: updated,
            removedDuplicateCount: duplicates
        )
    }

    public static func remove(
        existing: JSONValue,
        helperCommand: String = standardHelperCommand
    ) throws -> (document: JSONValue, removedCount: Int) {
        guard case var .object(root) = existing else { throw HookConfigError.invalidRoot }
        var hooks = root["hooks"]?.objectValue ?? [:]
        var removed = 0
        for event in hooks.keys {
            guard var groups = hooks[event]?.arrayValue else { continue }
            for index in groups.indices {
                guard var group = groups[index].objectValue else { continue }
                let entries = group["hooks"]?.arrayValue ?? []
                let filtered = entries.filter {
                    if isProjectHook($0, helperCommand: helperCommand) { removed += 1; return false }
                    return true
                }
                group["hooks"] = .array(filtered)
                groups[index] = .object(group)
            }
            hooks[event] = .array(groups)
        }
        root["hooks"] = .object(hooks)
        return (.object(root), removed)
    }

    public static func isProjectHook(_ value: JSONValue, helperCommand: String = standardHelperCommand) -> Bool {
        guard let command = command(of: value) else { return false }
        return normalize(command) == normalize(helperCommand)
            || command.contains("CodexAtoll") && command.contains("codex-atoll-hook")
            || command.contains("Application Support/Atoll/Codex/bin/CodexHookHelper")
    }

    private static func commandHook(_ command: String) -> JSONValue {
        .object([
            "type": .string("command"),
            "command": .string(command),
            "timeout": .number(2)
        ])
    }

    private static func command(of value: JSONValue) -> String? { value.objectValue?["command"]?.stringValue }
    private static func timeout(of value: JSONValue) -> Int? { value.objectValue?["timeout"]?.numberValue.map(Int.init) }
    private static func normalize(_ command: String) -> String { command.replacingOccurrences(of: "\"", with: "") }
}

public enum HookConfigError: Error, CustomStringConvertible {
    case invalidRoot
    case invalidJSON
    public var description: String {
        switch self { case .invalidRoot: return "hooks.json root must be an object"; case .invalidJSON: return "hooks.json is invalid JSON" }
    }
}
