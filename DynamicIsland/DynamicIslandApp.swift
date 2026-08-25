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

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI
import SkyLightWindow

@main
struct DynamicNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Default(.menubarIcon) var showMenuBarIcon
    @Environment(\.openWindow) var openWindow

    let updaterController: SPUStandardUpdaterController
    /// Retained delegate instance that dynamically selects the Sparkle feed URL
    /// based on the user's update channel preference.
    private let updaterDelegate = AtollUpdaterDelegate()

    init() {
        // Skip Sparkle's launch-time update check during UI testing.
        // The AtollUpdaterDelegate overrides the feed URL at runtime
        // based on the user's selected update channel.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: !AppRuntimeEnvironment.isUITesting,
            updaterDelegate: updaterDelegate, userDriverDelegate: nil)

        // Initialize the settings window controller with the updater controller
        SettingsWindowController.shared.setUpdaterController(updaterController)
    }

    var body: some Scene {
        MenuBarExtra("dynamic.island", systemImage: "mountain.2.fill", isInserted: $showMenuBarIcon) {
            Button("Settings") {
                SettingsWindowController.shared.showWindow()
            }
            CheckForUpdatesView(updater: updaterController.updater)
            Divider()
            Button("Restart Atoll") {
                guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

                let workspace = NSWorkspace.shared

                if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
                {

                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.createsNewApplicationInstance = true

                    workspace.openApplication(at: appURL, configuration: configuration)
                }

                NSApplication.shared.terminate(self)
            }
            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(self)
            }
            .keyboardShortcut(KeyEquivalent("Q"), modifiers: .command)
        }
    }

    @CommandsBuilder
    var commands: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                SettingsWindowController.shared.showWindow()
            }
        }
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

extension AppDelegate {
    static var shared: AppDelegate? {
        NSApplication.shared.delegate as? AppDelegate
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var windows: [NSScreen: NSWindow] = [:]
    var viewModels: [NSScreen: DynamicIslandViewModel] = [:]
    var window: NSWindow?
    let vm: DynamicIslandViewModel = .init()
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    var whatsNewWindow: NSWindow?
    var timer: Timer?
    let calendarManager = CalendarManager.shared
    let webcamManager = WebcamManager.shared
    let dndManager = DoNotDisturbManager.shared  // NEW: DND detection
    let bluetoothAudioManager = BluetoothAudioManager.shared  // NEW: Bluetooth audio detection
    let idleAnimationManager = IdleAnimationManager.shared  // NEW: Custom idle animations
    let downloadManager = DownloadManager.shared  // NEW: Chromium downloads detection
    let lockScreenPanelManager = LockScreenPanelManager.shared  // NEW: Lock screen music panel
    let mediaControlsStateCoordinator = MediaControlsStateCoordinator.shared
    let systemTimerBridge = SystemTimerBridge.shared
    let extensionXPCServiceHost = ExtensionXPCServiceHost.shared
    let extensionRPCServer = ExtensionRPCServer.shared
    var closeNotchWorkItem: DispatchWorkItem?
    private var previousScreens: [NSScreen]?
    private var onboardingWindowController: NSWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var windowsHiddenForLock = false
    private var optionalShortcutHandlersRegistered = false
    private weak var focusWithoutDevToolsMenuItem: NSMenuItem?
    private weak var focusUseDevToolsMenuItem: NSMenuItem?
    
    // Debouncing mechanism for window size updates
    private var windowSizeUpdateWorkItem: DispatchWorkItem?

    // Block-based AudioTap observers, kept with their center so they can be removed by token
    private var audioTapObserverTokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []
//    let calendarManager = CalendarManager.shared
//    let webcamManager = WebcamManager.shared
//    var closeNotchWorkItem: DispatchWorkItem?
//    private var previousScreens: [NSScreen]?
//    private var onboardingWindowController: NSWindowController?
//    private var cancellables = Set<AnyCancellable>()
//    
//    // Debouncing mechanism for window size updates
//    private var windowSizeUpdateWorkItem: DispatchWorkItem?
    
    private func debouncedUpdateWindowSize() {
        // Cancel any existing work item
        windowSizeUpdateWorkItem?.cancel()
        
        // Create new work item with delay
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateWindowSizeIfNeeded()
        }
        
        // Store reference and schedule
        windowSizeUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        installTopMenuItemsIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        _ = handleIncomingShelfURLs(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        handleIncomingShelfURLs([URL(fileURLWithPath: filename)])
    }

    private func handleIncomingShelfURLs(_ urls: [URL]) -> Bool {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }

        Task { @MainActor [weak self] in
            let items = await ShelfDropService.items(from: fileURLs)
            guard !items.isEmpty else { return }

            ShelfStateViewModel.shared.add(items)
            self?.coordinator.currentView = .shelf
        }

        return true
    }
    
