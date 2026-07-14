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

import Foundation
import AppKit
import Defaults
import AtollExtensionKit
import UniformTypeIdentifiers

/// Handles JSON-RPC method calls for a single WebSocket connection.
/// Mirrors the functionality of `ExtensionXPCService` but uses JSON-RPC transport.
@MainActor
final class ExtensionRPCService {
    let bundleIdentifier: String
    private weak var server: ExtensionRPCServer?

    private let liveActivityManager = ExtensionLiveActivityManager.shared
    private let widgetManager = ExtensionLockScreenWidgetManager.shared
    private let notchManager = ExtensionNotchExperienceManager.shared
    private let authorizationManager = ExtensionAuthorizationManager.shared

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // Keys whose values represent Swift enums that use {"type":...} in client format.
    // These need to be transformed to Swift Codable format: {"caseName": {params}}.
    private static let enumKeys: Set<String> = [
        "leadingIcon", "trailingContent", "progressIndicator",
        "badgeIcon", "leadingContent", "icon", "tint"
    ]

    // Enum-typed fields that can appear inside arrays (like content elements)
    private static let contentElementTypeFields: Set<String> = [
        "text", "icon", "progress", "graph", "gauge", "spacer", "divider", "webView"
    ]

    init(bundleIdentifier: String, server: ExtensionRPCServer) {
        self.bundleIdentifier = bundleIdentifier
        self.server = server
    }

    // MARK: - Method Routing

    func handleRequest(_ request: RPCRequest) -> Data {
        let result: Codable

        switch request.method {
        case "atoll.getVersion":
            result = handleGetVersion(id: request.id)

        case "atoll.requestAuthorization":
            result = handleRequestAuthorization(params: request.params, id: request.id)

        case "atoll.checkAuthorization":
            result = handleCheckAuthorization(params: request.params, id: request.id)

        case "atoll.presentLiveActivity":
            result = handlePresentLiveActivity(params: request.params, id: request.id)

        case "atoll.updateLiveActivity":
            result = handleUpdateLiveActivity(params: request.params, id: request.id)

        case "atoll.dismissLiveActivity":
            result = handleDismissLiveActivity(params: request.params, id: request.id)

        case "atoll.presentLockScreenWidget":
            result = handlePresentLockScreenWidget(params: request.params, id: request.id)

        case "atoll.updateLockScreenWidget":
            result = handleUpdateLockScreenWidget(params: request.params, id: request.id)

        case "atoll.dismissLockScreenWidget":
            result = handleDismissLockScreenWidget(params: request.params, id: request.id)

        case "atoll.presentNotchExperience":
            result = handlePresentNotchExperience(params: request.params, id: request.id)

        case "atoll.updateNotchExperience":
            result = handleUpdateNotchExperience(params: request.params, id: request.id)

        case "atoll.dismissNotchExperience":
            result = handleDismissNotchExperience(params: request.params, id: request.id)

        // MARK: File Sharing
        case "atoll.getShelfItems":
            result = handleGetShelfItems(params: request.params, id: request.id)

        case "atoll.getShelfItemData":
            result = handleGetShelfItemData(params: request.params, id: request.id)

        case "atoll.showFilePicker":
            result = handleShowFilePicker(params: request.params, id: request.id)

        case "atoll.shareShelfItems":
            result = handleShareShelfItemsSync(params: request.params, id: request.id)

        case "atoll.addFilesToShelf":
            result = handleAddFilesToShelf(params: request.params, id: request.id)

        case "atoll.subscribeShelfEvents":
            result = handleSubscribeShelfEvents(params: request.params, id: request.id)

        default:
            result = RPCErrorResponse(
                error: RPCErrorObject(code: RPCErrorCode.methodNotFound, message: "Method not found: \(request.method)"),
                id: request.id
            )
        }

        return (try? encoder.encode(result)) ?? Data()
    }

    // MARK: - Version

    private func handleGetVersion(id: String) -> RPCSuccessResponse {
        RPCSuccessResponse(
            result: ["version": .string(AtollExtensionKitVersion)],
            id: id
        )
    }

    // MARK: - Authorization

