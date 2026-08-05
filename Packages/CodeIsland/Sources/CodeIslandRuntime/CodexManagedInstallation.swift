import CodeIslandCore
import CryptoKit
import Foundation

/// Failures from the exact, Atoll-owned Codex installation adapter.
public enum CodexManagedInstallationError: Error, Equatable {
    case invalidPlan
    case bundledBridgeMissing
    case bundledBridgeNotExecutable
    case managedBridgeConflict
    case managedReceiptConflict
    case hookConfigurationUnreadable
    case verificationFailed
    case managedBridgeModified
    case fileOperationFailed
}

/// Installs and removes only hook handlers carrying one exact Atoll plan marker.
///
/// The adapter accepts paths solely from a consent-bound plan and confines its
/// helper and receipt operations to the managed root supplied at construction.
/// Provider hook JSON is preserved semantically. Unrelated handlers remain in
/// place; recognized legacy CodeIsland handlers are backed up and replaced so
/// Codex cannot deliver the same event through both the raw legacy bridge and
/// Atoll's metadata-only bridge.
public struct CodexManagedInstallation: CodeIslandManagedInstalling {
    private let managedRootURL: URL
    private let fileManager: FileManager

    public init(
        managedRootURL: URL,
        fileManager: FileManager = .default
    ) {
        self.managedRootURL = managedRootURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public func loadManagedReceipt() throws -> CodeIslandManagedInstallationReceipt? {
        let url = managedRootURL.appendingPathComponent("codex-installation.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard !isSymbolicLinkIfPresent(at: url),
              let receipt = try? decodedReceipt(at: url),
              receipt.managedReceiptURL.standardizedFileURL == url.standardizedFileURL else {
            throw CodexManagedInstallationError.managedReceiptConflict
        }
        try validateReceiptPaths(receipt)
        return receipt
    }

    public func install(
        plan: CodeIslandInstallationPlan
    ) throws -> CodeIslandManagedInstallationReceipt {
        let validated = try validatedPlan(plan)

        if fileManager.fileExists(atPath: validated.receiptURL.path) {
            guard let existing = try? decodedReceipt(at: validated.receiptURL),
                  existing.planID == plan.id,
                  existing.provider == plan.provider,
                  existing.hookConfigurationURL.standardizedFileURL == validated.hooksURL,
                  existing.managedBridgeURL.standardizedFileURL == validated.bridgeURL,
                  existing.managedReceiptURL.standardizedFileURL == validated.receiptURL,
                  existing.hookEvents == plan.hookEvents,
                  existing.listenerSocketURL?.standardizedFileURL == validated.socketURL,
                  existing.managedCommand == managedCommand(
                    bridgeURL: validated.bridgeURL,
                    socketURL: validated.socketURL,
                    planID: plan.id
                  )
            else {
                throw CodexManagedInstallationError.managedReceiptConflict
            }
            try verify(receipt: existing)
            return existing
        }
        guard !fileManager.fileExists(atPath: validated.bridgeURL.path) else {
            throw CodexManagedInstallationError.managedBridgeConflict
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: plan.bundledBridgeURL.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            throw CodexManagedInstallationError.bundledBridgeMissing
        }
        guard fileManager.isExecutableFile(atPath: plan.bundledBridgeURL.path) else {
            throw CodexManagedInstallationError.bundledBridgeNotExecutable
        }
        guard let bridgeData = try? Data(contentsOf: plan.bundledBridgeURL) else {
            throw CodexManagedInstallationError.bundledBridgeMissing
        }

        let originalHookData: Data?
        let createdHookConfiguration: Bool
        let originalRoot: [String: Any]
        if fileManager.fileExists(atPath: validated.hooksURL.path) {
            guard let data = try? Data(contentsOf: validated.hooksURL),
                  let root = try? decodedHookRoot(from: data)
            else {
                throw CodexManagedInstallationError.hookConfigurationUnreadable
            }
            originalHookData = data
            createdHookConfiguration = false
            originalRoot = root
        } else {
            originalHookData = nil
            createdHookConfiguration = true
            originalRoot = ["hooks": [String: Any]()]
        }

        let command = managedCommand(
            bridgeURL: validated.bridgeURL,
            socketURL: validated.socketURL,
            planID: plan.id
        )
        let legacyRemoval = try removingLegacyHooks(
            from: originalRoot,
            events: plan.hookEvents
        )
        if !legacyRemoval.backup.groups.isEmpty,
           validated.legacyReplacementURL != validated.hooksURL {
            throw CodexManagedInstallationError.invalidPlan
        }
        let installedRoot = try addingManagedHooks(
            to: legacyRemoval.root,
            events: plan.hookEvents,
            command: command
        )
        guard let installedHookData = try? encodedJSONObject(installedRoot) else {
            throw CodexManagedInstallationError.hookConfigurationUnreadable
        }

        let backupData = legacyRemoval.backup.groups.isEmpty
            ? nil
            : try encodedLegacyBackup(legacyRemoval.backup)
        let receipt = CodeIslandManagedInstallationReceipt(
            planID: plan.id,
            provider: plan.provider,
            hookConfigurationURL: validated.hooksURL,
            managedBridgeURL: validated.bridgeURL,
            managedReceiptURL: validated.receiptURL,
            managedCommand: command,
            hookEvents: plan.hookEvents,
            bridgeDigest: digest(bridgeData),
            createdHookConfiguration: createdHookConfiguration,
            createdManagedBridge: true,
            listenerSocketURL: validated.socketURL,
            legacyHookBackup: backupData
        )
        guard let receiptData = try? encodedReceipt(receipt) else {
            throw CodexManagedInstallationError.fileOperationFailed
        }

        var bridgeInstalled = false
        var hookConfigurationWritten = false
        do {
            try fileManager.createDirectory(
                at: managedRootURL,
                withIntermediateDirectories: true
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: managedRootURL.path
            )
            try fileManager.copyItem(at: plan.bundledBridgeURL, to: validated.bridgeURL)
            bridgeInstalled = true
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: validated.bridgeURL.path
            )

            try fileManager.createDirectory(
                at: validated.hooksURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try installedHookData.write(to: validated.hooksURL, options: .atomic)
            hookConfigurationWritten = true
            try writeManagedReceipt(receiptData, to: validated.receiptURL)
            return receipt
        } catch {
            if hookConfigurationWritten {
                restoreHookConfiguration(
                    originalData: originalHookData,
                    at: validated.hooksURL
                )
            }
            if bridgeInstalled {
                try? fileManager.removeItem(at: validated.bridgeURL)
            }
            try? fileManager.removeItem(at: validated.receiptURL)
            removeManagedRootIfEmpty()
            if let typed = error as? CodexManagedInstallationError {
                throw typed
            }
            throw CodexManagedInstallationError.fileOperationFailed
        }
    }

    public func verify(receipt: CodeIslandManagedInstallationReceipt) throws {
        try validateReceiptPaths(receipt)
        guard fileManager.isExecutableFile(atPath: receipt.managedBridgeURL.path),
              let bridgeData = try? Data(contentsOf: receipt.managedBridgeURL),
              digest(bridgeData) == receipt.bridgeDigest,
              permissions(at: managedRootURL) == 0o700,
              permissions(at: receipt.managedBridgeURL) == 0o700,
              permissions(at: receipt.managedReceiptURL) == 0o600,
              let persisted = try? decodedReceipt(at: receipt.managedReceiptURL),
              persisted == receipt,
              let hookData = try? Data(contentsOf: receipt.hookConfigurationURL),
              let root = try? decodedHookRoot(from: hookData)
        else {
            throw CodexManagedInstallationError.verificationFailed
        }

        for event in receipt.hookEvents {
            guard managedCommandCount(
                receipt.managedCommand,
                event: event,
                root: root
            ) == 1 else {
                throw CodexManagedInstallationError.verificationFailed
            }
        }
        guard legacyCommandCount(
            in: root,
            events: Set(receipt.hookEvents.map(\.rawValue))
        ) == 0 else {
            throw CodexManagedInstallationError.verificationFailed
        }
        if let backup = receipt.legacyHookBackup {
            guard (try? decodedLegacyBackup(backup)) != nil else {
                throw CodexManagedInstallationError.verificationFailed
            }
        }
    }

    public func repair(
        receipt: CodeIslandManagedInstallationReceipt,
        plan: CodeIslandInstallationPlan
    ) throws -> CodeIslandManagedInstallationReceipt {
        try validateReceiptPaths(receipt)
        guard plan.provider == receipt.provider,
              plan.hookEvents == receipt.hookEvents,
              plan.url(for: .modifyProviderHooks)?.standardizedFileURL
                == receipt.hookConfigurationURL.standardizedFileURL,
              plan.url(for: .installManagedBridge)?.standardizedFileURL
                == receipt.managedBridgeURL.standardizedFileURL,
              plan.url(for: .writeManagedReceipt)?.standardizedFileURL
                == receipt.managedReceiptURL.standardizedFileURL,
              plan.listenerSocketURL?.standardizedFileURL
                == receipt.listenerSocketURL?.standardizedFileURL,
              fileManager.isExecutableFile(atPath: plan.bundledBridgeURL.path),
              let bundledBridgeData = try? Data(contentsOf: plan.bundledBridgeURL),
              let persistedData = try? Data(contentsOf: receipt.managedReceiptURL),
              let persisted = try? JSONDecoder().decode(
                CodeIslandManagedInstallationReceipt.self,
                from: persistedData
              ),
              persisted == receipt else {
            throw CodexManagedInstallationError.invalidPlan
        }

        let originalBridgeData: Data?
        if fileManager.fileExists(atPath: receipt.managedBridgeURL.path) {
            guard let data = try? Data(contentsOf: receipt.managedBridgeURL),
                  digest(data) == receipt.bridgeDigest else {
                throw CodexManagedInstallationError.managedBridgeModified
            }
            originalBridgeData = data
        } else {
            guard receipt.createdManagedBridge else {
                throw CodexManagedInstallationError.managedBridgeConflict
            }
            originalBridgeData = nil
        }

        let originalHookData: Data?
        let hookRoot: [String: Any]
        if fileManager.fileExists(atPath: receipt.hookConfigurationURL.path) {
            guard let data = try? Data(contentsOf: receipt.hookConfigurationURL),
                  let root = try? decodedHookRoot(from: data) else {
                throw CodexManagedInstallationError.hookConfigurationUnreadable
            }
            originalHookData = data
            hookRoot = root
        } else {
            guard receipt.createdHookConfiguration else {
                throw CodexManagedInstallationError.hookConfigurationUnreadable
            }
            originalHookData = nil
            hookRoot = ["hooks": [String: Any]()]
        }
        guard legacyCommandCount(
            in: hookRoot,
            events: Set(receipt.hookEvents.map(\.rawValue))
        ) == 0 else {
            throw CodexManagedInstallationError.verificationFailed
        }

        let repairedRoot = try addingManagedHooks(
            to: hookRoot,
            events: receipt.hookEvents,
            command: receipt.managedCommand
        )
        let repairedHookData = try encodedJSONObject(repairedRoot)
        let repairedReceipt = CodeIslandManagedInstallationReceipt(
            planID: receipt.planID,
            provider: receipt.provider,
            hookConfigurationURL: receipt.hookConfigurationURL,
            managedBridgeURL: receipt.managedBridgeURL,
            managedReceiptURL: receipt.managedReceiptURL,
            managedCommand: receipt.managedCommand,
            hookEvents: receipt.hookEvents,
            bridgeDigest: digest(bundledBridgeData),
            createdHookConfiguration: receipt.createdHookConfiguration,
            createdManagedBridge: receipt.createdManagedBridge,
            listenerSocketURL: receipt.listenerSocketURL,
            legacyHookBackup: receipt.legacyHookBackup
        )
        let repairedReceiptData = try encodedReceipt(repairedReceipt)

        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: managedRootURL.path
            )
            try bundledBridgeData.write(to: receipt.managedBridgeURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: receipt.managedBridgeURL.path
            )
            try fileManager.createDirectory(
                at: receipt.hookConfigurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try repairedHookData.write(to: receipt.hookConfigurationURL, options: .atomic)
            try writeManagedReceipt(repairedReceiptData, to: receipt.managedReceiptURL)
            return repairedReceipt
        } catch {
            restoreHookConfiguration(
                originalData: originalHookData,
                at: receipt.hookConfigurationURL
            )
            if let originalBridgeData {
                try? originalBridgeData.write(to: receipt.managedBridgeURL, options: .atomic)
                try? fileManager.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: receipt.managedBridgeURL.path
                )
            } else {
                try? fileManager.removeItem(at: receipt.managedBridgeURL)
            }
            try? writeManagedReceipt(persistedData, to: receipt.managedReceiptURL)
            throw CodexManagedInstallationError.fileOperationFailed
        }
    }

