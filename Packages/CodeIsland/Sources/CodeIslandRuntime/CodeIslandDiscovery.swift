import AppKit
import CodeIslandCore
import Darwin
import Foundation

/// Read-only presence of the provider executable selected for one plan.
public enum CodeIslandToolPresence: Equatable, Sendable {
    case notDetected
    case detected(URL)
}

/// Ownership information derived from a provider hook file without changing it.
public enum CodeIslandManagedHookState: Equatable, Sendable {
    case missing
    case readable(atollManagedHandlerCount: Int, legacyHandlerCount: Int)
    case unreadable
}

/// Whether the standalone CodeIsland application currently owns a lifecycle.
public enum CodeIslandLegacyApplicationState: Equatable, Sendable {
    case notRunning
    case running
}

/// Read-only state of the legacy CodeIsland Unix-domain socket path.
public enum CodeIslandSocketState: Equatable, Sendable {
    case absent
    case stale
    case occupied
    case unexpectedFile
    case inaccessible
}

/// Existing standalone-CodeIsland artifacts that adoption may explain.
public enum CodeIslandLegacyFootprint: String, Hashable, Sendable {
    case preferences
    case supportDirectory
    case codexHooks
}

/// Session grouping choices that still map to the merged Atoll dashboard.
public enum CodeIslandLegacySessionGrouping: String, Codable, Sendable {
    case all
    case status
    case provider
}

/// Completion presentations that still map to Atoll activity policy.
public enum CodeIslandLegacyCompletionPresentation: String, Codable, Sendable {
    case expand
    case glance
    case off
}

/// Whitelisted, content-free standalone preferences eligible for guided import.
///
/// Security-sensitive auto-approval, webhook, remote, display, update, and app
/// lifecycle preferences are deliberately absent from this type.
public struct CodeIslandLegacyFeaturePreferences: Equatable, Sendable {
    public let sessionGrouping: CodeIslandLegacySessionGrouping?
    public let smartSuppressionEnabled: Bool?
    public let completionPresentation: CodeIslandLegacyCompletionPresentation?
    public let mascotSpeedPercent: Int?
    public let soundEffectsEnabled: Bool?
    public let soundVolumePercent: Int?
    public let defaultMascotProvider: AgentProvider?

    public init(
        sessionGrouping: CodeIslandLegacySessionGrouping? = nil,
        smartSuppressionEnabled: Bool? = nil,
        completionPresentation: CodeIslandLegacyCompletionPresentation? = nil,
        mascotSpeedPercent: Int? = nil,
        soundEffectsEnabled: Bool? = nil,
        soundVolumePercent: Int? = nil,
        defaultMascotProvider: AgentProvider? = nil
    ) {
        self.sessionGrouping = sessionGrouping
        self.smartSuppressionEnabled = smartSuppressionEnabled
        self.completionPresentation = completionPresentation
        self.mascotSpeedPercent = mascotSpeedPercent
        self.soundEffectsEnabled = soundEffectsEnabled
        self.soundVolumePercent = soundVolumePercent
        self.defaultMascotProvider = defaultMascotProvider
    }

    public var isEmpty: Bool {
        sessionGrouping == nil
            && smartSuppressionEnabled == nil
            && completionPresentation == nil
            && mascotSpeedPercent == nil
            && soundEffectsEnabled == nil
            && soundVolumePercent == nil
            && defaultMascotProvider == nil
    }
}

/// A condition that must be resolved before an activation transaction starts.
public enum CodeIslandAdoptionBlocker: String, Hashable, Sendable {
    case providerNotDetected
    case hookConfigurationUnreadable
    case legacyApplicationRunning
    case legacySocketOccupied
    case legacySocketPathUnsafe
}

/// The exact kind of path mutation disclosed by an activation plan.
public enum CodeIslandConfigurationChangeKind: String, Codable, Sendable {
    case modifyProviderHooks
    case installManagedBridge
    case writeManagedReceipt
    case createListenerSocket
    case replaceStaleListenerSocket
    case resolveLegacySocketConflict
}

