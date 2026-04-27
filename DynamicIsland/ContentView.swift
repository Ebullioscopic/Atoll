/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * Originally from boring.notch project
 * Modified and adapted for Atoll (DynamicIsland)
 * See NOTICE for details.
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
import Foundation
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect
import AtollExtensionKit
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @EnvironmentObject var webcamManager: WebcamManager

    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var reminderManager = ReminderLiveActivityManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var statsManager = StatsManager.shared
    @ObservedObject var recordingManager = ScreenRecordingManager.shared
    @ObservedObject var privacyManager = PrivacyIndicatorManager.shared
    @ObservedObject var doNotDisturbManager = DoNotDisturbManager.shared
    @ObservedObject var lockScreenManager = LockScreenManager.shared
    @ObservedObject var capsLockManager = CapsLockManager.shared
    @ObservedObject var extensionLiveActivityManager = ExtensionLiveActivityManager.shared
    @ObservedObject var extensionNotchExperienceManager = ExtensionNotchExperienceManager.shared
    @ObservedObject var localSendService = LocalSendService.shared
    @State private var downloadManager = DownloadManager.shared
    
    @Default(.enableStatsFeature) var enableStatsFeature
    @Default(.showCpuGraph) var showCpuGraph
    @Default(.showMemoryGraph) var showMemoryGraph
    @Default(.showGpuGraph) var showGpuGraph
    @Default(.showNetworkGraph) var showNetworkGraph
    @Default(.showDiskGraph) var showDiskGraph
    @Default(.enableReminderLiveActivity) var enableReminderLiveActivity
    @Default(.enableTimerFeature) var enableTimerFeature
    @Default(.timerDisplayMode) var timerDisplayMode
    @Default(.enableHorizontalMusicGestures) var enableHorizontalMusicGestures
    @Default(.reminderPresentationStyle) var reminderPresentationStyle
    @Default(.timerShowsCountdown) var timerShowsCountdown
    @Default(.timerShowsProgress) var timerShowsProgress
    @Default(.timerProgressStyle) var timerProgressStyle
    @Default(.timerIconColorMode) var timerIconColorMode
    @Default(.timerSolidColor) var timerSolidColor
    @Default(.timerPresets) var timerPresets
    @Default(.showCapsLockLabel) var showCapsLockLabel
    @Default(.capsLockIndicatorTintMode) var capsLockTintMode
    @Default(.enableDoNotDisturbDetection) var enableDoNotDisturbDetection
    @Default(.showDoNotDisturbIndicator) var showDoNotDisturbIndicator
    @Default(.enableScreenRecordingDetection) var enableScreenRecordingDetection
    @Default(.enableCapsLockIndicator) var enableCapsLockIndicator
    @Default(.enableExtensionLiveActivities) var enableExtensionLiveActivities
    @Default(.showStandardMediaControls) var showStandardMediaControls
    @Default(.externalDisplayStyle) var externalDisplayStyle
    @Default(.hideNonNotchUntilHover) var hideNonNotchUntilHover
    @Default(.terminalStickyMode) var terminalStickyMode
    
    // Dynamic sizing based on view type and graph count with smooth transitions
    var dynamicNotchSize: CGSize {
        let baseSize = Defaults[.enableMinimalisticUI] ? minimalisticOpenNotchSize : openNotchSize
        
        // When inline sneak peek is active in closed notch, use the wider inline width
        // so the outer maxWidth frame doesn't clip the expanded content
        let inlineSneakPeekActive = vm.notchState == .closed
            && coordinator.expandingView.show
            && (coordinator.expandingView.type == .music || coordinator.expandingView.type == .timer)
            && Defaults[.enableSneakPeek]
            && Defaults[.sneakPeekStyles] == .inline
        if inlineSneakPeekActive {
            let inlineWidth: CGFloat = 460
            return CGSize(width: max(baseSize.width, inlineWidth), height: baseSize.height)
        }
        
        if coordinator.currentView == .timer {
            return CGSize(width: baseSize.width, height: 250) // Extra height for timer presets
        }
        
        if coordinator.currentView == .notes || coordinator.currentView == .clipboard {
            let preferredHeight = coordinator.notesLayoutState.preferredHeight
            let resolvedHeight = max(baseSize.height, preferredHeight)
            return CGSize(width: baseSize.width, height: resolvedHeight)
        }

        if coordinator.currentView == .terminal {
            // Dynamic height: up to terminalMaxHeightFraction of screen, min 300pt
            let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
            let maxFraction = Defaults[.terminalMaxHeightFraction]
            let terminalHeight = min(screenHeight * maxFraction, max(300, screenHeight * maxFraction))
            return CGSize(width: baseSize.width, height: terminalHeight)
        }

        if coordinator.currentView == .extensionExperience {
            if let preferredHeight = extensionTabPreferredHeight(baseSize: baseSize) {
                return CGSize(width: baseSize.width, height: preferredHeight)
            }
            return baseSize
        }

        if enableMinimalisticUI,
           coordinator.currentView == .home,
           let preferredHeight = extensionMinimalisticPreferredHeight(baseSize: baseSize) {
            return CGSize(width: baseSize.width, height: preferredHeight)
        }
        
        guard coordinator.currentView == .stats else {
            return baseSize
        }
        
        let rows = statsRowCount()
        if rows <= 1 {
            return baseSize
        }
        
        let additionalRows = max(rows - 1, 0)
        let extraHeight = CGFloat(additionalRows) * statsAdditionalRowHeight
        return CGSize(width: baseSize.width, height: baseSize.height + extraHeight)
    }
    

    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var lastHapticTime: Date = Date()
    @State private var hoverClickMonitor: Any?
    @State private var hoverClickLocalMonitor: Any?
    @State private var stickyTerminalClickMonitor: Any?
    @State private var hiddenEdgeHoverPollingTask: Task<Void, Never>?
    @State private var isHoveringClosedMusicWaveformControl: Bool = false

    @State private var gestureProgress: CGFloat = .zero
    @State private var skipGestureActiveDirection: MusicManager.SkipDirection?
    @State private var isMusicControlWindowVisible = false
    @State private var pendingMusicControlTask: Task<Void, Never>?
    @State private var musicControlHideTask: Task<Void, Never>?
    @State private var musicControlVisibilityDeadline: Date?
    @State private var isMusicControlWindowSuppressed = false
    @State private var hasPendingMusicControlSync = false
    @State private var pendingMusicControlForceRefresh = false
    @State private var musicControlSuppressionTask: Task<Void, Never>?

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.musicControlWindowEnabled) var musicControlWindowEnabled
    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.useModernCloseAnimation) var useModernCloseAnimation
    @Default(.enableMinimalisticUI) var enableMinimalisticUI

    private static let musicControlLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private func logMusicControlEvent(_ message: String) {
#if DEBUG
        let timestamp = Self.musicControlLogFormatter.string(from: Date())
        print("[MusicControl] \(timestamp): \(message)")
#endif
    }

    private func runAfter(_ delay: TimeInterval, _ action: @escaping @Sendable @MainActor () -> Void) {
        guard delay >= 0 else { return }
        Task { @MainActor in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            action()
        }
    }

    private func requestMusicControlWindowSyncIfHidden(forceRefresh: Bool = false, delay: TimeInterval = 0) {
        guard !isMusicControlWindowVisible else { return }
        enqueueMusicControlWindowSync(forceRefresh: forceRefresh, delay: delay)
    }
    private var dynamicNotchResizeAnimation: Animation? {
        nil
    }
    
    private let zeroHeightHoverPadding: CGFloat = 10
    private let statsAdditionalRowHeight: CGFloat = statsSecondRowContentHeight + statsGridSpacingHeight
    private let musicControlPauseGrace: TimeInterval = 5
    private let musicControlResumeDelay: TimeInterval = 0.24

    // MARK: - Tab switch direction for smooth transitions
    
    private var tabSwitchTransition: AnyTransition {
        if coordinator.tabSwitchForward {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        } else {
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
    
    private var standardMediaControlsActive: Bool {
        showStandardMediaControls && !enableMinimalisticUI
    }

    private var closedMusicContentEnabled: Bool {
        enableMinimalisticUI || showStandardMediaControls
    }

    private var isMusicHUDDeferredAfterUnlock: Bool {
        lockScreenManager.shouldDelayPostUnlockMusicHUD
    }

    private var interactionsEnabled: Bool {
        !lockScreenManager.isLocked
    }

    private var isIslandMode: Bool {
        isDynamicIslandMode
    }

    private var notchHorizontalPadding: CGFloat {
        guard vm.notchState == .open else {
            return activeCornerRadiusInsets.closed.bottom
        }
        if Defaults[.cornerRadiusScaling] {
            return activeCornerRadiusInsets.opened.top - 5
        }
        return activeCornerRadiusInsets.opened.bottom - 5
    }

    private var bodyHoverAreaPadding: CGFloat {
        if vm.notchState == .open && Defaults[.extendHoverArea] {
            return 0
        }
        return vm.effectiveClosedNotchHeight == 0 ? zeroHeightHoverPadding : 0
    }

    private var notchBottomPadding: CGFloat {
        currentShadowPadding + bodyHoverAreaPadding
    }

    private var pillTopOffset: CGFloat {
        isIslandMode ? dynamicIslandTopOffset : 0
    }

    private func closedMusicPairingEligible(hasActiveMusicSnapshot: Bool) -> Bool {
        vm.notchState == .closed
            && hasActiveMusicSnapshot
            && coordinator.musicLiveActivityEnabled
            && closedMusicContentEnabled
            && !vm.hideOnClosed
            && !lockScreenManager.isLocked
            && !isMusicHUDDeferredAfterUnlock
    }

    private var closedLiveActivitySwapTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.965, anchor: .center))
                .animation(.spring(response: 0.34, dampingFraction: 0.88)),
            removal: .opacity
                .combined(with: .scale(scale: 0.92, anchor: .center))
                .animation(.smooth(duration: 0.22))
        )
    }
    
    // Use minimalistic corner radius ONLY when opened, keep normal when closed
    private var activeCornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) {
        if enableMinimalisticUI {
            // Keep normal closed corner radius, use minimalistic when opened
            return (opened: minimalisticCornerRadiusInsets.opened, closed: cornerRadiusInsets.closed)
        }
        return cornerRadiusInsets
    }
    
    private var currentShadowPadding: CGFloat {
        notchShadowPaddingValue(isMinimalistic: enableMinimalisticUI)
    }

    private var currentNotchShape: NotchShape {
        let topRadius = (vm.notchState == .open && Defaults[.cornerRadiusScaling])
            ? activeCornerRadiusInsets.opened.top
            : activeCornerRadiusInsets.closed.top
        let bottomRadius = (vm.notchState == .open && Defaults[.cornerRadiusScaling])
            ? activeCornerRadiusInsets.opened.bottom
            : activeCornerRadiusInsets.closed.bottom
        return NotchShape(topCornerRadius: topRadius, bottomCornerRadius: bottomRadius)
    }

    /// Whether the current screen should render as a Dynamic Island pill
    /// rather than the standard notch shape. Always false on physical notch screens.
    private var isDynamicIslandMode: Bool {
        shouldUseDynamicIslandMode(for: currentScreenName)
    }

    private var currentScreenName: String {
        vm.screen ?? coordinator.selectedScreen
    }

    /// Whether the current screen lacks a physical notch.
    private var isNonNotchScreen: Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return true
        }
        return screen.safeAreaInsets.top <= 0
    }

    /// Whether the global sneak peek is visible on this specific screen.
    private var isSneakPeekVisibleOnCurrentScreen: Bool {
        guard coordinator.sneakPeek.show else { return false }
        guard Defaults[.showOnAllDisplays] else { return true }
        guard let targetScreenName = coordinator.sneakPeek.targetScreenName else { return true }
        return currentScreenName == targetScreenName
    }

    /// Whether the notch/island should hide off-screen when closed on a non-notch display.
    /// Temporarily reveals the notch when a sneakPeek HUD (volume, brightness, music, etc.) is active.
    private var shouldHideUntilHover: Bool {
        hideNonNotchUntilHover && isNonNotchScreen && vm.notchState == .closed && !isSneakPeekVisibleOnCurrentScreen
    }

    /// Whether the fallback top-edge hover detector should run.
    /// This is only needed when the notch is fully hidden off-screen and
    /// regular `.onHover` hit-testing may not trigger reliably.
    private var shouldUseHiddenEdgeHoverPolling: Bool {
        shouldHideUntilHover && !lockScreenManager.isLocked
    }
    
    /// Whether the LocalSend live activity should be shown
    private var localSendLiveActivityActive: Bool {
        localSendService.isSending || 
        localSendService.transferState == .completed ||
        isLocalSendFailedOrRejected
    }
    
    private var isLocalSendFailedOrRejected: Bool {
        if case .failed = localSendService.transferState { return true }
        if case .rejected = localSendService.transferState { return true }
        return false
    }

    /// Pill shape for Dynamic Island mode with animated corner radius transitions.
    private var currentPillShape: DynamicIslandPillShape {
        let radius: CGFloat
        if vm.notchState == .open {
            radius = enableMinimalisticUI
                ? minimalisticCornerRadiusInsets.opened.top
                : dynamicIslandPillCornerRadiusInsets.opened
        } else {
            // Use half the closed height for a true capsule shape
            radius = max(vm.closedNotchSize.height / 2, dynamicIslandPillCornerRadiusInsets.closed.standard)
        }
        return DynamicIslandPillShape(cornerRadius: radius)
    }

    /// Resolves the clip/content shape per-screen: pill on non-notch screens
    /// when dynamic island mode is active, standard notch shape otherwise.
    private var resolvedClipShape: AnyShape {
        if isDynamicIslandMode {
            return AnyShape(currentPillShape)
        }
        return AnyShape(currentNotchShape)
    }

    var body: some View {
        installRootLifecycleHandlers(on: rootBodyView)
    }

    private var mainLayoutBase: some View {
        NotchLayout()
            .frame(alignment: .top)
            .padding(.horizontal, notchHorizontalPadding)
            .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
            .background(.black)
            .clipShape(resolvedClipShape)
            .compositingGroup()
            .shadow(
                color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                    ? .black.opacity(0.6)
                    : .clear,
                radius: Defaults[.cornerRadiusScaling] ? 10 : 5
            )
            // Extra horizontal inset for Dynamic Island mode so the shadow
            // is not clipped by the outer frame constraint
            .padding(.horizontal, isIslandMode ? dynamicIslandShadowInset : 0)
            .padding(.top, pillTopOffset)
    }

    private var configuredMainLayout: some View {
        mainLayoutBase
            .conditionalModifier(!useModernCloseAnimation) { view in
                let hoverAnimation = Animation.bouncy.speed(1.2)
                let notchStateAnimation = Animation.spring.speed(1.2)
                return view
                    .animation(hoverAnimation, value: isHovering)
                    .animation(notchStateAnimation, value: vm.notchState)
                    .animation(.smooth, value: gestureProgress)
                    .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
            }
            .conditionalModifier(useModernCloseAnimation) { view in
                let hoverAnimation = Animation.bouncy.speed(1.2)
                let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                let notchAnimation = vm.notchState == .open ? openAnimation : closeAnimation
                return view
                    .animation(hoverAnimation, value: isHovering)
                    .animation(notchAnimation, value: vm.notchState)
                    .animation(.smooth, value: gestureProgress)
            }
            .conditionalModifier(interactionsEnabled) { view in
                view
                    .contentShape(resolvedClipShape)
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        if handleClosedMusicWaveformTapIfNeeded() {
                            return
                        }
                        if vm.notchState == .closed && Defaults[.enableHaptics] {
                            triggerHapticIfAllowed()
                        }
                        openNotch()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                            .panGesture(direction: .left) { translation, phase in
                                handleSkipGesture(direction: .forward, translation: translation, phase: phase)
                            }
                            .panGesture(direction: .right) { translation, phase in
                                handleSkipGesture(direction: .backward, translation: translation, phase: phase)
                            }
                    }
            }
            .conditionalModifier((Defaults[.closeGestureEnabled] || Defaults[.reverseScrollGestures]) && Defaults[.enableGestures] && interactionsEnabled) { view in
                view
                    .panGesture(direction: .up) { translation, phase in
                        handleUpGesture(translation: translation, phase: phase)
                    }
            }
            // Shadow bottom padding and hide-until-hover offset applied AFTER
            // interaction modifiers so .contentShape / .onHover only covers
            // the actual notch content, not the shadow clearance below it.
            .padding(.bottom, notchBottomPadding)
            .offset(y: shouldHideUntilHover && !isHovering
                ? -(vm.closedNotchSize.height + pillTopOffset + currentShadowPadding + 10)
                : 0
            )
            .onAppear(perform: {
                if coordinator.firstLaunch {
                    // Single open during first launch; closeHello() handles the timed close.
                    runAfter(1) {
                        withAnimation(vm.animation) {
                            openNotch()
                        }
                    }
                }
            })
            .onChange(of: vm.notchState) { _, newState in
                // Update smart monitoring based on notch state
                if enableStatsFeature {
                    let currentViewString = coordinator.currentView == .stats ? "stats" : "other"
                    statsManager.updateMonitoringState(
                        notchIsOpen: newState == .open,
                        currentView: currentViewString
                    )
                }

                // Reset hover state when notch state changes
                if newState == .closed && isHovering {
                    withAnimation {
                        isHovering = false
                    }
                }
                if newState != .closed {
                    isHoveringClosedMusicWaveformControl = false
                }
                if newState == .closed {
                    removeStickyTerminalClickMonitor()
                }
                #if os(macOS)
                if newState == .open {
                    TimerControlWindowManager.shared.hide()
                }
                #endif
            }
            .onChange(of: vm.isBatteryPopoverActive) { _, newPopoverState in
                runAfter(0.1) {
                    if !newPopoverState && !isHovering && vm.notchState == .open && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }
            .onChange(of: vm.isStatsPopoverActive) { _, newPopoverState in
                runAfter(0.1) {
                    if !newPopoverState && !isHovering && vm.notchState == .open && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }
            .onChange(of: vm.shouldRecheckHover) { _, _ in
                // Recheck hover state when popovers are closed
                runAfter(0.1) {
                    if vm.notchState == .open && !shouldPreventAutoClose() && !isHovering {
                        vm.close()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                runAfter(0.1) {
                    if vm.notchState == .open && !isHovering && !shouldPreventAutoClose() {
                        vm.close()
                    }
                }
            }
            .onChange(of: coordinator.sneakPeek.show) { _, sneakPeekShowing in
                // When sneak peek finishes, check if user is still hovering and open notch if needed
                if !sneakPeekShowing {
                    runAfter(0.2) {
                        if isHovering && vm.notchState == .closed && !coordinator.isHoverOpenSuppressed {
                            openNotch()
                        }
                    }
                }
            }
            .onChange(of: coordinator.currentView) { _, newValue in
                if enableStatsFeature {
                    let currentViewString = newValue == .stats ? "stats" : "other"
                    statsManager.updateMonitoringState(
                        notchIsOpen: vm.notchState == .open,
                        currentView: currentViewString
                    )
                }
                syncStickyTerminalOutsideClickMonitor()
            }
            .sensoryFeedback(.alignment, trigger: haptics)
            .contextMenu {
                Button("Settings") {
                    SettingsWindowController.shared.showWindow()
                }
//                Button("Edit") { // Doesnt work....
//                    let dn = DynamicNotch(content: EditPanelView())
//                    dn.toggle()
//                }
//                #if DEBUG
//                .disabled(false)
//                #else
//                .disabled(true)
//                #endif
//                .keyboardShortcut("E", modifiers: .command)
            }
    }

    private var rootBodyView: some View {
        ZStack(alignment: .top) {
            configuredMainLayout
        }
        .frame(
            maxWidth: dynamicNotchSize.width + (isDynamicIslandMode ? dynamicIslandShadowInset * 2 : 0),
            maxHeight: dynamicNotchSize.height + currentShadowPadding + (isDynamicIslandMode ? dynamicIslandTopOffset : 0),
            alignment: .top
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environmentObject(privacyManager)
        .background(dragDetector)
        .environmentObject(vm)
        .environmentObject(webcamManager)
    }

    private func installRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        installSecondaryRootLifecycleHandlers(
            on: installPrimaryRootLifecycleHandlers(on: view)
        )
    }

    private func installPrimaryRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        view
            .onAppear {
                isMusicControlWindowSuppressed = vm.notchState != .closed
                    || lockScreenManager.isLocked
                    || isMusicHUDDeferredAfterUnlock
                if musicManager.isPlaying || !musicManager.isPlayerIdle {
                    clearMusicControlVisibilityDeadline()
                }
                if let deadline = musicControlVisibilityDeadline, Date() > deadline {
                    clearMusicControlVisibilityDeadline()
                }
                enqueueMusicControlWindowSync(forceRefresh: true)
                startHiddenEdgeHoverPolling()
            }
            .onChange(of: terminalStickyMode) { _, _ in
                syncStickyTerminalOutsideClickMonitor()
            }
            .onChange(of: vm.notchState) { _, state in
                if state == .open {
                    suppressMusicControlWindowUpdates()
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    releaseMusicControlWindowUpdates(after: musicControlResumeDelay)
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: musicControlWindowEnabled) { _, enabled in
                if enabled {
                    if musicManager.isPlaying || !musicManager.isPlayerIdle {
                        clearMusicControlVisibilityDeadline()
                    }
                    enqueueMusicControlWindowSync(forceRefresh: true)
                } else {
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                    clearMusicControlVisibilityDeadline()
                    hasPendingMusicControlSync = false
                    pendingMusicControlForceRefresh = false
                }
            }
            .onChange(of: coordinator.musicLiveActivityEnabled) { _, enabled in
                if enabled {
                    enqueueMusicControlWindowSync(forceRefresh: true)
                } else {
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                    clearMusicControlVisibilityDeadline()
                    hasPendingMusicControlSync = false
                    pendingMusicControlForceRefresh = false
                }
            }
            .onChange(of: vm.hideOnClosed) { _, hidden in
                if hidden {
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: lockScreenManager.isLocked) { _, locked in
                if locked {
                    suppressMusicControlWindowUpdates()
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    releaseMusicControlWindowUpdates(after: musicControlResumeDelay)
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: lockScreenManager.shouldDelayPostUnlockMusicHUD) { _, deferred in
                if deferred {
                    suppressMusicControlWindowUpdates()
                    cancelMusicControlWindowSync()
                    hideMusicControlWindow()
                } else {
                    releaseMusicControlWindowUpdates(after: 0)
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
    }

    private func installSecondaryRootLifecycleHandlers<Content: View>(on view: Content) -> some View {
        view
            .onChange(of: showStandardMediaControls) { _, _ in
                handleStandardMediaControlsAvailabilityChange()
            }
            .onChange(of: enableMinimalisticUI) { _, _ in
                handleStandardMediaControlsAvailabilityChange()
            }
            .onChange(of: gestureProgress) { _, _ in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: 0.05)
                }
            }
            .onChange(of: isHovering) { _, hovering in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true, delay: hovering ? 0.05 : 0.12)
                }
            }
            .onChange(of: musicManager.isPlaying) { _, isPlaying in
                handleMusicControlPlaybackChange(isPlaying: isPlaying)
            }
            .onChange(of: musicManager.isPlayerIdle) { _, isIdle in
                handleMusicControlIdleChange(isIdle: isIdle)
            }
            .onChange(of: vm.closedNotchSize) { _, _ in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true)
                }
            }
            .onChange(of: vm.effectiveClosedNotchHeight) { _, _ in
                if shouldShowMusicControlWindow() {
                    enqueueMusicControlWindowSync(forceRefresh: true)
                }
            }
            .onDisappear {
                hoverTask?.cancel()
                stopHoverClickMonitor()
                removeStickyTerminalClickMonitor()
                stopHiddenEdgeHoverPolling()
                cancelMusicControlWindowSync()
                hideMusicControlWindow()
                cancelMusicControlVisibilityTimer()
                clearMusicControlVisibilityDeadline()
                musicControlSuppressionTask?.cancel()
                isHoveringClosedMusicWaveformControl = false
            }
    }

    @ViewBuilder
      func NotchLayout() -> some View {
          VStack(alignment: .leading) {
              VStack(alignment: .leading) {
                  if coordinator.firstLaunch {
                      Spacer()
                      HelloAnimation().frame(width: 200, height: 80).onAppear(perform: {
                          vm.closeHello()
                      })
                      .padding(.top, 40)
                      Spacer()
                  } else {
                        let hasMusicMetadata = !musicManager.songTitle.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                            || !musicManager.artistName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
                      let hasActiveMusicSnapshot: Bool = {
                          if musicManager.isPlaying { return true }
                          return !musicManager.isPlayerIdle && hasMusicMetadata
                      }()
                      let musicPairingEligible = closedMusicPairingEligible(hasActiveMusicSnapshot: hasActiveMusicSnapshot)
                      let musicSecondary = resolveMusicSecondaryLiveActivity(isMusicPairingEligible: musicPairingEligible)
                      let extensionSecondaryPayloadID = extensionSecondaryPayloadID(for: musicSecondary)
                      let extensionStandalonePayload = resolvedExtensionStandalonePayload(excluding: extensionSecondaryPayloadID)
                      let activeSneakPeekStyle = resolvedSneakPeekStyle()
                      let expansionMatchesSecondary: Bool = {
                          guard let musicSecondary else { return false }
                          switch musicSecondary {
                          case .timer:
                              return coordinator.expandingView.type == .timer
                          case .reminder:
                              return coordinator.expandingView.type == .reminder
                          case .recording:
                              return coordinator.expandingView.type == .recording
                          case .focus:
                              return coordinator.expandingView.type == .doNotDisturb
                          case .capsLock:
                              return false
                          case .extensionPayload:
                              return false
                          }
                      }()
                      let canShowMusicDuringExpansion = !coordinator.expandingView.show
                          || coordinator.expandingView.type == .music
                          || expansionMatchesSecondary

                      if coordinator.expandingView.type == .battery && coordinator.expandingView.show && vm.notchState == .closed && Defaults[.showPowerStatusNotifications] {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                DynamicIslandBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
                      } else if isSneakPeekVisibleOnCurrentScreen && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && (coordinator.sneakPeek.type != .timer) && (coordinator.sneakPeek.type != .reminder) && !coordinator.sneakPeek.type.isExtensionPayload && ((coordinator.sneakPeek.type != .volume && coordinator.sneakPeek.type != .brightness && coordinator.sneakPeek.type != .backlight) || vm.notchState == .closed) {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(
                                  coordinator.sneakPeek.type == .capsLock
                                      ? AnyTransition.move(edge: .trailing).combined(with: .opacity)
                                      : AnyTransition.opacity
                              )
                      } else if vm.notchState == .closed && capsLockManager.isCapsLockActive && Defaults[.enableCapsLockIndicator] && !vm.hideOnClosed && !lockScreenManager.isLocked {
                          InlineHUD(type: .constant(.capsLock), value: .constant(1.0), icon: .constant(""), hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(AnyTransition.move(edge: .trailing).combined(with: .opacity))
                      } else if canShowMusicDuringExpansion && musicPairingEligible {
                          MusicLiveActivity(secondary: musicSecondary)
                              .id("closed-music-live-activity")
                              .transition(closedLiveActivitySwapTransition)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .timer) && vm.notchState == .closed && timerManager.isTimerActive && coordinator.timerLiveActivityEnabled && !vm.hideOnClosed {
                          TimerLiveActivity()
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .reminder) && vm.notchState == .closed && reminderManager.isActive && enableReminderLiveActivity && !vm.hideOnClosed {
                          ReminderLiveActivity()
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .recording) && vm.notchState == .closed && (recordingManager.isRecording || !recordingManager.isRecorderIdle) && Defaults[.enableScreenRecordingDetection] && !vm.hideOnClosed && !musicPairingEligible {
                          RecordingLiveActivity()
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .download) && vm.notchState == .closed && downloadManager.isDownloading && Defaults[.enableDownloadListener] && !vm.hideOnClosed {
                          DownloadLiveActivity()
                              .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && localSendLiveActivityActive && !vm.hideOnClosed {
                          LocalSendLiveActivity()
                              .transition(.blurReplace.animation(.interactiveSpring(dampingFraction: 1.2)))
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .doNotDisturb) && vm.notchState == .closed && Defaults[.enableDoNotDisturbDetection] && Defaults[.showDoNotDisturbIndicator] && (doNotDisturbManager.isDoNotDisturbActive || doNotDisturbManager.isFocusToastDismissing) && !vm.hideOnClosed && !lockScreenManager.isLocked {
                          DoNotDisturbLiveActivity()
                    } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .lockScreen) && vm.notchState == .closed && (lockScreenManager.isLocked || !lockScreenManager.isLockIdle) && Defaults[.enableLockScreenLiveActivity] && !vm.hideOnClosed {
                        LockScreenLiveActivity()
                            .id("lock-screen-live-activity")
                            .transition(closedLiveActivitySwapTransition)
                    } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .privacy) && vm.notchState == .closed && privacyManager.hasAnyIndicator && (Defaults[.enableCameraDetection] || Defaults[.enableMicrophoneDetection]) && !vm.hideOnClosed {
                        PrivacyLiveActivity()
                      } else if let extensionPayload = extensionStandalonePayload {
                          let layout = extensionStandaloneLayout(
                              for: extensionPayload,
                              notchHeight: vm.effectiveClosedNotchHeight,
                              isHovering: isHovering
                          )
                          ExtensionLiveActivityStandaloneView(
                              payload: extensionPayload,
                              layout: layout,
                              isHovering: isHovering
                          )
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          DynamicIslandFaceAnimation().animation(.interactiveSpring, value: musicManager.isPlayerIdle)
                      } else if vm.notchState == .open {
                          DynamicIslandHeader()
                              .frame(height: max(24, vm.effectiveClosedNotchHeight))
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }
                      
                      if isSneakPeekVisibleOnCurrentScreen {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && (coordinator.sneakPeek.type != .timer) && (coordinator.sneakPeek.type != .reminder) && (coordinator.sneakPeek.type != .capsLock) && !coordinator.sneakPeek.type.isExtensionPayload && !Defaults[.inlineHUD] && ((coordinator.sneakPeek.type != .volume && coordinator.sneakPeek.type != .brightness && coordinator.sneakPeek.type != .backlight) || vm.notchState == .closed) {
                              SystemEventIndicatorModifier(eventType: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, sendEventBack: { _ in
                                  //
                              })
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && activeSneakPeekStyle == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName), textColor: .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                          // Timer sneak peek
                          else if coordinator.sneakPeek.type == .timer {
                              if !vm.hideOnClosed && activeSneakPeekStyle == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "timer")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(timerManager.timerName + " - " + timerManager.formattedRemainingTime()), textColor: timerManager.timerColor, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(timerManager.timerColor)
                                  .padding(.bottom, 10)
                              }
                          }
                          else if coordinator.sneakPeek.type == .reminder {
                              if !vm.hideOnClosed && activeSneakPeekStyle == .standard, let reminder = reminderManager.activeReminder {
                                  GeometryReader { geo in
                                      let chipColor = Color(nsColor: reminder.event.calendar.color).ensureMinimumBrightness(factor: 0.7)
                                      HStack(spacing: 6) {
                                          RoundedRectangle(cornerRadius: 2)
                                              .fill(chipColor)
                                              .frame(width: 8, height: 12)
                                          MarqueeText(
                                              .constant(reminderSneakPeekText(for: reminder, now: reminderManager.currentDate)),
                                              textColor: reminderColor(for: reminder, now: reminderManager.currentDate),
                                              minDuration: 1,
                                              frameWidth: max(0, geo.size.width - 14)
                                          )
                                      }
                                  }
                                  .padding(.bottom, 10)
                              }
                          }
                          // Extension live activity sneak peek
                          else if case let .extensionLiveActivity(bundleID, activityID) = coordinator.sneakPeek.type {
                              if !vm.hideOnClosed && activeSneakPeekStyle == .standard {
                                  let payload = extensionLiveActivityManager.payload(bundleIdentifier: bundleID, activityID: activityID)
                                  let descriptor = payload?.descriptor
                                  let accent = (descriptor?.accentColor.swiftUIColor ?? coordinator.sneakPeek.accentColor ?? .gray)
                                      .ensureMinimumBrightness(factor: 0.7)
                                  GeometryReader { geo in
                                      HStack(spacing: 6) {
                                          RoundedRectangle(cornerRadius: 2)
                                              .fill(accent)
                                              .frame(width: 8, height: 12)
                                          MarqueeText(
                                              .constant(
                                                  extensionSneakPeekText(
                                                      preferredTitle: coordinator.sneakPeek.title,
                                                      preferredSubtitle: coordinator.sneakPeek.subtitle,
                                                      descriptor: descriptor
                                                  )
                                              ),
                                              textColor: accent,
                                              minDuration: 1,
                                              frameWidth: max(0, geo.size.width - 14)
                                          )
                                      }
                                  }
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier(shouldFixSizeForSneakPeek()) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
              
              ZStack {
                  if vm.notchState == .open {
                      Group {
                          switch coordinator.currentView {
                              case .home:
                                  NotchHomeView(albumArtNamespace: albumArtNamespace)
                              case .shelf:
                                  NotchShelfView()
                              case .timer:
                                  NotchTimerView()
                              case .stats:
                                  NotchStatsView()
                              case .colorPicker:
                                  NotchColorPickerView()
                            case .notes:
                                NotchNotesView()
                            case .clipboard:
                                NotchNotesView()
                            case .terminal:
                                NotchTerminalView()
                            case .extensionExperience:
                                if let payload = currentExtensionTabPayload() {
                                    ExtensionNotchExperienceTabView(payload: payload)
                                } else {
                                    NotchHomeView(albumArtNamespace: albumArtNamespace)
                                }
                          }
                      }
                      .id(coordinator.currentView)
                      .transition(tabSwitchTransition)
                  }
              }
              .zIndex(1)
              .allowsHitTesting(vm.notchState == .open)
              .blur(radius: abs(gestureProgress) > 0.3 ? min(abs(gestureProgress), 8) : 0)
              .opacity(abs(gestureProgress) > 0.3 ? min(abs(gestureProgress * 2), 0.8) : 1)
              .animation(.smooth(duration: 0.3), value: coordinator.currentView)
          }
      }

    private func reminderColor(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Color {
        if isReminderCritical(reminder, now: now) {
            return .red
        }
        return Color(nsColor: reminder.event.calendar.color).ensureMinimumBrightness(factor: 0.7)
    }

    private func reminderSneakPeekText(for entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let title = entry.event.title.isEmpty ? "Upcoming Reminder" : entry.event.title
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let window = TimeInterval(Defaults[.reminderSneakPeekDuration])

        if window > 0 && remaining <= window {
            return "\(title) • now"
        }

        let minutes = Int(ceil(remaining / 60))
        let timeString = reminderTimeFormatter.string(from: entry.event.start)

        if minutes <= 0 {
            return "\(title) • now • \(timeString)"
        } else if minutes == 1 {
            return "\(title) • in 1 min • \(timeString)"
        } else {
            return "\(title) • in \(minutes) min • \(timeString)"
        }
    }

    private func extensionSneakPeekText(preferredTitle: String, preferredSubtitle: String?, descriptor: AtollLiveActivityDescriptor?) -> String {
        let trimmedPreferredTitle = preferredTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let descriptorTitle = descriptor?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Extension"
        let title = trimmedPreferredTitle.isEmpty ? descriptorTitle : trimmedPreferredTitle

        let trimmedPreferredSubtitle = preferredSubtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let descriptorSubtitle = descriptor?.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let subtitle = !trimmedPreferredSubtitle.isEmpty ? trimmedPreferredSubtitle : descriptorSubtitle

        guard !subtitle.isEmpty else { return title }
        return "\(title) • \(subtitle)"
    }

    private let reminderTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    @ViewBuilder
    func DynamicIslandFaceAnimation() -> some View {
        let sideSize = max(0, vm.effectiveClosedNotchHeight - 12)
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(width: sideSize, height: sideSize)
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                IdleAnimationView()
                    .frame(width: sideSize, height: sideSize)
            }
        }.frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
    }

    @ViewBuilder
    private func MusicLiveActivity(secondary preResolvedSecondary: MusicSecondaryLiveActivity? = nil) -> some View {
        let secondary = preResolvedSecondary ?? resolveMusicSecondaryLiveActivity()
        let notchContentHeight = max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
        let wingBaseWidth = max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2)
        let rawCenterBaseWidth = vm.closedNotchSize.width + (isHovering ? 8 : 0)
        let centerBaseWidth = max(rawCenterBaseWidth, 96)
        let inlineSneakPeekActive = (
            coordinator.expandingView.show &&
            (coordinator.expandingView.type == .music || coordinator.expandingView.type == .timer) &&
            Defaults[.enableSneakPeek] &&
            Defaults[.sneakPeekStyles] == .inline
        )
        let rightWingWidth = resolvedRightWingWidth(
            for: secondary,
            baseWidth: wingBaseWidth,
            centerBaseWidth: centerBaseWidth,
            notchHeight: notchContentHeight
        )
        let effectiveCenterWidth = inlineSneakPeekActive ? 380 : centerBaseWidth
        let notchWidth = wingBaseWidth + effectiveCenterWidth + rightWingWidth
        let badgeBaseSize = max(13, notchContentHeight * 0.36)
        let badgeDisplaySize = badgeDisplaySize(for: secondary, baseSize: badgeBaseSize)
        let badgeOffset = badgeOverlayOffset(for: secondary, badgeSize: badgeDisplaySize)

        HStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .background(
                        Image(nsImage: musicManager.albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: musicManager.albumArt.size.width/musicManager.albumArt.size.height > 1.0 ? MusicPlayerImageSizes.cornerRadiusInset.closed/3.0 : MusicPlayerImageSizes.cornerRadiusInset.closed))
                    )
                    .clipped()
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .albumArtFlip(angle: musicManager.flipAngle)
                albumArtBadge(for: secondary, badgeSize: badgeDisplaySize)
                    .offset(x: badgeOffset.width, y: badgeOffset.height)
                    .id(secondary?.id ?? "music-badge")
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: wingBaseWidth, height: notchContentHeight)

            Rectangle()
                .fill(.black)
                .frame(width: effectiveCenterWidth, height: notchContentHeight)
                .overlay(
                    HStack(alignment: .top) {
                        if(coordinator.expandingView.show && coordinator.expandingView.type == .music) {
                            MusicTitleMarqueeView(
                                text: musicManager.songTitle,
                                isExplicit: musicManager.isCurrentTrackExplicit,
                                textColor: Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: max(0, (effectiveCenterWidth - vm.closedNotchSize.width) / 2 - 12),
                                badgeHeight: 13
                            )
                            .padding(.leading, 8)
                            .opacity((coordinator.expandingView.show && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                            Spacer(minLength: vm.closedNotchSize.width)
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor) : Color.gray)
                                .padding(.trailing, 8)
                                .opacity((coordinator.expandingView.show && coordinator.expandingView.type == .music && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                        } else if(coordinator.expandingView.show && coordinator.expandingView.type == .timer) {
                            MarqueeText(
                                .constant(timerManager.timerName),
                                textColor: timerManager.timerColor,
                                minDuration: 0.4,
                                frameWidth: max(0, (effectiveCenterWidth - vm.closedNotchSize.width) / 2 - 12)
                            )
                            .padding(.leading, 8)
                            .opacity((coordinator.expandingView.show && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                            Spacer(minLength: vm.closedNotchSize.width)
                            Text(timerManager.formattedRemainingTime())
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(timerManager.timerColor)
                                .padding(.trailing, 8)
                                .opacity((coordinator.expandingView.show && coordinator.expandingView.type == .timer && Defaults[.enableSneakPeek] && Defaults[.sneakPeekStyles] == .inline) ? 1 : 0)
                        }
                    }
                    .clipped()
                )

            musicRightWing(for: secondary, notchHeight: notchContentHeight, trailingWidth: rightWingWidth)
                .frame(width: rightWingWidth, height: notchContentHeight, alignment: .center)
                .contentShape(Rectangle())
                .onHover { hovering in
                    guard shouldShowClosedMusicWaveformPlayPauseOverlay(for: secondary) else {
                        if isHoveringClosedMusicWaveformControl {
                            isHoveringClosedMusicWaveformControl = false
                        }
                        return
                    }
                    withAnimation(.smooth(duration: 0.16)) {
                        isHoveringClosedMusicWaveformControl = hovering
                    }
                }
                .id(secondary?.id ?? "music-spectrum")
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: notchWidth, height: notchContentHeight)
        .frame(height: vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0), alignment: .center)
        .animation(.smooth(duration: 0.25), value: secondary?.id)
    }

    private func resolveMusicSecondaryLiveActivity(isMusicPairingEligible: Bool = true) -> MusicSecondaryLiveActivity? {
        if coordinator.timerLiveActivityEnabled && timerManager.isTimerActive {
            return .timer
        }

        if enableReminderLiveActivity, reminderManager.isActive, let reminder = reminderManager.activeReminder {
            return .reminder(reminder)
        }

        if enableScreenRecordingDetection && (recordingManager.isRecording || !recordingManager.isRecorderIdle) {
            return .recording
        }

        if enableDoNotDisturbDetection && showDoNotDisturbIndicator && doNotDisturbManager.isDoNotDisturbActive {
            let mode = FocusModeType.resolve(identifier: doNotDisturbManager.currentFocusModeIdentifier, name: doNotDisturbManager.currentFocusModeName)
            return .focus(mode)
        }

        if enableCapsLockIndicator && capsLockManager.isCapsLockActive {
            return .capsLock(showLabel: showCapsLockLabel)
        }

        if isMusicPairingEligible, let extensionPayload = resolvedExtensionMusicPayload() {
            return .extensionPayload(extensionPayload)
        }

        return nil
    }

    private func resolvedRightWingWidth(for secondary: MusicSecondaryLiveActivity?, baseWidth: CGFloat, centerBaseWidth: CGFloat, notchHeight: CGFloat) -> CGFloat {
        guard let secondary else { return baseWidth }

        switch secondary {
        case .timer:
            return timerRightWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth)
        case .reminder(let entry):
            return reminderRightWingWidth(for: entry, baseWidth: baseWidth, notchHeight: notchHeight, now: reminderManager.currentDate)
        case .capsLock(let showLabel):
            return showLabel ? scaledWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth, factor: 0.4, extra: 12) : baseWidth
        case .focus:
            return focusRightWingWidth(baseWidth: baseWidth)
        case .recording:
            return recordingRightWingWidth(baseWidth: baseWidth)
        case .extensionPayload(let payload):
            let maxWidth = baseWidth + centerBaseWidth * 0.6
            return ExtensionLayoutMetrics.trailingWidth(for: payload, baseWidth: baseWidth, maxWidth: maxWidth)
        }
    }

    private func timerRightWingWidth(baseWidth: CGFloat, centerBaseWidth: CGFloat) -> CGFloat {
        if timerShowsCountdown {
            return timerCountdownWingWidth(baseWidth: baseWidth)
        }

        let showsProgress = timerShowsProgress
        let usesRingProgress = timerProgressStyle == .ring

        switch (showsProgress, usesRingProgress) {
        case (true, true):
            return scaledWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth, factor: 0.46, extra: 18)
        case (true, false):
            return scaledWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth, factor: 0.52, extra: 24)
        case (false, _):
            return scaledWingWidth(baseWidth: baseWidth, centerBaseWidth: centerBaseWidth, factor: 0.38, extra: 12)
        }
    }

    private func timerCountdownWingWidth(baseWidth: CGFloat) -> CGFloat {
        let padding: CGFloat = 18
        let ringWidth: CGFloat = (timerShowsProgress && timerProgressStyle == .ring) ? 30 : 0
        let spacing: CGFloat = (ringWidth > 0) ? 8 : 0
        let countdownText = timerManager.formattedRemainingTime()
        let countdownWidth = TimerSupplementMetrics.countdownFrameWidth(for: countdownText)
        return max(baseWidth, padding + ringWidth + spacing + countdownWidth)
    }

    private func reminderRightWingWidth(for entry: ReminderLiveActivityManager.ReminderEntry, baseWidth: CGFloat, notchHeight: CGFloat, now: Date) -> CGFloat {
        let padding: CGFloat = 16
        switch reminderPresentationStyle {
        case .ringCountdown:
            let diameter = ReminderSupplementMetrics.ringDiameter(for: notchHeight)
            return max(baseWidth, padding + diameter)
        case .digital:
            let countdownText = ReminderSupplementMetrics.digitalCountdownText(for: entry, now: now)
            let width = ReminderSupplementMetrics.digitalFrameWidth(for: countdownText)
            return max(baseWidth, padding + width)
        case .minutes:
            let minutesText = ReminderSupplementMetrics.minutesCountdownText(for: entry, now: now)
            let width = ReminderSupplementMetrics.minutesFrameWidth(for: minutesText)
            return max(baseWidth, padding + width)
        }
    }

    private func focusRightWingWidth(baseWidth: CGFloat) -> CGFloat {
        // Focus pairings now mirror the default music spectrum width to keep the notch compact.
        return baseWidth
    }

    private func recordingRightWingWidth(baseWidth: CGFloat) -> CGFloat {
        // Keep recording pairings compact by reducing the width relative to the notch height.
        let absoluteMin: CGFloat = 38
        let preferredWidth = max(baseWidth * 0.6, 0)
        let maxWidth = min(baseWidth - 6, 52)
        let clampedPreferred = min(preferredWidth, maxWidth)
        return min(baseWidth, max(absoluteMin, clampedPreferred))
    }

    private func scaledWingWidth(baseWidth: CGFloat, centerBaseWidth: CGFloat, factor: CGFloat, extra: CGFloat) -> CGFloat {
        max(baseWidth, max(centerBaseWidth * factor, baseWidth + extra))
    }

    @ViewBuilder
    private func albumArtBadge(for secondary: MusicSecondaryLiveActivity?, badgeSize: CGFloat) -> some View {
        if let secondary, badgeSize > 0 {
            ZStack {
                Circle()
                    .fill(Color.black)

                switch secondary {
                case .timer:
                    Image(systemName: "timer")
                        .font(.system(size: badgeSize * 0.55, weight: .semibold))
                        .foregroundStyle(timerAccentColor)
                case .reminder(let entry):
                    let accent = reminderColor(for: entry, now: reminderManager.currentDate)
                    Image(systemName: "clock")
                        .font(.system(size: badgeSize * 0.55, weight: .semibold))
                        .foregroundStyle(accent)
                case .focus(let mode):
                    mode.resolvedActiveIcon(usePrivateSymbol: true)
                        .renderingMode(.template)
                        .font(.system(size: badgeSize * 0.5, weight: .semibold))
                        .foregroundStyle(mode.accentColor)
                case .recording:
                    Circle()
                        .fill(Color.red)
                        .frame(width: badgeSize * 0.45, height: badgeSize * 0.45)
                        .modifier(PulsingModifier())
                case .capsLock:
                    Image(systemName: "capslock.fill")
                        .font(.system(size: badgeSize * 0.5, weight: .semibold))
                        .foregroundStyle(capsLockTintMode.color)
                case .extensionPayload(let payload):
                    ExtensionBadgeIconView(
                        descriptor: payload.descriptor.leadingIcon,
                        accent: payload.descriptor.accentColor.swiftUIColor,
                        size: badgeSize
                    )
                }
            }
            .frame(width: badgeSize, height: badgeSize)
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            .transition(.opacity.combined(with: .scale))
        } else {
            EmptyView()
        }
    }

    private func badgeDisplaySize(for secondary: MusicSecondaryLiveActivity?, baseSize: CGFloat) -> CGFloat {
        guard let secondary else { return baseSize }
        switch secondary {
        default:
            return baseSize
        }
    }

    private func badgeOverlayOffset(for secondary: MusicSecondaryLiveActivity?, badgeSize: CGFloat) -> CGSize {
        guard let secondary else { return CGSize(width: badgeSize * 0.2, height: badgeSize * 0.25) }
        switch secondary {
        default:
            return CGSize(width: badgeSize * 0.2, height: badgeSize * 0.25)
        }
    }

    @ViewBuilder
    private func musicRightWing(for secondary: MusicSecondaryLiveActivity?, notchHeight: CGFloat, trailingWidth: CGFloat) -> some View {
        switch secondary {
        case .timer:
            MusicTimerSupplementView(
                timerManager: timerManager,
                accentColor: timerAccentColor,
                showsCountdown: timerShowsCountdown,
                showsProgress: timerShowsProgress,
                progressStyle: timerProgressStyle,
                notchHeight: notchHeight
            )
        case .reminder(let entry):
            MusicReminderSupplementView(
                entry: entry,
                now: reminderManager.currentDate,
                style: reminderPresentationStyle,
                accent: reminderColor(for: entry, now: reminderManager.currentDate),
                notchHeight: notchHeight
            )
        case .capsLock(let showLabel):
            if showLabel {
                MusicCapsLockLabelView(color: capsLockTintMode.color)
            } else {
                spectrumView(forceSpectrum: true)
            }
        case .focus:
            spectrumView(forceSpectrum: true)
        case .recording:
            spectrumView(forceSpectrum: true, trailingInset: 6)
        case .extensionPayload(let payload):
            ExtensionMusicWingView(payload: payload, notchHeight: notchHeight, trailingWidth: trailingWidth)
        case .none:
            spectrumView(
                forceSpectrum: false,
                enableClosedPlayPauseOverlay: shouldShowClosedMusicWaveformPlayPauseOverlay(for: secondary)
            )
        }
    }

    @ViewBuilder
    private func spectrumView(
        forceSpectrum: Bool,
        trailingInset: CGFloat = 0,
        enableClosedPlayPauseOverlay: Bool = false
    ) -> some View {
        if useMusicVisualizer || forceSpectrum {
            Rectangle()
                .fill(Defaults[.coloredSpectrogram] ? Color(nsColor: musicManager.avgColor).gradient : Color.gray.gradient)
                .frame(width: 50, alignment: .center)
                .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                .mask {
                    AudioVisualizerView(isPlaying: $musicManager.isPlaying)
                        .frame(width: 16, height: 12)
                }
                .blur(radius: (enableClosedPlayPauseOverlay && isHoveringClosedMusicWaveformControl) ? 2.4 : 0)
                .overlay {
                    if enableClosedPlayPauseOverlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(isHoveringClosedMusicWaveformControl ? 0.24 : 0.02))

                            Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(isHoveringClosedMusicWaveformControl ? 0.98 : 0.0))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.trailing, trailingInset)
                .animation(.smooth(duration: 0.16), value: isHoveringClosedMusicWaveformControl)
                .animation(.smooth(duration: 0.2), value: musicManager.isPlaying)
        } else {
            LottieAnimationView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var timerAccentColor: Color {
        switch timerIconColorMode {
        case .adaptive:
            if let presetId = timerManager.activePresetId,
               let preset = timerPresets.first(where: { $0.id == presetId }) {
                return preset.color
            }
            return timerManager.timerColor
        case .solid:
            return timerSolidColor
        }
    }

    private func reminderIconName(for reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        isReminderCritical(reminder, now: now) ? ReminderLiveActivityManager.criticalIconName : ReminderLiveActivityManager.standardIconName
    }

    private func isReminderCritical(_ reminder: ReminderLiveActivityManager.ReminderEntry, now: Date) -> Bool {
        let window = TimeInterval(Defaults[.reminderSneakPeekDuration])
        guard window > 0 else { return false }
        let remaining = reminder.event.start.timeIntervalSince(now)
        return remaining > 0 && remaining <= window
    }

    private func extensionSecondaryPayloadID(for secondary: MusicSecondaryLiveActivity?) -> String? {
        guard case let .extensionPayload(payload) = secondary else { return nil }
        return payload.id
    }

    private func resolvedExtensionMusicPayload() -> ExtensionLiveActivityPayload? {
        let candidates = extensionLiveActivityManager.sortedActivities(for: true)
        guard let payload = candidates.first else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "no eligible coexistence payloads",
                pendingCount: candidates.count
            )
            ExtensionRoutingDiagnostics.shared.reset(.music)
            return nil
        }

        guard enableExtensionLiveActivities else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "feature toggle disabled",
                pendingCount: candidates.count
            )
            return nil
        }

        guard closedMusicContentEnabled else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "music content disabled",
                pendingCount: candidates.count
            )
            return nil
        }

        guard vm.notchState == .closed else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "notch is \(vm.notchState)",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !vm.hideOnClosed else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "hideOnClosed engaged (fullscreen)",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !lockScreenManager.isLocked else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "lock screen currently active",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !isMusicHUDDeferredAfterUnlock else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "waiting for lock screen unlock animation to finish",
                pendingCount: candidates.count
            )
            return nil
        }

        guard coordinator.musicLiveActivityEnabled else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .music,
                reason: "music live activity disabled in settings",
                pendingCount: candidates.count
            )
            return nil
        }

        ExtensionRoutingDiagnostics.shared.logDisplay(.music, payload: payload)
        return payload
    }

    private func resolvedExtensionStandalonePayload(excluding musicPayloadID: String?) -> ExtensionLiveActivityPayload? {
        let baseCandidates = extensionLiveActivityManager.sortedActivities()
        guard !baseCandidates.isEmpty else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "no active extension payloads",
                pendingCount: 0
            )
            ExtensionRoutingDiagnostics.shared.reset(.standalone)
            return nil
        }

        let candidates = baseCandidates.filter { $0.id != musicPayloadID }
        guard let payload = candidates.first else {
            if let musicPayloadID {
                ExtensionRoutingDiagnostics.shared.logSuppression(
                    .standalone,
                    reason: "all pending payloads are paired with music (\(musicPayloadID))",
                    pendingCount: baseCandidates.count
                )
            } else {
                ExtensionRoutingDiagnostics.shared.logSuppression(
                    .standalone,
                    reason: "no standalone payloads after filtering",
                    pendingCount: baseCandidates.count
                )
                ExtensionRoutingDiagnostics.shared.reset(.standalone)
            }
            return nil
        }

        guard enableExtensionLiveActivities else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "feature toggle disabled",
                pendingCount: candidates.count
            )
            return nil
        }

        guard vm.notchState == .closed else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "notch is \(vm.notchState)",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !vm.hideOnClosed else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "hideOnClosed engaged (fullscreen)",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !lockScreenManager.isLocked else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "lock screen currently active",
                pendingCount: candidates.count
            )
            return nil
        }

        guard vm.effectiveClosedNotchHeight > 0 else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "effective notch height is \(vm.effectiveClosedNotchHeight)",
                pendingCount: candidates.count
            )
            return nil
        }

        guard !coordinator.expandingView.show else {
            ExtensionRoutingDiagnostics.shared.logSuppression(
                .standalone,
                reason: "expanding view \(coordinator.expandingView.type) visible",
                pendingCount: candidates.count
            )
            return nil
        }

        ExtensionRoutingDiagnostics.shared.logDisplay(.standalone, payload: payload)
        return payload
    }

    private func extensionStandaloneLayout(for payload: ExtensionLiveActivityPayload, notchHeight: CGFloat, isHovering: Bool) -> ExtensionStandaloneLayout {
        let outerHeight = notchHeight
        let contentHeight = max(0, notchHeight - (isHovering ? 0 : 12))
        let leadingWidth = max(contentHeight, 44)
        let centerWidth: CGFloat = max(vm.closedNotchSize.width + (isHovering ? 8 : 0), 96)
        let trailingWidth = ExtensionLayoutMetrics.trailingWidth(
            for: payload,
            baseWidth: leadingWidth,
            maxWidth: leadingWidth + centerWidth * 0.6
        )
        let totalWidth = leadingWidth + centerWidth + trailingWidth
        return ExtensionStandaloneLayout(
            totalWidth: totalWidth,
            outerHeight: outerHeight,
            contentHeight: contentHeight,
            leadingWidth: leadingWidth,
            centerWidth: centerWidth,
            trailingWidth: trailingWidth
        )
    }

    @MainActor
    private final class ExtensionRoutingDiagnostics {
        static let shared = ExtensionRoutingDiagnostics()

        enum Channel: Hashable {
            case music
            case standalone

            var label: String {
                switch self {
                case .music:
                    return "music pairing"
                case .standalone:
                    return "standalone notch"
                }
            }
        }

        private var lastMessages: [Channel: String] = [:]

        func logSuppression(_ channel: Channel, reason: String, pendingCount: Int) {
            log("Extension \(channel.label) suppressed: \(reason) (pending: \(pendingCount))", channel: channel)
        }

        func logDisplay(_ channel: Channel, payload: ExtensionLiveActivityPayload) {
            log("Extension \(channel.label) showing \(payload.descriptor.id) from \(payload.bundleIdentifier)", channel: channel)
        }

        func reset(_ channel: Channel) {
            lastMessages.removeValue(forKey: channel)
        }

        private func log(_ message: String, channel: Channel) {
            guard Defaults[.extensionDiagnosticsLoggingEnabled] else { return }
            guard lastMessages[channel] != message else { return }
            lastMessages[channel] = message
            Logger.log(message, category: .extensions)
        }
    }
    
    @ViewBuilder
    var dragDetector: some View {
        if lockScreenManager.isLocked {
            EmptyView()
        } else if Defaults[.dynamicShelf] && !Defaults[.enableMinimalisticUI] {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.data], isTargeted: $vm.dragDetectorTargeting) { _ in true }
                .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
                    if isTargeted, vm.notchState == .closed {
                        coordinator.currentView = .shelf
                        openNotch()
                    } else if !isTargeted {
                        if vm.dropEvent {
                            vm.dropEvent = false
                            return
                        }

                        vm.dropEvent = false
                        if !shouldPreventAutoClose() {
                            vm.close()
                        }
                    }
                }
        } else {
            EmptyView()
        }
    }

    // MARK: - Private Methods
    private func openNotch() {
        withAnimation(.bouncy.speed(1.2)) {
            vm.open()
        }
    }

    private func shouldShowClosedMusicWaveformPlayPauseOverlay(for secondary: MusicSecondaryLiveActivity?) -> Bool {
        guard secondary == nil else { return false }
        return isClosedMusicGestureContext && !Defaults[.openNotchOnHover]
    }

    private var isClosedMusicGestureContext: Bool {
        vm.notchState == .closed
            && coordinator.musicLiveActivityEnabled
            && closedMusicContentEnabled
            && !vm.hideOnClosed
            && !lockScreenManager.isLocked
            && !isMusicHUDDeferredAfterUnlock
            && !coordinator.expandingView.show
            && (!musicManager.isPlayerIdle || musicManager.bundleIdentifier != nil)
            && !coordinator.firstLaunch
    }

    private func handleClosedMusicWaveformTapIfNeeded() -> Bool {
        guard shouldShowClosedMusicWaveformPlayPauseOverlay(for: nil),
              isHoveringClosedMusicWaveformControl else {
            return false
        }

        if Defaults[.enableHaptics] {
            triggerHapticIfAllowed()
        }
        musicManager.playPause()
        return true
    }

    private func hiddenHoverActivationContainsMouse(_ location: NSPoint = NSEvent.mouseLocation) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.localizedName == currentScreenName }) else {
            return false
        }

        let horizontalPadding: CGFloat = 8
        let activationWidth = vm.closedNotchSize.width + horizontalPadding * 2
        let activationHeight = max(vm.closedNotchSize.height + zeroHeightHoverPadding, 14)

        let activationRect = CGRect(
            x: screen.frame.midX - activationWidth / 2,
            y: screen.frame.maxY - activationHeight,
            width: activationWidth,
            height: activationHeight
        )

        return activationRect.contains(location)
    }

    private func startHiddenEdgeHoverPolling() {
        guard hiddenEdgeHoverPollingTask == nil else { return }

        hiddenEdgeHoverPollingTask = Task { @MainActor in
            while !Task.isCancelled {
                if self.shouldUseHiddenEdgeHoverPolling {
                    let hovering = self.hiddenHoverActivationContainsMouse()
                    if hovering != self.isHovering {
                        self.handleHover(hovering)
                    }
                }

                try? await Task.sleep(for: .milliseconds(50))
            }

            self.hiddenEdgeHoverPollingTask = nil
        }
    }

    private func stopHiddenEdgeHoverPolling() {
        hiddenEdgeHoverPollingTask?.cancel()
        hiddenEdgeHoverPollingTask = nil
    }

    private func startHoverClickMonitor() {
        guard Defaults[.openNotchOnHover] else { return }
        guard hoverClickMonitor == nil else { return }

        let handleClick: @Sendable () -> Void = { [weak vm, weak lockScreenManager] in
            Task { @MainActor in
                guard let vm, let lockScreenManager else { return }
                guard !lockScreenManager.isLocked else { return }
                guard vm.notchState == .closed else { return }
                guard !self.coordinator.isHoverOpenSuppressed else { return }
                guard self.isHovering else { return }
                guard !self.handleClosedMusicWaveformTapIfNeeded() else { return }
                if Defaults[.enableHaptics] {
                    self.triggerHapticIfAllowed()
                }
                self.openNotch()
            }
        }

        // Global monitor catches clicks outside the app window (e.g. when
        // the cursor is at the very top screen edge and the click goes to
        // the system rather than our panel).
        hoverClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { _ in
            handleClick()
        }

        // Local monitor catches clicks that DO hit our window — at the
        // screen edge SwiftUI's .onTapGesture may not fire reliably, but
        // the NSEvent local monitor will.
        hoverClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
            handleClick()
            return event
        }
    }

    private func stopHoverClickMonitor() {
        if let hoverClickMonitor {
            NSEvent.removeMonitor(hoverClickMonitor)
            self.hoverClickMonitor = nil
        }
        if let hoverClickLocalMonitor {
            NSEvent.removeMonitor(hoverClickLocalMonitor)
            self.hoverClickLocalMonitor = nil
        }
    }

    /// Installs the global outside-click monitor when Terminal + sticky mode are active (e.g. keyboard-opened terminal).
    /// Removes the monitor when the tab, sticky setting, or open state no longer applies.
    private func syncStickyTerminalOutsideClickMonitor() {
        guard vm.notchState == .open, terminalStickyMode, coordinator.currentView == .terminal else {
            removeStickyTerminalClickMonitor()
            return
        }
        installStickyTerminalClickMonitor()
    }

    private func installStickyTerminalClickMonitor() {
        guard stickyTerminalClickMonitor == nil else { return }
        stickyTerminalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak vm] _ in
            Task { @MainActor in
                guard let vm, vm.notchState == .open else { return }
                let clickLocation = NSEvent.mouseLocation
                if self.isPointInsideNotchWindow(clickLocation) {
                    return
                }
                vm.close()
            }
        }
    }

    private func removeStickyTerminalClickMonitor() {
        if let stickyTerminalClickMonitor {
            NSEvent.removeMonitor(stickyTerminalClickMonitor)
            self.stickyTerminalClickMonitor = nil
        }
    }

    // MARK: - Hover Management
    
    /// Handle hover state changes with debouncing
    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()

        if hovering {
            startHoverClickMonitor()
            removeStickyTerminalClickMonitor()
        } else {
            stopHoverClickMonitor()
            if isHoveringClosedMusicWaveformControl {
                withAnimation(.smooth(duration: 0.16)) {
                    isHoveringClosedMusicWaveformControl = false
                }
            }
        }

        if hovering {
            withAnimation(.bouncy.speed(1.2)) {
                isHovering = true
            }

            if vm.notchState == .closed && Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }

            let shouldFocusTimerTab = enableTimerFeature && timerDisplayMode == .tab && timerManager.isTimerActive && !enableMinimalisticUI

            guard vm.notchState == .closed,
                !isSneakPeekVisibleOnCurrentScreen,
                (Defaults[.openNotchOnHover] || shouldFocusTimerTab) else { return }

            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.isSneakPeekVisibleOnCurrentScreen,
                          !self.coordinator.isHoverOpenSuppressed else { return }

                    if shouldFocusTimerTab {
                        withAnimation(.smooth) {
                            self.coordinator.currentView = .timer
                        }
                    }
                    self.openNotch()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    withAnimation(.bouncy.speed(1.2)) {
                        self.isHovering = false
                    }

                    if self.vm.notchState == .open && !self.shouldPreventAutoClose() {
                        self.vm.close()
                    } else if self.vm.notchState == .open
                                && Defaults[.terminalStickyMode]
                                && self.coordinator.currentView == .terminal {
                        // Re-sync monitor state through one code path to avoid
                        // monitor lifecycle races between hover and state updates.
                        self.syncStickyTerminalOutsideClickMonitor()
                    }
                }
            }
        }
    }

    private func isPointInsideNotchWindow(_ point: CGPoint) -> Bool {
        if let appDelegate = AppDelegate.shared {
            if Defaults[.showOnAllDisplays] {
                return appDelegate.windows.values.contains(where: { $0.frame.contains(point) })
            }
            if let window = appDelegate.window {
                return window.frame.contains(point)
            }
        }

        return NSApp.windows.contains(where: { $0.frame.contains(point) })
    }
    
    // Helper function to check if any popovers are active
    private func hasAnyActivePopovers() -> Bool {
     return vm.isBatteryPopoverActive || 
         vm.isClipboardPopoverActive || 
         vm.isColorPickerPopoverActive || 
         vm.isStatsPopoverActive ||
         vm.isTimerPopoverActive ||
         vm.isMediaOutputPopoverActive ||
         vm.isReminderPopoverActive
    }

    private func shouldPreventAutoClose() -> Bool {
        coordinator.firstLaunch || hasAnyActivePopovers() || vm.isAutoCloseSuppressed || SharingStateManager.shared.preventNotchClose || (Defaults[.terminalStickyMode] && coordinator.currentView == .terminal)
    }
    
    // Helper to prevent rapid haptic feedback
    private func triggerHapticIfAllowed() {
        let now = Date()
        if now.timeIntervalSince(lastHapticTime) > 0.3 { // Minimum 300ms between haptics
            haptics.toggle()
            lastHapticTime = now
        }
    }
    
    // Helper to check if stats tab has 4+ graphs (needs expanded height)
    private func enabledStatsGraphCount() -> Int {
        var enabledCount = 0
        if showCpuGraph { enabledCount += 1 }
        if showMemoryGraph { enabledCount += 1 }
        if showGpuGraph { enabledCount += 1 }
        if showNetworkGraph { enabledCount += 1 }
        if showDiskGraph { enabledCount += 1 }
        return enabledCount
    }

    private func statsRowCount() -> Int {
        let count = enabledStatsGraphCount()
        if count == 0 { return 0 }
        return count <= 3 ? 1 : 2
    }

    private func currentExtensionTabPayload() -> ExtensionNotchExperiencePayload? {
        guard Defaults[.enableThirdPartyExtensions],
              Defaults[.enableExtensionNotchExperiences],
              Defaults[.enableExtensionNotchTabs] else {
            return nil
        }
        if let selectedID = coordinator.selectedExtensionExperienceID,
           let payload = extensionNotchExperienceManager.payload(experienceID: selectedID) {
            return payload
        }
        return extensionNotchExperienceManager.highestPriorityTabPayload()
    }

    private func extensionTabPreferredHeight(baseSize: CGSize) -> CGFloat? {
        guard let preferred = currentExtensionTabPayload()?.descriptor.tab?.preferredHeight else {
            return nil
        }
        let minHeight = baseSize.height
        let maxHeight = baseSize.height + statsAdditionalRowHeight
        return min(max(preferred, minHeight), maxHeight)
    }

    // Estimate the height required for minimalistic overrides (notably web content) and clamp it to the notch bounds.
    private func extensionMinimalisticPreferredHeight(baseSize: CGSize) -> CGFloat? {
        guard let configuration = extensionNotchExperienceManager.minimalisticReplacementPayload()?.descriptor.minimalistic else {
            return nil
        }

        let minHeight = baseSize.height
        let maxHeight = baseSize.height + statsAdditionalRowHeight

        var contentHeight: CGFloat = 0
        var blockCount = 0

        if configuration.headline != nil {
            contentHeight += 24
            blockCount += 1
        }

        if configuration.subtitle != nil {
            contentHeight += 20
            blockCount += 1
        }

        if !configuration.sections.isEmpty {
            let sectionEstimate: CGFloat = 98
            contentHeight += CGFloat(configuration.sections.count) * sectionEstimate
            blockCount += configuration.sections.count
        }

        if let webDescriptor = configuration.webContent {
            contentHeight += webDescriptor.preferredHeight
            blockCount += 1
        }

        guard blockCount > 0 else { return nil }

        let spacingAllowance = CGFloat(max(blockCount - 1, 0)) * 16
        let topPadding: CGFloat = 10
        let bottomPadding: CGFloat = configuration.webContent == nil ? 10 : 0
        let estimatedHeight = contentHeight + spacingAllowance + topPadding + bottomPadding

        let clampedHeight = min(max(estimatedHeight, minHeight), maxHeight)
        return clampedHeight > minHeight ? clampedHeight : nil
    }
    
    // MARK: - Gesture Handling
    
    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleScrollGesture(isDownward: true, translation: translation, phase: phase)
    }
    
    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        handleScrollGesture(isDownward: false, translation: translation, phase: phase)
    }

    private func handleScrollGesture(isDownward: Bool, translation: CGFloat, phase: NSEvent.Phase) {
        let reverse = Defaults[.reverseScrollGestures]
        let shouldOpen = isDownward ? !reverse : reverse

        if shouldOpen {
            handleOpenScrollGesture(translation: translation, phase: phase)
        } else {
            guard Defaults[.closeGestureEnabled] else { return }
            handleCloseScrollGesture(translation: translation, phase: phase)
        }
    }

    private func handleOpenScrollGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        withAnimation(.smooth) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if phase == .ended {
            withAnimation(.smooth) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }
            withAnimation(.smooth) {
                gestureProgress = .zero
            }
            openNotch()
        }
    }

    private func handleCloseScrollGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open, !vm.isHoveringCalendar, !vm.isScrollGestureActive else { return }

        withAnimation(.smooth) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(.smooth) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(.smooth) {
                gestureProgress = .zero
                isHovering = false
            }
            vm.close()

            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }
        }
    }

    private func handleSkipGesture(direction: MusicManager.SkipDirection, translation: CGFloat, phase: NSEvent.Phase) {
        if phase == .ended {
            skipGestureActiveDirection = nil
            return
        }

        guard canPerformSkipGesture() else {
            skipGestureActiveDirection = nil
            return
        }

        if skipGestureActiveDirection == nil && translation > Defaults[.gestureSensitivity] {
            let effectiveDirection: MusicManager.SkipDirection
            if Defaults[.reverseSwipeGestures] {
                effectiveDirection = direction == .forward ? .backward : .forward
            } else {
                effectiveDirection = direction
            }
            skipGestureActiveDirection = effectiveDirection

            if Defaults[.enableHaptics] {
                triggerHapticIfAllowed()
            }

            musicManager.handleSkipGesture(direction: effectiveDirection)
        }
    }

    private func canPerformSkipGesture() -> Bool {
        let canSkipInOpenHome = vm.notchState == .open && coordinator.currentView == .home
        let canSkipInClosedMusic = !Defaults[.openNotchOnHover] && isClosedMusicGestureContext

        return enableHorizontalMusicGestures
            && (canSkipInOpenHome || canSkipInClosedMusic)
            && (!musicManager.isPlayerIdle || musicManager.bundleIdentifier != nil)
            && !lockScreenManager.isLocked
            && !hasAnyActivePopovers()
            && !vm.isHoveringCalendar
            && !vm.isScrollGestureActive
    }

    private func handleMusicControlPlaybackChange(isPlaying: Bool) {
        guard musicControlWindowEnabled else { return }

        if isPlaying {
            clearMusicControlVisibilityDeadline()
            requestMusicControlWindowSyncIfHidden()
        } else {
            extendMusicControlVisibilityAfterPause()
        }
    }

    private func handleMusicControlIdleChange(isIdle: Bool) {
        guard musicControlWindowEnabled else { return }

        if isIdle {
            if musicControlVisibilityDeadline == nil {
                extendMusicControlVisibilityAfterPause()
            }
        } else if musicManager.isPlaying {
            clearMusicControlVisibilityDeadline()
        }
    }

    private func handleStandardMediaControlsAvailabilityChange() {
        guard musicControlWindowEnabled else {
            hideMusicControlWindow()
            return
        }

        if standardMediaControlsActive {
            if musicManager.isPlaying || !musicManager.isPlayerIdle {
                clearMusicControlVisibilityDeadline()
            }
            enqueueMusicControlWindowSync(forceRefresh: true)
        } else {
            cancelMusicControlWindowSync()
            hideMusicControlWindow()
            clearMusicControlVisibilityDeadline()
            hasPendingMusicControlSync = false
            pendingMusicControlForceRefresh = false
        }
    }

    private func extendMusicControlVisibilityAfterPause() {
        let deadline = Date().addingTimeInterval(musicControlPauseGrace)
        musicControlVisibilityDeadline = deadline
        scheduleMusicControlVisibilityCheck(deadline: deadline)
        requestMusicControlWindowSyncIfHidden()
    }

    private func clearMusicControlVisibilityDeadline() {
        musicControlVisibilityDeadline = nil
        cancelMusicControlVisibilityTimer()
    }

    private func scheduleMusicControlVisibilityCheck(deadline: Date) {
        cancelMusicControlVisibilityTimer()

        let interval = max(0, deadline.timeIntervalSinceNow)

        musicControlHideTask = Task.detached(priority: .background) { [interval] in
            if interval > 0 {
                let nanoseconds = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if let currentDeadline = musicControlVisibilityDeadline, currentDeadline <= Date() {
                    musicControlVisibilityDeadline = nil
                }

                enqueueMusicControlWindowSync(forceRefresh: false)

                musicControlHideTask = nil
            }
        }
    }

    private func cancelMusicControlVisibilityTimer() {
        musicControlHideTask?.cancel()
        musicControlHideTask = nil
    }

    private func musicControlVisibilityIsActive() -> Bool {
        if musicManager.isPlaying {
            return true
        }

        guard let deadline = musicControlVisibilityDeadline else { return false }
        return Date() <= deadline
    }

    private func suppressMusicControlWindowUpdates() {
        isMusicControlWindowSuppressed = true
        musicControlSuppressionTask?.cancel()
        musicControlSuppressionTask = nil
    }

    private func releaseMusicControlWindowUpdates(after delay: TimeInterval) {
        musicControlSuppressionTask?.cancel()
        musicControlSuppressionTask = Task { [delay] in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if vm.notchState == .closed && !lockScreenManager.isLocked && !isMusicHUDDeferredAfterUnlock {
                    isMusicControlWindowSuppressed = false
                    triggerPendingMusicControlSyncIfNeeded()
                } else {
                    isMusicControlWindowSuppressed = true
                }
                musicControlSuppressionTask = nil
            }
        }
    }

    private func triggerPendingMusicControlSyncIfNeeded() {
        guard hasPendingMusicControlSync else { return }

        let shouldForce = pendingMusicControlForceRefresh
        hasPendingMusicControlSync = false
        pendingMusicControlForceRefresh = false

        logMusicControlEvent("Flushing pending floating window sync (force: \(shouldForce))")
        scheduleMusicControlWindowSync(forceRefresh: shouldForce, bypassSuppression: true)
    }

    private func shouldDeferMusicControlSync() -> Bool {
        vm.notchState != .closed
            || lockScreenManager.isLocked
            || isMusicHUDDeferredAfterUnlock
            || isMusicControlWindowSuppressed
    }

    private func enqueueMusicControlWindowSync(forceRefresh: Bool, delay: TimeInterval = 0) {
        if shouldDeferMusicControlSync() {
            hasPendingMusicControlSync = true
            if forceRefresh {
                pendingMusicControlForceRefresh = true
            }
            logMusicControlEvent("Queued floating window sync (force: \(forceRefresh)) while deferred")
            return
        }

        logMusicControlEvent("Scheduling floating window sync (force: \(forceRefresh), delay: \(delay))")
        scheduleMusicControlWindowSync(forceRefresh: forceRefresh, delay: delay)
    }

    private func shouldShowMusicControlWindow() -> Bool {
        guard musicControlWindowEnabled,
              coordinator.musicLiveActivityEnabled,
              standardMediaControlsActive,
              vm.notchState == .closed,
              !vm.hideOnClosed,
              !lockScreenManager.isLocked,
              !isMusicHUDDeferredAfterUnlock,
              !isMusicControlWindowSuppressed else {
            return false
        }

        return musicControlVisibilityIsActive()
    }

    private func scheduleMusicControlWindowSync(forceRefresh: Bool, delay: TimeInterval = 0, bypassSuppression: Bool = false) {
        #if os(macOS)
        cancelMusicControlWindowSync()

        guard shouldShowMusicControlWindow() else {
            hasPendingMusicControlSync = false
            pendingMusicControlForceRefresh = false
            hideMusicControlWindow()
            return
        }

        if !bypassSuppression && (isMusicControlWindowSuppressed || lockScreenManager.isLocked || isMusicHUDDeferredAfterUnlock) {
            hasPendingMusicControlSync = true
            if forceRefresh {
                pendingMusicControlForceRefresh = true
            }
            return
        }

        hasPendingMusicControlSync = false
        pendingMusicControlForceRefresh = false

        let syncDelay = max(0, delay)

        pendingMusicControlTask = Task.detached(priority: .userInitiated) { [forceRefresh, syncDelay] in
            if syncDelay > 0 {
                let nanoseconds = UInt64(syncDelay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if shouldShowMusicControlWindow() {
                    logMusicControlEvent("Running floating window sync (force: \(forceRefresh))")
                    syncMusicControlWindow(forceRefresh: forceRefresh)
                } else {
                    logMusicControlEvent("Skipping floating window sync (conditions changed)")
                    hideMusicControlWindow()
                }

                pendingMusicControlTask = nil
            }
        }
        #endif
    }

    private func cancelMusicControlWindowSync() {
        pendingMusicControlTask?.cancel()
        pendingMusicControlTask = nil
    }

    #if os(macOS)
    private func currentMusicControlWindowMetrics() -> MusicControlWindowMetrics {
        MusicControlWindowMetrics(
            notchHeight: max(vm.closedNotchSize.height, vm.effectiveClosedNotchHeight),
            notchWidth: vm.closedNotchSize.width + (isHovering ? 8 : 0),
            rightWingWidth: max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12) + gestureProgress / 2),
            cornerRadius: activeCornerRadiusInsets.closed.bottom,
            spacing: 36
        )
    }

    private func syncMusicControlWindow(forceRefresh: Bool = false) {
        let notchAvailable = vm.effectiveClosedNotchHeight > 0 && vm.closedNotchSize.width > 0
        let targetVisible = shouldShowMusicControlWindow() && notchAvailable

        if targetVisible {
            let metrics = currentMusicControlWindowMetrics()
            if !isMusicControlWindowVisible {
                let didPresent = MusicControlWindowManager.shared.present(using: vm, metrics: metrics)
                isMusicControlWindowVisible = didPresent
            } else if forceRefresh {
                let didRefresh = MusicControlWindowManager.shared.refresh(using: vm, metrics: metrics)
                if !didRefresh {
                    MusicControlWindowManager.shared.hide()
                    isMusicControlWindowVisible = false
                }
            }
        } else if isMusicControlWindowVisible {
            MusicControlWindowManager.shared.hide()
            isMusicControlWindowVisible = false
        }
    }

    private func hideMusicControlWindow() {
        if isMusicControlWindowVisible {
            MusicControlWindowManager.shared.hide()
            isMusicControlWindowVisible = false
        }
    }
    #else
    private func syncMusicControlWindow(forceRefresh: Bool = false) {}

    private func hideMusicControlWindow() {}
    #endif
    
    private func shouldFixSizeForSneakPeek() -> Bool {
        guard isSneakPeekVisibleOnCurrentScreen else { return false }
        let style = resolvedSneakPeekStyle()
        
        // Check for extension sneak peek
        if case .extensionLiveActivity = coordinator.sneakPeek.type {
            return vm.notchState == .closed && style == .standard
        }
        
        // Original logic for other types
        let isMusicSneak = coordinator.sneakPeek.type == .music && vm.notchState == .closed && !vm.hideOnClosed && style == .standard
        let isTimerSneak = coordinator.sneakPeek.type == .timer && !vm.hideOnClosed && style == .standard
        let isReminderSneak = coordinator.sneakPeek.type == .reminder && !vm.hideOnClosed && style == .standard
        let isOtherSneak = coordinator.sneakPeek.type != .music && coordinator.sneakPeek.type != .timer && coordinator.sneakPeek.type != .reminder && vm.notchState == .closed
        
        return isMusicSneak || isTimerSneak || isReminderSneak || isOtherSneak
    }

    private func resolvedSneakPeekStyle() -> SneakPeekStyle {
        if case .extensionLiveActivity = coordinator.sneakPeek.type {
            return .standard
        }
        return coordinator.sneakPeek.styleOverride ?? Defaults[.sneakPeekStyles]
    }
}

