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

import SwiftUI
import Defaults

#if canImport(AppKit)
import AppKit
typealias PlatformFont = NSFont
#elseif canImport(UIKit)
import UIKit
typealias PlatformFont = UIFont
#endif

struct TimerLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var timerManager = TimerManager.shared
    @ObservedObject var lockScreenManager = LockScreenManager.shared
    @State private var isHovering: Bool = false
    @State private var showTransientLabel: Bool = false
    @State private var labelHideTask: DispatchWorkItem?
    @State private var isControlWindowVisible: Bool = false
    @State private var pendingControlWindowTask: Task<Void, Never>?
    @State private var controlWindowSuppressionTask: Task<Void, Never>?
    @State private var hasPendingControlWindowSync: Bool = false
    @State private var pendingControlWindowForceRefresh: Bool = false
    @State private var isControlWindowSuppressed: Bool = false
    @Default(.timerShowsCountdown) private var showsCountdown
    @Default(.timerShowsProgress) private var showsProgress
    @Default(.timerShowsLabel) private var showsLabel
    @Default(.timerProgressStyle) private var progressStyle
    @Default(.timerIconColorMode) private var colorMode
    @Default(.timerSolidColor) private var solidColor
    @Default(.timerPresets) private var timerPresets
    @Default(.timerControlWindowEnabled) private var controlWindowEnabled
    @Default(.enableMinimalisticUI) private var enableMinimalisticUI
    
    private var notchContentHeight: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - (isHovering ? 0 : 12))
    }

    private var wingPadding: CGFloat { 22 }
    private var ringStrokeWidth: CGFloat { 3 }
    private var transientLabelDuration: TimeInterval { 4 }
    private let controlWindowResumeDelay: TimeInterval = 0.22

    private struct ControlWindowSyncKey: Equatable {
        var isTimerActive: Bool
        var timerNameSignature: Int
        var isFinished: Bool
        var isOvertime: Bool
        var isPaused: Bool
        var closedNotchSize: CGSize
        var screenName: String?
        var hideOnClosed: Bool
        var controlWindowEnabled: Bool
        var showsLabel: Bool
        var showTransientLabel: Bool
        var showsCountdown: Bool
        var showsProgress: Bool
        var progressStyleIdentifier: String
        var activeSourceIdentifier: String
    }

    private var ringWrapsIcon: Bool {
        showsRingProgress && showsCountdown
    }

    private var ringOnRight: Bool {
        showsRingProgress && !ringWrapsIcon
    }

    private var iconWidth: CGFloat {
        ringWrapsIcon ? max(notchContentHeight - 6, 28) : max(0, notchContentHeight)
    }

    private var infoContentWidth: CGFloat {
        guard showsInfoSection else { return 0 }
        if shouldDisplayLabel {
            let textWidth = min(max(titleTextWidth, 44), 220)
            return textWidth
        } else {
            return min(max(notchContentHeight * 1.4, 64), 220)
        }
    }

    private var infoWidth: CGFloat {
        guard showsInfoSection else { return 0 }
        return infoContentWidth + 18
    }

    private var leftWingWidth: CGFloat {
        // Only reserve the outer half of the wing padding so the icon sits flush
        // against the notch (matching the album-art / Toggl layout) instead of
        // leaving an empty gap between the icon and the notch body.
        var width = iconWidth + wingPadding / 2
        if showsInfoSection {
            width += 8 + infoWidth
        }
        return width
    }

    private var ringWidth: CGFloat {
        ringOnRight ? 30 : 0
    }

    private var rightWingWidth: CGFloat {
        var width = wingPadding
        if ringOnRight {
            width += ringWidth
        }
        if ringOnRight && showsCountdown {
            width += 8
        }
        if showsCountdown {
            width += countdownWidth
        }
        return width
    }

    private var titleTextWidth: CGFloat {
        measureTextWidth(timerManager.timerName, font: systemFont(size: 12, weight: .medium))
    }

    private var countdownTextWidth: CGFloat {
        measureTextWidth(timerManager.formattedRemainingTime(), font: monospacedFont(size: 13, weight: .semibold))
    }

    private var countdownWidth: CGFloat {
        guard showsCountdown else { return 0 }
        return max(countdownTextWidth + 16, 72)
    }

    private var clampedProgress: Double {
        min(max(timerManager.progress, 0), 1)
    }

    private var glyphColor: Color {
        switch colorMode {
        case .adaptive:
            return activePresetColor ?? timerManager.timerColor
        case .solid:
            return solidColor
        }
    }

    private var showsRingProgress: Bool {
        showsProgress && progressStyle == .ring
    }

    private var showsBarProgress: Bool {
        showsProgress && progressStyle == .bar
    }

    private var shouldDisplayLabel: Bool {
        showsLabel || showTransientLabel
    }

    private var showsInfoSection: Bool {
        shouldDisplayLabel || (showsBarProgress && !showsCountdown)
    }

    private var activePresetColor: Color? {
        guard let presetId = timerManager.activePresetId else { return nil }
        return timerPresets.first { $0.id == presetId }?.color
    }

    private var middleSectionWidth: CGFloat {
        vm.closedNotchSize.width + (isHovering ? 8 : 0)
    }

    private var adjustedNotchHeight: CGFloat {
        vm.effectiveClosedNotchHeight + (isHovering ? 8 : 0)
    }

    private var controlWindowSyncKey: ControlWindowSyncKey {
        ControlWindowSyncKey(
            isTimerActive: timerManager.isTimerActive,
            timerNameSignature: timerManager.timerName.hashValue,
            isFinished: timerManager.isFinished,
            isOvertime: timerManager.isOvertime,
            isPaused: timerManager.isPaused,
            closedNotchSize: vm.closedNotchSize,
            screenName: vm.screen,
            hideOnClosed: vm.hideOnClosed,
            controlWindowEnabled: controlWindowEnabled,
            showsLabel: showsLabel,
            showTransientLabel: showTransientLabel,
            showsCountdown: showsCountdown,
            showsProgress: showsProgress,
            progressStyleIdentifier: progressStyle.rawValue,
            activeSourceIdentifier: timerManager.activeSource.rawValue
        )
    }

        private var shouldShowControlWindow: Bool {
        if !controlWindowEnabled { return false }
        if showsLabel { return false }

        let timerEligible = timerManager.isTimerActive && !timerManager.isExternalTimerActive
        if !timerEligible { return false }

        let notchReady = vm.notchState == .closed && !vm.hideOnClosed
        if !notchReady { return false }

        if isControlWindowSuppressed { return false }
        if lockScreenManager.isLocked { return false }

        return true
        }
    
    private func measureTextWidth(_ text: String, font: PlatformFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let width = NSAttributedString(string: text, attributes: attributes).size().width
        return CGFloat(ceil(width))
    }

    private func systemFont(size: CGFloat, weight: PlatformFont.Weight) -> PlatformFont {
        #if canImport(AppKit)
        return NSFont.systemFont(ofSize: size, weight: weight)
        #else
        return UIFont.systemFont(ofSize: size, weight: weight)
        #endif
    }

    private func monospacedDigitFont(size: CGFloat, weight: PlatformFont.Weight) -> PlatformFont {
        #if canImport(AppKit)
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        #else
        return UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        #endif
    }

    // Fully monospaced font matching the countdown's `.monospaced` design so the
    // measured width equals the rendered width (digit-only monospacing under-measures
    // separators, clipping hour-format times like 1:00:00).
    private func monospacedFont(size: CGFloat, weight: PlatformFont.Weight) -> PlatformFont {
        #if canImport(AppKit)
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        #else
        return UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        #endif
    }

    var body: some View {
        baseTimerLayout
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.18)) {
                isHovering = hovering
            }
            requestControlWindowSync(forceRefresh: true, delay: hovering ? 0.05 : 0)
        }
        .onAppear {
            requestControlWindowSync(forceRefresh: true)
        }
        .onDisappear {
            hideControlWindow()
            cancelControlWindowSync()
            cancelControlWindowSuppressionTask()
        }
        .onChange(of: timerManager.isTimerActive) { _, isActive in
            if isActive {
                if !timerManager.isFinished && !timerManager.isOvertime {
                    requestControlWindowSync(forceRefresh: true)
                    triggerTransientLabel()
                }
            } else {
                hideControlWindow()
                cancelTransientLabel()
                showTransientLabel = false
                isHovering = false
                cancelControlWindowSync()
                resetPendingControlWindowFlags()
            }
        }
        .onChange(of: timerManager.timerName) { _, _ in
            if timerManager.isTimerActive && !timerManager.isFinished && !timerManager.isOvertime {
                requestControlWindowSync(forceRefresh: true)
                triggerTransientLabel()
            }
        }
        .onChange(of: timerManager.isFinished) { _, finished in
            if finished {
                cancelTransientLabel()
                withAnimation(.smooth) {
                    showTransientLabel = true
                    isHovering = false
                }
                requestControlWindowSync()
            }
        }
        .onChange(of: timerManager.isOvertime) { _, overtime in
            if overtime {
                cancelTransientLabel()
                withAnimation(.smooth) {
                    showTransientLabel = true
                    isHovering = false
                }
                requestControlWindowSync()
            }
        }
        .onChange(of: timerManager.isPaused) { _, _ in
            requestControlWindowSync(forceRefresh: true)
        }
        .onChange(of: controlWindowSyncKey) { _, _ in
            requestControlWindowSync(forceRefresh: true)
        }
        .onChange(of: vm.notchState) { _, state in
            handleControlWindowNotchStateChange(state)
        }
        .onChange(of: lockScreenManager.isLocked) { _, locked in
            handleControlWindowLockStateChange(locked)
        }
    }

    private var baseTimerLayout: some View {
        HStack(spacing: 0) {
            leftWingView()
            middleSectionView()
            rightWingView()
        }
        .frame(height: adjustedNotchHeight, alignment: .top)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func leftWingView() -> some View {
        Color.clear
            .frame(width: leftWingWidth, height: notchContentHeight)
            .background(alignment: .leading) {
                HStack(spacing: showsInfoSection ? 8 : 0) {
                    iconSection
                    if showsInfoSection {
                        infoSection
                    }
                }
                .padding(.leading, wingPadding / 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
    }

    @ViewBuilder
    private func middleSectionView() -> some View {
        Rectangle()
            .fill(.black)
            .frame(width: middleSectionWidth, height: notchContentHeight)
    }

    @ViewBuilder
    private func rightWingView() -> some View {
        Color.clear
            .frame(width: rightWingWidth, height: notchContentHeight)
            .background(alignment: .trailing) {
                HStack(spacing: ringOnRight && showsCountdown ? 8 : 0) {
                    if ringOnRight {
                        ringSection
                    }
                    if showsCountdown {
                        countdownSection
                    }
                }
                // Tighter trailing margin (~6px) so the countdown sits a little further
                // right, keeping the leading hour digit clear of the notch region.
                .padding(.trailing, wingPadding / 2 - 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
    }
    
    private var iconSection: some View {
        let baseDiameter = ringWrapsIcon ? iconWidth : iconWidth
        let ringDiameter = ringWrapsIcon ? max(min(baseDiameter, notchContentHeight - 2), 22) : iconWidth
        let iconSize = ringWrapsIcon ? max(ringDiameter - 12, 16) : max(18, iconWidth - 6)

        return ZStack {
            if ringWrapsIcon {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: ringStrokeWidth)
                    .frame(width: ringDiameter, height: ringDiameter)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(glyphColor, style: StrokeStyle(lineWidth: ringStrokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.25), value: clampedProgress)
                    .frame(width: ringDiameter, height: ringDiameter)
            }

            Image(systemName: "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(glyphColor)
                .frame(width: iconSize, height: iconSize)
        }
        .frame(width: ringWrapsIcon ? ringDiameter : iconWidth,
               height: notchContentHeight,
               alignment: .center)
    }
    
    private var infoSection: some View {
    let availableWidth = max(0, infoWidth - 10)
    let safeWidth = max(44, availableWidth - 6)
    let resolvedTextWidth = min(max(titleTextWidth, 44), safeWidth)
        let marqueeLabel = shouldDisplayLabel && (timerManager.isFinished || timerManager.isOvertime || titleTextWidth > availableWidth)
        let showsBarHere = showsBarProgress && !showsCountdown
        let barWidth = shouldDisplayLabel ? resolvedTextWidth : availableWidth

        return Rectangle()
            .fill(.black)
            .frame(width: infoWidth, height: notchContentHeight)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: showsBarHere ? 4 : 0) {
                    if shouldDisplayLabel {
                        if marqueeLabel {
                            MarqueeText(
                                .constant(timerManager.timerName),
                                font: .system(size: 12, weight: .medium),
                                nsFont: .callout,
                                textColor: .white,
                                minDuration: 0.25,
                                frameWidth: resolvedTextWidth
                            )
                        } else {
                            Text(timerManager.timerName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(.white)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                                .frame(width: resolvedTextWidth, alignment: .leading)
                        }
                    }

                    if showsBarHere {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: barWidth, height: 3)
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(glyphColor)
                                    .frame(width: barWidth * max(0, CGFloat(clampedProgress)))
                                    .animation(.smooth(duration: 0.25), value: clampedProgress)
                            }
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 6)
            }
            .animation(.smooth, value: timerManager.isFinished)
    }
    
    private var ringSection: some View {
        let diameter = max(min(notchContentHeight - 4, 26), 20)
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: ringStrokeWidth)
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(glyphColor, style: StrokeStyle(lineWidth: ringStrokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.25), value: clampedProgress)
        }
        .frame(width: diameter, height: diameter)
        .frame(width: ringWidth, height: notchContentHeight, alignment: .center)
    }
    
    private var countdownSection: some View {
        let barWidth = max(countdownTextWidth, 1)
        return VStack(spacing: 4) {
            Text(timerManager.formattedRemainingTime())
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(timerManager.isOvertime ? .red : .white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.25), value: timerManager.remainingTime)
                .frame(maxWidth: .infinity, alignment: .trailing)

            if showsBarProgress {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: barWidth, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(glyphColor)
                            .frame(width: barWidth * max(0, CGFloat(clampedProgress)))
                            .animation(.smooth(duration: 0.25), value: clampedProgress)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
     // Note: rightWingView already applies a trailing wing padding, so no extra
     // trailing padding here — a second one pushes the digits left and clips the
     // hour under the notch while wasting space on the right.
     .frame(width: countdownWidth,
         height: notchContentHeight, alignment: .center)
    }

    private func requestControlWindowSync(forceRefresh: Bool = false, delay: TimeInterval = 0) {
        enqueueControlWindowSync(forceRefresh: forceRefresh, delay: delay)
    }

    private func enqueueControlWindowSync(forceRefresh: Bool, delay: TimeInterval = 0) {
        if shouldDeferControlWindowSync() {
            hasPendingControlWindowSync = true
            if forceRefresh {
                pendingControlWindowForceRefresh = true
            }
            return
        }

        scheduleControlWindowSync(forceRefresh: forceRefresh, delay: delay)
    }

    private func scheduleControlWindowSync(forceRefresh: Bool, delay: TimeInterval = 0, bypassSuppression: Bool = false) {
        cancelControlWindowSync()

        guard shouldShowControlWindow else {
            resetPendingControlWindowFlags()
            hideControlWindow()
            return
        }

        if !bypassSuppression && shouldDeferControlWindowSync() {
            hasPendingControlWindowSync = true
            if forceRefresh {
                pendingControlWindowForceRefresh = true
            }
            return
        }

        resetPendingControlWindowFlags()

        let syncDelay = max(0, delay)

        if syncDelay <= 0 {
            syncControlWindow(forceRefresh: forceRefresh)
            return
        }

        pendingControlWindowTask = Task { @MainActor [forceRefresh] in
            let nanoseconds = UInt64(syncDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)

            guard !Task.isCancelled else { return }

            if shouldShowControlWindow {
                syncControlWindow(forceRefresh: forceRefresh)
            } else {
                hideControlWindow()
            }

            pendingControlWindowTask = nil
        }
    }

    private func cancelControlWindowSync() {
        pendingControlWindowTask?.cancel()
        pendingControlWindowTask = nil
    }

    private func resetPendingControlWindowFlags() {
        hasPendingControlWindowSync = false
        pendingControlWindowForceRefresh = false
    }

    private func shouldDeferControlWindowSync() -> Bool {
        vm.notchState != .closed || lockScreenManager.isLocked || isControlWindowSuppressed
    }

    private func triggerPendingControlWindowSyncIfNeeded() {
        guard hasPendingControlWindowSync else { return }
        let shouldForce = pendingControlWindowForceRefresh
        resetPendingControlWindowFlags()
        scheduleControlWindowSync(forceRefresh: shouldForce, delay: 0, bypassSuppression: true)
    }

    private func suppressControlWindowUpdates() {
        isControlWindowSuppressed = true
        cancelControlWindowSuppressionTask()
    }

    private func releaseControlWindowUpdates(after delay: TimeInterval) {
        cancelControlWindowSuppressionTask()
        controlWindowSuppressionTask = Task { [delay] in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if vm.notchState == .closed && !lockScreenManager.isLocked {
                    isControlWindowSuppressed = false
                    triggerPendingControlWindowSyncIfNeeded()
                } else {
                    isControlWindowSuppressed = true
                }

                controlWindowSuppressionTask = nil
            }
        }
    }

    private func cancelControlWindowSuppressionTask() {
        controlWindowSuppressionTask?.cancel()
        controlWindowSuppressionTask = nil
    }

    private func handleControlWindowNotchStateChange(_ state: NotchState) {
        if state == .open {
            suppressControlWindowUpdates()
            cancelControlWindowSync()
            hideControlWindow()
        } else {
            releaseControlWindowUpdates(after: controlWindowResumeDelay)
            requestControlWindowSync(forceRefresh: true, delay: 0.05)
        }
    }

    private func handleControlWindowLockStateChange(_ locked: Bool) {
        if locked {
            suppressControlWindowUpdates()
            cancelControlWindowSync()
            hideControlWindow()
        } else {
            releaseControlWindowUpdates(after: controlWindowResumeDelay)
            requestControlWindowSync(forceRefresh: true, delay: 0.05)
        }
    }

    private func triggerTransientLabel() {
        guard !showsLabel else { return }
        guard !enableMinimalisticUI else { return }
        cancelTransientLabel()
        withAnimation(.smooth) {
            showTransientLabel = true
        }
        let task = DispatchWorkItem {
            withAnimation(.smooth) {
                showTransientLabel = false
            }
            requestControlWindowSync(forceRefresh: true)
        }
        labelHideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + transientLabelDuration, execute: task)
    }

    private func cancelTransientLabel() {
        labelHideTask?.cancel()
        labelHideTask = nil
    }

    private func syncControlWindow(forceRefresh: Bool = false) {
#if os(macOS)
        let notchAvailable = vm.effectiveClosedNotchHeight > 0 && vm.closedNotchSize.width > 0
        let targetVisible = shouldShowControlWindow && notchAvailable
        if targetVisible {
            let metrics = currentControlWindowMetrics()
            if !isControlWindowVisible {
                let didPresent = TimerControlWindowManager.shared.present(using: vm, metrics: metrics)
                isControlWindowVisible = didPresent
            } else if forceRefresh {
                let didRefresh = TimerControlWindowManager.shared.refresh(using: vm, metrics: metrics)
                isControlWindowVisible = didRefresh
                if !didRefresh {
                    TimerControlWindowManager.shared.hide()
                }
            }
        } else if isControlWindowVisible {
            TimerControlWindowManager.shared.hide()
            isControlWindowVisible = false
        }
#endif
    }

    private func hideControlWindow() {
#if os(macOS)
        if isControlWindowVisible {
            TimerControlWindowManager.shared.hide()
            isControlWindowVisible = false
        }
#endif
    }

    private func currentControlWindowMetrics() -> TimerControlWindowMetrics {
        TimerControlWindowMetrics(
            notchHeight: max(vm.closedNotchSize.height, vm.effectiveClosedNotchHeight),
            notchWidth: vm.closedNotchSize.width + (isHovering ? 8 : 0),
            rightWingWidth: rightWingWidth,
            cornerRadius: cornerRadiusInsets.closed.bottom,
            spacing: 6
        )
    }
}

#Preview {
    TimerLiveActivity()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 300, height: 32)
        .background(.black)
        .onAppear {
            TimerManager.shared.startDemoTimer(duration: 300)
        }
}