    /// Setup observers for music player state changes to restart AudioTap capture
    private func setupAudioTapMusicObservers() {
        // Registration is additive and this runs again every time the waveform setting is
        // switched back on, so drop the previous generation instead of stacking duplicates.
        // Block-based observers are only removable through the token they return, which is
        // why they are retained in `audioTapObserverTokens`.
        tearDownAudioTapMusicObservers()

        // Listen for app launches to restart capture when music apps are opened
        let targetBundleIDs = [
            "com.apple.Music",
            "com.spotify.client",
            "com.amazon.music",
            "sh.cider.genten.mac",
            "com.apple.Safari",
            "com.tidal.desktop",
            "tv.plex.plexamp",
            "com.roon.Roon",
            "com.audirvana.Audirvana-Studio",
            "com.vox.vox",
            "com.coppertino.Vox",
        ]
        
        let launchToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  targetBundleIDs.contains(bundleID) else { return }
            
            // A target music app was launched, restart capture to include it
            if Defaults[.enableRealTimeWaveform] {
                print("🎵 [AudioTap] Music app launched: \(bundleID), restarting capture...")
                // Give the app a moment to fully launch
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    AudioTap.shared.restartCapture()
                }
            }
        }
        
        // Also observe app terminations to restart capture
        let terminateToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  targetBundleIDs.contains(bundleID) else { return }
            
            // A target music app was terminated, restart capture to update the list
            if Defaults[.enableRealTimeWaveform] {
                print("🎵 [AudioTap] Music app terminated: \(bundleID), restarting capture...")
                AudioTap.shared.restartCapture()
            }
        }

        // Restart capture when the audio output route changes (e.g. AirPods connect/
        // disconnect). AudioTap skips Spotify while a Bluetooth route is active to keep the
        // AirPods pause gesture working, so the tap must be rebuilt to re-include or exclude
        // Spotify whenever the route flips.
        let routeToken = NotificationCenter.default.addObserver(
            forName: .systemAudioRouteDidChange,
            object: nil,
            queue: .main
        ) { _ in
            if Defaults[.enableRealTimeWaveform] {
                print("🔀 [AudioTap] Audio route changed, restarting capture...")
                AudioTap.shared.restartCapture()
            }
        }

        audioTapObserverTokens = [
            (NSWorkspace.shared.notificationCenter, launchToken),
            (NSWorkspace.shared.notificationCenter, terminateToken),
            (NotificationCenter.default, routeToken),
        ]
    }

    /// Removes the AudioTap observers registered by `setupAudioTapMusicObservers()`.
    private func tearDownAudioTapMusicObservers() {
        for (center, token) in audioTapObserverTokens {
            center.removeObserver(token)
        }
        audioTapObserverTokens.removeAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        let userInfo: [String: Any] = [
            AtollDistributedNotifications.UserInfoKey.sourcePID: NSNumber(value: ProcessInfo.processInfo.processIdentifier)
        ]
        DistributedNotificationCenter.default().postNotificationName(
            AtollDistributedNotifications.didBecomeIdle,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )

        // Guarantee the native OSD is usable after we exit: if we were
        // suppressing it, OSDUIHelper is SIGSTOP-frozen and the async restore in
        // enableSystemHUD() would not finish before the process dies. Resume it
        // synchronously here so it is never left frozen. (See issue #568.)
        SystemOSDManager.resumeOSDUIHelperForTermination()

        // Cancel any pending window size updates
        windowSizeUpdateWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
        extensionXPCServiceHost.stop()
        extensionRPCServer.stop()
        
        // Stop AudioTap capture
        AudioTap.shared.stopCapture()

        // Restore Lunar's native OSD if integration was active
        LunarManager.shared.appWillTerminate()
    }
    
    @objc func onScreenLocked(_: Notification) {
        print("Screen locked")
        hideWindowsForLock()
    }

    @objc func onScreenUnlocked(_: Notification) {
        print("Screen unlocked")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.restoreWindowsAfterLock()
            self.adjustWindowPosition(changeAlpha: true)
        }
    }

    private func hideWindowsForLock() {
        guard !windowsHiddenForLock else { return }
        windowsHiddenForLock = true

        if Defaults[.showOnAllDisplays] {
            for window in windows.values {
                window.alphaValue = 0
                window.orderOut(nil)
            }
        } else if let window = window {
            window.alphaValue = 0
            window.orderOut(nil)
        }
    }

    private func restoreWindowsAfterLock() {
        guard windowsHiddenForLock else { return }
        windowsHiddenForLock = false

        if Defaults[.showOnAllDisplays] {
            for window in windows.values {
                window.orderFrontRegardless()
                window.alphaValue = 1
            }
        } else if let window = window {
            window.orderFrontRegardless()
            window.alphaValue = 1
        }
    }
    
    private func cleanupWindows(shouldInvert: Bool = false) {
        if shouldInvert ? !Defaults[.showOnAllDisplays] : Defaults[.showOnAllDisplays] {
            for (screen, window) in windows {
                // Tear down the hosted ContentView before dropping the window
                // (`.onDisappear` is unreliable for borderless panels).
                viewModels[screen]?.onViewTeardown?()
                viewModels[screen]?.onViewTeardown = nil
                NotchSpaceManager.shared.notchSpace.windows.remove(window)
                window.close()
            }
            windows.removeAll()
            viewModels.removeAll()
        } else if let window = window {
            vm.onViewTeardown?()
            vm.onViewTeardown = nil
            NotchSpaceManager.shared.notchSpace.windows.remove(window)
            window.close()
            self.window = nil
        }
    }

    /// Rebuilds the notch's CGSSpace membership from the live windows.
    /// This intentionally does not gate on `hideNotchOption == .never`: Space
    /// membership keeps the window anchored while switching desktops, while
    /// FullscreenMediaDetector/`hideOnClosed` owns whether the closed notch renders
    /// in fullscreen.
    @MainActor
    private func syncNotchSpaceMembership() {
        NotchSpaceManager.shared.notchSpace.windows = currentDynamicIslandWindows()
    }

    private func currentDynamicIslandWindows() -> Set<NSWindow> {
        if Defaults[.showOnAllDisplays] {
            return Set(windows.values)
        } else if let window = window {
            return [window]
        }
        return []
    }

    @MainActor
    private func reassertDynamicIslandWindowSpacePresence() {
        guard !windowsHiddenForLock else { return }

        syncNotchSpaceMembership()

        for window in currentDynamicIslandWindows() {
            window.collectionBehavior = DynamicIslandWindow.pinnedCollectionBehavior
            window.orderFrontRegardless()
        }
    }

    private func createDynamicIslandWindow(for screen: NSScreen, with viewModel: DynamicIslandViewModel)
        -> NSWindow
    {
        // Use the current required size instead of always using openNotchSize
        let baseSize = calculateRequiredNotchSize()
        let requiredSize = adjustedSizeForScreen(baseSize, screen: screen)
        let roundedWidth = requiredSize.width.rounded()
        let roundedHeight = requiredSize.height.rounded()
        
        let window = DynamicIslandWindow(
            contentRect: NSRect(
                x: 0, y: 0, width: roundedWidth, height: roundedHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.animationBehavior = .none
        // collectionBehavior is configured in DynamicIslandWindow.init

        window.contentView = FirstMouseHostingView(
            rootView: ContentView()
                .environmentObject(viewModel)
                .environmentObject(webcamManager)
                //.moveToSky()
        )
        
        window.orderFrontRegardless()
        NotchSpaceManager.shared.notchSpace.windows.insert(window)
        //SkyLightOperator.shared.delegateWindow(window)
        return window
    }

    private func positionWindow(_ window: NSWindow, on screen: NSScreen, changeAlpha: Bool = false)
    {
        if changeAlpha {
            window.alphaValue = 0
        }
        
        let screenFrame = screen.frame
        let topBleed = notchTopScreenBleed(for: screen.localizedName)
        let centerX = screenFrame.origin.x + (screenFrame.width / 2)
        let roundedWidth = window.frame.width.rounded()
        let roundedHeight = window.frame.height.rounded()
        let newX = (centerX - (roundedWidth / 2)).rounded()
        let newY = (screenFrame.maxY + topBleed - roundedHeight).rounded()

        window.setFrame(NSRect(
            x: newX,
            y: newY,
            width: roundedWidth,
            height: roundedHeight
        ), display: false)
        
        if changeAlpha {
            window.alphaValue = 1
        }
    }
    
    private func updateWindowSizeIfNeeded() {
        // Calculate required size based on current state
        let requiredSize = calculateRequiredNotchSize()
        let animateResize = shouldAnimateResize(for: requiredSize)
        resizeWindows(to: requiredSize, animated: animateResize, force: false)
    }

    private func updateWindowSizeForTabSwitch() {
        let requiredSize = calculateRequiredNotchSize()
        resizeWindows(to: requiredSize, animated: false, force: true)
    }
    
    private func calculateRequiredNotchSize() -> CGSize {
        // Check if inline sneak peek is showing and notch is closed
        let airPodsListeningModeSneakActive = vm.notchState == .closed &&
                                      coordinator.sneakPeek.show &&
                                      coordinator.sneakPeek.type == .bluetoothAudio &&
                                      coordinator.sneakPeek.value < 0 &&
                                      AirPodsListeningMode.fromHUDSymbol(coordinator.sneakPeek.icon) != nil
        let isInlineSneakPeekActive = vm.notchState == .closed && 
                                      Defaults[.enableSneakPeek] &&
                                      (
                                          coordinator.expandingView.show &&
                                          (coordinator.expandingView.type == .music || coordinator.expandingView.type == .timer) &&
                                          Defaults[.sneakPeekStyles] == .inline ||
                                          airPodsListeningModeSneakActive
                                      )
        
        // If inline sneak peek is active, use a wider width to accommodate the expanded content
        if isInlineSneakPeekActive {
            // Calculate required width for inline sneak peek:
            // Album art (~32) + Middle section (380) + Visualizer (~32) + horizontal padding (28) + clip shape margin (12)
            let inlineSneakPeekWidth: CGFloat = 460
            return CGSize(width: inlineSneakPeekWidth, height: vm.effectiveClosedNotchHeight)
        }

        if let recordingHUDSize = recordingHUDLayoutForSizing().size(
            closedNotchSize: vm.closedNotchSize,
            effectiveClosedNotchHeight: vm.effectiveClosedNotchHeight
        ) {
            return addShadowPadding(to: recordingHUDSize, isMinimalistic: Defaults[.enableMinimalisticUI])
        }

        // Check for battery HUD expansion
        if vm.notchState == .closed && 
           coordinator.expandingView.show && 
           coordinator.expandingView.type == .battery &&
           Defaults[.showPowerStatusNotifications] {
            
            let batteryModel = BatteryStatusViewModel.shared
            if let kind = batteryModel.activeTemporaryHUDKind {
                let closedNotchHeight = vm.effectiveClosedNotchHeight
                let closedNotchWidth = vm.closedNotchSize.width
                
                let style: BatteryNotificationStyle = {
                    switch kind {
                    case .charging: return .compact
                    case .lowBattery: return Defaults[.lowBatteryHUDStyle]
                    case .fullBattery: return Defaults[.fullBatteryHUDStyle]
                    }
                }()
                
                var width = closedNotchWidth
                var height = closedNotchHeight
                
                switch (kind, style) {
                case (.charging, _), (.lowBattery, .compact), (.fullBattery, .compact):
                    width += 180
                case (.lowBattery, .standard):
                    width += 100
                    height += 75
                case (.fullBattery, .standard):
                    width += 80
                    height += 70
                }
                
                return addShadowPadding(to: CGSize(width: width, height: height), isMinimalistic: Defaults[.enableMinimalisticUI])
            }
        }
        
        // Use minimalistic or normal size based on settings
        var baseSize = Defaults[.enableMinimalisticUI] ? minimalisticOpenNotchSize(isDynamicIslandMode: shouldUseDynamicIslandMode(for: vm.screen)) : openNotchSize
        
        // Use a consistent height for different view types
        if coordinator.currentView == .timer {
            baseSize.height = 250 // Extra space for timer presets
        } else if coordinator.currentView == .notes {
            let preferredHeight = coordinator.notesLayoutState.preferredHeight
            baseSize.height = max(baseSize.height, preferredHeight)
        } else if coordinator.currentView == .clipboard {
            // Clipboard has its own fixed height source; don't inherit the notes layout state.
            baseSize.height = max(baseSize.height, NotesLayoutState.list.preferredHeight)
        } else if coordinator.currentView == .terminal {
            let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
            let maxFraction = Defaults[.terminalMaxHeightFraction]
            baseSize.height = min(screenHeight * maxFraction, max(300, screenHeight * maxFraction))
        } else if coordinator.currentView == .llmUsage {
            baseSize.height = max(baseSize.height, llmUsageOpenNotchHeight)
        }
        
        baseSize = inlineLyricsAdjustedNotchSize(
            from: baseSize,
            isHomeTabActive: coordinator.currentView == .home
        )

        let adjustedContentSize = statsAdjustedNotchSize(
            from: baseSize,
            isStatsTabActive: coordinator.currentView == .stats,
            secondRowProgress: coordinator.statsSecondRowExpansion
        )
        let result = addShadowPadding(
            to: adjustedContentSize,
            isMinimalistic: Defaults[.enableMinimalisticUI]
        )

        return result
    }

    private func recordingHUDLayoutForSizing() -> RecordingHUDLayout {
        makeRecordingHUDLayout(
            notchState: vm.notchState,
            screenRecordingDetectionEnabled: Defaults[.enableScreenRecordingDetection],
            showRecordingIndicator: Defaults[.showRecordingIndicator],
            hideOnClosed: vm.hideOnClosed,
            isRecording: ScreenRecordingManager.shared.isRecording,
            closedMusicPairingEligible: closedMusicPairingEligibleForSizing(),
            recordingControlMode: Defaults[.recordingControlMode],
            canStopFromHUD: ScreenRecordingManager.shared.shouldShowStopControlsInHUD,
            enableMinimalisticUI: Defaults[.enableMinimalisticUI],
            recordingHoverStyle: Defaults[.recordingHoverStyle],
            suppressHoverExpansion: ScreenRecordingManager.shared.isScreenSharingAppActive,
            expanded: true
        )
    }

    private func closedMusicPairingEligibleForSizing() -> Bool {
        let musicManager = MusicManager.shared
        let hasMusicMetadata = !musicManager.songTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !musicManager.artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasActiveMusicSnapshot = musicManager.isPlaying || (!musicManager.isPlayerIdle && hasMusicMetadata)

        return isClosedMusicPairingEligible(
            notchState: vm.notchState,
            hasActiveMusicSnapshot: hasActiveMusicSnapshot,
            musicLiveActivityEnabled: coordinator.musicLiveActivityEnabled,
            closedMusicContentEnabled: Defaults[.enableMinimalisticUI] || Defaults[.showStandardMediaControls],
            hideOnClosed: vm.hideOnClosed,
            isLocked: LockScreenManager.shared.isLocked,
            isDeferredAfterUnlock: LockScreenManager.shared.shouldDelayPostUnlockMusicHUD
        )
    }

    /// Adds Dynamic Island shadow/top insets on non-notch screens, or top bleed on physical-notch screens.
    private func adjustedSizeForScreen(_ baseSize: CGSize, screen: NSScreen) -> CGSize {
        var adjusted = baseSize
        if shouldUseDynamicIslandMode(for: screen.localizedName) {
            adjusted.width += dynamicIslandShadowInset * 2
            adjusted.height += dynamicIslandTopOffset
        } else {
            adjusted.height += notchTopScreenBleed(for: screen.localizedName)
        }
        return adjusted
    }

    func ensureWindowSize(_ size: CGSize, animated: Bool, force: Bool = false) {
        resizeWindows(to: size, animated: animated, force: force)
    }

    private func resizeWindows(to size: CGSize, animated: Bool, force: Bool) {
        guard size.width > 0, size.height > 0 else { return }

        if Defaults[.showOnAllDisplays] {
            for (screen, window) in windows {
                let screenSize = adjustedSizeForScreen(size, screen: screen)
                if force || window.frame.size != screenSize {
                    resizeWindow(window, on: screen, to: screenSize, animated: animated)
                }
            }
        } else if let window {
            let screen = window.screen ?? NSScreen.screens.first { $0.frame.intersects(window.frame) } ?? NSScreen.main ?? NSScreen.screens.first
            guard let screen else { return }
            let screenSize = adjustedSizeForScreen(size, screen: screen)
            if force || window.frame.size != screenSize {
                resizeWindow(window, on: screen, to: screenSize, animated: animated)
            }
        }
    }

    private func resizeWindow(_ window: NSWindow, on screen: NSScreen, to size: CGSize, animated: Bool) {
        let screenFrame = screen.frame
        let topBleed = notchTopScreenBleed(for: screen.localizedName)
        // Clamp width to screen width so the notch never extends beyond screen edges on scaled displays
        let clampedWidth = min(size.width, screenFrame.width).rounded()
        let maxHeight = screenFrame.height + topBleed
        let clampedHeight = min(size.height, maxHeight).rounded()
        let centerX = screenFrame.midX
        let newX = (centerX - (clampedWidth / 2)).rounded()
        let newY = (screenFrame.maxY + topBleed - clampedHeight).rounded()
        let targetFrame = NSRect(x: newX, y: newY, width: clampedWidth, height: clampedHeight)

        // `open()` intentionally requests a forced resize so every display is
        // considered, but an unchanged frame still needs no AppKit display
        // transaction. Avoiding that no-op matters during hover/click opens.
        guard window.frame != targetFrame else { return }
        window.setFrame(targetFrame, display: true)
    }

    private func shouldAnimateResize(for newSize: CGSize) -> Bool {
        if Defaults[.enableMinimalisticUI] && !ReminderLiveActivityManager.shared.activeWindowReminders.isEmpty {
            return false
        }
        return true
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let userInfo: [String: Any] = [
            AtollDistributedNotifications.UserInfoKey.sourcePID: NSNumber(value: ProcessInfo.processInfo.processIdentifier)
        ]
        DistributedNotificationCenter.default().postNotificationName(
            AtollDistributedNotifications.didBecomeActive,
            object: nil,
            userInfo: userInfo,
            deliverImmediately: true
        )

        LockScreenLiveActivityWindowManager.shared.configure(viewModel: vm)
        LockScreenManager.shared.configure(viewModel: vm)
        extensionXPCServiceHost.start()
        extensionRPCServer.start()
        
        // Migrate legacy progress bar settings
        Defaults.Keys.migrateProgressBarStyle()
        Defaults.Keys.migrateMusicAuxControls()
        Defaults.Keys.migrateMusicControlSlots()
        Defaults.Keys.migrateCapsLockTintMode()
        Defaults.Keys.migrateThirdPartyDDCIntegration()
        Defaults.Keys.migrateAIProviderKeysToKeychain()
        Defaults.Keys.migrateClipboardShortcutToV()

        Defaults.publisher(.enableThirdPartyDDCIntegration, options: [])
            .sink { _ in
                Defaults.Keys.syncLegacyThirdPartyDDCKeys()
            }
            .store(in: &cancellables)

        Defaults.publisher(.thirdPartyDDCProvider, options: [])
            .sink { _ in
                Defaults.Keys.syncLegacyThirdPartyDDCKeys()
            }
            .store(in: &cancellables)
        
        // Initialize idle animations (load bundled + built-in face)
        idleAnimationManager.initializeDefaultAnimations()

        applySelectedAppIcon()
        installTopMenuItemsIfNeeded()

        Defaults.publisher(.focusMonitoringMode, options: [])
            .sink { [weak self] _ in
                self?.updateFocusMenuState()
            }
            .store(in: &cancellables)
        
        // Setup SystemHUD Manager
        SystemHUDManager.shared.setup(coordinator: coordinator)

        // Setup BetterDisplay integration
        BetterDisplayManager.shared.configure(coordinator: coordinator)

        // Setup Lunar integration
        LunarManager.shared.configure(coordinator: coordinator)
        
        // Setup ScreenRecording Manager
        if Defaults[.enableScreenRecordingDetection] && !AppRuntimeEnvironment.isUITesting {
            ScreenRecordingManager.shared.startMonitoring()
        }

        // Setup Do Not Disturb Manager
        if Defaults[.enableDoNotDisturbDetection] && !AppRuntimeEnvironment.isUITesting {
            dndManager.startMonitoring()
        }

        // Setup Privacy Indicator Manager (camera/mic; skipped under UI testing).
        if !AppRuntimeEnvironment.isUITesting {
            PrivacyIndicatorManager.shared.startMonitoring()
        }
        
        // Setup Real-time Audio Waveform capture if enabled
        if Defaults[.enableRealTimeWaveform] {
            Task {
                await AudioTap.shared.startCapture()
            }
            setupAudioTapMusicObservers()
        }
        
        // Observe enableRealTimeWaveform changes
        Defaults.publisher(.enableRealTimeWaveform, options: [])
            .sink { [weak self] change in
                if change.newValue {
                    Task {
                        await AudioTap.shared.startCapture()
                    }
                    self?.setupAudioTapMusicObservers()
                } else {
                    AudioTap.shared.stopCapture()
                    self?.tearDownAudioTapMusicObservers()
                }
            }
            .store(in: &cancellables)
        
        // Observe tab changes - use immediate resize to keep the notch pinned
        // Deferred to next run loop tick because @Published fires on willSet,
        // so coordinator.currentView still holds the OLD value at emission time.
        coordinator.$currentView.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateWindowSizeForTabSwitch()
            }
        }.store(in: &cancellables)

        coordinator.$notesLayoutState
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateWindowSizeIfNeeded()
            }
            .store(in: &cancellables)
        
        // Observe stats settings changes - use debounced updates
        Defaults.publisher(.enableStatsFeature, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)
        
        Defaults.publisher(.showCpuGraph, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)
        
        Defaults.publisher(.showMemoryGraph, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)
        
        Defaults.publisher(.showGpuGraph, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)
        
        Defaults.publisher(.showNetworkGraph, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)
        
        Defaults.publisher(.showDiskGraph, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)

        Defaults.publisher(.openNotchWidth, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)

        // Observe terminal settings changes
        Defaults.publisher(.enableTerminalFeature, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)

        Defaults.publisher(.terminalMaxHeightFraction, options: []).sink { [weak self] _ in
            self?.debouncedUpdateWindowSize()
        }.store(in: &cancellables)

        MemoryUsageMonitor.shared.startMonitoring()

        ReminderLiveActivityManager.shared.$activeWindowReminders
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.debouncedUpdateWindowSize()
            }
            .store(in: &cancellables)

        TimerManager.shared.$activeSource
            .combineLatest(TimerManager.shared.$isTimerActive)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.debouncedUpdateWindowSize()
            }
            .store(in: &cancellables)

        Defaults.publisher(.enableShortcuts, options: []).sink { [weak self] change in
            Task { @MainActor [weak self] in
                guard let self else { return }
                KeyboardShortcuts.isEnabled = change.newValue
                self.updateFeatureShortcutAvailability()
            }
        }.store(in: &cancellables)

        Defaults.publisher(.enableTimerFeature, options: []).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFeatureShortcutAvailability()
            }
        }.store(in: &cancellables)

        Defaults.publisher(.enableClipboardManager, options: []).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFeatureShortcutAvailability()
            }
        }.store(in: &cancellables)

        Defaults.publisher(.enableColorPickerFeature, options: []).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFeatureShortcutAvailability()
            }
        }.store(in: &cancellables)

        Defaults.publisher(.enableScreenAssistant, options: []).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateFeatureShortcutAvailability()
            }
        }.store(in: &cancellables)

        // The hide option changes fullscreen visibility, not Spaces pinning.
        // Re-sync in case the user changes it while macOS is moving Spaces.
        Defaults.publisher(.hideNotchOption, options: []).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncNotchSpaceMembership()
            }
        }.store(in: &cancellables)
        
        // Observe minimalistic UI setting changes - trigger window resize
        Defaults.publisher(.enableMinimalisticUI, options: []).sink { [weak self] _ in
            // Update window size IMMEDIATELY (no debouncing) to prevent position shift
            self?.updateWindowSizeIfNeeded()
        }.store(in: &cancellables)
        
        // Observe screen recording settings changes
        Defaults.publisher(.enableScreenRecordingDetection, options: []).sink { _ in
            if Defaults[.enableScreenRecordingDetection] {
                ScreenRecordingManager.shared.startMonitoring()
            } else {
                ScreenRecordingManager.shared.stopMonitoring()
            }
        }.store(in: &cancellables)
        
        Defaults.publisher(.enableDoNotDisturbDetection, options: []).sink { [weak self] _ in
            guard let self else { return }

            if Defaults[.enableDoNotDisturbDetection] {
                self.dndManager.startMonitoring()
            } else {
                self.dndManager.stopMonitoring()
            }
        }.store(in: &cancellables)

        // Note: Polling setting removed - now uses event-driven private API detection only

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reassertDynamicIslandWindowSpacePresence()
                self?.adjustWindowPosition()
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.selectedScreenChanged, object: nil, queue: nil
        ) { [weak self] _ in
            self?.adjustWindowPosition(changeAlpha: true)
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.notchHeightChanged, object: nil, queue: nil
        ) { [weak self] _ in
            self?.adjustWindowPosition()
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.automaticallySwitchDisplayChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self, let window = self.window else { return }
            DispatchQueue.main.async {
                window.alphaValue =
                    self.coordinator.selectedScreen == self.coordinator.preferredScreen ? 1 : 0
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name.showOnAllDisplaysChanged, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self = self else { return }
            self.cleanupWindows(shouldInvert: true)

            if !Defaults[.showOnAllDisplays] {
                let viewModel = self.vm
                let window = self.createDynamicIslandWindow(
                    for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
                self.window = window
                self.adjustWindowPosition(changeAlpha: true)
            } else {
                self.adjustWindowPosition()
            }
        }

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(onScreenLocked(_:)),
            name: NSNotification.Name(rawValue: "com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(onScreenUnlocked(_:)),
            name: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"), object: nil)

        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) { [weak self] in
            guard let self = self else { return }
            guard Defaults[.enableShortcuts] else { return }

            self.coordinator.toggleSneakPeek(
                status: !self.coordinator.sneakPeek.show,
                type: .music,
                duration: 3.0
            )
        }

        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            guard let self = self else { return }
            guard Defaults[.enableShortcuts] else { return }

            let mouseLocation = NSEvent.mouseLocation

            var viewModel = self.vm

            if Defaults[.showOnAllDisplays] {
                for screen in NSScreen.screens {
                    if screen.frame.contains(mouseLocation) {
                        if let screenViewModel = self.viewModels[screen] {
                            viewModel = screenViewModel
                            break
                        }
                    }
                }
            }

            self.closeNotchWorkItem?.cancel()
            self.closeNotchWorkItem = nil

            switch viewModel.notchState {
            case .closed:
                viewModel.open()

                let workItem = DispatchWorkItem { [weak viewModel] in
                    viewModel?.close()
                }
                self.closeNotchWorkItem = workItem

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
            case .open:
                viewModel.close()
            }
        }

        KeyboardShortcuts.isEnabled = Defaults[.enableShortcuts]
        registerOptionalShortcutHandlers()
        updateFeatureShortcutAvailability()

        if !Defaults[.showOnAllDisplays] {
            let viewModel = self.vm
            let window = createDynamicIslandWindow(
                for: NSScreen.main ?? NSScreen.screens.first!, with: viewModel)
            self.window = window
            adjustWindowPosition(changeAlpha: true)
        } else {
            adjustWindowPosition(changeAlpha: true)
        }
        
        // Skip onboarding window and welcome sound under UI testing.
        if coordinator.firstLaunch && !AppRuntimeEnvironment.isUITesting {
            DispatchQueue.main.async {
                self.showOnboardingWindow()
            }
            playWelcomeSound()
        }
        
        previousScreens = NSScreen.screens

        // Skip weather under UI testing: prepareLocationAccess prompts for Location.
        if Defaults[.enableLockScreenWeatherWidget] && !AppRuntimeEnvironment.isUITesting {
            LockScreenWeatherManager.shared.prepareLocationAccess()
            Task { @MainActor in
                await LockScreenWeatherManager.shared.refresh(force: true)
            }
        }

        // Warm up the lock screen timer widget manager so it can observe timer/default
        // changes immediately instead of waiting for the first lock event.
        let timerWidgetManager = LockScreenTimerWidgetManager.shared
        timerWidgetManager.handleLockStateChange(isLocked: LockScreenManager.shared.currentLockStatus)

    }

    private func installTopMenuItemsIfNeeded() {
        guard let mainMenu = NSApp.mainMenu else { return }
        if mainMenu.items.contains(where: { $0.identifier?.rawValue == "Atoll.Focus.Menu" }) {
            updateFocusMenuState()
            return
        }

        let insertionIndex = preferredMenuInsertionIndex(in: mainMenu)

        let focusMenuItem = NSMenuItem(title: "Focus", action: nil, keyEquivalent: "")
        focusMenuItem.identifier = NSUserInterfaceItemIdentifier("Atoll.Focus.Menu")
        let focusSubmenu = NSMenu(title: "Focus")

        let withoutDevTools = NSMenuItem(
            title: "Use without DevTools",
            action: #selector(selectFocusWithoutDevTools),
            keyEquivalent: ""
        )
        withoutDevTools.target = self

        let useDevTools = NSMenuItem(
            title: "Use DevTools",
            action: #selector(selectFocusUseDevTools),
            keyEquivalent: ""
        )
        useDevTools.target = self

        focusSubmenu.addItem(withoutDevTools)
        focusSubmenu.addItem(useDevTools)
        focusMenuItem.submenu = focusSubmenu
        mainMenu.insertItem(focusMenuItem, at: insertionIndex)

        focusWithoutDevToolsMenuItem = withoutDevTools
        focusUseDevToolsMenuItem = useDevTools

        let accessibilityMenuItem = NSMenuItem(title: "Accessibility", action: nil, keyEquivalent: "")
        accessibilityMenuItem.identifier = NSUserInterfaceItemIdentifier("Atoll.Accessibility.Menu")
        let accessibilitySubmenu = NSMenu(title: "Accessibility")

        let requestAccessibility = NSMenuItem(
            title: "Request Accessibility Access",
            action: #selector(requestAccessibilityAccess),
            keyEquivalent: ""
        )
        requestAccessibility.target = self

        let openAccessibility = NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        openAccessibility.target = self

        accessibilitySubmenu.addItem(requestAccessibility)
        accessibilitySubmenu.addItem(openAccessibility)
        accessibilityMenuItem.submenu = accessibilitySubmenu
        mainMenu.insertItem(accessibilityMenuItem, at: insertionIndex + 1)

        let permissionsMenuItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        permissionsMenuItem.identifier = NSUserInterfaceItemIdentifier("Atoll.Permissions.Menu")
        let permissionsSubmenu = NSMenu(title: "Permissions")

        let requestFullDisk = NSMenuItem(
            title: "Request Full Disk Access",
            action: #selector(requestFullDiskAccess),
            keyEquivalent: ""
        )
        requestFullDisk.target = self

        let openFullDisk = NSMenuItem(
            title: "Open Full Disk Access Settings",
            action: #selector(openFullDiskAccessSettings),
            keyEquivalent: ""
        )
        openFullDisk.target = self

        let openDevTools = NSMenuItem(
            title: "Open Developer Tools Settings",
            action: #selector(openDeveloperToolsSettingsFromMenu),
            keyEquivalent: ""
        )
        openDevTools.target = self

        permissionsSubmenu.addItem(requestFullDisk)
        permissionsSubmenu.addItem(openFullDisk)
        permissionsSubmenu.addItem(NSMenuItem.separator())
        permissionsSubmenu.addItem(openDevTools)
        permissionsMenuItem.submenu = permissionsSubmenu
        mainMenu.insertItem(permissionsMenuItem, at: insertionIndex + 2)

        let toolsMenuItem = NSMenuItem(title: "Tools", action: nil, keyEquivalent: "")
        toolsMenuItem.identifier = NSUserInterfaceItemIdentifier("Atoll.Tools.Menu")
        let toolsSubmenu = NSMenu(title: "Tools")

        let loggingLevelItem = NSMenuItem(title: "Logging Level", action: nil, keyEquivalent: "")
        let loggingLevelSubmenu = NSMenu(title: "Logging Level")
        
        let levels: [(String, LogLevel)] = [
            ("No Logging", .none),
            ("Error", .error),
            ("Warning", .warning),
            ("Info", .info),
            ("Debug", .debug)
        ]
        
        for (title, level) in levels {
            let item = NSMenuItem(title: title, action: #selector(setLogLevel(_:)), keyEquivalent: "")
            item.target = self
            item.tag = level.rawValue
            item.state = (Defaults[.logLevel] == level) ? NSControl.StateValue.on : NSControl.StateValue.off
            loggingLevelSubmenu.addItem(item)
        }
        loggingLevelItem.submenu = loggingLevelSubmenu
        toolsSubmenu.addItem(loggingLevelItem)

        toolsSubmenu.addItem(NSMenuItem.separator())
        
        let exportLogsItem = NSMenuItem(title: "Export Logs", action: #selector(exportLogs), keyEquivalent: "")
        exportLogsItem.target = self
        toolsSubmenu.addItem(exportLogsItem)

        toolsMenuItem.submenu = toolsSubmenu
        mainMenu.insertItem(toolsMenuItem, at: insertionIndex + 3)

        updateFocusMenuState()
    }

    private func preferredMenuInsertionIndex(in mainMenu: NSMenu) -> Int {
        if let index = mainMenu.items.firstIndex(where: { $0.title == "Window" }) {
            return index
        }
        if let index = mainMenu.items.firstIndex(where: { $0.title == "Help" }) {
            return index
        }
        return max(mainMenu.numberOfItems, 0)
    }

    private func updateFocusMenuState() {
        let mode = Defaults[.focusMonitoringMode]
        focusWithoutDevToolsMenuItem?.state = mode == .withoutDevTools ? .on : .off
        focusUseDevToolsMenuItem?.state = mode == .useDevTools ? .on : .off
    }

    @objc private func selectFocusWithoutDevTools() {
        Defaults[.focusMonitoringMode] = .withoutDevTools
        updateFocusMenuState()
    }

    @objc private func selectFocusUseDevTools() {
        Defaults[.focusMonitoringMode] = .useDevTools
        updateFocusMenuState()
    }

    @objc private func requestAccessibilityAccess() {
        AccessibilityPermissionStore.shared.requestAuthorizationPrompt()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermissionStore.shared.openSystemSettings()
    }

    @objc private func requestFullDiskAccess() {
        FullDiskAccessPermissionStore.shared.requestAccessPrompt()
    }

    @objc private func openFullDiskAccessSettings() {
        FullDiskAccessPermissionStore.shared.openSystemSettings()
    }

    @objc private func openDeveloperToolsSettingsFromMenu() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_DevTools",
            "x-apple.systempreferences:com.apple.preference.security"
        ]

        for candidate in urls {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    @objc private func setLogLevel(_ sender: NSMenuItem) {
        guard let level = LogLevel(rawValue: sender.tag) else { return }
        Defaults[.logLevel] = level
        
        guard let mainMenu = NSApp.mainMenu,
              let toolsItem = mainMenu.item(withTitle: "Tools"),
              let toolsMenu = toolsItem.submenu,
              let loggingItem = toolsMenu.items.first(where: { $0.title == "Logging Level" }),
              let loggingSubmenu = loggingItem.submenu else { return }
              
        for item in loggingSubmenu.items {
            item.state = (item.tag == level.rawValue) ? NSControl.StateValue.on : NSControl.StateValue.off
        }
    }

    @objc private func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "Atoll_Logs.zip"
        savePanel.title = "Export Logs & Crash Reports"
        
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            
            Task.detached(priority: .utility) {
                do {
                    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    
                    let logsFile = tempDir.appendingPathComponent("app_logs.txt")
                    let logProcess = Process()
                    logProcess.executableURL = URL(fileURLWithPath: "/usr/bin/log")
                    logProcess.arguments = ["show", "--predicate", "subsystem == 'com.Ebullioscopic.Atoll' OR subsystem == 'com.Ebullioscopic.Atoll.dev'", "--info", "--debug", "--last", "2d"]
                    
                    let pipe = Pipe()
                    logProcess.standardOutput = pipe
                    try logProcess.run()
                    logProcess.waitUntilExit()
                    
                    let logData = pipe.fileHandleForReading.readDataToEndOfFile()
                    try logData.write(to: logsFile)
                    
                    let diagDir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/DiagnosticReports")
                    let allFiles = (try? FileManager.default.contentsOfDirectory(at: diagDir, includingPropertiesForKeys: nil)) ?? []
                    for file in allFiles where file.lastPathComponent.contains("Atoll") {
                        try? FileManager.default.copyItem(at: file, to: tempDir.appendingPathComponent(file.lastPathComponent))
                    }
                    
                    let sysDiagDir = URL(fileURLWithPath: "/Library/Logs/DiagnosticReports")
                    let sysFiles = (try? FileManager.default.contentsOfDirectory(at: sysDiagDir, includingPropertiesForKeys: nil)) ?? []
                    for file in sysFiles where file.lastPathComponent.contains("Atoll") {
                        try? FileManager.default.copyItem(at: file, to: tempDir.appendingPathComponent(file.lastPathComponent))
                    }
                    
                    let zipProcess = Process()
                    zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                    zipProcess.currentDirectoryURL = tempDir
                    let items = (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
                    zipProcess.arguments = ["-r", url.path] + items
                    
                    try zipProcess.run()
                    zipProcess.waitUntilExit()
                    
                    try? FileManager.default.removeItem(at: tempDir)
                    
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Logs Exported"
                        alert.informativeText = "Logs and crash reports have been successfully exported to \(url.lastPathComponent)."
                        alert.alertStyle = .informational
                        alert.runModal()
                    }
                } catch {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Export Failed"
                        alert.informativeText = "Failed to export logs: \(error.localizedDescription)"
                        alert.alertStyle = .critical
                        alert.runModal()
                    }
                }
            }
        }
    }

    // Cancel the auto-close armed by `toggleNotchOpen`. Switching to the clipboard tab
    // from the header only changes `coordinator.currentView`, so without this the notch
    // can close mid-copy/drag a few seconds after it was opened.
    func cancelPendingNotchAutoClose() {
        closeNotchWorkItem?.cancel()
        closeNotchWorkItem = nil
    }

    private func registerOptionalShortcutHandlers() {
        guard !optionalShortcutHandlersRegistered else { return }
        optionalShortcutHandlersRegistered = true

        KeyboardShortcuts.onKeyDown(for: .startDemoTimer) {
            guard Defaults[.enableShortcuts], Defaults[.enableTimerFeature] else { return }
            TimerManager.shared.startDemoTimer(duration: 300)
        }

        KeyboardShortcuts.onKeyDown(for: .clipboardHistoryPanel) { [weak self] in
            guard let self else { return }
            guard Defaults[.enableShortcuts], Defaults[.enableClipboardManager] else { return }

            if !ClipboardManager.shared.isMonitoring {
                ClipboardManager.shared.startMonitoring()
            }

            switch Defaults[.clipboardDisplayMode] {
            case .panel:
                ClipboardPanelManager.shared.toggleClipboardPanel()
            case .popover:
                if vm.notchState == .closed {
                    vm.open()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: NSNotification.Name("ToggleClipboardPopover"), object: nil)
                    }
                } else {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleClipboardPopover"), object: nil)
                }
            case .separateTab:
                if vm.notchState == .closed {
                    vm.open()
                    coordinator.currentView = .notes
                } else {
                    if coordinator.currentView == .notes {
                        vm.close()
                    } else {
                        coordinator.currentView = .notes
                    }
                }
            case .notchTab:
                // Act on the notch under the cursor, matching toggleNotchOpen: with
                // showOnAllDisplays the rendered windows use viewModels[screen], so mutating
                // the primary vm could flip currentView without opening a visible notch.
                var activeVM = vm
                if Defaults[.showOnAllDisplays] {
                    let mouseLocation = NSEvent.mouseLocation
                    for screen in NSScreen.screens where screen.frame.contains(mouseLocation) {
                        if let screenViewModel = viewModels[screen] {
                            activeVM = screenViewModel
                            break
                        }
                    }
                }
                // Cancel any pending auto-close armed by toggleNotchOpen, so it can't fire
                // and close the notch a few seconds after this shortcut opens/switches to it.
                cancelPendingNotchAutoClose()
                if activeVM.notchState == .closed {
                    activeVM.open()
                    coordinator.currentView = .clipboard
                } else {
                    if coordinator.currentView == .clipboard {
                        activeVM.close()
                    } else {
                        coordinator.currentView = .clipboard
                    }
                }
            }
        }

        KeyboardShortcuts.onKeyDown(for: .colorPickerPanel) {
            guard Defaults[.enableShortcuts], Defaults[.enableColorPickerFeature] else { return }
            ColorPickerPanelManager.shared.toggleColorPickerPanel()
        }

        KeyboardShortcuts.onKeyDown(for: .toggleTerminalTab) { [weak self] in
            guard let self else { return }
            guard Defaults[.enableShortcuts], Defaults[.enableTerminalFeature] else { return }

            if vm.notchState == .closed {
                closeNotchWorkItem?.cancel()
                closeNotchWorkItem = nil
                vm.open()
                coordinator.currentView = .terminal
                TerminalManager.shared.refreshTerminalAppearanceIfNeeded()
                TerminalManager.shared.focusTerminalIfPossible()
                TerminalManager.shared.refreshTerminalAppearanceIfNeeded()
            } else {
                if coordinator.currentView == .terminal {
                    coordinator.suppressHoverOpen()
                    TerminalManager.shared.resignTerminalFirstResponderIfNeeded()
                    vm.close()
                } else {
                    closeNotchWorkItem?.cancel()
                    closeNotchWorkItem = nil
                    coordinator.currentView = .terminal
                    TerminalManager.shared.refreshTerminalAppearanceIfNeeded()
                    TerminalManager.shared.focusTerminalIfPossible()
                    TerminalManager.shared.refreshTerminalAppearanceIfNeeded()
                }
            }
        }

        KeyboardShortcuts.onKeyDown(for: .screenAssistantPanel) { [weak self] in
            guard let self else { return }
            guard Defaults[.enableShortcuts], Defaults[.enableScreenAssistant] else { return }

            switch Defaults[.screenAssistantDisplayMode] {
            case .panel:
                ScreenAssistantPanelManager.shared.toggleScreenAssistantPanel()
            case .popover:
                if vm.notchState == .closed {
                    vm.open()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NotificationCenter.default.post(name: NSNotification.Name("ToggleScreenAssistantPopover"), object: nil)
                    }
                } else {
                    NotificationCenter.default.post(name: NSNotification.Name("ToggleScreenAssistantPopover"), object: nil)
                }
            }
        }
    }

    @MainActor
    private func updateFeatureShortcutAvailability() {
        updateShortcut(.startDemoTimer, isEnabled: Defaults[.enableShortcuts] && Defaults[.enableTimerFeature])
        updateShortcut(.clipboardHistoryPanel, isEnabled: Defaults[.enableShortcuts] && Defaults[.enableClipboardManager])
        updateShortcut(.colorPickerPanel, isEnabled: Defaults[.enableShortcuts] && Defaults[.enableColorPickerFeature])
        updateShortcut(.screenAssistantPanel, isEnabled: Defaults[.enableShortcuts] && Defaults[.enableScreenAssistant])
        updateShortcut(.toggleTerminalTab, isEnabled: Defaults[.enableShortcuts] && Defaults[.enableTerminalFeature])
    }

    @MainActor
    private func updateShortcut(_ name: KeyboardShortcuts.Name, isEnabled: Bool) {
        if isEnabled {
            KeyboardShortcuts.enable(name)
        } else {
            KeyboardShortcuts.disable(name)
        }
    }
    
    func playWelcomeSound() {
        let audioPlayer = AudioPlayer()
        audioPlayer.play(fileName: "dynamic", fileExtension: "m4a")
    }
    
    func deviceHasNotch() -> Bool {
        if #available(macOS 12.0, *) {
            for screen in NSScreen.screens {
                if screen.safeAreaInsets.top > 0 {
                    return true
                }
            }
        }
        return false
    }
    
    @objc func screenConfigurationDidChange() {
        let currentScreens = NSScreen.screens

        let screensChanged =
            currentScreens.count != previousScreens?.count
            || Set(currentScreens.map { $0.localizedName })
                != Set(previousScreens?.map { $0.localizedName } ?? [])
            || Set(currentScreens.map { $0.frame }) != Set(previousScreens?.map { $0.frame } ?? [])

        previousScreens = currentScreens
        
        if screensChanged {
            DispatchQueue.main.async { [weak self] in
                self?.cleanupWindows()
                self?.adjustWindowPosition()
            }
        }
    }
    
    @objc func adjustWindowPosition(changeAlpha: Bool = false) {
        if Defaults[.showOnAllDisplays] {
            let currentScreens = Set(NSScreen.screens)
            
            for screen in windows.keys where !currentScreens.contains(screen) {
                if let window = windows[screen] {
                    viewModels[screen]?.onViewTeardown?()
                    viewModels[screen]?.onViewTeardown = nil
                    window.close()
                    windows.removeValue(forKey: screen)
                    viewModels.removeValue(forKey: screen)
                }
            }
            
            for screen in currentScreens {
                if windows[screen] == nil {
                    let viewModel = DynamicIslandViewModel(screen: screen.localizedName)
                    let window = createDynamicIslandWindow(for: screen, with: viewModel)
                    
                    windows[screen] = window
                    viewModels[screen] = viewModel
                }
                
                if let window = windows[screen], let viewModel = viewModels[screen] {
                    positionWindow(window, on: screen, changeAlpha: changeAlpha)
                    
                    if viewModel.notchState == .closed {
                        viewModel.close()
                    }
                }
            }
        } else {
            let selectedScreen: NSScreen

            if let preferredScreen = NSScreen.screens.first(where: {
                $0.localizedName == coordinator.preferredScreen
            }) {
                coordinator.selectedScreen = coordinator.preferredScreen
                selectedScreen = preferredScreen
            } else if Defaults[.automaticallySwitchDisplay], let mainScreen = NSScreen.main {
                coordinator.selectedScreen = mainScreen.localizedName
                selectedScreen = mainScreen
            } else {
                if let window = window {
                    window.alphaValue = 0
                }
                return
            }
            
            vm.screen = selectedScreen.localizedName
            vm.notchSize = getClosedNotchSize(screen: selectedScreen.localizedName)
            
            if window == nil {
                window = createDynamicIslandWindow(for: selectedScreen, with: vm)
            }
            if let window = window {
                positionWindow(window, on: selectedScreen, changeAlpha: changeAlpha)

                if vm.notchState == .closed {
                    vm.close()
                }
            }
        }

        syncNotchSpaceMembership()
    }
    
    @objc func togglePopover(_ sender: Any?) {
        if window?.isVisible == true {
            window?.orderOut(nil)
        } else {
            window?.orderFrontRegardless()
        }
    }
    
    @objc func showMenu() {
        statusItem?.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
    
    @objc func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    
    
    private func showOnboardingWindow() {
        if onboardingWindowController == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Onboarding"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(rootView: OnboardingView(
                onFinish: {
                    window.orderOut(nil)
                    NSApp.setActivationPolicy(.accessory)
                    window.close()
                    NSApp.deactivate()
                },
                onOpenSettings: {
                    window.close()
                    SettingsWindowController.shared.showWindow()
                }
            ))
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("OnboardingWindow")

            ScreenCaptureVisibilityManager.shared.register(window, scope: .panelsOnly)

            onboardingWindowController = NSWindowController(window: window)
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.window?.makeKeyAndOrderFront(nil)
        onboardingWindowController?.window?.orderFrontRegardless()
    }
}

extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let showOnAllDisplaysChanged = Notification.Name("showOnAllDisplaysChanged")
    static let automaticallySwitchDisplayChanged = Notification.Name("automaticallySwitchDisplayChanged")
}

extension CGRect: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(origin.x)
        hasher.combine(origin.y)
        hasher.combine(size.width)
        hasher.combine(size.height)
    }

    public static func == (lhs: CGRect, rhs: CGRect) -> Bool {
        return lhs.origin == rhs.origin && lhs.size == rhs.size
    }
}

@MainActor
final class MediaControlsStateCoordinator {
    static let shared = MediaControlsStateCoordinator()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let masterPublisher = Defaults.publisher(.showStandardMediaControls)
        let minimalisticPublisher = Defaults.publisher(.enableMinimalisticUI)

        Publishers.CombineLatest(masterPublisher, minimalisticPublisher)
            .receive(on: RunLoop.main)
            .sink { [weak self] masterChange, minimalisticChange in
                self?.handleStateChange(
                    showStandard: masterChange.newValue,
                    minimalistic: minimalisticChange.newValue
                )
            }
            .store(in: &cancellables)
    }

    private func handleStateChange(showStandard: Bool, minimalistic: Bool) {
        if !showStandard && !minimalistic {
            cacheAndDisableMusicLiveActivity()
        } else {
            restoreMusicLiveActivity(clearCache: showStandard)
        }

        if showStandard {
            restoreLockScreenPanelIfNeeded()
            restoreMusicControlWindowIfNeeded()
        } else {
            cacheAndDisableLockScreenPanel()
            cacheAndDisableMusicControlWindow()
        }
    }

    private func cacheAndDisableMusicLiveActivity() {
        if Defaults[.cachedMusicLiveActivityPreference] == nil {
            Defaults[.cachedMusicLiveActivityPreference] = DynamicIslandViewCoordinator.shared.musicLiveActivityEnabled
        }

        if DynamicIslandViewCoordinator.shared.musicLiveActivityEnabled {
            DynamicIslandViewCoordinator.shared.musicLiveActivityEnabled = false
        }
    }

    private func restoreMusicLiveActivity(clearCache: Bool) {
        guard let cached = Defaults[.cachedMusicLiveActivityPreference] else { return }

        if DynamicIslandViewCoordinator.shared.musicLiveActivityEnabled != cached {
            DynamicIslandViewCoordinator.shared.musicLiveActivityEnabled = cached
        }

        if clearCache {
            Defaults[.cachedMusicLiveActivityPreference] = nil
        }
    }

    private func cacheAndDisableLockScreenPanel() {
        if Defaults[.cachedLockScreenMediaWidgetPreference] == nil {
            Defaults[.cachedLockScreenMediaWidgetPreference] = Defaults[.enableLockScreenMediaWidget]
        }

        if Defaults[.enableLockScreenMediaWidget] {
            Defaults[.enableLockScreenMediaWidget] = false
            LockScreenPanelManager.shared.hidePanel()
        }
    }

    private func restoreLockScreenPanelIfNeeded() {
        guard let cached = Defaults[.cachedLockScreenMediaWidgetPreference] else { return }
        Defaults[.enableLockScreenMediaWidget] = cached
        Defaults[.cachedLockScreenMediaWidgetPreference] = nil
    }

    private func cacheAndDisableMusicControlWindow() {
        if Defaults[.cachedMusicControlWindowPreference] == nil {
            Defaults[.cachedMusicControlWindowPreference] = Defaults[.musicControlWindowEnabled]
        }

        if Defaults[.musicControlWindowEnabled] {
            Defaults[.musicControlWindowEnabled] = false
        }

        MusicControlWindowManager.shared.hide()
    }

    private func restoreMusicControlWindowIfNeeded() {
        guard let cached = Defaults[.cachedMusicControlWindowPreference] else { return }
        Defaults[.musicControlWindowEnabled] = cached
        Defaults[.cachedMusicControlWindowPreference] = nil
    }
}
