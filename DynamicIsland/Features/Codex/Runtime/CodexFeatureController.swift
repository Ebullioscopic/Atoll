import AppKit
import Combine
import Defaults
import Foundation

@MainActor
final class CodexFeatureController: ObservableObject {
    static let shared = CodexFeatureController()

    static let hookEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "PermissionRequest",
        "PostToolUse",
        "Stop",
        "SessionEnd",
    ]

    @Published private(set) var snapshot: CodexTaskStoreSnapshot
    @Published private(set) var diagnostics: CodexDiagnosticsSnapshot?
    @Published private(set) var helperInstallation: HookInstallationState?
    @Published private(set) var hooksInstalled = false
    @Published private(set) var isRunning = false
    @Published private(set) var lastOperationMessage: String?
    @Published private(set) var lastError: String?

    private let paths: AppPaths
    private let processor: EventFileProcessor
    private let repository: StateRepository
    private let presentationCoordinator: CodexPresentationCoordinator
    private var store: CodexTaskStore
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(
        paths: AppPaths = .default,
        presentationCoordinator: CodexPresentationCoordinator? = nil
    ) {
        self.paths = paths
        self.processor = EventFileProcessor(paths: paths)
        self.repository = StateRepository(paths: paths)
        self.presentationCoordinator = presentationCoordinator ?? CodexPresentationCoordinator()
        let restored = (try? repository.load()) ?? .empty
        self.store = CodexTaskStore(snapshot: restored)
        self.snapshot = restored
    }

    func start() {
        retireLegacyExternalExtension()
        performMigration()
        refreshInstallationState()
        observeSettings()
        if Defaults[.enableCodexIntegration] {
            enableRuntime(installIfAvailable: true)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        presentationCoordinator.dismiss()
    }

    func setEnabled(_ enabled: Bool) {
        Defaults[.enableCodexIntegration] = enabled
        if enabled {
            enableRuntime(installIfAvailable: true)
        } else {
            stop()
        }
    }

    func installOrRepair() {
        do {
            guard let helperSource = bundledHelperURL() else {
                throw CodexFeatureError.bundledHelperUnavailable
            }
            let installer = HookInstaller(paths: paths)
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
            _ = try installer.installHelper(from: helperSource, version: version)
            _ = try installer.installHooks(events: Self.hookEvents)
            refreshInstallationState()
            lastOperationMessage = "Codex Helper 和 Hooks 已安装或修复"
            lastError = nil
            if Defaults[.enableCodexIntegration] {
                enableRuntime(installIfAvailable: false)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func uninstallHooks() {
        do {
            let removed = try HookInstaller(paths: paths).uninstallHooks()
            refreshInstallationState()
            lastOperationMessage = removed > 0 ? "已卸载 \(removed) 条 Codex Hook" : "没有发现 Codex Hook"
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() {
        guard Defaults[.enableCodexIntegration] else { return }
        do {
            store.preferences.previewMode = Defaults[.codexShowContentPreviews] ? .projectAndPreview : .projectOnly
            var effects: [CodexStateEffect] = []
            _ = try processor.processInbox { [weak self] envelope in
                guard let self else { return }
                effects.append(contentsOf: self.store.apply(envelope))
            }
            effects.append(contentsOf: store.performMaintenance())
            try repository.save(store.snapshot)
            snapshot = store.snapshot
            refreshInstallationState()
            diagnostics = try DiagnosticsCollector(paths: paths).collect(
                snapshot: snapshot,
                helperPath: helperInstallation?.helperPath,
                helperVersion: helperInstallation?.helperVersion
            )
            let completionSessionIDs = Defaults[.codexCompletionNotifications]
                ? effects.compactMap { effect -> String? in
                    guard case .showCompletion(let sessionID) = effect else { return nil }
                    return sessionID
                }
                : []
            presentationCoordinator.update(
                snapshot: presentationSnapshot(),
                completionSessionIDs: completionSessionIDs
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshPresentation() {
        guard Defaults[.enableCodexIntegration] else {
            presentationCoordinator.dismiss()
            return
        }
        presentationCoordinator.update(snapshot: presentationSnapshot())
    }

    func openCodexConversation(sessionID: String) {
        guard let url = CodexAppLink.url(forSessionID: sessionID), NSWorkspace.shared.open(url) else {
            lastError = "无法打开 Codex 对话"
            return
        }
        lastError = nil
    }

    func openDataDirectory() {
        try? paths.prepareDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([paths.root])
    }

    private func enableRuntime(installIfAvailable: Bool) {
        if installIfAvailable && (!hooksInstalled || helperInstallation == nil), bundledHelperURL() != nil {
            installOrRepair()
        }
        timer?.invalidate()
        isRunning = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func observeSettings() {
        guard cancellables.isEmpty else { return }
        Publishers.MergeMany([
            Defaults.publisher(.codexShowClosedStatus).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.codexShowTaskTab).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.codexShowContentPreviews).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.codexShowInFullscreen).map { _ in () }.eraseToAnyPublisher(),
        ])
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.refreshPresentation() }
        .store(in: &cancellables)
    }

    private func presentationSnapshot() -> CodexTaskStoreSnapshot {
        guard !Defaults[.codexShowContentPreviews] else { return snapshot }
        var redacted = snapshot
        for index in redacted.tasks.indices {
            redacted.tasks[index].promptPreview = nil
            redacted.tasks[index].resultPreview = nil
            redacted.tasks[index].approvalPreview = nil
        }
        redacted.recentCompletions = redacted.recentCompletions.map { completion in
            CodexCompletionRecord(
                id: completion.id,
                sessionID: completion.sessionID,
                projectName: completion.projectName,
                promptPreview: nil,
                resultPreview: nil,
                completedAt: completion.completedAt
            )
        }
        return redacted
    }

    private func performMigration() {
        do {
            let result = try CodexDataMigrator(paths: paths).migrateIfNeeded()
            if result.importedLegacyState {
                let restored = (try? repository.load()) ?? .empty
                store = CodexTaskStore(snapshot: restored)
                snapshot = restored
                Defaults[.enableCodexIntegration] = true
                lastOperationMessage = "已迁移旧 CodexAtoll 状态"
            }
        } catch {
            lastError = "迁移旧 CodexAtoll 数据失败：\(error.localizedDescription)"
        }
    }

    private func retireLegacyExternalExtension() {
        for bundleIdentifier in CodexPresentationConstants.legacyExternalBundleIdentifiers {
            ExtensionLiveActivityManager.shared.dismiss(
                activityID: CodexPresentationConstants.liveActivityID,
                bundleIdentifier: bundleIdentifier
            )
            ExtensionNotchExperienceManager.shared.dismiss(
                experienceID: CodexPresentationConstants.experienceID,
                bundleIdentifier: bundleIdentifier
            )
            ExtensionAuthorizationManager.shared.removeEntry(bundleIdentifier: bundleIdentifier)
        }
    }

    private func refreshInstallationState() {
        let installer = HookInstaller(paths: paths)
        helperInstallation = try? installer.loadInstallationState()
        let hooksConfig = try? installer.readHooksConfig()
        hooksInstalled = Self.hookEvents.allSatisfy { event in
            let groups = hooksConfig?.objectValue?["hooks"]?.objectValue?[event]?.arrayValue ?? []
            return groups.contains { group in
                let entries = group.objectValue?["hooks"]?.arrayValue ?? []
                return entries.contains {
                    HookConfigMerger.isProjectHook($0, helperCommand: installer.helperCommand)
                }
            }
        }
    }

    private func bundledHelperURL() -> URL? {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexHookHelper"),
            Bundle.main.url(forAuxiliaryExecutable: "CodexHookHelper"),
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

private enum CodexFeatureError: LocalizedError {
    case bundledHelperUnavailable

    var errorDescription: String? {
        switch self {
        case .bundledHelperUnavailable:
            return "Atoll App 包中找不到 CodexHookHelper"
        }
    }
}
