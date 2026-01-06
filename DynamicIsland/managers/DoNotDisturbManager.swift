//
//  DoNotDisturbManager.swift
//  DynamicIsland
//
//  Replaces the legacy polling-based Focus detection with
//  NSDistributedNotificationCenter-backed monitoring.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

final class DoNotDisturbManager: ObservableObject {
    static let shared = DoNotDisturbManager()

    @Published private(set) var isMonitoring = false
    @Published var isDoNotDisturbActive = false
    @Published var currentFocusModeName: String = ""
    @Published var currentFocusModeIdentifier: String = ""

    private let notificationCenter = DistributedNotificationCenter.default()
    private let metadataExtractionQueue = DispatchQueue(label: "com.dynamicisland.focus.metadata", qos: .userInitiated)
    private let focusLogStream = FocusLogStream()

    private init() {
        focusLogStream.onMetadataUpdate = { [weak self] identifier, name in
            self?.handleLogMetadataUpdate(identifier: identifier, name: name)
        }
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusEnabled(_:)),
            name: .focusModeEnabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusDisabled(_:)),
            name: .focusModeDisabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        focusLogStream.start()
        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        notificationCenter.removeObserver(self, name: .focusModeEnabled, object: nil)
        notificationCenter.removeObserver(self, name: .focusModeDisabled, object: nil)

        focusLogStream.stop()
        isMonitoring = false

        DispatchQueue.main.async {
            self.isDoNotDisturbActive = false
            self.currentFocusModeIdentifier = ""
            self.currentFocusModeName = ""
        }
    }

    @objc private func handleFocusEnabled(_ notification: Notification) {
        apply(notification: notification, isActive: true)
    }

    @objc private func handleFocusDisabled(_ notification: Notification) {
        apply(notification: notification, isActive: false)
    }

    private func apply(notification: Notification, isActive: Bool) {
        metadataExtractionQueue.async { [weak self] in
            guard let self = self else { return }

            let metadata = self.extractMetadata(from: notification)
            self.publishMetadata(identifier: metadata.identifier, name: metadata.name, isActive: isActive, source: notification.name.rawValue)
        }
    }

    private func publishMetadata(identifier: String?, name: String?, isActive: Bool?, source: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)

            let resolvedMode = FocusModeType.resolve(identifier: trimmedIdentifier, name: trimmedName)

            let finalIdentifier: String
            if let identifier = trimmedIdentifier, !identifier.isEmpty {
                finalIdentifier = identifier
            } else {
                finalIdentifier = resolvedMode.rawValue
            }

            let finalName: String
            if let name = trimmedName, !name.isEmpty {
                finalName = name
            } else if !resolvedMode.displayName.isEmpty {
                finalName = resolvedMode.displayName
            } else if let identifier = trimmedIdentifier, !identifier.isEmpty {
                finalName = identifier
            } else {
                finalName = "Focus"
            }

            let previousIdentifier = self.currentFocusModeIdentifier
            let previousName = self.currentFocusModeName
            let previousActive = self.isDoNotDisturbActive

            let identifierChanged = finalIdentifier != previousIdentifier
            let nameChanged = finalName != previousName
            let shouldToggleActive = isActive.map { $0 != previousActive } ?? false

            if identifierChanged {
                self.currentFocusModeIdentifier = finalIdentifier
            }

            if nameChanged {
                self.currentFocusModeName = finalName
            }

            if identifierChanged || nameChanged || shouldToggleActive {
                debugPrint("[DoNotDisturbManager] Focus update -> source: \(source) | identifier: \(trimmedIdentifier ?? "<nil>") | name: \(trimmedName ?? "<nil>") | resolved: \(resolvedMode.rawValue)")
            }

            guard let isActive = isActive, shouldToggleActive else { return }

            withAnimation(.smooth(duration: 0.25)) {
                self.isDoNotDisturbActive = isActive
            }
        }
    }

    private func handleLogMetadataUpdate(identifier: String?, name: String?) {
        metadataExtractionQueue.async { [weak self] in
            guard let self = self else { return }
            let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)

            let hasIdentifier = (trimmedIdentifier?.isEmpty == false)
            let hasName = (trimmedName?.isEmpty == false)

            guard hasIdentifier || hasName else { return }

            self.publishMetadata(identifier: trimmedIdentifier, name: trimmedName, isActive: nil, source: "log-stream")
        }
    }

    private func extractMetadata(from notification: Notification) -> (name: String?, identifier: String?) {
        var identifier: String?
        var name: String?

        let identifierKeys = [
            "FocusModeIdentifier",
            "focusModeIdentifier",
            "FocusModeUUID",
            "focusModeUUID",
            "UUID",
            "uuid",
            "identifier",
            "Identifier"
        ]

        let nameKeys = [
            "FocusModeName",
            "focusModeName",
            "FocusMode",
            "focusMode",
            "displayName",
            "display_name",
            "name",
            "Name"
        ]

        var candidates: [Any] = []
        if let userInfo = notification.userInfo {
            candidates.append(userInfo)
        }

        if let object = notification.object {
            candidates.append(object)
        }

        debugPrint("[DoNotDisturbManager] raw focus payload -> name: \(notification.name.rawValue), object: \(String(describing: notification.object)), userInfo: \(String(describing: notification.userInfo))")

        for candidate in candidates {
            if identifier == nil {
                identifier = firstMatch(for: identifierKeys, in: candidate)
            }

            if name == nil {
                name = firstMatch(for: nameKeys, in: candidate)
            }

            if identifier != nil && name != nil {
                break
            }
        }

        if identifier == nil || name == nil {
            for candidate in candidates {
                if let decoded = decodeFocusPayloadIfNeeded(candidate) {
                    if identifier == nil {
                        identifier = firstMatch(for: identifierKeys, in: decoded)
                    }

                    if name == nil {
                        name = firstMatch(for: nameKeys, in: decoded)
                    }

                    if identifier != nil && name != nil {
                        break
                    }
                }
            }
        }

        if identifier == nil || name == nil {
            for candidate in candidates {
                if let object = candidate as? NSObject {
                    if identifier == nil, let extractedIdentifier = extractIdentifier(fromFocusObject: object) {
                        identifier = extractedIdentifier
                    }

                    if name == nil, let extractedName = extractDisplayName(fromFocusObject: object) {
                        name = extractedName
                    }

                    if identifier != nil && name != nil {
                        break
                    }
                }
            }
        }

        if identifier == nil || name == nil {
            var descriptionSources: [Any] = candidates

            for candidate in candidates {
                if let decoded = decodeFocusPayloadIfNeeded(candidate) {
                    descriptionSources.append(decoded)
                }
            }

            for candidate in descriptionSources {
                let description = String(describing: candidate)

                if identifier == nil, let inferredIdentifier = FocusMetadataDecoder.extractIdentifier(from: description) {
                    identifier = inferredIdentifier
                }

                if name == nil, let inferredName = FocusMetadataDecoder.extractName(from: description) {
                    name = inferredName
                }

                if identifier != nil && name != nil {
                    break
                }
            }
        }

        if identifier == nil || name == nil {
            if let logMetadata = focusLogStream.latestMetadata() {
                if identifier == nil {
                    identifier = logMetadata.identifier
                }

                if name == nil {
                    name = logMetadata.name
                }
            }
        }

        return (name, identifier)
    }

}