    public func remove(receipt: CodeIslandManagedInstallationReceipt) throws {
        try validateReceiptPaths(receipt)
        guard let persisted = try? decodedReceipt(at: receipt.managedReceiptURL),
              persisted == receipt else {
            throw CodexManagedInstallationError.managedReceiptConflict
        }

        if fileManager.fileExists(atPath: receipt.managedBridgeURL.path) {
            guard let bridgeData = try? Data(contentsOf: receipt.managedBridgeURL),
                  digest(bridgeData) == receipt.bridgeDigest else {
                throw CodexManagedInstallationError.managedBridgeModified
            }
        }

        let hookMutation: HookRemovalMutation
        if fileManager.fileExists(atPath: receipt.hookConfigurationURL.path) {
            guard let hookData = try? Data(contentsOf: receipt.hookConfigurationURL),
                  let root = try? decodedHookRoot(from: hookData),
                  let managedRemoved = try? removingManagedHooks(
                    from: root,
                    events: receipt.hookEvents,
                    command: receipt.managedCommand
                  )
            else {
                throw CodexManagedInstallationError.hookConfigurationUnreadable
            }
            let removed: [String: Any]
            if let backupData = receipt.legacyHookBackup {
                guard let backup = try? decodedLegacyBackup(backupData),
                      let restored = try? restoringLegacyHooks(
                        backup,
                        to: managedRemoved
                      ) else {
                    throw CodexManagedInstallationError.hookConfigurationUnreadable
                }
                removed = restored
            } else {
                removed = managedRemoved
            }
            if receipt.createdHookConfiguration, isEmptyManagedHookRoot(removed) {
                hookMutation = .removeFile
            } else if let data = try? encodedJSONObject(removed) {
                hookMutation = .write(data)
            } else {
                throw CodexManagedInstallationError.hookConfigurationUnreadable
            }
        } else if let backupData = receipt.legacyHookBackup {
            guard let backup = try? decodedLegacyBackup(backupData),
                  let restored = try? restoringLegacyHooks(
                    backup,
                    to: ["hooks": [String: Any]()]
                  ),
                  let data = try? encodedJSONObject(restored) else {
                throw CodexManagedInstallationError.hookConfigurationUnreadable
            }
            hookMutation = .write(data)
        } else {
            hookMutation = .none
        }

        do {
            switch hookMutation {
            case .none:
                break
            case .removeFile:
                try fileManager.removeItem(at: receipt.hookConfigurationURL)
            case .write(let data):
                try fileManager.createDirectory(
                    at: receipt.hookConfigurationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: receipt.hookConfigurationURL, options: .atomic)
            }
            if receipt.createdManagedBridge,
               fileManager.fileExists(atPath: receipt.managedBridgeURL.path) {
                try fileManager.removeItem(at: receipt.managedBridgeURL)
            }
            try fileManager.removeItem(at: receipt.managedReceiptURL)
            removeManagedRootIfEmpty()
        } catch {
            throw CodexManagedInstallationError.fileOperationFailed
        }
    }