private enum MusicSecondaryLiveActivity: Equatable {
    case timer
    case reminder(ReminderLiveActivityManager.ReminderEntry)
    case recording
    case focus(FocusModeType)
    case capsLock(showLabel: Bool)
    case extensionPayload(ExtensionLiveActivityPayload)

    var id: String {
        switch self {
        case .timer:
            return "timer"
        case .reminder(let entry):
            return "reminder-\(entry.id)"
        case .recording:
            return "recording"
        case .focus(let mode):
            return "focus-\(mode.rawValue)"
        case .capsLock(let showLabel):
            return showLabel ? "caps-lock-label" : "caps-lock-icon"
        case .extensionPayload(let payload):
            return "extension-\(payload.id)"
        }
    }
}

private struct MusicTimerSupplementView: View {
    @ObservedObject var timerManager: TimerManager
    let accentColor: Color
    let showsCountdown: Bool
    let showsProgress: Bool
    let progressStyle: TimerProgressStyle
    let notchHeight: CGFloat

    private var clampedProgress: Double {
        min(max(timerManager.progress, 0), 1)
    }

    private var showsRingProgress: Bool {
        showsProgress && progressStyle == .ring
    }

    private var showsBarProgress: Bool {
        showsProgress && progressStyle == .bar
    }

    private var countdownText: String {
        timerManager.formattedRemainingTime()
    }

