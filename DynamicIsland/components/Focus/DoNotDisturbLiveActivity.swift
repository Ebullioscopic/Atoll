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

import AppKit
import Defaults
import SwiftUI

struct DoNotDisturbLiveActivity: View {
    @EnvironmentObject var vm: DynamicIslandViewModel
    @ObservedObject var manager = DoNotDisturbManager.shared
    @Default(.showDoNotDisturbLabel) private var showLabelSetting
    @Default(.focusIndicatorNonPersistent) private var focusToastMode

    @State private var isExpanded = false
    @State private var showInactiveIcon = false
    @State private var iconScale: CGFloat = 1.0
    @State private var scaleResetTask: Task<Void, Never>?
    @State private var collapseTask: Task<Void, Never>?
    @State private var cleanupTask: Task<Void, Never>?

    private enum ToastTiming {
        static let activeDisplay: UInt64 = 1800  // focus enabled toast linger
        static let inactiveDisplay: UInt64 = 1500  // focus disabled toast linger
    }

    var body: some View {
        HStack(spacing: 0) {
            iconWing
                .frame(width: iconWingWidth, height: wingHeight)

            Rectangle()
                .fill(Color.black)
                .frame(width: centerSegmentWidth)

            labelWing
                .frame(width: labelWingWidth, height: wingHeight)
        }
        .frame(width: notchEnvelopeWidth, height: vm.effectiveClosedNotchHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .onAppear(perform: handleInitialState)
        .onChange(of: manager.isDoNotDisturbActive, handleFocusStateChange)
        .onChange(of: manager.focusToastTrigger, handleFocusModeSwitchToast)
        .onChange(of: focusToastMode, handleToastModeSettingChange)
        .onDisappear(perform: cancelPendingTasks)
    }

    // MARK: - Layout helpers

    private var collapsedNotchWidth: CGFloat {
        let width = currentClosedNotchWidth
        let scale = (resolvedScreen?.backingScaleFactor).flatMap { $0 > 0 ? $0 : nil }
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let aligned = (width * scale).rounded(.down) / scale
        return max(0, aligned)
    }

    private var currentClosedNotchWidth: CGFloat {
        if vm.notchState == .closed, vm.notchSize.width > 0 {
            return vm.notchSize.width
        }
        return vm.closedNotchSize.width
    }

    private var resolvedScreen: NSScreen? {
        if let name = vm.screen,
           let match = NSScreen.screen(named: name) {
            return match
        }
        return NSScreen.main
    }

    private var wingHeight: CGFloat {
        max(vm.effectiveClosedNotchHeight - 10, 20)
    }

    private var iconWingWidth: CGFloat {
        (isExpanded || showInactiveIcon) ? minimalWingWidth : 0
    }

    private var labelWingWidth: CGFloat {
        guard shouldShowLabel else {
            return focusToastMode ? 0 : ((isExpanded || showInactiveIcon) ? minimalWingWidth : 0)
        }

        if focusToastMode {
            return max(labelIntrinsicWidth + 26, minimalWingWidth)
        }

        return max(desiredLabelWidth, minimalWingWidth)
    }

    private var notchEnvelopeWidth: CGFloat {
        centerSegmentWidth + iconWingWidth + labelWingWidth
    }

    private var minimalWingWidth: CGFloat {
        max(vm.effectiveClosedNotchHeight - 12, 24)
    }

    private var closedNotchContentInset: CGFloat {
        cornerRadiusInsets.closed.top + cornerRadiusInsets.closed.bottom
    }

    private var collapsedToastBaseWidth: CGFloat {
        max(0, collapsedNotchWidth - closedNotchContentInset)
    }

    private var centerSegmentWidth: CGFloat {
        if focusToastMode && iconWingWidth == 0 && labelWingWidth == 0 {
            return collapsedToastBaseWidth
        }
        return collapsedNotchWidth
    }

    private var desiredLabelWidth: CGFloat {
        let fallbackWidth = max(collapsedNotchWidth * 0.52, 136)
        var width = fallbackWidth

        if focusMode == .doNotDisturb && shouldShowLabel {
            width = max(width, 164)
        }

        if !shouldMarqueeLabel {
            width = max(width, labelIntrinsicWidth + 8)
        }

        return width
    }

    private var shouldShowLabel: Bool {
        focusToastMode ? (isExpanded && !labelText.isEmpty) : (showLabelSetting && isExpanded && !labelText.isEmpty)
    }

    private var labelIntrinsicWidth: CGFloat {
        guard !labelText.isEmpty else { return 0 }
        return (labelText as NSString).size(withAttributes: [.font: focusLabelNSFont]).width
    }

    private var shouldMarqueeLabel: Bool {
        shouldShowLabel && labelIntrinsicWidth > focusLabelBaselineWidth
    }

    private var marqueeFrameWidth: CGFloat {
        max(48, labelWingWidth - 8)
    }

    private var focusLabelFont: Font {
        .system(size: 12, weight: .semibold, design: .rounded)
    }

    private var focusLabelNSFont: NSFont {
        NSFont.systemFont(ofSize: 12, weight: .semibold)
    }

    private var focusLabelBaselineWidth: CGFloat {
        FocusLabelMetrics.baselineWidth
    }

    // MARK: - Focus metadata

    private var focusMode: FocusModeType {
        FocusModeType.resolve(
            identifier: manager.currentFocusModeIdentifier,
            name: manager.currentFocusModeName
        )
    }

    private var activeAccentColor: Color {
        focusMode.accentColor
    }

    private var labelText: String {
        if focusToastMode {
            return manager.isDoNotDisturbActive ? "On" : "Off"
        }

        let trimmed = manager.currentFocusModeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if showLabelSetting {
            if !trimmed.isEmpty {
                return trimmed
            } else if focusMode == .doNotDisturb {
                return "Do Not Disturb"
            } else {
                let fallback = focusMode.displayName
                return fallback.isEmpty ? "Focus" : fallback
            }
        }

        return ""
    }

    private var accessibilityDescription: String {
        if manager.isDoNotDisturbActive {
            return "Focus active: \(labelText)"
        } else {
            return "Focus inactive"
        }
    }

    private var currentIcon: Image {
        if manager.isDoNotDisturbActive {
            return focusMode.resolvedActiveIcon(usePrivateSymbol: true)
        } else if showInactiveIcon {
            return inactiveIconMatchingActiveStyle
        } else {
            return focusMode.resolvedActiveIcon(usePrivateSymbol: true)
        }
    }

    private var inactiveIconMatchingActiveStyle: Image {
        if focusMode == .work {
            return focusMode.resolvedActiveIcon(usePrivateSymbol: true).renderingMode(.template)
        }

        if focusMode == .gaming,
           SymbolAvailabilityCache.shared.isSymbolAvailable("rocket.circle.fill") {
            return Image(systemName: "rocket.circle.fill")
        }

        if let internalName = focusMode.internalSymbolName {
            if let outlineName = outlineVariant(for: internalName),
               SymbolAvailabilityCache.shared.isSymbolAvailable(outlineName),
               let outlinedImage = Image(internalSystemName: outlineName) {
                return outlinedImage.renderingMode(.template)
            }

            if let filledImage = Image(internalSystemName: internalName) {
                return filledImage.renderingMode(.template)
            }
        }

        return Image(systemName: focusMode.inactiveSymbol)
    }

    private func outlineVariant(for internalName: String) -> String? {
        guard internalName.hasSuffix(".fill") else { return nil }
        let trimmed = String(internalName.dropLast(5))
        return trimmed.isEmpty ? nil : trimmed
    }

    private var currentIconColor: Color {
        if manager.isDoNotDisturbActive {
            return activeAccentColor
        } else if showInactiveIcon {
            return .white
        } else {
            return activeAccentColor
        }
    }

    // MARK: - Subviews

    private var iconWing: some View {
        Color.clear
            .overlay(alignment: .center) {
                if iconWingWidth > 0 {
                    currentIcon
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(currentIconColor)
                        .contentTransition(.opacity)
                        .scaleEffect(iconScale)
                        .animation(.none, value: iconScale)
                }
            }
            .animation(.smooth(duration: 0.3), value: iconWingWidth)
    }

    private var labelWing: some View {
        Color.clear
            .overlay(alignment: .trailing) {
                if shouldShowLabel {
                    Group {
                        if shouldMarqueeLabel {
                            MarqueeText(
                                .constant(labelText),
                                font: focusLabelFont,
                                nsFont: .caption1,
                                textColor: labelColor,
                                minDuration: 0.4,
                                frameWidth: marqueeFrameWidth
                            )
                            .frame(width: marqueeFrameWidth, alignment: .trailing)
                        } else {
                            Text(labelText)
                                .font(focusLabelFont)
                                .foregroundColor(labelColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .contentTransition(.opacity)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            .animation(.smooth(duration: 0.3), value: shouldShowLabel)
    }

    private var labelColor: Color {
        if focusToastMode {
            return manager.isDoNotDisturbActive ? activeAccentColor : .white
        }
        return activeAccentColor
    }

    // MARK: - State transitions

    private func handleInitialState() {
        if manager.isDoNotDisturbActive {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = true
            }
            if focusToastMode {
                scheduleTransientCollapse()
            }
        }
    }

    private func handleFocusStateChange(_ oldValue: Bool, _ isActive: Bool) {
        cancelPendingTasks()

        if isActive {
            // Force a clean collapsed baseline before animating ON.
            // This avoids cases where prior OFF state leaves the view mid-transition.
            withAnimation(.none) {
                showInactiveIcon = false
                isExpanded = false
                iconScale = 1.0
            }

            // Run the expansion on the next runloop tick so the reset takes effect first.
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    iconScale = 1.0
                    isExpanded = true
                }
                if focusToastMode {
                    scheduleTransientCollapse()
                }
            }
        } else {
            triggerInactiveAnimation()
        }
    }

    private func handleFocusModeSwitchToast(_ oldValue: UUID, _ newValue: UUID) {
        // Only show a toast when Focus is currently active.
        guard manager.isDoNotDisturbActive else { return }

        // Only relevant for the non-persistent (brief toast) mode.
        guard focusToastMode else { return }

        // Cancel any pending collapse so the new mode can animate in cleanly.
        cancelPendingTasks()

        // Force a clean collapsed baseline before animating ON for the *new* mode.
        // Without this, a mode switch can appear to start then cancel.
        withAnimation(.none) {
            showInactiveIcon = false
            isExpanded = false
            iconScale = 1.0
        }

        // Run the expansion on the next runloop tick so the reset takes effect first.
        DispatchQueue.main.async {
            guard manager.isDoNotDisturbActive else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                iconScale = 1.0
                isExpanded = true
            }
            scheduleTransientCollapse()
        }
    }

    /// When the user toggles between toast / persistent mode while focus is active,
    /// re-expand the view so the wings become visible again.
    private func handleToastModeSettingChange(_ oldValue: Bool, _ newToastMode: Bool) {
        guard manager.isDoNotDisturbActive else { return }

        cancelPendingTasks()

        if newToastMode {
            // Switched TO toast mode — show a brief expansion then collapse.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = true
                showInactiveIcon = false
                iconScale = 1.0
            }
            scheduleTransientCollapse()
        } else {
            // Switched TO persistent mode — ensure wings are expanded.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = true
                showInactiveIcon = false
                iconScale = 1.0
            }
        }
    }