/// One path an activation transaction would change after explicit consent.
public struct CodeIslandConfigurationChange: Equatable, Sendable {
    public let kind: CodeIslandConfigurationChangeKind
    public let url: URL

    public init(kind: CodeIslandConfigurationChangeKind, url: URL) {
        self.kind = kind
        self.url = url
    }
}

/// Immutable, per-provider disclosure produced by read-only discovery.
public struct CodeIslandInstallationPlan: Equatable, Sendable {
    public let id: UUID
    public let provider: AgentProvider
    public let bundledBridgeURL: URL
    public let changes: [CodeIslandConfigurationChange]
    public let blockers: Set<CodeIslandAdoptionBlocker>
    public let hookEvents: [CodexManagedHookEvent]

    public init(
        id: UUID = UUID(),
        provider: AgentProvider,
        bundledBridgeURL: URL,
        changes: [CodeIslandConfigurationChange],
        blockers: Set<CodeIslandAdoptionBlocker>,
        hookEvents: [CodexManagedHookEvent] = CodexManagedHookEvent.phaseFourMonitoringEvents
    ) {
        self.id = id
        self.provider = provider
        self.bundledBridgeURL = bundledBridgeURL
        self.changes = changes
        self.blockers = blockers
        self.hookEvents = hookEvents
    }

    /// Returns the disclosed path for one change kind, if it is unambiguous.
    public func url(for kind: CodeIslandConfigurationChangeKind) -> URL? {
        let matches = changes.filter { $0.kind == kind }
        guard matches.count == 1 else { return nil }
        return matches[0].url
    }

    /// Creates a plan-bound token only after the host records explicit consent.
    public func consent(confirmedByUser: Bool) -> CodeIslandActivationConsent? {
        guard confirmedByUser else { return nil }
        return CodeIslandActivationConsent(planID: id, provider: provider)
    }
}

/// Content-free result of discovering Codex and standalone CodeIsland state.
public struct CodeIslandAdoptionAssessment: Equatable, Sendable {
    public let provider: AgentProvider
    public let toolPresence: CodeIslandToolPresence
    public let hookState: CodeIslandManagedHookState
    public let legacyApplicationState: CodeIslandLegacyApplicationState
    public let legacySocketState: CodeIslandSocketState
    public let legacyFootprints: Set<CodeIslandLegacyFootprint>
    public let compatiblePreferences: CodeIslandLegacyFeaturePreferences
    public let blockers: Set<CodeIslandAdoptionBlocker>
    public let installationPlan: CodeIslandInstallationPlan

    public init(
        provider: AgentProvider,
        toolPresence: CodeIslandToolPresence,
        hookState: CodeIslandManagedHookState,
        legacyApplicationState: CodeIslandLegacyApplicationState,
        legacySocketState: CodeIslandSocketState,
        legacyFootprints: Set<CodeIslandLegacyFootprint>,
        compatiblePreferences: CodeIslandLegacyFeaturePreferences,
        blockers: Set<CodeIslandAdoptionBlocker>,
        installationPlan: CodeIslandInstallationPlan
    ) {
        self.provider = provider
        self.toolPresence = toolPresence
        self.hookState = hookState
        self.legacyApplicationState = legacyApplicationState
        self.legacySocketState = legacySocketState
        self.legacyFootprints = legacyFootprints
        self.compatiblePreferences = compatiblePreferences
        self.blockers = blockers
        self.installationPlan = installationPlan
    }
}

/// All paths considered by discovery. Construction does not create them.
public struct CodeIslandDiscoveryPaths: Equatable, Sendable {
    public let codexExecutableCandidates: [URL]
    public let codexHooksURL: URL
    public let legacySupportDirectoryURL: URL
    public let legacyPreferencesURL: URL
    public let legacySocketURL: URL
    public let bundledBridgeURL: URL
    public let managedBridgeURL: URL
    public let managedReceiptURL: URL