    private var countdownTextWidth: CGFloat {
        max(1, TimerSupplementMetrics.countdownTextWidth(for: countdownText))
    }

    private var countdownFrameWidth: CGFloat {
        TimerSupplementMetrics.countdownFrameWidth(for: countdownText)
    }

    private var timerNameFrameWidth: CGFloat {
        TimerSupplementMetrics.timerNameFrameWidth(for: timerManager.timerName)
    }

    private var ringDiameter: CGFloat {
        max(min(notchHeight - 4, 26), 20)
    }

    var body: some View {
        HStack(spacing: showsRingProgress && showsCountdown ? 8 : 0) {
            if showsRingProgress {
                ringView
            }

            if showsCountdown {
                countdownStack
            } else if showsBarProgress {
                standaloneBarView
            } else {
                timerNameView
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var countdownStack: some View {
        VStack(alignment: .trailing, spacing: showsBarProgress ? 4 : 0) {
            Text(countdownText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(timerManager.isOvertime ? .red : .white)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: timerManager.remainingTime)
                .frame(width: countdownFrameWidth, alignment: .trailing)

            if showsBarProgress {
                barView(width: countdownTextWidth)
            }
        }
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var ringView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: clampedProgress)
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .frame(width: max(ringDiameter + 4, 30), height: notchHeight, alignment: .center)
    }

    private var standaloneBarView: some View {
        barView(width: 68)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var timerNameView: some View {
        Text(timerManager.timerName)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .lineLimit(1)
            .frame(width: timerNameFrameWidth, alignment: .trailing)
    }

    private func barView(width: CGFloat) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.15))
            .frame(width: width, height: 4)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(accentColor)
                    .frame(width: width * max(0, CGFloat(clampedProgress)), height: 4)
                    .animation(.smooth(duration: 0.25), value: clampedProgress)
            }
    }

}

