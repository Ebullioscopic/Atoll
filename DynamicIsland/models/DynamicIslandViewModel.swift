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

import Combine
import Defaults
import SwiftUI

@MainActor
class DynamicIslandViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = DynamicIslandViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: DynamicIslandAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    @Published var dragDetectorTargeting: Bool = false
    @Published var dropZoneTargeting: Bool = false
    @Published var dropEvent: Bool = false
    @Published var anyDropZoneTargeting: Bool = false
    var cancellables: Set<AnyCancellable> = []

    /// Teardown hook ContentView registers in `onAppear`; the window-cleanup path
    /// invokes it before closing the panel since `.onDisappear` is unreliable for
    /// borderless panels, preventing leaked hover-polling Tasks from accumulating.
    var onViewTeardown: (() -> Void)?
    
    @Published var hideOnClosed: Bool = true
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false
    @Published var isClipboardPopoverActive: Bool = false
    @Published var isColorPickerPopoverActive: Bool = false
    @Published var isStatsPopoverActive: Bool = false
    @Published var isReminderPopoverActive: Bool = false
    /// Whether any output picker popover is open.
    ///
    /// Four separate views can present one of these -- the media output and
    /// AirPlay pickers, in both the standard and minimalistic players -- and they
    /// all used to assign this directly. Whichever ran last won, so closing one
    /// picker cleared the flag while another was still open and let the notch
    /// auto-close underneath it. Presenters register instead, and the flag stays
    /// true while any of them is still open.
    @Published private(set) var isMediaOutputPopoverActive: Bool = false

    private var activeMediaOutputPopovers: Set<UUID> = []

    /// Registers or withdraws one presenter, identified by a token that is stable
    /// for the lifetime of the view holding it.
    func setMediaOutputPopoverActive(_ isActive: Bool, token: UUID) {
        if isActive {
            activeMediaOutputPopovers.insert(token)
        } else {
            activeMediaOutputPopovers.remove(token)
        }

        let isAnyActive = !activeMediaOutputPopovers.isEmpty
        if isMediaOutputPopoverActive != isAnyActive {
            isMediaOutputPopoverActive = isAnyActive
        }
    }
    @Published var isTimerPopoverActive: Bool = false
    @Published var shouldRecheckHover: Bool = false
    @Published var isScrollGestureActive: Bool = false
    private var scrollGestureSuppressionTokens: Set<UUID> = []
    @Published private(set) var isAutoCloseSuppressed: Bool = false
    private var autoCloseSuppressionTokens: Set<UUID> = []
    private let clipboardFocusWindow: TimeInterval = 10

    func setScrollGestureSuppression(_ active: Bool, token: UUID) {
        if active {
            let inserted = scrollGestureSuppressionTokens.insert(token).inserted
            if inserted {
                isScrollGestureActive = true
            }
        } else {
            if scrollGestureSuppressionTokens.remove(token) != nil {
                isScrollGestureActive = !scrollGestureSuppressionTokens.isEmpty
            }
        }
    }

    private func resetScrollGestureSuppression() {
        scrollGestureSuppressionTokens.removeAll()
        isScrollGestureActive = false
    }

    func setAutoCloseSuppression(_ active: Bool, token: UUID) {
        if active {
            let inserted = autoCloseSuppressionTokens.insert(token).inserted
            if inserted {
                isAutoCloseSuppressed = true
            }
        } else if autoCloseSuppressionTokens.remove(token) != nil {
            isAutoCloseSuppressed = !autoCloseSuppressionTokens.isEmpty
        }
    }

    private func resetAutoCloseSuppression() {
        autoCloseSuppressionTokens.removeAll()
        isAutoCloseSuppressed = false
    }

    private func focusClipboardTabIfNeeded() {
        guard !Defaults[.enableMinimalisticUI] else { return }
        guard Defaults[.enableClipboardManager] else { return }
        guard Defaults[.clipboardDisplayMode] == .separateTab else { return }
        guard let lastCopyDate = ClipboardManager.shared.lastCopiedItemDate else { return }
        guard Date().timeIntervalSince(lastCopyDate) <= clipboardFocusWindow else { return }
        guard coordinator.currentView != .notes else { return }
        withAnimation(.smooth) {
            coordinator.currentView = .notes
        }
    }
    
    let webcamManager = WebcamManager.shared
    @Published var isCameraExpanded: Bool = false
    @Published var isRequestingAuthorization: Bool = false

    @Published var screen: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    
    @MainActor
    deinit {
        destroy()
    }

    func destroy() {
        onViewTeardown?()
        onViewTeardown = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screen: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screen = screen
        notchSize = getClosedNotchSize(screen: screen)
        closedNotchSize = notchSize

        Publishers.CombineLatest($dropZoneTargeting, $dragDetectorTargeting)
            .map { value1, value2 in
                value1 || value2
            }
            .assign(to: \.anyDropZoneTargeting, on: self)
            .store(in: &cancellables)
        
        setupDetectorObserver()

        ReminderLiveActivityManager.shared.$activeWindowReminders
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let updatedTarget = self.calculateDynamicNotchSize()
                guard self.notchState == .open else { return }
                guard self.notchSize != updatedTarget else { return }
                withAnimation(.smooth) {
                    self.notchSize = updatedTarget
                }
                if let delegate = AppDelegate.shared {
                    delegate.ensureWindowSize(
                        addShadowPadding(to: updatedTarget, isMinimalistic: Defaults[.enableMinimalisticUI]),
                        animated: true,
                        force: false
                    )
                }
            }
            .store(in: &cancellables)

        // Observe settings + lyrics changes to dynamically resize the notch
        let enableLyricsPublisher = Defaults.publisher(.enableLyrics).map { $0.newValue }

        enableLyricsPublisher
            .combineLatest(MusicManager.shared.$currentLyrics)
            .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard Defaults[.enableMinimalisticUI] else { return }
                let updatedTarget = self.calculateDynamicNotchSize()
                guard self.notchState == .open else { return }
                guard self.notchSize != updatedTarget else { return }
                withAnimation(.smooth) {
                    self.notchSize = updatedTarget
                }
                if let delegate = AppDelegate.shared {
                    delegate.ensureWindowSize(
                        addShadowPadding(to: updatedTarget, isMinimalistic: Defaults[.enableMinimalisticUI]),
                        animated: true,
                        force: false
                    )
                }
            }
            .store(in: &cancellables)

        TimerManager.shared.$activeSource
            .combineLatest(TimerManager.shared.$isTimerActive)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.handleMinimalisticTimerHeightChange()
            }
            .store(in: &cancellables)

        coordinator.$statsSecondRowExpansion
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.notchState == .open else { return }
                let updatedTarget = self.calculateDynamicNotchSize()
                guard self.notchSize != updatedTarget else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.notchSize = updatedTarget
                }
                if let delegate = AppDelegate.shared {
                    delegate.ensureWindowSize(
                        addShadowPadding(to: updatedTarget, isMinimalistic: Defaults[.enableMinimalisticUI]),
                        animated: false,
                        force: false
                    )
                }
            }
            .store(in: &cancellables)

        coordinator.$notesLayoutState
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.notchState == .open else { return }
                let updatedTarget = self.calculateDynamicNotchSize()
                guard self.notchSize != updatedTarget else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.notchSize = updatedTarget
                }
                if let delegate = AppDelegate.shared {
                    delegate.ensureWindowSize(
                        addShadowPadding(to: updatedTarget, isMinimalistic: Defaults[.enableMinimalisticUI]),
                        animated: true,
                        force: false
                    )
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.openNotchWidth, options: [])
            .map { $0.newValue }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                guard self.notchState == .open else { return }
                guard !Defaults[.enableMinimalisticUI] else { return }
                let updatedTarget = self.calculateDynamicNotchSize()
                guard self.notchSize != updatedTarget else { return }
                withAnimation(.smooth) {
                    self.notchSize = updatedTarget
                }
                if let delegate = AppDelegate.shared {
                    delegate.ensureWindowSize(
                        addShadowPadding(to: updatedTarget, isMinimalistic: false),
                        animated: true,
                        force: false
                    )
                }
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            Defaults.publisher(.enableLyrics, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showCalendar, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showStandardMediaControls, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.autoHideInactiveNotchMediaPlayer, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.showMirror, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lyricsPanelWidth, options: []).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.lyricsPanelOffset, options: []).map { _ in () }.eraseToAnyPublisher(),
            MusicManager.shared.$isPlaying.map { _ in () }.eraseToAnyPublisher(),
            MusicManager.shared.$songTitle.map { _ in () }.eraseToAnyPublisher(),
            MusicManager.shared.$artistName.map { _ in () }.eraseToAnyPublisher(),
            WebcamManager.shared.$cameraAvailable.map { _ in () }.eraseToAnyPublisher()
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateSideLyricsNotchSizeIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func updateSideLyricsNotchSizeIfNeeded() {
        guard notchState == .open, !Defaults[.enableMinimalisticUI] else { return }

        let updatedTarget = calculateDynamicNotchSize()
        guard notchSize != updatedTarget else { return }
        withAnimation(.smooth) {
            notchSize = updatedTarget
        }
        AppDelegate.shared?.ensureWindowSize(
            addShadowPadding(to: updatedTarget, isMinimalistic: false),
            animated: true,
            force: false
        )
    }

    private func handleMinimalisticTimerHeightChange() {
        guard Defaults[.enableMinimalisticUI] else { return }
        guard notchState == .open else { return }
        let updatedTarget = calculateDynamicNotchSize()
        guard notchSize != updatedTarget else { return }
        withAnimation(.smooth) {
            notchSize = updatedTarget
        }
        if let delegate = AppDelegate.shared {
            delegate.ensureWindowSize(
                addShadowPadding(to: updatedTarget, isMinimalistic: Defaults[.enableMinimalisticUI]),
                animated: true,
                force: false
            )
        }
    }
    
    private func setupDetectorObserver() {
        // 1) Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.enableFullscreenMediaDetection)
            .map(\.newValue)

        // 2) For each non‑nil screen name, map to a Bool publisher for that screen's status
        let statusPublisher = $screen
            .compactMap { $0 }
            .removeDuplicates()
            .map { screenName in
                self.detector.$fullscreenStatus
                    .map { $0[screenName] ?? false }
                    .removeDuplicates()
            }
            .switchToLatest()

        // 3) Combine enabled & status, animate only on changes
        Publishers.CombineLatest(statusPublisher, enabledPublisher)
            .map { status, enabled in enabled && status }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }
    
    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = NSScreen.screens.first { $0.localizedName == screen }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        return noNotchAndFullscreen ? 0 : closedNotchSize.height
    }

    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screen)
        if let frame = screenFrame {
            
            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2
            
            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    func open() {
        let targetSize = calculateDynamicNotchSize()

        let applyWindowResize: () -> Void = {
            guard let delegate = AppDelegate.shared else { return }
            delegate.ensureWindowSize(
                addShadowPadding(to: targetSize, isMinimalistic: Defaults[.enableMinimalisticUI]),
                animated: false,
                force: true
            )
        }

        if Thread.isMainThread {
            applyWindowResize()
        } else {
            DispatchQueue.main.async(execute: applyWindowResize)
        }

        notchSize = targetSize
        notchState = .open

        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
        focusClipboardTabIfNeeded()
    }
    
    private func calculateDynamicNotchSize() -> CGSize {
        let baseSize = Defaults[.enableMinimalisticUI] ? minimalisticOpenNotchSize(isDynamicIslandMode: shouldUseDynamicIslandMode(for: screen)) : openNotchSize
        var adjustedSize = baseSize

        if coordinator.currentView == .notes || coordinator.currentView == .clipboard {
            let preferred = coordinator.notesLayoutState.preferredHeight
            adjustedSize.height = max(adjustedSize.height, preferred)
            return adjustedSize
        }

        if coordinator.currentView == .llmUsage {
            adjustedSize.height = max(adjustedSize.height, llmUsageOpenNotchHeight)
            return adjustedSize
        }

        adjustedSize = inlineLyricsAdjustedNotchSize(
            from: adjustedSize,
            isHomeTabActive: coordinator.currentView == .home
        )

        return statsAdjustedNotchSize(
            from: adjustedSize,
            isStatsTabActive: coordinator.currentView == .stats,
            secondRowProgress: coordinator.statsSecondRowExpansion
        )
    }

    func close() {
        let targetSize = getClosedNotchSize(screen: screen)
        notchSize = targetSize
        closedNotchSize = targetSize
        notchState = .closed
        resetScrollGestureSuppression()
        resetAutoCloseSuppression()

        // Set the current view to shelf if it contains files and the user enables openShelfByDefault
        // Otherwise, if the user has not enabled openLastShelfByDefault, set the view to home
        if !ShelfStateViewModel.shared.isEmpty && Defaults[.openShelfByDefault] && !Defaults[.enableMinimalisticUI] {
            coordinator.currentView = .shelf
        } else if !coordinator.openLastTabByDefault {
            coordinator.currentView = .home
        }
    }

    func closeForLockScreen() {
        let targetSize = getClosedNotchSize(screen: screen)
        withAnimation(.none) {
            notchSize = targetSize
            closedNotchSize = targetSize
            notchState = .closed
            resetScrollGestureSuppression()
            resetAutoCloseSuppression()
        }
    }

    private var helloCloseScheduled = false

    func closeHello() {
        guard !helloCloseScheduled else { return }
        helloCloseScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            guard let self else { return }
            self.coordinator.firstLaunch = false
            withAnimation(self.animationLibrary.animation) {
                self.close()
            }
        }
    }
    
    func toggleCameraPreview() {
        if isRequestingAuthorization {
            return
        }

        switch webcamManager.authorizationStatus {
        case .authorized:
            if webcamManager.isSessionRunning {
                webcamManager.stopSession()
                isCameraExpanded = false
            } else if webcamManager.cameraAvailable {
                webcamManager.startSession()
                isCameraExpanded = true
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)

                let alert = NSAlert()
                alert.messageText = String(localized: "Camera Access Required")
                alert.informativeText = String(localized: "Please allow camera access in System Settings.")
                alert.addButton(withTitle: String(localized: "OK"))
                alert.runModal()

                NSApp.setActivationPolicy(.accessory)
                NSApp.deactivate()
            }

        case .notDetermined:
            isRequestingAuthorization = true
            webcamManager.checkAndRequestVideoAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.isRequestingAuthorization = false
            }

        default:
            break
        }
    }
}
