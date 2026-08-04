import AppKit
import SwiftUI
import os.log
import CodeIslandCore

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated private static let log = Logger(subsystem: "com.codeisland", category: "AppDelegate")

    var panelController: PanelWindowController?
    private var hookServer: HookServer?
    private var hookRecoveryTimer: Timer?
    private var lastHookCheck: Date = .distantPast
    private let hotKeyManager = GlobalHotKeyManager()
    private var localShortcutMonitor: Any?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("CodeIsland must stay running")
        ProcessInfo.processInfo.disableSuddenTermination()
        // Pre-set app icon so Dock/menu bar use the packaged bundle icon.
        NSApp.applicationIconImage = SettingsWindowController.bundleAppIcon()
        SettingsWindowController.shared.appState = appState
        StatusItemController.shared.startObserving()
        // Start HookServer BEFORE installing hooks into CLI configs.
        // If we write settings.json first, Claude Code picks up the new hooks
        // immediately but the socket isn't listening yet — PermissionRequest
        // hooks get no response and Claude Code denies them.
        hookServer = HookServer(appState: appState)
        hookServer?.start()
        RemoteManager.shared.onDisconnect = { [weak appState] hostId in
            appState?.removeRemoteSessions(hostId: hostId)
        }

        // Prewarm the usage footer off the launch path — first panel expansion
        // then shows data immediately instead of popping in a beat later.
        Task { @MainActor [weak appState] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            appState?.refreshClaudeUsageIfStale()
        }

        // Hook installation does subprocess version detection plus disk I/O —
        // keep it off the main thread so app launch isn't blocked even when a
        // CLI binary hangs. See #139.
        Task.detached(priority: .userInitiated) {
            if ConfigInstaller.install() {
                Self.log.info("Hooks installed")
            } else {
                Self.log.warning("Failed to install hooks")
            }
        }

        // Watch system sleep/wake so the mascot animations pause and re-anchor
        // their periodic schedules instead of pinning a core after wake (#225).
        MascotAnimationGate.shared.start()

        panelController = PanelWindowController(appState: appState)
        panelController?.showPanel()

        appState.startSessionDiscovery()
        appState.startCodexAppServerWatcher()
        RemoteManager.shared.startup()

        // Buddy bridge (opt-in): mirrors the Dynamic Island onto the companion
        // device and routes its button press back to TerminalActivator.
        ESP32StatePublisher.shared.attach(appState)
        ESP32BridgeManager.shared.onFocusRequest = { [weak appState] mascot in
            guard let appState else { return }
            ESP32FocusCoordinator.handle(mascot: mascot, appState: appState)
        }
        ESP32BridgeManager.shared.onControlCommand = { [weak appState] command in
            guard let appState else { return }
            appState.handleBuddyControlCommand(command)
        }
        AppleCompanionPublisher.shared.attach(appState)
        AppleCompanionPublisher.shared.onFocusRequest = { [weak appState] mascot in
            guard let appState else { return }
            ESP32FocusCoordinator.handle(mascot: mascot, appState: appState)
        }
        AppleCompanionPublisher.shared.onControlCommand = { [weak appState] command in
            guard let appState else { return }
            appState.handleBuddyControlCommand(command)
        }
        AppleCompanionPublisher.shared.onQuestionAnswer = { [weak appState] answer in
            guard let appState else { return }
            appState.answerCompanionQuestion(answer)
        }
        let buddyEnabled = UserDefaults.standard.bool(forKey: SettingsKey.esp32BridgeEnabled)
        let buddySyncInterval = UserDefaults.standard.double(forKey: SettingsKey.esp32HeartbeatSeconds)
        let buddyBrightness = UserDefaults.standard.double(forKey: SettingsKey.buddyScreenBrightnessPercent)
        let buddyScreenOrientation = BuddyScreenOrientation(
            settingsValue: UserDefaults.standard.string(forKey: SettingsKey.buddyScreenOrientation)
        )
        ESP32StatePublisher.shared.configure(
            enabled: buddyEnabled,
            heartbeatSeconds: buddySyncInterval > 0 ? buddySyncInterval : SettingsDefaults.esp32HeartbeatSeconds,
            brightnessPercent: buddyBrightness > 0 ? buddyBrightness : SettingsDefaults.buddyScreenBrightnessPercent,
            screenOrientation: buddyScreenOrientation
        )
        let appleCompanionEnabled = UserDefaults.standard.bool(forKey: SettingsKey.appleCompanionEnabled)
        let appleCompanionHeartbeat = UserDefaults.standard.double(forKey: SettingsKey.appleCompanionHeartbeatSeconds)
        AppleCompanionPublisher.shared.configure(
            enabled: appleCompanionEnabled,
            heartbeatSeconds: appleCompanionHeartbeat > 0 ? appleCompanionHeartbeat : SettingsDefaults.appleCompanionHeartbeatSeconds
        )

        // Hooks auto-recovery: periodic + app activation trigger
        hookRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndRepairHooks()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndRepairHooks()
            }
        }

        #if DEBUG
        // Preview mode: inject mock data if --preview flag is present
        if let scenario = DebugHarness.requestedScenario() {
            Self.log.debug("Loading scenario: \(scenario.rawValue)")
            DebugHarness.apply(scenario, to: appState)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                if appState.surface == .collapsed {
                    withAnimation(NotchAnimation.pop) {
                        appState.surface = .sessionList
                    }
                }
            }
            return
        }
        #endif

        // Sparkle runs scheduled checks itself on the cadence declared in
        // Info.plist (SUScheduledCheckInterval). Start the updater once — it
        // no-ops for Homebrew-installed builds (brew owns those upgrades).
        UpdateChecker.shared.start()

        SoundManager.shared.playBoot()
        setupGlobalShortcut()

        // Boot animation: brief expand to confirm app is running
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard appState.surface == .collapsed else { return }
            withAnimation(NotchAnimation.pop) {
                appState.surface = .sessionList
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if case .sessionList = appState.surface {
                withAnimation(NotchAnimation.close) {
                    appState.surface = .collapsed
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hookRecoveryTimer?.invalidate()
        teardownGlobalShortcut()
        appState.saveSessions()
        RemoteManager.shared.shutdown()
        hookServer?.stop()
        appState.stopCodexAppServerWatcher()
        appState.stopSessionDiscovery()
    }

    // MARK: - Global Shortcuts

    func setupGlobalShortcut() {
        teardownGlobalShortcut()

        // Collect all enabled shortcut bindings, skip duplicates (first wins)
        var bindings: [(keyCode: UInt16, mods: NSEvent.ModifierFlags, action: ShortcutAction)] = []
        var seen: Set<String> = []
        for action in ShortcutAction.allCases {
            guard action.isEnabled else { continue }
            let b = action.binding
            let key = "\(b.keyCode)-\(b.modifiers.rawValue)"
            guard seen.insert(key).inserted else { continue }
            bindings.append((b.keyCode, b.modifiers, action))
        }
        guard !bindings.isEmpty else { return }

        // Global path: Carbon RegisterEventHotKey fires from any frontmost app
        // and — unlike an NSEvent global keyboard monitor — needs no
        // Accessibility permission. This is the primary handler. See #217.
        for b in bindings {
            hotKeyManager.register(keyCode: b.keyCode, modifiers: b.mods) { [weak self] in
                Task { @MainActor in self?.executeShortcut(b.action) }
            }
        }

        // Local monitor: same-app fallback so the shortcut still works (and is
        // swallowed) while CodeIsland's own panel/settings window is focused.
        let localHandler: (NSEvent) -> Bool = { [weak self] event in
            let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            for b in bindings where event.keyCode == b.keyCode && eventMods == b.mods {
                Task { @MainActor in self?.executeShortcut(b.action) }
                return true
            }
            return false
        }
        localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            localHandler(event) ? nil : event
        }
    }

    private func teardownGlobalShortcut() {
        hotKeyManager.unregisterAll()
        if let m = localShortcutMonitor { NSEvent.removeMonitor(m) }
        localShortcutMonitor = nil
    }

    private func executeShortcut(_ action: ShortcutAction) {
        switch action {
        case .togglePanel:
            if appState.surface.isExpanded {
                withAnimation(NotchAnimation.close) { appState.surface = .collapsed }
            } else {
                withAnimation(NotchAnimation.open) {
                    appState.surface = .sessionList
                    appState.cancelCompletionQueue()
                    if appState.activeSessionId == nil {
                        appState.activeSessionId = appState.sessions.keys.sorted().first
                    }
                }
            }
        case .approve:
            appState.approvePermission()
        case .approveAlways:
            appState.approvePermission(always: true)
        case .deny:
            appState.denyPermission()
        case .skipQuestion:
            appState.skipQuestion()
        case .jumpToTerminal:
            if let id = appState.activeSessionId, let session = appState.sessions[id] {
                TerminalActivator.activate(session: session, sessionId: id)
            }
        }
    }

    private func checkAndRepairHooks() {
        guard Date().timeIntervalSince(lastHookCheck) > 60 else { return }
        lastHookCheck = Date()
        // verifyAndRepair walks every enabled CLI and rewrites settings on
        // disk — keep it off the main thread so the activation observer (fires
        // on every app switch) can't stutter the UI. See #139.
        Task.detached(priority: .background) {
            let repaired = ConfigInstaller.verifyAndRepair()
            if !repaired.isEmpty {
                Self.log.info("Auto-repaired hooks for: \(repaired.joined(separator: ", "))")
            }
        }
    }

}