private struct MusicReminderSupplementView: View {
    let entry: ReminderLiveActivityManager.ReminderEntry
    let now: Date
    let style: ReminderPresentationStyle
    let accent: Color
    let notchHeight: CGFloat

    var body: some View {
        Group {
            switch style {
            case .ringCountdown:
                ringCountdownView
            case .digital:
                digitalCountdownView
            case .minutes:
                minutesCountdownView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private var ringCountdownView: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progressValue)
                .stroke(accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: progressValue)
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .frame(width: max(ringDiameter + 4, 26), height: notchHeight, alignment: .center)
    }

    private var digitalCountdownView: some View {
        Text(digitalCountdownText)
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundColor(accent)
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.25), value: digitalCountdownText)
            .frame(width: digitalFrameWidth, alignment: .trailing)
            .frame(height: notchHeight, alignment: .center)
    }

    private var minutesCountdownView: some View {
        Text(minutesCountdownText)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(accent)
            .frame(width: minutesFrameWidth, alignment: .trailing)
            .frame(height: notchHeight, alignment: .center)
    }

    private var progressValue: Double {
        guard entry.leadTime > 0 else { return 1 }
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let elapsed = entry.leadTime - remaining
        return min(max(elapsed / entry.leadTime, 0), 1)
    }

    private var digitalCountdownText: String {
        ReminderSupplementMetrics.digitalCountdownText(for: entry, now: now)
    }

    private var minutesCountdownText: String {
        ReminderSupplementMetrics.minutesCountdownText(for: entry, now: now)
    }

    private var ringDiameter: CGFloat {
        ReminderSupplementMetrics.ringDiameter(for: notchHeight)
    }

    private var digitalFrameWidth: CGFloat {
        ReminderSupplementMetrics.digitalFrameWidth(for: digitalCountdownText)
    }

    private var minutesFrameWidth: CGFloat {
        ReminderSupplementMetrics.minutesFrameWidth(for: minutesCountdownText)
    }
}