private extension Notification.Name {
    static let focusModeEnabled = Notification.Name("_NSDoNotDisturbEnabledNotification")
    static let focusModeDisabled = Notification.Name("_NSDoNotDisturbDisabledNotification")
}

// MARK: - Focus Mode Types

enum FocusModeType: String, CaseIterable {
    case doNotDisturb = "com.apple.donotdisturb.mode"
    case work = "com.apple.focus.work"
    case personal = "com.apple.focus.personal"
    case sleep = "com.apple.focus.sleep"
    case driving = "com.apple.focus.driving"
    case fitness = "com.apple.focus.fitness"
    case reduceInterruptions = "com.apple.focus.reduce-interruptions"
    case gaming = "com.apple.focus.gaming"
    case mindfulness = "com.apple.focus.mindfulness"
    case reading = "com.apple.focus.reading"
    case custom = "com.apple.focus.custom"
    case unknown = ""
    
    var displayName: String {
        switch self {
    case .doNotDisturb: return "Do Not Disturb"
        case .work: return "Work"
        case .personal: return "Personal"
        case .sleep: return "Sleep"
        case .driving: return "Driving"
        case .fitness: return "Fitness"
        case .reduceInterruptions: return "Reduce Interruptions"
        case .gaming: return "Gaming"
        case .mindfulness: return "Mindfulness"
        case .reading: return "Reading"
        case .custom: return "Focus"
        case .unknown: return "Focus Mode"
        }
    }
    