    private func validatedPlan(
        _ plan: CodeIslandInstallationPlan
    ) throws -> ValidatedPlan {
        guard plan.provider == .codex,
              plan.blockers.isEmpty,
              !plan.hookEvents.isEmpty,
              Set(plan.hookEvents.map(\.rawValue)).count == plan.hookEvents.count,
              let hooksURL = plan.url(for: .modifyProviderHooks),
              let bridgeURL = plan.url(for: .installManagedBridge),
              let receiptURL = plan.url(for: .writeManagedReceipt),
              let socketURL = listenerSocketURL(in: plan),
              hooksURL.isFileURL,
              bridgeURL.isFileURL,
              receiptURL.isFileURL,
              socketURL.isFileURL,
              plan.bundledBridgeURL.isFileURL,
              bridgeURL.standardizedFileURL.deletingLastPathComponent() == managedRootURL,
              receiptURL.standardizedFileURL.deletingLastPathComponent() == managedRootURL,
              bridgeURL.lastPathComponent == "codeisland-bridge",
              receiptURL.lastPathComponent == "codex-installation.json",
              hooksURL.lastPathComponent == "hooks.json",
              managedRootURL.path != "/",
              managedRootIsSafe(),
              !isSymbolicLinkIfPresent(at: bridgeURL),
              !isSymbolicLinkIfPresent(at: receiptURL)
        else {
            throw CodexManagedInstallationError.invalidPlan
        }
        return ValidatedPlan(
            hooksURL: hooksURL.standardizedFileURL,
            bridgeURL: bridgeURL.standardizedFileURL,
            receiptURL: receiptURL.standardizedFileURL,
            socketURL: socketURL.standardizedFileURL,
            legacyReplacementURL: plan.url(for: .replaceLegacyProviderHooks)?.standardizedFileURL
        )
    }