    public init(
        codexExecutableCandidates: [URL],
        codexHooksURL: URL,
        legacySupportDirectoryURL: URL,
        legacyPreferencesURL: URL,
        legacySocketURL: URL,
        bundledBridgeURL: URL,
        managedBridgeURL: URL,
        managedReceiptURL: URL
    ) {
        self.codexExecutableCandidates = codexExecutableCandidates
        self.codexHooksURL = codexHooksURL
        self.legacySupportDirectoryURL = legacySupportDirectoryURL
        self.legacyPreferencesURL = legacyPreferencesURL
        self.legacySocketURL = legacySocketURL
        self.bundledBridgeURL = bundledBridgeURL
        self.managedBridgeURL = managedBridgeURL
        self.managedReceiptURL = managedReceiptURL
    }

    /// Resolves the live paths Atoll may inspect, without creating any directory.
    public static func live(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        bundle: Bundle = .main
    ) -> CodeIslandDiscoveryPaths {
        let home = fileManager.homeDirectoryForCurrentUser
        let codexHome = resolvedCodexHome(environment: environment, home: home)
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let managedRoot = applicationSupport
            .appendingPathComponent("Atoll", isDirectory: true)
            .appendingPathComponent("CodeIsland", isDirectory: true)

        return CodeIslandDiscoveryPaths(
            codexExecutableCandidates: executableCandidates(environment: environment, home: home),
            codexHooksURL: codexHome.appendingPathComponent("hooks.json"),
            legacySupportDirectoryURL: home.appendingPathComponent(".codeisland", isDirectory: true),
            legacyPreferencesURL: home
                .appendingPathComponent("Library/Preferences", isDirectory: true)
                .appendingPathComponent("com.codeisland.app.plist"),
            legacySocketURL: URL(fileURLWithPath: "/tmp/codeisland-\(getuid()).sock"),
            bundledBridgeURL: bundle.bundleURL
                .appendingPathComponent("Contents/Helpers", isDirectory: true)
                .appendingPathComponent("codeisland-bridge"),
            managedBridgeURL: managedRoot.appendingPathComponent("codeisland-bridge"),
            managedReceiptURL: managedRoot.appendingPathComponent("codex-installation.json")
        )
    }

    private static func resolvedCodexHome(
        environment: [String: String],
        home: URL
    ) -> URL {
        let configured = environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configured.isEmpty else {
            return home.appendingPathComponent(".codex", isDirectory: true)
        }
        if configured == "~" {
            return home
        }
        if configured.hasPrefix("~/") {
            return home.appendingPathComponent(String(configured.dropFirst(2)), isDirectory: true)
        }
        return URL(fileURLWithPath: configured, isDirectory: true)
    }

    private static func executableCandidates(
        environment: [String: String],
        home: URL
    ) -> [URL] {
        var candidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("codex") }
        candidates.append(contentsOf: [
            home.appendingPathComponent(".local/bin/codex"),
            home.appendingPathComponent(".npm-global/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ])

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

/// System boundary used to inspect, never claim, the legacy socket.
public protocol CodeIslandSocketInspecting {
    func state(at socketURL: URL) -> CodeIslandSocketState
}

/// System boundary used to detect the standalone app without controlling it.
public protocol CodeIslandLegacyApplicationInspecting {
    func isApplicationRunning(bundleIdentifier: String) -> Bool
}

/// Live read-only application lookup for guided adoption.
public struct CodeIslandSystemApplicationInspector: CodeIslandLegacyApplicationInspecting {
    public init() {}

    public func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).isEmpty
    }
}

/// Live read-only Unix-domain socket probe.
public struct CodeIslandSystemSocketInspector: CodeIslandSocketInspecting {
    public init() {}

    public func state(at socketURL: URL) -> CodeIslandSocketState {
        var fileStatus = stat()
        guard lstat(socketURL.path, &fileStatus) == 0 else {
            return errno == ENOENT ? .absent : .inaccessible
        }
        guard fileStatus.st_mode & S_IFMT == S_IFSOCK else {
            return .unexpectedFile
        }

        let pathBytes = Array(socketURL.path.utf8)
        var address = sockaddr_un()
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            return .inaccessible
        }
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: pathBytes)
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return .inaccessible }
        defer { Darwin.close(descriptor) }