    var sfSymbol: String {
        switch self {
        case .doNotDisturb: return "moon.fill"
        case .work: return "briefcase.fill"
        case .personal: return "person.fill"
        case .sleep: return "bed.double.fill"
        case .driving: return "car.fill"
        case .fitness: return "figure.run"
        case .reduceInterruptions: return "apple.intelligence"
        case .gaming: return "gamecontroller.fill"
        case .mindfulness: return "circle.hexagongrid"
        case .reading: return "book.closed.fill"
        case .custom: return "app.badge"
        case .unknown: return "moon.fill"
        }
    }

    var internalSymbolName: String? {
        switch self {
        case .work: return "person.lanyardcard.fill"
        case .mindfulness: return "apple.mindfulness"
        case .gaming: return "rocket.fill"
        case .reduceInterruptions: return "apple.intelligence"
        default: return nil
        }
    }

    var activeIcon: Image {
        resolvedActiveIcon()
    }

    func resolvedActiveIcon(usePrivateSymbol: Bool = true) -> Image {
        if usePrivateSymbol,
           let internalSymbolName,
           let image = Image(internalSystemName: internalSymbolName) {
            return image
        }

        return Image(systemName: sfSymbol)
    }

    var accentColor: Color {
        switch self {
        case .doNotDisturb:
            return Color(red: 0.370, green: 0.360, blue: 0.902)
        case .work:
            return Color(red: 0.414, green: 0.769, blue: 0.863, opacity: 1.0)
        case .personal:
            return Color(red: 0.748, green: 0.354, blue: 0.948, opacity: 1.0)
        case .sleep:
            return Color(red: 0.341, green: 0.384, blue: 0.980)
        case .driving:
            return Color(red: 0.427, green: 0.486, blue: 0.996)
        case .fitness:
            return Color(red: 0.176, green: 0.804, blue: 0.459)
        case .reduceInterruptions:
            return Color(red: 0.878, green: 0.475, blue: 0.912, opacity: 1.0)
        case .gaming:
            return Color(red: 0.043, green: 0.518, blue: 1.000, opacity: 1.0)
        case .mindfulness:
            return Color(red: 0.361, green: 0.898, blue: 0.883, opacity: 1.0)
        case .reading:
            return Color(red: 1.000, green: 0.622, blue: 0.044, opacity: 1.0)
        case .custom:
            return Color(red: 0.513, green: 0.478, blue: 0.965)
        case .unknown:
            return Color(red: 0.370, green: 0.360, blue: 0.902)
        }
    }

    var inactiveSymbol: String {
        switch self {
        case .doNotDisturb:
            return "moon.circle.fill"
        default:
            return sfSymbol
        }
    }
}

extension FocusModeType {
    init(identifier: String) {
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLowercased = normalized.lowercased()

        guard !normalized.isEmpty else {
            self = .doNotDisturb
            return
        }

        if let direct = FocusModeType(rawValue: normalized) ?? FocusModeType(rawValue: normalizedLowercased) {
            self = direct
            return
        }

        if let resolved = FocusModeType.allCases.first(where: {
            guard !$0.rawValue.isEmpty else { return false }
            return normalized.hasPrefix($0.rawValue) || normalizedLowercased.hasPrefix($0.rawValue)
        }) {
            self = resolved
            return
        }

        if normalizedLowercased.hasPrefix("com.apple.focus.") {
            self = .custom
            return
        }

        self = .doNotDisturb
    }