private struct MusicCapsLockLabelView: View {
    let color: Color

    var body: some View {
        Text("Caps Lock")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentTransition(.opacity)
    }
}

#if canImport(AppKit)
private typealias MusicSupplementFont = NSFont
#elseif canImport(UIKit)
private typealias MusicSupplementFont = UIFont
#endif

private enum TimerSupplementMetrics {
    static func countdownTextWidth(for text: String) -> CGFloat {
        musicMeasureText(text, font: MusicSupplementFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold))
    }

    static func countdownFrameWidth(for text: String) -> CGFloat {
        max(countdownTextWidth(for: text) + 16, 72)
    }

    static func timerNameFrameWidth(for text: String) -> CGFloat {
        guard !text.isEmpty else { return 64 }
        let width = musicMeasureText(text, font: MusicSupplementFont.systemFont(ofSize: 12, weight: .medium))
        return max(width + 14, 64)
    }
}

private enum ReminderSupplementMetrics {
    static func digitalCountdownText(for entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let totalSeconds = Int(remaining.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func minutesCountdownText(for entry: ReminderLiveActivityManager.ReminderEntry, now: Date) -> String {
        let remaining = max(entry.event.start.timeIntervalSince(now), 0)
        let minutes = max(1, Int(ceil(remaining / 60)))
        return minutes == 1 ? "in 1 min" : "in \(minutes) min"
    }

    static func digitalFrameWidth(for text: String) -> CGFloat {
        let width = musicMeasureText(text, font: MusicSupplementFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold))
        return max(width + 18, 76)
    }

    static func minutesFrameWidth(for text: String) -> CGFloat {
        let width = musicMeasureText(text, font: MusicSupplementFont.systemFont(ofSize: 13, weight: .semibold))
        return max(width + 18, 88)
    }

    static func ringDiameter(for notchHeight: CGFloat) -> CGFloat {
        max(min(notchHeight - 12, 22), 16)
    }
}

private func musicMeasureText(_ text: String, font: MusicSupplementFont) -> CGFloat {
    guard !text.isEmpty else { return 0 }
    let attributes: [NSAttributedString.Key: Any] = [.font: font]
    return CGFloat(ceil(NSAttributedString(string: text, attributes: attributes).size().width))
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }
}