    private func handleRequestAuthorization(params: RPCParams?, id: String) -> Codable {
        guard Defaults[.enableThirdPartyExtensions] else {
            return RPCErrorResponse(
                error: RPCErrorObject(code: RPCErrorCode.featureDisabled, message: "Extensions are disabled"),
                id: id
            )
        }

        let bi = params?["bundleIdentifier"]?.stringValue ?? bundleIdentifier
        let entry = authorizationManager.ensureEntryExists(bundleIdentifier: bi, appName: bi)

        if entry.isAuthorized {
            return RPCSuccessResponse(result: ["authorized": .bool(true)], id: id)
        }

        // Auto-authorize for now (user can revoke in settings)
        authorizationManager.authorize(bundleIdentifier: bi, appName: bi)
        logDiagnostics("Authorized RPC client \(bi)")

        return RPCSuccessResponse(result: ["authorized": .bool(true)], id: id)
    }

    private func handleCheckAuthorization(params: RPCParams?, id: String) -> Codable {
        let bi = params?["bundleIdentifier"]?.stringValue ?? bundleIdentifier

        guard Defaults[.enableThirdPartyExtensions] else {
            return RPCSuccessResponse(result: ["authorized": .bool(false)], id: id)
        }

        let entry = authorizationManager.authorizationEntry(for: bi)
        let authorized = entry?.isAuthorized ?? false

        return RPCSuccessResponse(result: ["authorized": .bool(authorized)], id: id)
    }

    // MARK: - Live Activities

    private func handlePresentLiveActivity(params: RPCParams?, id: String) -> Codable {
        guard let descriptorData = params?.jsonData(for: "descriptor") else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Missing descriptor", id: id)
        }