    static func resolve(identifier: String?, name: String?) -> FocusModeType {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            if let match = FocusModeType.allCases.first(where: {
                guard !$0.displayName.isEmpty else { return false }
                return $0.displayName.compare(trimmedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return match
            }
        }

        let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedIdentifier.isEmpty {
            return FocusModeType(identifier: trimmedIdentifier)
        }

        return .doNotDisturb
    }
}

// MARK: - Metadata helpers

private extension DoNotDisturbManager {
    func firstMatch(for keys: [String], in value: Any) -> String? {
        if let dictionary = value as? [AnyHashable: Any] {
            for key in keys {
                if let candidate = dictionary[key], let string = normalizedString(from: candidate) {
                    return string
                }
            }

            for nestedValue in dictionary.values {
                if let nestedMatch = firstMatch(for: keys, in: nestedValue) {
                    return nestedMatch
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let nestedMatch = firstMatch(for: keys, in: element) {
                    return nestedMatch
                }
            }
        }

        return nil
    }

    func normalizedString(from value: Any) -> String? {
        switch value {
        case let string as String:
            let cleaned = FocusMetadataDecoder.cleanedString(string)
            return cleaned.isEmpty ? nil : cleaned
        case let number as NSNumber:
            return FocusMetadataDecoder.cleanedString(number.stringValue)
        case let uuid as UUID:
            return uuid.uuidString
        case let uuid as NSUUID:
            return uuid.uuidString
        case let data as Data:
            if let decoded = decodeFocusPayload(from: data) {
                if let nested = firstMatch(for: ["identifier", "Identifier", "uuid", "UUID"], in: decoded) {
                    return nested
                }
                if let name = firstMatch(for: ["name", "Name", "displayName", "display_name"], in: decoded) {
                    return name
                }
            }
            if let string = String(data: data, encoding: .utf8) {
                let cleaned = FocusMetadataDecoder.cleanedString(string)
                return cleaned.isEmpty ? nil : cleaned
            }
            return nil
        case let dict as [AnyHashable: Any]:
            // Attempt to pull common keys from nested dictionaries
            if let nested = firstMatch(for: ["identifier", "Identifier", "uuid", "UUID"], in: dict) {
                return nested
            }
            if let name = firstMatch(for: ["name", "Name", "displayName", "display_name"], in: dict) {
                return name
            }
            return nil
        default:
            return nil
        }
    }

    func decodeFocusPayloadIfNeeded(_ value: Any) -> Any? {
        switch value {
        case let data as Data:
            return decodeFocusPayload(from: data)
        case let data as NSData:
            return decodeFocusPayload(from: data as Data)
        default:
            return nil
        }
    }

    func decodeFocusPayload(from data: Data) -> Any? {
        guard !data.isEmpty else { return nil }

        if let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) {
            return propertyList
        }

        if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return jsonObject
        }

        if let string = String(data: data, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        return nil
    }