    private func validateReceiptPaths(
        _ receipt: CodeIslandManagedInstallationReceipt
    ) throws {
        guard let listenerSocketURL = receipt.listenerSocketURL,
              receipt.provider == .codex,
              receipt.hookConfigurationURL.isFileURL,
              receipt.managedBridgeURL.isFileURL,
              receipt.managedReceiptURL.isFileURL,
              !receipt.hookEvents.isEmpty,
              Set(receipt.hookEvents.map(\.rawValue)).count == receipt.hookEvents.count,
              receipt.managedBridgeURL.standardizedFileURL.deletingLastPathComponent() == managedRootURL,
              receipt.managedReceiptURL.standardizedFileURL.deletingLastPathComponent() == managedRootURL,
              receipt.managedBridgeURL.lastPathComponent == "codeisland-bridge",
              receipt.managedReceiptURL.lastPathComponent == "codex-installation.json",
              receipt.hookConfigurationURL.lastPathComponent == "hooks.json",
              listenerSocketURL.isFileURL,
              receipt.managedCommand == managedCommand(
                bridgeURL: receipt.managedBridgeURL,
                socketURL: listenerSocketURL,
                planID: receipt.planID
              ),
              managedRootIsSafe(),
              !isSymbolicLinkIfPresent(at: receipt.managedBridgeURL),
              !isSymbolicLinkIfPresent(at: receipt.managedReceiptURL)
        else {
            throw CodexManagedInstallationError.invalidPlan
        }
    }