        do {
            let transformed = Self.transformClientJSON(descriptorData)
            let descriptor = try decoder.decode(AtollLiveActivityDescriptor.self, from: transformed)
            try ExtensionDescriptorValidator.validate(descriptor)
            try liveActivityManager.present(descriptor: descriptor, bundleIdentifier: descriptor.bundleIdentifier)
            logDiagnostics("RPC: Presented live activity \(descriptor.id) for \(descriptor.bundleIdentifier)")
            return RPCSuccessResponse(result: ["success": .bool(true)], id: id)
        } catch let error as ExtensionValidationError {
            return errorResponse(from: error, id: id)
        } catch {
            logDiagnostics("RPC: Decode error for presentLiveActivity: \(error)")
            logDiagnostics("RPC: Raw payload: \(String(data: descriptorData, encoding: .utf8) ?? "<binary>")")
            return errorResponse(code: RPCErrorCode.internalError, message: error.localizedDescription, id: id)
        }
    }

    private func handleUpdateLiveActivity(params: RPCParams?, id: String) -> Codable {
        guard let descriptorData = params?.jsonData(for: "descriptor") else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Missing descriptor", id: id)
        }

        do {
            let transformed = Self.transformClientJSON(descriptorData)
            let descriptor = try decoder.decode(AtollLiveActivityDescriptor.self, from: transformed)
            try liveActivityManager.update(descriptor: descriptor, bundleIdentifier: descriptor.bundleIdentifier)
            logDiagnostics("RPC: Updated live activity \(descriptor.id) for \(descriptor.bundleIdentifier)")
            return RPCSuccessResponse(result: ["success": .bool(true)], id: id)
        } catch let error as ExtensionValidationError {
            return errorResponse(from: error, id: id)
        } catch {
            logDiagnostics("RPC: Decode error for updateLiveActivity: \(error)")
            return errorResponse(code: RPCErrorCode.internalError, message: error.localizedDescription, id: id)
        }
    }

    private func handleDismissLiveActivity(params: RPCParams?, id: String) -> Codable {
        guard let activityID = params?["activityID"]?.stringValue else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Missing activityID", id: id)
        }
        let bi = params?["bundleIdentifier"]?.stringValue ?? bundleIdentifier
        liveActivityManager.dismiss(activityID: activityID, bundleIdentifier: bi)
        logDiagnostics("RPC: Dismissed live activity \(activityID) for \(bi)")
        return RPCSuccessResponse(result: ["success": .bool(true)], id: id)
    }

    // MARK: - Lock Screen Widgets

    private func handlePresentLockScreenWidget(params: RPCParams?, id: String) -> Codable {
        guard let descriptorData = params?.jsonData(for: "descriptor") else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Missing descriptor", id: id)
        }

        do {
            let transformed = Self.transformClientJSON(descriptorData)
            let descriptor = try decoder.decode(AtollLockScreenWidgetDescriptor.self, from: transformed)
            try ExtensionDescriptorValidator.validate(descriptor)
            try widgetManager.present(descriptor: descriptor, bundleIdentifier: descriptor.bundleIdentifier)
            logDiagnostics("RPC: Presented widget \(descriptor.id) for \(descriptor.bundleIdentifier)")
            return RPCSuccessResponse(result: ["success": .bool(true)], id: id)
        } catch let error as ExtensionValidationError {
            return errorResponse(from: error, id: id)
        } catch {
            logDiagnostics("RPC: Decode error for presentWidget: \(error)")
            logDiagnostics("RPC: Raw payload: \(String(data: descriptorData, encoding: .utf8) ?? "<binary>")")
            return errorResponse(code: RPCErrorCode.internalError, message: error.localizedDescription, id: id)
        }
    }

    private func handleUpdateLockScreenWidget(params: RPCParams?, id: String) -> Codable {
        guard let descriptorData = params?.jsonData(for: "descriptor") else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Missing descriptor", id: id)
        }

        do {
            let transformed = Self.transformClientJSON(descriptorData)
            let descriptor = try decoder.decode(AtollLockScreenWidgetDescriptor.self, from: transformed)
            try widgetManager.update(descriptor: descriptor, bundleIdentifier: descriptor.bundleIdentifier)
            logDiagnostics("RPC: Updated widget \(descriptor.id) for \(descriptor.bundleIdentifier)")
            return RPCSuccessResponse(result: ["success": .bool(true)], id: id)
        } catch let error as ExtensionValidationError {
            return errorResponse(from: error, id: id)
        } catch {
            logDiagnostics("RPC: Decode error for updateWidget: \(error)")
            return errorResponse(code: RPCErrorCode.internalError, message: error.localizedDescription, id: id)
        }
    }

    private func handleDismissLockScreenWidget(params: RPCParams?, id: String) -> Codable {
        guard let widgetID = params?["widgetID"]?.stringValue else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Missing widgetID", id: id)
        }
        let bi = params?["bundleIdentifier"]?.stringValue ?? bundleIdentifier
        widgetManager.dismiss(widgetID: widgetID, bundleIdentifier: bi)
        logDiagnostics("RPC: Dismissed widget \(widgetID) for \(bi)")
        return RPCSuccessResponse(result: ["success": .bool(true)], id: id)
    }

    // MARK: - Notch Experiences

    private func handlePresentNotchExperience(params: RPCParams?, id: String) -> Codable {
        guard let descriptorData = params?.jsonData(for: "descriptor") else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Missing descriptor", id: id)
        }

        do {
            let transformed = Self.transformClientJSON(descriptorData)
            let descriptor = try decoder.decode(AtollNotchExperienceDescriptor.self, from: transformed)
            try ExtensionDescriptorValidator.validate(descriptor)
            try notchManager.present(descriptor: descriptor, bundleIdentifier: descriptor.bundleIdentifier)
            logDiagnostics("RPC: Presented notch experience \(descriptor.id) for \(descriptor.bundleIdentifier)")
            return RPCSuccessResponse(result: ["success": .bool(true)], id: id)
        } catch let error as ExtensionValidationError {
            return errorResponse(from: error, id: id)
        } catch {
            logDiagnostics("RPC: Decode error for presentNotchExperience: \(error)")
            logDiagnostics("RPC: Raw payload: \(String(data: descriptorData, encoding: .utf8) ?? "<binary>")")
            return errorResponse(code: RPCErrorCode.internalError, message: error.localizedDescription, id: id)
        }
    }

    private func handleUpdateNotchExperience(params: RPCParams?, id: String) -> Codable {
        guard let descriptorData = params?.jsonData(for: "descriptor") else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Missing descriptor", id: id)
        }

        do {
            let transformed = Self.transformClientJSON(descriptorData)
            let descriptor = try decoder.decode(AtollNotchExperienceDescriptor.self, from: transformed)
            try notchManager.update(descriptor: descriptor, bundleIdentifier: descriptor.bundleIdentifier)
            logDiagnostics("RPC: Updated notch experience \(descriptor.id) for \(descriptor.bundleIdentifier)")
            return RPCSuccessResponse(result: ["success": .bool(true)], id: id)
        } catch let error as ExtensionValidationError {
            return errorResponse(from: error, id: id)
        } catch {
            logDiagnostics("RPC: Decode error for updateNotchExperience: \(error)")
            return errorResponse(code: RPCErrorCode.internalError, message: error.localizedDescription, id: id)
        }
    }

    private func handleDismissNotchExperience(params: RPCParams?, id: String) -> Codable {
        guard let experienceID = params?["experienceID"]?.stringValue else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Missing experienceID", id: id)
        }
        let bi = params?["bundleIdentifier"]?.stringValue ?? bundleIdentifier
        notchManager.dismiss(experienceID: experienceID, bundleIdentifier: bi)
        logDiagnostics("RPC: Dismissed notch experience \(experienceID) for \(bi)")
        return RPCSuccessResponse(result: ["success": .bool(true)], id: id)
    }

    // MARK: - Helpers

    private func errorResponse(code: Int, message: String, id: String) -> RPCErrorResponse {
        RPCErrorResponse(
            error: RPCErrorObject(code: code, message: message),
            id: id
        )
    }

    private func errorResponse(from error: ExtensionValidationError, id: String) -> RPCErrorResponse {
        let code: Int
        switch error {
        case .featureDisabled:     code = RPCErrorCode.featureDisabled
        case .unauthorized:        code = RPCErrorCode.unauthorized
        case .invalidDescriptor:   code = RPCErrorCode.descriptorInvalid
        case .exceedsCapacity:     code = RPCErrorCode.capacityExceeded
        case .unsupportedContent:  code = RPCErrorCode.unsupported
        case .rateLimited:         code = RPCErrorCode.internalError
        case .duplicateIdentifier: code = RPCErrorCode.descriptorInvalid
        }
        return RPCErrorResponse(
            error: RPCErrorObject(code: code, message: error.localizedDescription),
            id: id
        )
    }

    private func logDiagnostics(_ message: String) {
        guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
        Logger.log(message, category: .extensions)
    }

    // MARK: - File Sharing Authorization Check

    private func checkFileSharingAuthorization(id: String) -> RPCErrorResponse? {
        guard Defaults[.enableThirdPartyExtensions] else {
            return errorResponse(code: RPCErrorCode.featureDisabled, message: "Extensions are disabled", id: id)
        }
        guard Defaults[.enableExtensionFileSharing] else {
            return errorResponse(code: RPCErrorCode.featureDisabled, message: "Extension file sharing is disabled", id: id)
        }
        let entry = authorizationManager.authorizationEntry(for: bundleIdentifier)
        guard entry?.isAuthorized == true else {
            return errorResponse(code: RPCErrorCode.unauthorized, message: "Extension not authorized", id: id)
        }
        guard entry?.allowedScopes.contains(.fileSharing) == true else {
            return errorResponse(code: RPCErrorCode.unauthorized, message: "File sharing scope not granted", id: id)
        }
        return nil
    }

    // MARK: - File Sharing Handlers

    private func handleGetShelfItems(params: RPCParams?, id: String) -> Codable {
        if let err = checkFileSharingAuthorization(id: id) { return err }

        let items = ShelfStateViewModel.shared.items
        var result: [RPCValue] = []

        for item in items {
            var entry: [String: RPCValue] = [
                "id": .string(item.id.uuidString),
                "name": .string(item.displayName)
            ]
            switch item.kind {
            case .file(let bookmark):
                entry["kind"] = .string("file")
                if let url = Bookmark(data: bookmark).resolveURL() {
                    entry["path"] = .string(url.path)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let size = attrs[.size] as? Int {
                        entry["size"] = .int(size)
                    }
                }
            case .text(let string):
                entry["kind"] = .string("text")
                entry["textContent"] = .string(string)
            case .link(let url):
                entry["kind"] = .string("link")
                entry["url"] = .string(url.absoluteString)
            }
            result.append(.object(entry))
        }

        logDiagnostics("RPC: getShelfItems returned \(result.count) items for \(bundleIdentifier)")
        return RPCSuccessResponse(result: ["items": .array(result)], id: id)
    }

    private func handleGetShelfItemData(params: RPCParams?, id: String) -> Codable {
        if let err = checkFileSharingAuthorization(id: id) { return err }

        guard let itemID = params?["itemID"]?.stringValue,
              let uuid = UUID(uuidString: itemID) else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Missing or invalid itemID", id: id)
        }

        guard let item = ShelfStateViewModel.shared.items.first(where: { $0.id == uuid }) else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Item not found", id: id)
        }

        switch item.kind {
        case .file(let bookmark):
            guard let url = Bookmark(data: bookmark).resolveURL() else {
                return errorResponse(code: RPCErrorCode.internalError, message: "Cannot resolve file bookmark", id: id)
            }
            guard let fileData = url.accessSecurityScopedResource(accessor: { try? Data(contentsOf: $0) }) else {
                return errorResponse(code: RPCErrorCode.internalError, message: "Cannot read file data", id: id)
            }
            let base64 = fileData.base64EncodedString()
            logDiagnostics("RPC: getShelfItemData returned \(fileData.count) bytes for \(bundleIdentifier)")
            return RPCSuccessResponse(result: [
                "data": .string(base64),
                "fileName": .string(url.lastPathComponent),
                "mimeType": .string(url.mimeType ?? "application/octet-stream")
            ], id: id)
        case .text(let string):
            return RPCSuccessResponse(result: [
                "data": .string(Data(string.utf8).base64EncodedString()),
                "fileName": .string("text.txt"),
                "mimeType": .string("text/plain")
            ], id: id)
        case .link(let url):
            return RPCSuccessResponse(result: [
                "data": .string(Data(url.absoluteString.utf8).base64EncodedString()),
                "fileName": .string("link.url"),
                "mimeType": .string("text/uri-list")
            ], id: id)
        }
    }

    private func handleShowFilePicker(params: RPCParams?, id: String) -> Codable {
        if let err = checkFileSharingAuthorization(id: id) { return err }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Select files to share"

        let response = panel.runModal()
        guard response == .OK, !panel.urls.isEmpty else {
            return RPCSuccessResponse(result: ["itemIDs": .array([])], id: id)
        }

        var newItemIDs: [RPCValue] = []
        var newItems: [ShelfItem] = []

        for url in panel.urls {
            if let bookmark = try? Bookmark(url: url) {
                let item = ShelfItem(kind: .file(bookmark: bookmark.data))
                newItems.append(item)
                newItemIDs.append(.string(item.id.uuidString))
            }
        }

        ShelfStateViewModel.shared.add(newItems)
        logDiagnostics("RPC: showFilePicker added \(newItems.count) items for \(bundleIdentifier)")
        return RPCSuccessResponse(result: ["itemIDs": .array(newItemIDs)], id: id)
    }

    private func handleShareShelfItems(params: RPCParams?, id: String) async -> Codable {
        if let err = checkFileSharingAuthorization(id: id) { return err }

        guard let itemIDsValue = params?["itemIDs"],
              case .array(let itemIDArray) = itemIDsValue else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Missing itemIDs array", id: id)
        }

        let provider = params?["provider"]?.stringValue ?? "AirDrop"
        let itemIDs = itemIDArray.compactMap { $0.stringValue }.compactMap { UUID(uuidString: $0) }
        let items = ShelfStateViewModel.shared.items.filter { itemIDs.contains($0.id) }

        guard !items.isEmpty else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "No matching shelf items found", id: id)
        }

        // Use async resolution since this is called from an async context
        let urls = await ShelfStateViewModel.shared.resolveFileURLsAsync(for: items)
        guard !urls.isEmpty else {
            return errorResponse(code: RPCErrorCode.internalError, message: "Could not resolve file URLs", id: id)
        }

        // Find and invoke the sharing service
        QuickShareService.shared.ensureDiscovered()
        if let shareProvider = QuickShareService.shared.availableProviders.first(where: { $0.id == provider }) {
            Task {
                await QuickShareService.shared.shareFilesOrText(urls, using: shareProvider, from: nil)
            }
            logDiagnostics("RPC: shareShelfItems sharing \(urls.count) files via \(provider) for \(bundleIdentifier)")
            return RPCSuccessResponse(result: ["success": .bool(true), "fileCount": .int(urls.count)], id: id)
        } else {
            return errorResponse(code: RPCErrorCode.invalidParams, message: "Provider '\(provider)' not found", id: id)
        }
    }

    // Sync wrapper for backward compatibility - calls async version with semaphore
    private func handleShareShelfItemsSync(params: RPCParams?, id: String) -> Codable {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Codable!
        Task.detached { [weak self] in
            guard let self = self else { return }
            result = await self.handleShareShelfItems(params: params, id: id)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 30.0)
        return result
    }

    private func handleAddFilesToShelf(params: RPCParams?, id: String) -> Codable {
        if let err = checkFileSharingAuthorization(id: id) { return err }

        var newItems: [ShelfItem] = []
        var newItemIDs: [RPCValue] = []

        // Handle file paths
        if let pathsValue = params?["paths"],
           case .array(let pathArray) = pathsValue {
            for pathValue in pathArray {
                guard let path = pathValue.stringValue else { continue }
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: path) else { continue }
                if let bookmark = try? Bookmark(url: url) {
                    let item = ShelfItem(kind: .file(bookmark: bookmark.data))
                    newItems.append(item)
                    newItemIDs.append(.string(item.id.uuidString))
                }
            }
        }

        // Handle base64-encoded file data
        if let filesValue = params?["files"],
           case .array(let filesArray) = filesValue {
            for fileValue in filesArray {
                guard case .object(let fileObj) = fileValue,
                      let dataStr = fileObj["data"]?.stringValue,
                      let fileName = fileObj["fileName"]?.stringValue,
                      let fileData = Data(base64Encoded: dataStr) else { continue }

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("AtollExtensionFiles", isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let fileURL = tempDir.appendingPathComponent(fileName)
                guard (try? fileData.write(to: fileURL)) != nil else { continue }

                if let bookmark = try? Bookmark(url: fileURL) {
                    let item = ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: true)
                    newItems.append(item)
                    newItemIDs.append(.string(item.id.uuidString))
                }
            }
        }

        // Handle text content
        if let text = params?["text"]?.stringValue, !text.isEmpty {
            let item = ShelfItem(kind: .text(string: text))
            newItems.append(item)
            newItemIDs.append(.string(item.id.uuidString))
        }

        ShelfStateViewModel.shared.add(newItems)
        logDiagnostics("RPC: addFilesToShelf added \(newItems.count) items for \(bundleIdentifier)")
        return RPCSuccessResponse(result: ["itemIDs": .array(newItemIDs)], id: id)
    }

    private func handleSubscribeShelfEvents(params: RPCParams?, id: String) -> Codable {
        if let err = checkFileSharingAuthorization(id: id) { return err }

        server?.registerShelfSubscription(for: bundleIdentifier)
        logDiagnostics("RPC: subscribeShelfEvents registered for \(bundleIdentifier)")
        return RPCSuccessResponse(result: ["subscribed": .bool(true)], id: id)
    }

    // MARK: - Client JSON Transformation

    /// Converts client wire format to Swift Codable format for enum types.
    ///
    /// Client sends: `{ "type": "symbol", "name": "timer", "size": 16 }`
    /// Swift expects: `{ "symbol": { "name": "timer", "size": 16 } }`
    ///
    /// For enums with unnamed parameters (e.g., `case text(String, font:, color:)`):
    /// Client sends: `{ "type": "text", "text": "LIVE", "font": {...} }`
    /// Swift expects: `{ "text": { "_0": "LIVE", "font": {...} } }`
    static func transformClientJSON(_ data: Data) -> Data {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        let transformed = transformObject(json)
        return (try? JSONSerialization.data(withJSONObject: transformed)) ?? data
    }

    private static func transformObject(_ obj: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]

        for (key, value) in obj {
            if let dict = value as? [String: Any] {
                if enumKeys.contains(key), let typeName = dict["type"] as? String {
                    // Transform: { "type": "symbol", ... } → { "symbol": { ... } }
                    result[key] = transformEnumValue(dict, typeName: typeName)
                } else {
                    result[key] = transformObject(dict)
                }
            } else if let arr = value as? [[String: Any]] {
                // Arrays like "content", "elements", "sections"
                result[key] = arr.map { item in
                    if let typeName = item["type"] as? String,
                       (key == "content" || key == "elements") {
                        return transformEnumValue(item, typeName: typeName)
                    }
                    return transformObject(item)
                }
            } else {
                result[key] = value
            }
        }

        return result
    }

    /// Transforms `{ "type": "caseName", ...params }` → `{ "caseName": { ...params } }`.
    /// Handles special cases where Swift enum cases have unnamed first parameters:
    /// - `text` / `marquee`: `text` field → `_0`
    /// - `icon`: `icon` field → `_0` (AtollIconDescriptor)
    /// - `progress`: `indicator` field → `_0` (AtollProgressIndicator)
    /// - `webView`: `content` field → `_0` (AtollWidgetWebContentDescriptor)
    /// - `animation`: `data` field → `_0` (Data)
    private static func transformEnumValue(_ dict: [String: Any], typeName: String) -> [String: Any] {
        var inner: [String: Any] = [:]

        for (k, v) in dict where k != "type" {
            if let nestedDict = v as? [String: Any] {
                // Check if this nested dict is an enum-typed field
                if (enumKeys.contains(k) || k == "indicator"),
                   let nestedType = nestedDict["type"] as? String {
                    inner[k] = transformEnumValue(nestedDict, typeName: nestedType)
                } else {
                    inner[k] = transformObject(nestedDict)
                }
            } else if let nestedArr = v as? [[String: Any]] {
                inner[k] = nestedArr.map { item in
                    if let t = item["type"] as? String {
                        return transformEnumValue(item, typeName: t)
                    }
                    return transformObject(item)
                }
            } else {
                inner[k] = v
            }
        }

        // Handle unnamed first parameter for specific enum cases.
        // Swift's auto-synthesized Codable encodes unnamed associated values as `_0`, `_1`, etc.
        switch typeName {
        case "text":
            // AtollTrailingContent.text(String, ...) AND AtollWidgetContentElement.text(String, ...)
            if let textValue = inner.removeValue(forKey: "text") {
                inner["_0"] = textValue
            }
        case "marquee":
            // AtollTrailingContent.marquee(String, ...)
            if let textValue = inner.removeValue(forKey: "text") {
                inner["_0"] = textValue
            }
        case "icon":
            // AtollWidgetContentElement.icon(AtollIconDescriptor, tint:)
            if let iconValue = inner.removeValue(forKey: "icon") {
                inner["_0"] = iconValue
            }
        case "progress":
            // AtollWidgetContentElement.progress(AtollProgressIndicator, value:, color:)
            if let indicatorValue = inner.removeValue(forKey: "indicator") {
                inner["_0"] = indicatorValue
            }
        case "webView":
            // AtollWidgetContentElement.webView(AtollWidgetWebContentDescriptor)
            if let contentValue = inner.removeValue(forKey: "content") {
                inner["_0"] = contentValue
            }
        case "animation":
            // AtollTrailingContent.animation(data:, size:) — data is named but let's be safe
            break
        default:
            break
        }

        return [typeName: inner]
    }
}

// MARK: - URL MIME Type Helper

private extension URL {
    var mimeType: String? {
        guard let uti = UTType(filenameExtension: self.pathExtension) else { return nil }
        return uti.preferredMIMEType
    }
}