    func extractIdentifier(fromFocusObject object: NSObject) -> String? {
        if let array = object as? [Any] {
            for element in array {
                if let nested = element as? NSObject, let identifier = extractIdentifier(fromFocusObject: nested) {
                    return identifier
                }
            }
            return nil
        }

        if let identifier = focusString(object, selector: "modeIdentifier") {
            return identifier
        }

        if let identifier = focusString(object, selector: "identifier") {
            return identifier
        }

        if let details = focusObject(object, selector: "details"), let identifier = extractIdentifier(fromFocusObject: details) {
            return identifier
        }

        if let metadata = focusObject(object, selector: "activeModeAssertionMetadata"), let identifier = extractIdentifier(fromFocusObject: metadata) {
            return identifier
        }

        if let configuration = focusObject(object, selector: "activeModeConfiguration"), let identifier = extractIdentifier(fromFocusObject: configuration) {
            return identifier
        }

        if let modeConfiguration = focusObject(object, selector: "modeConfiguration"), let identifier = extractIdentifier(fromFocusObject: modeConfiguration) {
            return identifier
        }

        if let mode = focusObject(object, selector: "mode") {
            return extractIdentifier(fromFocusObject: mode)
        }

        if let identifiers = focusObject(object, selector: "activeModeIdentifiers") {
            if let stringArray = identifiers as? [String] {
                if let first = stringArray.compactMap({ FocusMetadataDecoder.cleanedString($0) }).first(where: { !$0.isEmpty }) {
                    return first
                }
            } else if let array = identifiers as? NSArray {
                for case let string as String in array {
                    let trimmed = FocusMetadataDecoder.cleanedString(string)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }

        return nil
    }

    func extractDisplayName(fromFocusObject object: NSObject) -> String? {
        if let array = object as? [Any] {
            for element in array {
                if let nested = element as? NSObject, let name = extractDisplayName(fromFocusObject: nested) {
                    return name
                }
            }
            return nil
        }

        if let name = focusString(object, selector: "name") {
            return name
        }

        if let name = focusString(object, selector: "displayName") {
            return name
        }

        if let name = focusString(object, selector: "activityDisplayName") {
            return name
        }

        if let descriptor = focusObject(object, selector: "symbolDescriptor"), let name = focusString(descriptor, selector: "name") {
            return name
        }

        if let mode = focusObject(object, selector: "mode"), let name = extractDisplayName(fromFocusObject: mode) {
            return name
        }

        if let details = focusObject(object, selector: "details"), let name = extractDisplayName(fromFocusObject: details) {
            return name
        }

        if let configuration = focusObject(object, selector: "modeConfiguration"), let name = extractDisplayName(fromFocusObject: configuration) {
            return name
        }

        return nil
    }

    func focusObject(_ object: NSObject, selector selectorName: String) -> NSObject? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        guard let value = object.perform(selector)?.takeUnretainedValue() else { return nil }
        return value as? NSObject
    }

    func focusString(_ object: NSObject, selector selectorName: String) -> String? {
        let selector = NSSelectorFromString(selectorName)
        guard object.responds(to: selector) else { return nil }
        guard let value = object.perform(selector)?.takeUnretainedValue() else { return nil }

        switch value {
        case let string as String:
            return FocusMetadataDecoder.cleanedString(string)
        case let string as NSString:
            return FocusMetadataDecoder.cleanedString(string as String)
        case let number as NSNumber:
            return FocusMetadataDecoder.cleanedString(number.stringValue)
        default:
            return nil
        }
    }

}

private final class FocusLogStream {
    private let queue = DispatchQueue(label: "com.dynamicisland.focus.logstream", qos: .utility)
    private var process: Process?
    private var pipe: Pipe?
    private var buffer = Data()
    private var isRunning = false

    private let metadataLock = NSLock()
    private var lastIdentifier: String?
    private var lastName: String?

    var onMetadataUpdate: ((String?, String?) -> Void)?

    func start() {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isRunning else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = [
                "stream",
                "--style",
                "compact",
                "--level",
                "info",
                "--predicate",
                "subsystem == \"com.apple.focus\""
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let data = handle.availableData

                if data.isEmpty {
                    self.queue.async { [weak self] in
                        self?.handleTermination()
                    }
                    return
                }

                self.queue.async { [weak self] in
                    self?.handleIncomingData(data)
                }
            }

            process.terminationHandler = { [weak self] _ in
                self?.queue.async {
                    self?.handleTermination()
                }
            }

            do {
                try process.run()
                self.process = process
                self.pipe = pipe
                self.isRunning = true
                debugPrint("[FocusLogStream] Started unified log tail for com.apple.focus")
            } catch {
                debugPrint("[FocusLogStream] Failed to start log stream: \(error)")
                pipe.fileHandleForReading.readabilityHandler = nil
                self.process = nil
                self.pipe = nil
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.isRunning else { return }
            self.handleTermination(terminateProcess: true)
        }
    }

    func latestMetadata() -> (identifier: String?, name: String?)? {
        metadataLock.lock()
        let identifier = lastIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = lastName?.trimmingCharacters(in: .whitespacesAndNewlines)
        metadataLock.unlock()

        let normalizedIdentifier = (identifier?.isEmpty == false) ? identifier : nil
        let normalizedName = (name?.isEmpty == false) ? name : nil

        if normalizedIdentifier == nil && normalizedName == nil {
            return nil
        }

        return (normalizedIdentifier, normalizedName)
    }

    private func handleIncomingData(_ data: Data) {
        buffer.append(data)

        let newline: UInt8 = 0x0A

        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)

            let trimmedLineData: Data
            if let lastByte = lineData.last, lastByte == 0x0D {
                trimmedLineData = lineData.dropLast()
            } else {
                trimmedLineData = lineData
            }

            guard !trimmedLineData.isEmpty,
                  let line = String(data: trimmedLineData, encoding: .utf8) else {
                continue
            }

            processLine(line)
        }
    }