        let pathOffset = MemoryLayout<sockaddr_un>.size
            - MemoryLayout.size(ofValue: address.sun_path)
        let length = socklen_t(pathOffset + pathBytes.count + 1)
        address.sun_len = UInt8(length)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, length)
            }
        }
        if result == 0 {
            return .occupied
        }
        switch errno {
        case ECONNREFUSED, ENOENT:
            return .stale
        default:
            return .inaccessible
        }
    }
}

/// Produces a disclosure and adoption assessment without writing any path.
public struct CodeIslandReadOnlyDiscovery {
    private let paths: CodeIslandDiscoveryPaths
    private let fileManager: FileManager
    private let socketInspector: any CodeIslandSocketInspecting
    private let applicationInspector: any CodeIslandLegacyApplicationInspecting

    public init(
        paths: CodeIslandDiscoveryPaths = .live(),
        fileManager: FileManager = .default,
        socketInspector: any CodeIslandSocketInspecting = CodeIslandSystemSocketInspector(),
        applicationInspector: any CodeIslandLegacyApplicationInspecting = CodeIslandSystemApplicationInspector()
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.socketInspector = socketInspector
        self.applicationInspector = applicationInspector
    }

    /// Inspects Codex and legacy CodeIsland footprints. This method is read-only.
    public func assessCodex() -> CodeIslandAdoptionAssessment {
        let executable = paths.codexExecutableCandidates.first {
            fileManager.isExecutableFile(atPath: $0.path)
        }
        let toolPresence = executable.map(CodeIslandToolPresence.detected) ?? .notDetected
        let hookState = inspectHooks(at: paths.codexHooksURL)
        let applicationState: CodeIslandLegacyApplicationState = applicationInspector
            .isApplicationRunning(bundleIdentifier: "com.codeisland.app") ? .running : .notRunning
        let socketState = socketInspector.state(at: paths.legacySocketURL)
        let compatiblePreferences = inspectLegacyPreferences(
            at: paths.legacyPreferencesURL
        )

        var footprints = Set<CodeIslandLegacyFootprint>()
        if fileManager.fileExists(atPath: paths.legacyPreferencesURL.path) {
            footprints.insert(.preferences)
        }
        if fileManager.fileExists(atPath: paths.legacySupportDirectoryURL.path) {
            footprints.insert(.supportDirectory)
        }
        if case .readable(_, let legacyCount) = hookState, legacyCount > 0 {
            footprints.insert(.codexHooks)
        }

        var blockers = Set<CodeIslandAdoptionBlocker>()
        if executable == nil { blockers.insert(.providerNotDetected) }
        if hookState == .unreadable { blockers.insert(.hookConfigurationUnreadable) }
        if applicationState == .running { blockers.insert(.legacyApplicationRunning) }
        switch socketState {
        case .occupied:
            blockers.insert(.legacySocketOccupied)
        case .unexpectedFile, .inaccessible:
            blockers.insert(.legacySocketPathUnsafe)
        case .absent, .stale:
            break
        }

        let socketChangeKind: CodeIslandConfigurationChangeKind
        switch socketState {
        case .stale:
            socketChangeKind = .replaceStaleListenerSocket
        case .occupied, .unexpectedFile, .inaccessible:
            socketChangeKind = .resolveLegacySocketConflict
        case .absent:
            socketChangeKind = .createListenerSocket
        }
        let changes = [
            CodeIslandConfigurationChange(kind: .modifyProviderHooks, url: paths.codexHooksURL),
            CodeIslandConfigurationChange(kind: .installManagedBridge, url: paths.managedBridgeURL),
            CodeIslandConfigurationChange(kind: .writeManagedReceipt, url: paths.managedReceiptURL),
            CodeIslandConfigurationChange(kind: socketChangeKind, url: paths.legacySocketURL),
        ]
        let plan = CodeIslandInstallationPlan(
            provider: .codex,
            bundledBridgeURL: paths.bundledBridgeURL,
            changes: changes,
            blockers: blockers
        )

        return CodeIslandAdoptionAssessment(
            provider: .codex,
            toolPresence: toolPresence,
            hookState: hookState,
            legacyApplicationState: applicationState,
            legacySocketState: socketState,
            legacyFootprints: footprints,
            compatiblePreferences: compatiblePreferences,
            blockers: blockers,
            installationPlan: plan
        )
    }