    private func triggerInactiveAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            isExpanded = true
        }
        withAnimation(.smooth(duration: 0.2)) {
            showInactiveIcon = true
        }

        if focusToastMode {
            iconScale = 1.0
            scaleResetTask?.cancel()
        } else {
            withAnimation(.interpolatingSpring(stiffness: 220, damping: 12)) {
                iconScale = 1.2
            }

            scaleResetTask?.cancel()
            scaleResetTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.interpolatingSpring(stiffness: 180, damping: 18)) {
                    iconScale = 1.0
                }
                withAnimation(.smooth(duration: 0.2)) {
                    showInactiveIcon = false
                }
            }
        }

        collapseTask?.cancel()
        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(focusToastMode ? ToastTiming.inactiveDisplay : 320))
            withAnimation(.smooth(duration: 0.32)) {
                isExpanded = false
                if focusToastMode {
                    showInactiveIcon = false
                }
            }
        }

        cleanupTask?.cancel()
        guard !focusToastMode else { return }
        cleanupTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.smooth(duration: 0.2)) {
                showInactiveIcon = false
            }
        }
    }

    private func scheduleTransientCollapse() {
        collapseTask?.cancel()
        cleanupTask?.cancel()

        collapseTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(ToastTiming.activeDisplay))
            withAnimation(.smooth(duration: 0.32)) {
                isExpanded = false
                showInactiveIcon = false
            }
        }
    }

    private func cancelPendingTasks() {
        scaleResetTask?.cancel()
        collapseTask?.cancel()
        cleanupTask?.cancel()
        scaleResetTask = nil
        collapseTask = nil
        cleanupTask = nil
    }
}

#Preview {
    DoNotDisturbLiveActivity()
        .environmentObject(DynamicIslandViewModel())
        .frame(width: 320, height: 54)
        .background(Color.black)
}

private final class SymbolAvailabilityCache {
    static let shared = SymbolAvailabilityCache()
    private var cache: [String: Bool] = [:]
    private let lock = NSLock()

    func isSymbolAvailable(_ name: String) -> Bool {
        lock.lock()
        if let cached = cache[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        #if canImport(AppKit)
        let available = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        #else
        let available = false
        #endif

        lock.lock()
        cache[name] = available
        lock.unlock()
        return available
    }
}

private enum FocusLabelMetrics {
    static let baselineText = "Do Not Disturb"

    static let baselineWidth: CGFloat = {
        #if canImport(AppKit)
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        return (baselineText as NSString).size(withAttributes: [.font: font]).width
        #else
        return 0
        #endif
    }()
}