    private func processLine(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.hasPrefix("Filtering the log data") || trimmed.hasPrefix("Timestamp") {
            return
        }

        if trimmed.contains("active mode assertion: (null)") || trimmed.contains("active activity: (null)") {
            clearMetadata()
            return
        }

        var updatedIdentifier: String?
        var updatedName: String?

        if let identifier = FocusMetadataDecoder.extractIdentifier(from: trimmed), !identifier.isEmpty {
            updatedIdentifier = identifier
        }

        if let name = FocusMetadataDecoder.extractName(from: trimmed), !name.isEmpty {
            updatedName = name
        }

        guard updatedIdentifier != nil || updatedName != nil else { return }

        var identifierToSend: String?
        var nameToSend: String?

        metadataLock.lock()
        if let identifier = updatedIdentifier, !identifier.isEmpty {
            lastIdentifier = identifier
        }

        if let name = updatedName, !name.isEmpty {
            lastName = name
        }

        identifierToSend = lastIdentifier
        nameToSend = lastName
        metadataLock.unlock()

        notifyMetadataUpdate(identifier: identifierToSend, name: nameToSend)
    }

    private func clearMetadata() {
        metadataLock.lock()
        lastIdentifier = nil
        lastName = nil
        metadataLock.unlock()
        notifyMetadataUpdate(identifier: nil, name: nil)
    }

    private func handleTermination(terminateProcess: Bool = false) {
        if terminateProcess, let process, process.isRunning {
            process.terminate()
        }

        pipe?.fileHandleForReading.readabilityHandler = nil
        pipe?.fileHandleForReading.closeFile()
        pipe = nil

        process = nil
        buffer.removeAll(keepingCapacity: false)
        isRunning = false
        clearMetadata()
        debugPrint("[FocusLogStream] Stopped unified log tail for com.apple.focus")
    }

    private func notifyMetadataUpdate(identifier: String?, name: String?) {
        guard let handler = onMetadataUpdate else { return }
        handler(identifier, name)
    }
}

private enum FocusNotificationParsing {
    static let identifierPattern: NSRegularExpression? = {
        let pattern = "com\\.apple\\.(?:focus|donotdisturb)[A-Za-z0-9_.-]*"
        return try? NSRegularExpression(pattern: pattern, options: [])
    }()

    static let identifierDetailPatterns: [NSRegularExpression] = {
        let patterns = [
            "modeIdentifier:\\s*'([^'\\s]+)'",
            "activityIdentifier:\\s*([A-Za-z0-9._-]+)"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    static let namePatterns: [NSRegularExpression] = {
        let patterns = [
            "(?i)(?:focusModeName|focusMode|displayName|name)\\s*=\\s*\"([^\"]+)\"",
            "(?i)(?:focusModeName|focusMode|displayName|name)\\s*=\\s*([^;\\n]+)",
            "activityDisplayName:\\s*([^;>\\n]+)",
            "modeIdentifier:\\s*'com\\.apple\\.focus\\.([A-Za-z0-9._-]+)'"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()
}

private enum FocusMetadataDecoder {
    static func cleanedString(_ string: String) -> String {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        return trimmed
    }

    static func extractIdentifier(from description: String) -> String? {
        let fullRange = NSRange(description.startIndex..<description.endIndex, in: description)

        if let regex = FocusNotificationParsing.identifierPattern,
           let match = regex.firstMatch(in: description, options: [], range: fullRange),
           match.numberOfRanges > 0,
           let identifierRange = Range(match.range(at: 0), in: description) {
            let candidate = cleanedString(String(description[identifierRange]))
            if !candidate.isEmpty {
                return candidate
            }
        }

        for regex in FocusNotificationParsing.identifierDetailPatterns {
            if let match = regex.firstMatch(in: description, options: [], range: fullRange),
               match.numberOfRanges > 1,
               let identifierRange = Range(match.range(at: 1), in: description) {
                let candidate = cleanedString(String(description[identifierRange]))
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }

        return nil
    }

    static func extractName(from description: String) -> String? {
        let fullRange = NSRange(description.startIndex..<description.endIndex, in: description)

        for regex in FocusNotificationParsing.namePatterns {
            if let match = regex.firstMatch(in: description, options: [], range: fullRange),
               match.numberOfRanges > 1,
               let nameRange = Range(match.range(at: 1), in: description) {
                let candidate = cleanedString(String(description[nameRange]))
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }

        return nil
    }
}