    private func inspectLegacyPreferences(
        at url: URL
    ) -> CodeIslandLegacyFeaturePreferences {
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any]
        else {
            return CodeIslandLegacyFeaturePreferences()
        }

        let grouping: CodeIslandLegacySessionGrouping?
        switch root["sessionGroupingMode"] as? String {
        case "all": grouping = .all
        case "status": grouping = .status
        case "cli": grouping = .provider
        default: grouping = nil
        }
        let completion = (root["completionNotificationStyle"] as? String)
            .flatMap(CodeIslandLegacyCompletionPresentation.init(rawValue:))
        let mascotSpeed = boundedInteger(root["mascotSpeed"], range: 0...300)
        let soundVolume = boundedInteger(root["soundVolume"], range: 0...100)
        let defaultProvider: AgentProvider? = root["defaultSource"] as? String == "codex"
            ? .codex
            : nil

        return CodeIslandLegacyFeaturePreferences(
            sessionGrouping: grouping,
            smartSuppressionEnabled: root["smartSuppress"] as? Bool,
            completionPresentation: completion,
            mascotSpeedPercent: mascotSpeed,
            soundEffectsEnabled: root["soundEnabled"] as? Bool,
            soundVolumePercent: soundVolume,
            defaultMascotProvider: defaultProvider
        )
    }

    private func boundedInteger(_ value: Any?, range: ClosedRange<Int>) -> Int? {
        let integer: Int?
        if let value = value as? Int {
            integer = value
        } else if let value = value as? NSNumber {
            integer = value.intValue
        } else {
            integer = nil
        }
        guard let integer, range.contains(integer) else { return nil }
        return integer
    }

    private func inspectHooks(at url: URL) -> CodeIslandManagedHookState {
        guard fileManager.fileExists(atPath: url.path) else { return .missing }
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .unreadable
        }
        guard let hooks = root["hooks"] else {
            return .readable(atollManagedHandlerCount: 0, legacyHandlerCount: 0)
        }
        guard hooks is [String: Any] else { return .unreadable }

        var managedCount = 0
        var legacyCount = 0
        inspectCommands(in: hooks) { command in
            if Self.isAtollManagedCommand(command) {
                managedCount += 1
            } else if Self.isLegacyCodeIslandCommand(command) {
                legacyCount += 1
            }
        }
        return .readable(
            atollManagedHandlerCount: managedCount,
            legacyHandlerCount: legacyCount
        )
    }

    private func inspectCommands(in value: Any, visit: (String) -> Void) {
        if let dictionary = value as? [String: Any] {
            if dictionary["type"] as? String == "command",
               let command = dictionary["command"] as? String {
                visit(command)
            }
            for child in dictionary.values {
                inspectCommands(in: child, visit: visit)
            }
        } else if let array = value as? [Any] {
            for child in array {
                inspectCommands(in: child, visit: visit)
            }
        }
    }

    static func isAtollManagedCommand(_ command: String) -> Bool {
        command.split(whereSeparator: { $0.isWhitespace })
            .contains("--managed-by-atoll")
    }

    static func isLegacyCodeIslandCommand(_ command: String) -> Bool {
        command.contains("/.codeisland/codeisland-bridge")
            || command.contains("/.codeisland/codeisland-hook.sh")
    }
}