    private func decodedHookRoot(from data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CodexManagedInstallationError.hookConfigurationUnreadable
        }
        if let hooks = root["hooks"], !(hooks is [String: Any]) {
            throw CodexManagedInstallationError.hookConfigurationUnreadable
        }
        return root
    }

    private func addingManagedHooks(
        to root: [String: Any],
        events: [CodexManagedHookEvent],
        command: String
    ) throws -> [String: Any] {
        var result = try removingManagedHooks(
            from: root,
            events: events,
            command: command
        )
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups: [[String: Any]]
            if let existing = hooks[event.rawValue] {
                guard let typed = existing as? [[String: Any]] else {
                    throw CodexManagedInstallationError.hookConfigurationUnreadable
                }
                groups = typed
            } else {
                groups = []
            }
            groups.append(managedGroup(event: event, command: command))
            hooks[event.rawValue] = groups
        }
        result["hooks"] = hooks
        return result
    }

    private func removingLegacyHooks(
        from root: [String: Any],
        events: [CodexManagedHookEvent]
    ) throws -> LegacyHookRemoval {
        var result = root
        guard var hooks = result["hooks"] as? [String: Any] else {
            return LegacyHookRemoval(root: result, backup: LegacyHookBackup(groups: []))
        }
        var backups: [LegacyHookGroupBackup] = []

        for event in events {
            guard let rawGroups = hooks[event.rawValue] else { continue }
            guard let groups = rawGroups as? [[String: Any]] else {
                throw CodexManagedInstallationError.hookConfigurationUnreadable
            }
            var keptGroups: [[String: Any]] = []
            for (groupIndex, originalGroup) in groups.enumerated() {
                var group = originalGroup
                guard let rawHandlers = group["hooks"] else {
                    keptGroups.append(group)
                    continue
                }
                guard let handlers = rawHandlers as? [[String: Any]] else {
                    throw CodexManagedInstallationError.hookConfigurationUnreadable
                }
                let removedHandlers = handlers.filter(isLegacyCodeIslandHandler)
                guard !removedHandlers.isEmpty else {
                    keptGroups.append(group)
                    continue
                }

                var metadata = group
                metadata.removeValue(forKey: "hooks")
                let keptHandlers = handlers.filter { !isLegacyCodeIslandHandler($0) }
                let groupWasRemoved = keptHandlers.isEmpty && metadata.isEmpty
                backups.append(LegacyHookGroupBackup(
                    event: event.rawValue,
                    originalGroupIndex: groupIndex,
                    groupWasRemoved: groupWasRemoved,
                    groupMetadata: try encodedJSONObject(metadata),
                    handlers: try JSONSerialization.data(
                        withJSONObject: removedHandlers,
                        options: [.sortedKeys, .withoutEscapingSlashes]
                    )
                ))

                if groupWasRemoved {
                    continue
                }
                group["hooks"] = keptHandlers
                keptGroups.append(group)
            }
            if keptGroups.isEmpty {
                hooks.removeValue(forKey: event.rawValue)
            } else {
                hooks[event.rawValue] = keptGroups
            }
        }
        result["hooks"] = hooks
        return LegacyHookRemoval(
            root: result,
            backup: LegacyHookBackup(groups: backups)
        )
    }

    private func restoringLegacyHooks(
        _ backup: LegacyHookBackup,
        to root: [String: Any]
    ) throws -> [String: Any] {
        var result = root
        var hooks = result["hooks"] as? [String: Any] ?? [:]

        for snapshot in backup.groups {
            guard let metadata = try JSONSerialization.jsonObject(
                with: snapshot.groupMetadata
            ) as? [String: Any],
            let handlers = try JSONSerialization.jsonObject(
                with: snapshot.handlers
            ) as? [[String: Any]] else {
                throw CodexManagedInstallationError.hookConfigurationUnreadable
            }
            var groups = hooks[snapshot.event] as? [[String: Any]] ?? []
            let metadataMatches: ([String: Any]) -> Bool = { group in
                var currentMetadata = group
                currentMetadata.removeValue(forKey: "hooks")
                return NSDictionary(dictionary: currentMetadata).isEqual(to: metadata)
            }
            let existingIndex: Int?
            if !snapshot.groupWasRemoved,
               groups.indices.contains(snapshot.originalGroupIndex),
               metadataMatches(groups[snapshot.originalGroupIndex]) {
                existingIndex = snapshot.originalGroupIndex
            } else if !snapshot.groupWasRemoved {
                existingIndex = groups.firstIndex(where: metadataMatches)
            } else {
                existingIndex = nil
            }

            if let index = existingIndex {
                var group = groups[index]
                var currentHandlers = group["hooks"] as? [[String: Any]] ?? []
                for handler in handlers where !currentHandlers.contains(where: {
                    NSDictionary(dictionary: $0).isEqual(to: handler)
                }) {
                    currentHandlers.append(handler)
                }
                group["hooks"] = currentHandlers
                groups[index] = group
            } else {
                var group = metadata
                group["hooks"] = handlers
                groups.insert(
                    group,
                    at: min(max(0, snapshot.originalGroupIndex), groups.count)
                )
            }
            hooks[snapshot.event] = groups
        }
        result["hooks"] = hooks
        return result
    }

    private func removingManagedHooks(
        from root: [String: Any],
        events: [CodexManagedHookEvent],
        command: String
    ) throws -> [String: Any] {
        var result = root
        guard var hooks = result["hooks"] as? [String: Any] else { return result }
        for event in events {
            guard let rawGroups = hooks[event.rawValue] else { continue }
            guard let groups = rawGroups as? [[String: Any]] else {
                throw CodexManagedInstallationError.hookConfigurationUnreadable
            }
            var keptGroups: [[String: Any]] = []
            for var group in groups {
                guard let rawHandlers = group["hooks"] else {
                    keptGroups.append(group)
                    continue
                }
                guard let handlers = rawHandlers as? [[String: Any]] else {
                    throw CodexManagedInstallationError.hookConfigurationUnreadable
                }
                let keptHandlers = handlers.filter {
                    !isExactManagedHandler($0, command: command)
                }
                if keptHandlers.isEmpty, group.keys.count == 1 {
                    continue
                }
                group["hooks"] = keptHandlers
                keptGroups.append(group)
            }
            if keptGroups.isEmpty {
                hooks.removeValue(forKey: event.rawValue)
            } else {
                hooks[event.rawValue] = keptGroups
            }
        }
        result["hooks"] = hooks
        return result
    }

    private func managedGroup(
        event: CodexManagedHookEvent,
        command: String
    ) -> [String: Any] {
        let timeout = event == .sessionEnd ? 3 : 2
        return [
            "hooks": [[
                "type": "command",
                "command": command,
                "timeout": timeout,
            ]],
        ]
    }

    private func managedCommand(
        bridgeURL: URL,
        socketURL: URL,
        planID: UUID
    ) -> String {
        "\(shellQuote(bridgeURL.path)) --source codex --socket \(shellQuote(socketURL.path)) --managed-by-atoll \(planID.uuidString.lowercased())"
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func managedCommandCount(
        _ command: String,
        event: CodexManagedHookEvent,
        root: [String: Any]
    ) -> Int {
        guard let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[event.rawValue]
        else { return 0 }
        return managedCommandCount(command, in: groups)
    }

    private func managedCommandCount(_ command: String, in value: Any) -> Int {
        if let dictionary = value as? [String: Any] {
            let own = isExactManagedHandler(dictionary, command: command) ? 1 : 0
            return own + dictionary.values.reduce(0) {
                $0 + managedCommandCount(command, in: $1)
            }
        }
        if let array = value as? [Any] {
            return array.reduce(0) {
                $0 + managedCommandCount(command, in: $1)
            }
        }
        return 0
    }

    private func isExactManagedHandler(
        _ dictionary: [String: Any],
        command: String
    ) -> Bool {
        dictionary["type"] as? String == "command"
            && dictionary["command"] as? String == command
    }

    private func isLegacyCodeIslandHandler(_ dictionary: [String: Any]) -> Bool {
        guard dictionary["type"] as? String == "command",
              let command = dictionary["command"] as? String else {
            return false
        }
        return command.contains("/.codeisland/codeisland-bridge")
            || command.contains("/.codeisland/codeisland-hook.sh")
    }

    private func legacyCommandCount(
        in root: [String: Any],
        events: Set<String>
    ) -> Int {
        guard let hooks = root["hooks"] as? [String: Any] else { return 0 }
        return events.reduce(0) { total, event in
            guard let groups = hooks[event] else { return total }
            return total + recursiveLegacyCommandCount(in: groups)
        }
    }

    private func recursiveLegacyCommandCount(in value: Any) -> Int {
        if let dictionary = value as? [String: Any] {
            let own = isLegacyCodeIslandHandler(dictionary) ? 1 : 0
            return own + dictionary.values.reduce(0) {
                $0 + recursiveLegacyCommandCount(in: $1)
            }
        }
        if let array = value as? [Any] {
            return array.reduce(0) {
                $0 + recursiveLegacyCommandCount(in: $1)
            }
        }
        return 0
    }

    private func encodedJSONObject(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func encodedReceipt(
        _ receipt: CodeIslandManagedInstallationReceipt
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(receipt)
    }

    private func encodedLegacyBackup(_ backup: LegacyHookBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(backup)
    }

    private func decodedLegacyBackup(_ data: Data) throws -> LegacyHookBackup {
        try JSONDecoder().decode(LegacyHookBackup.self, from: data)
    }

    private func listenerSocketURL(in plan: CodeIslandInstallationPlan) -> URL? {
        let socketKinds: Set<CodeIslandConfigurationChangeKind> = [
            .createListenerSocket,
            .replaceStaleListenerSocket,
            .resolveLegacySocketConflict,
        ]
        let matches = plan.changes.filter { socketKinds.contains($0.kind) }
        guard matches.count == 1 else { return nil }
        return matches[0].url
    }

    private func decodedReceipt(
        at url: URL
    ) throws -> CodeIslandManagedInstallationReceipt {
        try JSONDecoder().decode(
            CodeIslandManagedInstallationReceipt.self,
            from: Data(contentsOf: url)
        )
    }

    private func writeManagedReceipt(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private func permissions(at url: URL) -> Int? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let value = attributes[.posixPermissions] as? NSNumber else {
            return nil
        }
        return value.intValue
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func restoreHookConfiguration(originalData: Data?, at url: URL) {
        if let originalData {
            try? originalData.write(to: url, options: .atomic)
        } else {
            try? fileManager.removeItem(at: url)
        }
    }

    private func isEmptyManagedHookRoot(_ root: [String: Any]) -> Bool {
        guard root.keys.count == 1,
              let hooks = root["hooks"] as? [String: Any]
        else { return false }
        return hooks.isEmpty
    }

    private func removeManagedRootIfEmpty() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: managedRootURL,
            includingPropertiesForKeys: nil
        ), contents.isEmpty else { return }
        try? fileManager.removeItem(at: managedRootURL)
    }

    private func managedRootIsSafe() -> Bool {
        guard fileManager.fileExists(atPath: managedRootURL.path) else { return true }
        guard let attributes = try? fileManager.attributesOfItem(
            atPath: managedRootURL.path
        ), let type = attributes[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeDirectory
    }

    private func isSymbolicLinkIfPresent(at url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else { return false }
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let type = attributes[.type] as? FileAttributeType else {
            return true
        }
        return type == .typeSymbolicLink
    }
}

private struct ValidatedPlan {
    let hooksURL: URL
    let bridgeURL: URL
    let receiptURL: URL
    let socketURL: URL
    let legacyReplacementURL: URL?
}

private struct LegacyHookRemoval {
    let root: [String: Any]
    let backup: LegacyHookBackup
}

private struct LegacyHookBackup: Codable {
    let groups: [LegacyHookGroupBackup]
}

private struct LegacyHookGroupBackup: Codable {
    let event: String
    let originalGroupIndex: Int
    let groupWasRemoved: Bool
    let groupMetadata: Data
    let handlers: Data
}

private enum HookRemovalMutation {
    case none
    case removeFile
    case write(Data)
}
